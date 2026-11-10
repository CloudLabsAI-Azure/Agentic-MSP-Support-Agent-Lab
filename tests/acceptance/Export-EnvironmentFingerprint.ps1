#Requires -Version 7.0
<#
.SYNOPSIS
    Acceptance criterion 3 (part 1): records one environment's configuration as a fingerprint that
    Compare-ConsistencyReports.ps1 compares across environments.

.DESCRIPTION
    Reads (read-only) the environment's Golden Environment version, resource types and SKUs, model
    deployments, agent definition, project connections, Container App, API Management APIs and
    policies, search service, Key Vault and storage settings, and the seed manifest's counts. Every
    environment-specific value (Deployment ID, resource names, IDs, user names, tenant) is replaced by
    a placeholder, so two identical environments give identical fingerprints. Instructions and
    policies are recorded as SHA-256 hashes. Pass -ReadinessReport to include the readiness check's
    result (a JSON file of component, status and detail).

    Run it on each environment's lab VM before the event (as a supplier account or the provisioning
    identity) and collect the files in one folder.

.EXAMPLE
    .\Export-EnvironmentFingerprint.ps1 -OutPath C:\Acceptance\fingerprints
#>
[CmdletBinding()]
param(
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json',
    [string]$ManifestPath,
    [string]$ReadinessReport,
    [ValidateSet('Current', 'Senior', 'Provisioning')][string]$Identity = 'Current',
    [string]$OutPath = (Join-Path $HOME 'acceptance-evidence')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AcceptanceCommon.psm1') -Force

$settings = Read-LabSettings $SettingsPath @('DeploymentID', 'ResourceGroup', 'SubscriptionId')
Use-LabIdentity $Identity $settings

# ==== Placeholders for everything that is specific to this environment
$replacements = [System.Collections.Generic.List[object]]::new()
foreach ($key in 'SubscriptionId', 'TenantId', 'ResourceGroup', 'FoundryResource', 'FoundryProject', 'SearchService', 'StorageAccount', 'ApimName', 'ContainerApp',
    'ContainerRegistry', 'KeyVault', 'LogAnalyticsWorkspace', 'AppInsights', 'AgentId', 'AgentIdentityObjectId', 'McpBackendIdentityClientId', 'ProvisioningIdentityClientId',
    'Tier1UserObjectId', 'SeniorUser', 'Tier1User', 'McpGatewayAppId', 'LogAnalyticsWorkspaceId', 'SensitivityLabelId') {
    $v = [string]$settings.$key
    if ($v.Length -ge 6) { $replacements.Add(@($v, "<$key>")) }
}
if ($settings.DataverseUrl) { $replacements.Add(@(([uri]$settings.DataverseUrl).Host.Split('.')[0], '<DataverseOrg>')) }
if ($settings.SeniorUser -match '@(.+)$') { $replacements.Add(@($Matches[1], '<TenantDomain>')) }
$ordered = @($replacements | Sort-Object { $_[0].Length } -Descending)

function ConvertTo-Neutral([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $t = $Text
    foreach ($r in $ordered) { $t = [regex]::Replace($t, [regex]::Escape($r[0]), $r[1], 'IgnoreCase') }
    $t = $t.Replace([string]$settings.DeploymentID, '<DID>')
    return [regex]::Replace($t, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}', '<guid>')
}
function Get-Hash([string]$Text) {
    if ($null -eq $Text) { return '' }
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes((ConvertTo-Neutral $Text)))).ToLowerInvariant()
}
function Read-Az([string[]]$Arguments) {
    $out = & az @Arguments --output json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) { return $null }
    return (($out -join "`n") | ConvertFrom-Json)
}

