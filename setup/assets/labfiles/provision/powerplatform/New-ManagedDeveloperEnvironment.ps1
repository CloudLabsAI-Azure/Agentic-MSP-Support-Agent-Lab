#Requires -Version 7.0
<#
.SYNOPSIS
    Creates (or finds) the participant's managed developer environment with a Dataverse database,
    restricts developer environment creation to admins, and adds the lab's application users.

.DESCRIPTION
    Runs as the setup app, which the bootstrap registered as a Power Platform management
    application (it acts like a Power Platform administrator, app-only), or, when that registration
    was not possible, as a CloudLabs bootstrap service principal that CloudLabs registered
    (Get-PowerPlatformToken in MspLab.Common.psm1).

    1. Looks for the environment by display name ("Relecloud Service Desk <DeploymentID>").
    2. Otherwise creates it with one Power Platform API request:
         environmentSku Developer + governanceConfiguration.protectionLevel Standard (managed),
         usedBy = the Senior Technician, domain mspdesk<DeploymentID>, the region from the template.
       Unmanaged developer environments can no longer be created after 2026-11-15. If the request
       with usedBy fails validation it is sent again without usedBy; if a developer environment is
       refused, a managed sandbox is created instead (same licensing, no inactivity cleanup).
    3. Waits for the Dataverse instance URL.
    4. Tenant setting, best effort: only admins may create developer environments, so the
       participant cannot create a second environment once the Global Administrator role is gone.
    5. Adds each given client ID (setup app, id-prov, id-mcp) as an application user. The admin API
       always assigns System Administrator; Set-DataverseSecurity.ps1 replaces id-mcp's roles, and
       the last provisioning step reduces id-prov to Service Desk Agent Read.
    6. Adds the two technicians as Dataverse users (the admin force-sync, the same call as
       Add-AdminPowerAppsSyncUser), so their roles can be set before they ever sign in. A user is
       added only once the license that includes Dataverse has reached the account, so the call is
       retried for up to -UserWaitMinutes.
    7. Waits until id-prov can call Dataverse (WhoAmI).
    Returns EnvironmentId, InstanceUrl, Sku, ProtectionLevel, UsedBy, Created and the synced users.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DeploymentId,
    [Parameter(Mandatory)][string]$TenantId,
    [Parameter(Mandatory)][string]$SeniorObjectId,
    [string]$SeniorDisplayName = 'Senior Technician',
    [Parameter(Mandatory)][string]$Location,
    [Parameter(Mandatory)][string]$DomainName,
    [Parameter(Mandatory)][string[]]$AppUserClientIds,
    [string[]]$UserObjectIds = @(),
    [int]$WaitMinutes = 60,
    [int]$UserWaitMinutes = 30
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MspLab.Common.psm1') -Force
$config = Get-LabConfig
$displayName = "$($config.Dataverse.DisplayNamePrefix) $DeploymentId"
$bapBase = 'https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform'
$ppBase = 'https://api.powerplatform.com/environmentmanagement'

function Get-BapToken { Get-PowerPlatformToken -Resource 'https://service.powerapps.com/' }
function Get-PpApiToken { Get-PowerPlatformToken -Resource 'https://api.powerplatform.com/' }

function Find-Environment {
    $r = Invoke-LabRest -Method GET -Uri "$bapBase/scopes/admin/environments?api-version=2021-04-01" -Token (Get-BapToken)
    return @($r.Body.value) | Where-Object { $_.properties.displayName -eq $displayName } | Select-Object -First 1
}

function Wait-Operation {
    param($Response)
    $operationId = $Response.Body.operationId
    $operationUri = if ($operationId) { "$ppBase/operations/$($operationId)?api-version=2024-10-01" }
                    else { ($Response.Headers['Operation-Location'] ?? $Response.Headers['Location']) | Select-Object -First 1 }
    if (-not $operationUri) { return $Response.Body }
    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    do {
        Start-Sleep -Seconds 30
        $op = (Invoke-LabRest -Method GET -Uri $operationUri -Token (Get-PpApiToken)).Body
        $state = [string]$op.status
        Write-Step "  environment operation: $state"
        if ($state -in 'Succeeded', 'NoOperation') { return $op }
        if ($state -in 'Failed', 'ValidationFailed') { throw "Environment creation $state`: $(Get-RestErrorText $op)" }
    } while ((Get-Date) -lt $deadline)
    throw "Environment creation did not finish within $WaitMinutes minutes."
}

function New-Environment {
    param([string]$Sku, [switch]$WithUsedBy)
    $body = [ordered]@{
        displayName               = $displayName
        environmentSku            = $Sku
        databaseType              = 'CommonDataService'
        location                  = $Location
        governanceConfiguration   = @{ protectionLevel = 'Standard' }
        linkedEnvironmentMetadata = @{
            baseLanguageCode = $config.Dataverse.LanguageCode
            currency         = @{ code = $config.Dataverse.Currency }
            domainName       = $DomainName
        }
    }
    if ($WithUsedBy) { $body.usedBy = @{ userId = $SeniorObjectId; tenantId = $TenantId; type = 'User'; displayName = $SeniorDisplayName } }
    $r = Invoke-LabRest -Method POST -Uri "$ppBase/provisioning/environments?api-version=2024-10-01" -Token (Get-PpApiToken) -Body $body
    return Wait-Operation $r
}

