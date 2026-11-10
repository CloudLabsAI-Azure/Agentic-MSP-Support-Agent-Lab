#Requires -Version 7.0
<#
.SYNOPSIS
    Acceptance criterion 2: isolation. One participant's credentials can't read or change another
    participant's resources or data.

.DESCRIPTION
    Run on environment A's lab VM, signed in as A's Senior Technician, with a copy of environment B's
    lab-settings.json (B's settings hold no secret). Every read the test attempts against B must be
    refused or must fail to get a token at all, because B lives in another Microsoft Entra tenant:
      Azure Resource Manager (B's resource group), Azure AI Search (B's indexes), Microsoft Foundry
      (B's agents), Dataverse (B's tickets), API Management (B's read gateway), Key Vault (B's
      secrets), Storage (B's export container) and Log Analytics (B's workspace).
    Only reads are attempted: a refused read also proves a refused write, since both need the same
    sign-in. Swap the two settings files and run it again on B's VM for the other direction.

.EXAMPLE
    .\Test-Isolation.ps1 -OtherSettingsPath C:\Acceptance\environment-b\lab-settings.json
#>
[CmdletBinding()]
param(
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json',
    [Parameter(Mandatory)][string]$OtherSettingsPath,
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AcceptanceCommon.psm1') -Force

function Test-Refused([string]$Name, [scriptblock]$Attempt) {
    # Passes when the attempt gets no token, or the service answers 401, 403 or 404, or refuses the tenant.
    $outcome = ''
    $refused = $true
    try {
        $r = & $Attempt
        if ($r -is [pscustomobject] -and $r.PSObject.Properties['Status']) {
            $outcome = "HTTP $($r.Status) $(Protect-Text ([string]$r.Error))".Trim()
            $refused = ($r.Status -in 0, 400, 401, 403, 404) -or ("$($r.Error)" -match '(?i)tenant|not authorized|forbidden|unauthorized|AuthorizationFailed|InvalidAuthenticationToken')
            if ($r.Status -ge 200 -and $r.Status -lt 300) { $refused = $false }
        }
        else { $outcome = "returned data: $([string]$r)".Substring(0, [Math]::Min(120, "returned data: $([string]$r)".Length)); $refused = $false }
    }
    catch { $outcome = "refused before the call: $(Protect-Text $_.Exception.Message)"; $refused = $true }
    if ($outcome.Length -gt 300) { $outcome = $outcome.Substring(0, 300) }
    Add-Check $script:Report "Refused: $Name" $refused $outcome
}

$own = Read-LabSettings $SettingsPath @('TenantId', 'DeploymentID')
$other = Read-LabSettings $OtherSettingsPath @('TenantId', 'SubscriptionId', 'ResourceGroup', 'DeploymentID')
$script:Report = New-AcceptanceReport 2 'Isolation between participant environments' $own
try {
    if ($own.TenantId -eq $other.TenantId) { Add-Note $script:Report "Both environments share tenant $($own.TenantId): the design puts each participant in its own tenant." }
    Add-Note $script:Report "Signed in to deployment $($own.DeploymentID) (tenant $($own.TenantId)); attempting reads of deployment $($other.DeploymentID) (tenant $($other.TenantId))."
    Use-LabIdentity Senior $own

    Test-Refused "Azure Resource Manager: resource group $($other.ResourceGroup)" {
        Invoke-LabRest GET "https://management.azure.com/subscriptions/$($other.SubscriptionId)/resourceGroups/$($other.ResourceGroup)?api-version=2021-04-01" (Get-LabToken 'https://management.azure.com/') }
    if ($other.SearchEndpoint) {
        Test-Refused "Azure AI Search: indexes on $($other.SearchService)" {
            Invoke-LabRest GET "$(([string]$other.SearchEndpoint).TrimEnd('/'))/indexes?api-version=2024-07-01" (Get-LabToken 'https://search.azure.com') }
    }
    if ($other.FoundryProjectEndpoint) {
        Test-Refused "Microsoft Foundry: agents in $($other.FoundryProject)" {
            Invoke-LabRest GET "$(([string]$other.FoundryProjectEndpoint).TrimEnd('/'))/agents?api-version=v1" (Get-LabToken 'https://ai.azure.com') }
    }
    if ($other.DataverseUrl) {
        Test-Refused "Dataverse: tickets in $($other.DataverseUrl)" {
            $dv = ([string]$other.DataverseUrl).TrimEnd('/')
            Invoke-LabRest GET "$dv/api/data/v9.2/spk_tickets?`$top=1" (Get-LabToken $dv) }
    }
    if ($other.McpReadGatewayUrl) {
        Test-Refused "API Management: read gateway $($other.McpReadGatewayUrl)" {
            $body = @{ jsonrpc = '2.0'; id = 1; method = 'tools/list'; params = @{} }
            $token = $null
            if ($own.McpGatewayScope) { try { $token = (& az account get-access-token --scope $own.McpGatewayScope --query accessToken --output tsv 2>$null) } catch { $token = $null } }
            Invoke-LabRest POST $other.McpReadGatewayUrl ([string]$token) $body @{ Accept = 'application/json, text/event-stream' } }
    }
    if ($other.KeyVaultUrl) {
        Test-Refused "Key Vault: secrets in $($other.KeyVault)" {
            Invoke-LabRest GET "$(([string]$other.KeyVaultUrl).TrimEnd('/'))/secrets?api-version=7.4" (Get-LabToken 'https://vault.azure.net') }
    }
    if ($other.StorageAccount -and $other.ExportContainer) {
        Test-Refused "Storage: export container on $($other.StorageAccount)" {
            Invoke-LabRest GET "https://$($other.StorageAccount).blob.core.windows.net/$($other.ExportContainer)?restype=container&comp=list&maxresults=1" (Get-LabToken 'https://storage.azure.com/') $null @{ 'x-ms-version' = '2021-08-06' } }
    }
    if ($other.LogAnalyticsWorkspaceId) {
        Test-Refused "Log Analytics: workspace $($other.LogAnalyticsWorkspace)" {
            Invoke-LabRest POST "https://api.loganalytics.io/v1/workspaces/$($other.LogAnalyticsWorkspaceId)/query" (Get-LabToken 'https://api.loganalytics.io') @{ query = 'ContainerAppConsoleLogs | take 1'; timespan = 'P1D' } }
    }
}
catch {
    Add-Check $script:Report 'Test ran to completion' $false $_.Exception.Message
}
exit (Complete-AcceptanceReport $script:Report $EvidencePath)