$fp = [ordered]@{ collectedAt = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'); deploymentId = [string]$settings.DeploymentID; errors = [System.Collections.Generic.List[string]]::new() }
function Add-Section([string]$Name, [scriptblock]$Collect) {
    try { $fp[$Name] = & $Collect }
    catch { $fp.errors.Add("$($Name): $($_.Exception.Message)"); $fp[$Name] = 'unavailable' }
}

Add-Section 'lab' {
    $m = try { Get-SeedManifest $settings $ManifestPath } catch { $null }
    [ordered]@{
        goldenEnvironmentVersion = [string]$settings.GoldenEnvironmentVersion; region = [string]$settings.Region
        seedDataVersion = [string]$m.data_version; seedCounts = $m.counts; searchableDocuments = $m.searchable_documents
        seedScenarioHash = (Get-Hash (($m.role_keys | ConvertTo-Json -Depth 5 -Compress) + ($m.numbering | ConvertTo-Json -Compress)))
    }
}
Add-Section 'resources' {
    @(Read-Az @('resource', 'list', '--resource-group', $settings.ResourceGroup, '--query', '[].{type:type, kind:kind, sku:sku.name, location:location}') |
        ForEach-Object { "$($_.type)|$($_.kind)|$($_.sku)|$($_.location)".ToLowerInvariant() } | Sort-Object)
}
Add-Section 'modelDeployments' {
    @(Read-Az @('cognitiveservices', 'account', 'deployment', 'list', '--resource-group', $settings.ResourceGroup, '--name', $settings.FoundryResource,
        '--query', '[].{name:name, model:properties.model.name, version:properties.model.version, sku:sku.name, capacity:sku.capacity}') |
        ForEach-Object { "$($_.name)|$($_.model)|$($_.version)|$($_.sku)|$($_.capacity)" } | Sort-Object)
}
Add-Section 'agent' {
    $a = (Invoke-LabRest GET "$(([string]$settings.FoundryProjectEndpoint).TrimEnd('/'))/agents/$($settings.AgentName)?api-version=v1" (Get-LabToken 'https://ai.azure.com')).Body
    $d = $a.versions.latest.definition
    [ordered]@{
        latestVersion = [string]$a.versions.latest.version; hasAgentId = [bool]$a.instance_identity.client_id; model = $d.model; kind = $d.kind
        reasoning = ($d.reasoning | ConvertTo-Json -Compress); instructionsHash = (Get-Hash ([string]$d.instructions))
        tools = @(@($d.tools) | Where-Object { $_ } | ForEach-Object {
            if ($_.type -eq 'mcp') { "mcp|$($_.server_label)|$(ConvertTo-Neutral ([string]$_.project_connection_id))|approval=$(($_.require_approval | ConvertTo-Json -Compress -Depth 5))|allowed=$((@($_.allowed_tools) | Sort-Object) -join ',')|$(ConvertTo-Neutral ([string]$_.server_url))" }
            elseif ($_.type -eq 'azure_ai_search') { $ix = @($_.azure_ai_search.indexes)[0]; "azure_ai_search|$($ix.index_name)|$($ix.query_type)|$($ix.top_k)|$(ConvertTo-Neutral ([string]$ix.project_connection_id))" }
            else { [string]$_.type } } | Sort-Object)
    }
}
Add-Section 'projectConnections' {
    $project = "/subscriptions/$($settings.SubscriptionId)/resourceGroups/$($settings.ResourceGroup)/providers/Microsoft.CognitiveServices/accounts/$($settings.FoundryResource)/projects/$($settings.FoundryProject)"
    @((Read-Az @('rest', '--method', 'get', '--uri', "https://management.azure.com$project/connections?api-version=2025-06-01")).value |
        ForEach-Object { "$($_.name)|$($_.properties.category)|$($_.properties.authType)|$(ConvertTo-Neutral ([string]$_.properties.target))" } | Sort-Object)
}
Add-Section 'containerApp' {
    $app = Read-Az @('containerapp', 'show', '--name', $settings.ContainerApp, '--resource-group', $settings.ResourceGroup)
    [ordered]@{
        image = ConvertTo-Neutral ([string]$app.properties.template.containers[0].image); revisionMode = [string]$app.properties.configuration.activeRevisionsMode
        minReplicas = $app.properties.template.scale.minReplicas; maxReplicas = $app.properties.template.scale.maxReplicas
        ingressExternal = $app.properties.configuration.ingress.external; targetPort = $app.properties.configuration.ingress.targetPort
        ipRestrictions = @($app.properties.configuration.ingress.ipSecurityRestrictions).Count
        envNames = @($app.properties.template.containers[0].env | ForEach-Object { $_.name } | Sort-Object)
        envValues = @($app.properties.template.containers[0].env | Where-Object { $_.value } | ForEach-Object { "$($_.name)=$(ConvertTo-Neutral ([string]$_.value))" } | Sort-Object)
        secretNames = @($app.properties.configuration.secrets | ForEach-Object { $_.name } | Sort-Object)
        identities = @($app.identity.type)
    }
}
Add-Section 'apiManagement' {
    $apim = "/subscriptions/$($settings.SubscriptionId)/resourceGroups/$($settings.ResourceGroup)/providers/Microsoft.ApiManagement/service/$($settings.ApimName)"
    $svc = Read-Az @('rest', '--method', 'get', '--uri', "https://management.azure.com$($apim)?api-version=2024-05-01")
    $apis = @((Read-Az @('rest', '--method', 'get', '--uri', "https://management.azure.com$apim/apis?api-version=2024-05-01")).value)
    [ordered]@{
        sku = "$($svc.sku.name)|$($svc.sku.capacity)"
        apis = @($apis | ForEach-Object {
            $policy = Read-Az @('rest', '--method', 'get', '--uri', "https://management.azure.com$apim/apis/$($_.name)/policies/policy?api-version=2024-05-01&format=rawxml")
            "$($_.name)|$($_.properties.path)|$($_.properties.type)|subscription=$($_.properties.subscriptionRequired)|policy=$(Get-Hash ([string]$policy.properties.value))"
        } | Sort-Object)
    }
}
Add-Section 'search' {
    $s = Read-Az @('search', 'service', 'show', '--name', $settings.SearchService, '--resource-group', $settings.ResourceGroup)
    [ordered]@{ sku = $s.sku.name; replicas = $s.replicaCount; partitions = $s.partitionCount; semanticSearch = $s.semanticSearch
        disableLocalAuth = $s.disableLocalAuth; authOptions = ($s.authOptions | ConvertTo-Json -Compress); identity = $s.identity.type; publicNetworkAccess = $s.publicNetworkAccess }
}
Add-Section 'keyVault' {
    $kv = Read-Az @('keyvault', 'show', '--name', $settings.KeyVault)
    [ordered]@{ rbac = $kv.properties.enableRbacAuthorization; softDelete = $kv.properties.enableSoftDelete
        secretNames = @(Read-Az @('keyvault', 'secret', 'list', '--vault-name', $settings.KeyVault, '--query', '[].name') | Sort-Object) }
}
Add-Section 'storage' {
    $st = Read-Az @('storage', 'account', 'show', '--name', $settings.StorageAccount, '--resource-group', $settings.ResourceGroup)
    [ordered]@{ sku = $st.sku.name; kind = $st.kind; allowSharedKeyAccess = $st.allowSharedKeyAccess; minimumTlsVersion = $st.minimumTlsVersion; publicNetworkAccess = $st.publicNetworkAccess }
}
if ($ReadinessReport) {
    Add-Section 'readiness' { @(Get-Content -LiteralPath $ReadinessReport -Raw | ConvertFrom-Json | ForEach-Object { "$($_.Component)|$($_.Status)" } | Sort-Object) }
}

New-Item -ItemType Directory -Path $OutPath -Force | Out-Null
$file = Join-Path $OutPath "fingerprint-$($settings.DeploymentID).json"
Protect-Text ($fp | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $file -Encoding utf8
Write-Host "Fingerprint of deployment $($settings.DeploymentID) written to $file$(if ($fp.errors.Count) { " with $($fp.errors.Count) unreadable section(s): $($fp.errors -join '; ')" })." -ForegroundColor $(if ($fp.errors.Count) { 'Yellow' } else { 'Green' })