# ==== 1 and 2. Find or create
$created = $false
$usedBy = 'not set'
$environment = Find-Environment
if (-not $environment) {
    $attempts = @(@{ Sku = 'Developer'; UsedBy = $true }, @{ Sku = 'Developer'; UsedBy = $false }, @{ Sku = 'Sandbox'; UsedBy = $false })
    $errors = @()
    foreach ($a in $attempts) {
        try {
            Write-Step "Creating $displayName ($($a.Sku), managed, $Location, domain $DomainName$(if ($a.UsedBy) { ', used by the Senior Technician' }))"
            $null = New-Environment -Sku $a.Sku -WithUsedBy:$a.UsedBy
            $created = $true
            if ($a.UsedBy) { $usedBy = 'Senior Technician' }
            break
        }
        catch {
            $errors += "$($a.Sku)$(if ($a.UsedBy) { ' with usedBy' }): $($_.Exception.Message)"
            Write-Step "  $($errors[-1])"
            $environment = Find-Environment
            if ($environment) { $created = $true; break }
        }
    }
    if (-not $created) { throw "The managed developer environment could not be created. $($errors -join ' | ')" }
}

# ==== 3. Instance URL
$deadline = (Get-Date).AddMinutes($WaitMinutes)
do {
    $environment = Find-Environment
    $instanceUrl = if ($environment) { [string]$environment.properties.linkedEnvironmentMetadata.instanceUrl } else { '' }
    $state = if ($environment) { [string]$environment.properties.provisioningState } else { 'not listed yet' }
    if (-not $instanceUrl -or $state -notin 'Succeeded', '') {
        Write-Step "  waiting for the Dataverse database ($state)"
        Start-Sleep -Seconds 30
    }
} until (($instanceUrl -and $state -in 'Succeeded', '') -or (Get-Date) -gt $deadline)
if (-not $instanceUrl) { throw "The Dataverse database of $displayName did not finish provisioning within $WaitMinutes minutes." }
$instanceUrl = $instanceUrl.TrimEnd('/')
$environmentId = [string]$environment.name

# ==== 4. Tenant setting: only admins create developer environments (best effort; the setting is read
#      first and written back whole, so no other tenant setting changes)
$tenantSetting = 'unchanged'
try {
    $settings = (Invoke-LabRest -Method POST -Uri "$bapBase/listTenantSettings?api-version=2020-10-01" -Token (Get-BapToken)).Body
    if ($settings.powerPlatform.governance.disableDeveloperEnvironmentCreationByNonAdminUsers -ne $true) {
        $settings.powerPlatform.governance | Add-Member -NotePropertyName disableDeveloperEnvironmentCreationByNonAdminUsers -NotePropertyValue $true -Force
        $null = Invoke-LabRest -Method POST -Uri "$bapBase/scopes/admin/updateTenantSettings?api-version=2020-10-01" -Token (Get-BapToken) -Body $settings
        $tenantSetting = 'developer environments: only admins'
    }
    else { $tenantSetting = 'developer environments: only admins (already)' }
}
catch { $tenantSetting = "not changed: $($_.Exception.Message)"; Write-Step "  WARNING: tenant setting $tenantSetting" }

# ==== 5. Application users (the admin API assigns System Administrator; roles are narrowed later)
foreach ($clientId in ($AppUserClientIds | Where-Object { $_ } | Select-Object -Unique)) {
    $null = Invoke-WithRetry -What "application user $clientId" -Attempts 10 -DelaySeconds 30 -Action {
        $r = Invoke-LabRest -Method POST -Uri "$bapBase/scopes/admin/environments/$environmentId/addAppUser?api-version=2020-10-01" `
            -Token (Get-BapToken) -Body @{ servicePrincipalAppId = $clientId } -AllowStatus 409
        $r
    }
    Write-Step "  application user for $clientId is in the environment"
}

# ==== 6. The technicians as Dataverse users (force-sync from Microsoft Entra ID)
$syncedUsers = @()
foreach ($objectId in ($UserObjectIds | Where-Object { $_ } | Select-Object -Unique)) {
    $null = Invoke-WithRetry -What "Dataverse user $objectId" -Attempts ([Math]::Max(1, $UserWaitMinutes * 2)) -DelaySeconds 30 -Action {
        Invoke-LabRest -Method POST -Uri "$bapBase/scopes/admin/environments/$environmentId/addUser?api-version=2020-10-01" `
            -Token (Get-BapToken) -Body @{ ObjectId = $objectId } -Attempts 2
    }
    $syncedUsers += $objectId
    Write-Step "  user $objectId is in the environment"
}

# ==== 7. The provisioning identity can call Dataverse
$null = Invoke-WithRetry -What 'Dataverse WhoAmI as id-prov' -Attempts 30 -DelaySeconds 30 -Action {
    Invoke-LabRest -Method GET -Uri "$instanceUrl/api/data/v9.2/WhoAmI" -Token (Get-ManagedIdentityToken -Resource $instanceUrl) -Attempts 1
}

[pscustomobject]@{
    EnvironmentId   = $environmentId
    DisplayName     = $displayName
    InstanceUrl     = $instanceUrl
    Sku             = [string]$environment.properties.environmentSku
    ProtectionLevel = [string]$environment.properties.governanceConfiguration.protectionLevel
    UsedBy          = $usedBy
    Created         = $created
    TenantSetting   = $tenantSetting
    SyncedUsers     = @($syncedUsers)
}
