<#
.SYNOPSIS
    Creates (or finds) the team's Power Platform developer environment with a Dataverse database.
    Windows PowerShell 5.1 only: the Microsoft.PowerApps.Administration.PowerShell module does
    not support PowerShell 7.

.DESCRIPTION
    Signs in as the TEAM USER, so the developer environment is the team user's own and the team
    user is its System Administrator. The tenant must allow developer environment creation for
    lab users (PPAC > Tenant settings > Developer environment assignments) and the team user
    must hold the Power Apps Developer Plan licence (POWERAPPS_DEV). See setup/README.md.

    -AdditionalUserObjectIds adds other lab users to the environment (the Tier 1 Technician):
    users are not added to a developer environment automatically. Each needs the Power Apps
    Developer Plan licence; their security roles are set by Set-DataverseSecurity.ps1.

    The team user's password is read from the MSPLAB_SIGNIN_SECRET environment variable of the
    calling process, never from the command line. Writes a JSON result file for the caller.
#>
param(
    [Parameter(Mandatory = $true)][string]$DeploymentID,
    [Parameter(Mandatory = $true)][string]$AzureUserName,
    [Parameter(Mandatory = $true)][string]$DomainName,
    [string]$Location = 'europe',
    [string[]]$AdditionalUserObjectIds = @(),
    [Parameter(Mandatory = $true)][string]$OutFile
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

foreach ($module in 'Microsoft.PowerApps.Administration.PowerShell', 'Microsoft.PowerApps.PowerShell') {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
            Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
        }
        Install-Module -Name $module -Force -AllowClobber -Scope AllUsers
    }
    Import-Module $module -Force
}

if (-not $env:MSPLAB_SIGNIN_SECRET) { throw 'MSPLAB_SIGNIN_SECRET is not set by the caller.' }
$secure = ConvertTo-SecureString $env:MSPLAB_SIGNIN_SECRET -AsPlainText -Force
Add-PowerAppsAccount -Username $AzureUserName -Password $secure | Out-Null

$displayName = "Relecloud Service Desk $DeploymentID"

function Find-Environment {
    $all = @()
    try { $all = @(Get-AdminPowerAppEnvironment) } catch { $all = @() }
    if (-not $all) { try { $all = @(Get-PowerAppEnvironment) } catch { $all = @() } }
    return $all | Where-Object { $_.DisplayName -eq $displayName } | Select-Object -First 1
}

$environment = Find-Environment
if (-not $environment) {
    Write-Host "Creating developer environment '$displayName' ($DomainName, $Location)..."
    $created = New-AdminPowerAppEnvironment -DisplayName $displayName -LocationName $Location -EnvironmentSku Developer `
        -ProvisionDatabase -CurrencyName USD -LanguageName 1033 -DomainName $DomainName -WaitUntilFinished $true
    if ($created.Code -and $created.Code -ge 400) {
        throw "New-AdminPowerAppEnvironment failed: $($created.Code) $($created.Description) $($created.Error | ConvertTo-Json -Depth 5 -Compress)"
    }
    $environment = Find-Environment
}
if (-not $environment) { throw "Environment '$displayName' was not found after creation." }

# Wait for the Dataverse instance URL (database provisioning can lag the environment record).
$deadline = (Get-Date).AddMinutes(45)
do {
    $instanceUrl = $environment.Internal.properties.linkedEnvironmentMetadata.instanceUrl
    if (-not $instanceUrl) {
        Start-Sleep -Seconds 30
        $environment = Find-Environment
    }
} until ($instanceUrl -or (Get-Date) -gt $deadline)
if (-not $instanceUrl) { throw "Dataverse database for '$displayName' did not finish provisioning in 45 minutes." }

$added = @()
foreach ($objectId in @($AdditionalUserObjectIds | Where-Object { $_ })) {
    # Forces the user into the environment's Dataverse database now, instead of at first sign-in.
    $result = Add-AdminPowerAppsSyncUser -EnvironmentName $environment.EnvironmentName -PrincipalObjectId $objectId
    if ($result.Code -and $result.Code -ge 400) {
        throw "Adding user $objectId to the environment failed: $($result.Code) $($result.Description)"
    }
    $added += $objectId
    Write-Host "Added user $objectId to the environment."
}

@{
    environmentId = $environment.EnvironmentName
    displayName   = $displayName
    instanceUrl   = $instanceUrl.TrimEnd('/')
    sku           = $environment.Internal.properties.environmentSku
    addedUsers    = $added
} | ConvertTo-Json | Set-Content -Path $OutFile -Encoding UTF8
Write-Host "Developer environment ready: $instanceUrl"
