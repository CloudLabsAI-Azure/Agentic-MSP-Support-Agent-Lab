#Requires -Version 7.0
<#
.SYNOPSIS
    Microsoft Purview configuration of one lab tenant, app-only through Security & Compliance
    PowerShell with the setup app's certificate: the sensitivity label and its publishing policy,
    the DLP policy and rule for the MCP server's Entra-registered app (Credit Card Number, block),
    the optional collection policy, and the Senior Technician's Purview role groups.

.DESCRIPTION
    Idempotent: each object is looked up by its exact name and created only when missing, and an
    existing object is left as it is (a re-run never resets what a supplier changed on purpose).
    Names come from LabConfig.psd1 (Purview section); setup/tenant/PURVIEW-RUNBOOK.md documents the
    same configuration for the portal, and the pay-as-you-go step that has no API.

    The DLP policy is scoped to the Purview integration app (EnforcementPlanes Application): the
    Microsoft Purview portal cannot create DLP policies for Entra-registered apps. Labels can take
    up to 24 hours to reach every service and a DLP policy about an hour to take effect, which is
    why environments are provisioned at least a day ahead.

    Needs: ExchangeOnlineManagement 3.x (installed by psscript-01.ps1), the setup app with
    Exchange.ManageAsApp and the directory role from LabConfig.psd1, and its certificate in
    Cert:\LocalMachine\My. Returns an object with the label GUID and what was created.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PurviewAppId,
    [Parameter(Mandatory)][string]$SeniorUserPrincipalName,
    [int]$ConnectWaitMinutes = 20
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MspLab.Common.psm1') -Force
$config = Get-LabConfig
$p = $config.Purview
$info = Get-SetupAppInfo
if (-not $info -or $info.stripped) { throw 'The setup app is not available; run the bootstrap first.' }
$cert = Get-SetupAppCertificate
if (-not $cert) { throw 'The setup app certificate is missing from Cert:\LocalMachine\My.' }
if (-not $info.initialDomain) { throw 'The tenant''s initial domain is unknown (setup-app.json initialDomain).' }

$module = Get-Module -ListAvailable -Name ExchangeOnlineManagement | Sort-Object Version -Descending | Select-Object -First 1
if (-not $module) { throw 'The ExchangeOnlineManagement module is not installed (psscript-01.ps1 installs it).' }
Import-Module $module.Path -ErrorAction Stop | Out-Null
$created = New-Object System.Collections.Generic.List[string]

# ==== Connect. The setup app's role reaches Security & Compliance minutes after the grant, so
#      retry the connection and one read until both work.
$deadline = (Get-Date).AddMinutes($ConnectWaitMinutes)
$connected = $false
$lastError = ''
while (-not $connected -and (Get-Date) -lt $deadline) {
    try {
        Connect-IPPSSession -AppId $info.appId -Certificate $cert -Organization $info.initialDomain -ShowBanner:$false -ErrorAction Stop | Out-Null
        $null = Get-Label -ErrorAction Stop | Select-Object -First 1
        $connected = $true
    }
    catch {
        $lastError = $_.Exception.Message
        Write-Step "  Security & Compliance PowerShell not ready yet: $lastError"
        try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch { }
        Start-Sleep -Seconds 60
    }
}
if (-not $connected) { throw "Security & Compliance PowerShell refused the setup app for $ConnectWaitMinutes minutes: $lastError" }

