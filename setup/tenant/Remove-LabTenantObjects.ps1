#Requires -Version 7.0
<#
.SYNOPSIS
    Removes the lab's objects that are not Azure resources from one participant tenant, when
    CloudLabs returns the tenant to a pool after an event (phase 7, setup/tenant/RUNBOOK.md).

.DESCRIPTION
    Azure resources go with the resource group and the subscription, and the setup app's certificate
    goes with the lab VM. What stays in a tenant that is reused:
      Power Platform   the managed developer environment 'Relecloud Service Desk <DeploymentID>'
      Microsoft Entra  the app registrations 'Relecloud Lab Setup <DeploymentID>', 'Relecloud Service
                       Desk MCP Gateway' and 'Relecloud Service Desk Purview Integration'
      Microsoft Purview  the DLP rule and policy, the label publishing policy, the label, the AI
                       interactions collection policy, and the Senior Technician's role group
                       memberships
    The script finds each object, shows it, and asks before it deletes it (use -WhatIf to list only,
    -Confirm:$false to skip the questions). Deleted app registrations stay in the tenant's recycle
    bin for 30 days. Run it as a supplier Global Administrator of the tenant, from any computer with
    PowerShell 7, Azure CLI and the ExchangeOnlineManagement module. You sign in interactively;
    nothing is stored.

.EXAMPLE
    pwsh setup/tenant/Remove-LabTenantObjects.ps1 -TenantId <tenant ID> -DeploymentID 123456 -WhatIf

.EXAMPLE
    pwsh setup/tenant/Remove-LabTenantObjects.ps1 -TenantId <tenant ID> -DeploymentID 123456 `
        -AdminUserPrincipalName admin@<tenant domain> -SeniorUserPrincipalName <ODL user>
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$TenantId,
    [Parameter(Mandatory)][string]$DeploymentID,
    # Your account, for the Security & Compliance PowerShell sign-in. Without it, Purview is skipped.
    [string]$AdminUserPrincipalName,
    # The participant's Senior Technician account, to remove its Purview role group memberships.
    [string]$SeniorUserPrincipalName,
    [string]$LabConfigPath = (Join-Path $PSScriptRoot '..\assets\labfiles\provision\LabConfig.psd1')
)

$ErrorActionPreference = 'Stop'
$config = Import-PowerShellDataFile -Path $LabConfigPath
$removed = New-Object System.Collections.Generic.List[string]
$kept = New-Object System.Collections.Generic.List[string]

function Get-Token([string]$Resource) {
    $json = & az account get-access-token --tenant $TenantId --resource $Resource --output json 2>$null
    if ($LASTEXITCODE -or -not $json) {
        Write-Host "Sign in as a Global Administrator of tenant $TenantId."
        & az login --tenant $TenantId --allow-no-subscriptions --output none
        if ($LASTEXITCODE) { throw 'az login failed.' }
        $json = & az account get-access-token --tenant $TenantId --resource $Resource --output json
        if ($LASTEXITCODE) { throw "No token for $Resource." }
    }
    return ($json | ConvertFrom-Json).accessToken
}

function Invoke-Api([string]$Method, [string]$Uri, [string]$Token) {
    $r = Invoke-RestMethod -Method $Method -Uri $Uri -Headers @{ Authorization = "Bearer $Token" } -SkipHttpErrorCheck -StatusCodeVariable 'code'
    if ($code -ge 400) { throw "$Method $(($Uri -split '\?')[0]) returned HTTP $code`: $($r | ConvertTo-Json -Depth 4 -Compress)" }
    return $r
}

# ==== Power Platform: the managed developer environment
$environmentName = "$($config.Dataverse.DisplayNamePrefix) $DeploymentID"
$bap = 'https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments'
$ppToken = Get-Token 'https://service.powerapps.com/'
$environments = @((Invoke-Api GET "$($bap)?api-version=2021-04-01" $ppToken).value | Where-Object { $_.properties.displayName -eq $environmentName })
if (-not $environments.Count) { $kept.Add("Power Platform environment '$environmentName': not found") }
foreach ($e in $environments) {
    if ($PSCmdlet.ShouldProcess("Power Platform environment '$environmentName' ($($e.name))", 'Delete')) {
        $null = Invoke-Api DELETE "$bap/$($e.name)?api-version=2021-04-01" $ppToken
        $removed.Add("Power Platform environment '$environmentName' (deletion started)")
    }
}