try {
    # ==== Sensitivity label and its publishing policy
    $label = Get-Label -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $p.LabelName } | Select-Object -First 1
    if (-not $label) {
        $clash = Get-Label -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $p.LabelDisplayName } | Select-Object -First 1
        if ($clash) { throw "A label with the display name '$($p.LabelDisplayName)' already exists ($($clash.Name)); rename it or change LabConfig.psd1." }
        $label = New-Label -Name $p.LabelName -DisplayName $p.LabelDisplayName -Tooltip $p.LabelTooltip -ContentType 'File, Email'
        $created.Add("label $($p.LabelDisplayName)")
    }
    $labelGuid = [string]$label.Guid
    if (-not $labelGuid -and $label.ImmutableId) { $labelGuid = [string]$label.ImmutableId }
    if (-not $labelGuid) { throw "The label $($p.LabelName) has no GUID." }

    $labelPolicy = Get-LabelPolicy -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $p.LabelPolicyName } | Select-Object -First 1
    if (-not $labelPolicy) {
        $null = New-LabelPolicy -Name $p.LabelPolicyName -Labels $p.LabelName -ExchangeLocation 'All'
        $created.Add("label policy $($p.LabelPolicyName)")
    }

    # ==== DLP policy and rule for the Purview integration app (prompts sent to the AI)
    $policy = Get-DlpCompliancePolicy -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $p.DlpPolicyName } | Select-Object -First 1
    if (-not $policy) {
        $locations = ConvertTo-Json -Compress -InputObject @([ordered]@{
            Workload = 'Applications'; Location = $PurviewAppId; LocationDisplayName = $config.PurviewAppName
            LocationSource = 'Entra'; LocationType = 'Individual'; Inclusions = @(@{ Type = 'Tenant'; Identity = 'All' })
        })
        $null = New-DlpCompliancePolicy -Name $p.DlpPolicyName -Mode Enable -Locations $locations -EnforcementPlanes @('Application') `
            -Comment 'Blocks credit card numbers in Relecloud Service Desk content that the MCP server sends to Microsoft Purview.'
        $created.Add("DLP policy $($p.DlpPolicyName)")
    }
    $rule = Get-DlpComplianceRule -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $p.DlpRuleName } | Select-Object -First 1
    if (-not $rule) {
        $null = New-DlpComplianceRule -Name $p.DlpRuleName -Policy $p.DlpPolicyName `
            -ContentContainsSensitiveInformation @{ Name = 'Credit Card Number' } `
            -RestrictAccess @(@{ setting = 'UploadText'; value = 'Block' })
        $created.Add("DLP rule $($p.DlpRuleName)")
    }

    # ==== Collection policy for enterprise AI apps (public preview cmdlet; optional)
    $collection = 'not available in this tenant'
    if (Get-Command New-FeatureConfiguration -ErrorAction SilentlyContinue) {
        try {
            $existing = Get-FeatureConfiguration -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $p.CollectionPolicyName } | Select-Object -First 1
            if (-not $existing) {
                $null = New-FeatureConfiguration -FeatureScenario KnowYourData -Name $p.CollectionPolicyName -Mode Enable `
                    -ScenarioConfig '{"Activities": ["UploadText", "DownloadText"], "EnforcementPlanes": ["Application"], "SensitiveTypeIds": ["All"], "IsIngestionEnabled": true}' `
                    -Locations '[{"Workload": "Applications","Location": "ee1680d0-702f-4090-b26c-c49091e86531","LocationSource":"Entra","LocationType":"Group","Inclusions": [{"Type": "Tenant","Identity": "All"}]}]'
                $created.Add("collection policy $($p.CollectionPolicyName)")
            }
            $collection = 'present'
        }
        catch { $collection = "not created: $($_.Exception.Message)" }
    }

    # ==== Role groups of the Senior Technician (view DLP policies, labels, Activity explorer and DSPM AI data)
    $groups = @()
    $allGroups = @(Get-RoleGroup -ResultSize Unlimited -ErrorAction Stop)
    foreach ($wanted in $p.SeniorRoleGroups) {
        $group = $allGroups | Where-Object { $_.DisplayName -eq $wanted -or $_.Name -eq $wanted } | Select-Object -First 1
        if (-not $group) { throw "Purview role group '$wanted' was not found." }
        $members = @(Get-RoleGroupMember -Identity $group.Identity -ResultSize Unlimited -ErrorAction Stop)
        $isMember = @($members | Where-Object {
            $_.WindowsLiveID -eq $SeniorUserPrincipalName -or $_.PrimarySmtpAddress -eq $SeniorUserPrincipalName -or $_.Name -eq $SeniorUserPrincipalName }).Count -gt 0
        if (-not $isMember) {
            Add-RoleGroupMember -Identity $group.Identity -Member $SeniorUserPrincipalName -BypassSecurityGroupManagerCheck -ErrorAction Stop
            $created.Add("role group member $wanted")
        }
        $groups += $wanted
    }

    [pscustomobject]@{
        LabelGuid        = $labelGuid
        LabelName        = $p.LabelName
        LabelDisplayName = $p.LabelDisplayName
        LabelPolicy      = $p.LabelPolicyName
        DlpPolicy        = $p.DlpPolicyName
        DlpRule          = $p.DlpRuleName
        DlpMode          = [string](Get-DlpCompliancePolicy -Identity $p.DlpPolicyName).Mode
        CollectionPolicy = $collection
        RoleGroups       = $groups
        Created          = @($created)
    }
}
finally {
    try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch { }
}