# ==== Microsoft Entra: the three app registrations
$graphToken = Get-Token 'https://graph.microsoft.com'
foreach ($name in @("$($config.SetupAppName) $DeploymentID", $config.GatewayAppName, $config.PurviewAppName)) {
    $escaped = $name.Replace("'", "''")
    $apps = @((Invoke-Api GET "https://graph.microsoft.com/v1.0/applications?`$filter=displayName eq '$escaped'&`$select=id,appId,displayName" $graphToken).value)
    if (-not $apps.Count) { $kept.Add("app registration '$name': not found") }
    foreach ($app in $apps) {
        if ($PSCmdlet.ShouldProcess("app registration '$name' ($($app.appId))", 'Delete')) {
            $null = Invoke-Api DELETE "https://graph.microsoft.com/v1.0/applications/$($app.id)" $graphToken
            $removed.Add("app registration '$name'")
        }
    }
}

# ==== Microsoft Purview (Security & Compliance PowerShell)
if (-not $AdminUserPrincipalName) { $kept.Add('Microsoft Purview objects: skipped (pass -AdminUserPrincipalName)') }
else {
    Import-Module ExchangeOnlineManagement -ErrorAction Stop
    Connect-IPPSSession -UserPrincipalName $AdminUserPrincipalName -ShowBanner:$false
    try {
        $p = $config.Purview
        $rule = Get-DlpComplianceRule -Policy $p.DlpPolicyName -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $p.DlpRuleName }
        if ($rule -and $PSCmdlet.ShouldProcess("DLP rule '$($p.DlpRuleName)'", 'Delete')) { Remove-DlpComplianceRule -Identity $p.DlpRuleName -Confirm:$false; $removed.Add("DLP rule '$($p.DlpRuleName)'") }
        if (Get-DlpCompliancePolicy -Identity $p.DlpPolicyName -ErrorAction SilentlyContinue) {
            if ($PSCmdlet.ShouldProcess("DLP policy '$($p.DlpPolicyName)'", 'Delete')) { Remove-DlpCompliancePolicy -Identity $p.DlpPolicyName -Confirm:$false; $removed.Add("DLP policy '$($p.DlpPolicyName)'") }
        }
        else { $kept.Add("DLP policy '$($p.DlpPolicyName)': not found") }
        if (Get-Command Get-FeatureConfiguration -ErrorAction SilentlyContinue) {
            if (Get-FeatureConfiguration -Identity $p.CollectionPolicyName -ErrorAction SilentlyContinue) {
                if ($PSCmdlet.ShouldProcess("collection policy '$($p.CollectionPolicyName)'", 'Delete')) { Remove-FeatureConfiguration -Identity $p.CollectionPolicyName -Confirm:$false; $removed.Add("collection policy '$($p.CollectionPolicyName)'") }
            }
        }
        if (Get-LabelPolicy -Identity $p.LabelPolicyName -ErrorAction SilentlyContinue) {
            if ($PSCmdlet.ShouldProcess("label policy '$($p.LabelPolicyName)'", 'Delete')) { Remove-LabelPolicy -Identity $p.LabelPolicyName -Confirm:$false; $removed.Add("label policy '$($p.LabelPolicyName)'") }
        }
        else { $kept.Add("label policy '$($p.LabelPolicyName)': not found") }
        $label = Get-Label -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $p.LabelName -or $_.DisplayName -eq $p.LabelDisplayName } | Select-Object -First 1
        if ($label) {
            if ($PSCmdlet.ShouldProcess("sensitivity label '$($label.DisplayName)'", 'Delete')) {
                # A label is removed only after the policy that published it is gone; Purview finishes it in the background.
                Remove-Label -Identity $label.Guid.ToString() -Confirm:$false
                $removed.Add("sensitivity label '$($label.DisplayName)' (removal can take a few hours)")
            }
        }
        else { $kept.Add("sensitivity label '$($p.LabelDisplayName)': not found") }
        if ($SeniorUserPrincipalName) {
            foreach ($group in $p.SeniorRoleGroups) {
                $members = @(Get-RoleGroupMember -Identity $group -ErrorAction SilentlyContinue)
                $member = $members | Where-Object { $_.WindowsLiveID -eq $SeniorUserPrincipalName -or $_.PrimarySmtpAddress -eq $SeniorUserPrincipalName -or $_.Name -eq $SeniorUserPrincipalName }
                if ($member -and $PSCmdlet.ShouldProcess("$SeniorUserPrincipalName in role group '$group'", 'Remove')) {
                    Remove-RoleGroupMember -Identity $group -Member $SeniorUserPrincipalName -BypassSecurityGroupManagerCheck -Confirm:$false
                    $removed.Add("role group membership '$group'")
                }
            }
        }
    }
    finally { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null }
}

Write-Host ''
Write-Host "Tenant $TenantId, deployment $DeploymentID" -ForegroundColor Cyan
foreach ($r in $removed) { Write-Host "  removed  $r" -ForegroundColor Green }
foreach ($k in $kept) { Write-Host "  skipped  $k" }
