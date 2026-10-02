#Requires -Version 7.0
<#
.SYNOPSIS
    Lab readiness check: confirms every component of your team environment is in place and
    reports each one as Ready or Not ready.

.DESCRIPTION
    Run it from the 'Lab readiness check' shortcut on the desktop. It needs no sign-in: it uses
    the lab VM's provisioning identity (a managed identity with read access) in an Azure CLI
    profile of its own, so it never touches your own 'az login'.

    Components:
      Azure resources            the team's resource group holds the lab resources
      Service Desk app and data  the Service Desk app exists and the seeded data is complete:
                                 customer profiles and procedures, knowledge articles,
                                 runbooks, technicians, SLA definitions and ticket history,
                                 plus the two new incidents (untriaged)
      Tier 1 Technician          the second identity exists in Dataverse with the read-only role
      Foundry agent              the agent exists with its Microsoft Entra Agent ID, has no
                                 knowledge source and only the Service Desk MCP tool
      MCP connection             the project connection uses OAuth identity passthrough to
                                 the team's API Management gateway
      MCP server                 healthy, reads its gateway key from Key Vault, acts on behalf
                                 of the signed-in user
      Baseline read tool         a read tool called through API Management returns real
                                 ticket data
      Search content             the export the knowledge index is loaded from is complete

    If a component is Not ready, contact support with the table this script prints.
#>
[CmdletBinding()]
param(
    [string]$SettingsPath = 'C:\LabFiles\team-settings.json',
    [string]$SeedManifestPath = 'C:\LabFiles\seed\data\manifest.json',
    # Lab provisioning: use the current Azure CLI session instead of the readiness profile.
    [switch]$AsProvisioning,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
$results = [System.Collections.Generic.List[object]]::new()
function Add-Result([string]$component, [string]$status, [string]$detail) {
    $results.Add([pscustomobject]@{ Component = $component; Status = $status; Detail = $detail })
}

if (-not $AsProvisioning) {
    $env:AZURE_CONFIG_DIR = 'C:\LabFiles\.azure-readiness'
    New-Item -ItemType Directory -Path $env:AZURE_CONFIG_DIR -Force | Out-Null
    $current = az account show --query user.name --output tsv 2>$null
    if (-not $current) {
        Write-Host 'Signing in with the lab VM identity...' -ForegroundColor DarkGray
        az login --identity --client-id $settings.ProvisioningIdentityClientId --allow-no-subscriptions --output none 2>$null
        if ($LASTEXITCODE) { az login --identity --username $settings.ProvisioningIdentityClientId --allow-no-subscriptions --output none }
        if ($LASTEXITCODE) { throw 'The lab VM identity could not sign in. Contact support.' }
    }
    az account set --subscription $settings.SubscriptionId --output none
}
$tokens = @{}
function Token([string]$resource) {
    if (-not $tokens[$resource]) {
        $tokens[$resource] = az account get-access-token --resource $resource --query accessToken --output tsv 2>$null
        if (-not $tokens[$resource]) { throw "no access token for $resource" }
    }
    return $tokens[$resource]
}
function Check([string]$component, [scriptblock]$body) {
    try {
        $outcome = & $body
        if ($outcome -is [array]) { $outcome = $outcome[-1] }
        Add-Result $component $outcome.Status $outcome.Detail
    }
    catch { Add-Result $component 'Not ready' $_.Exception.Message }
}
function Ready([string]$detail) { return @{ Status = 'Ready'; Detail = $detail } }
function NotReady([string]$detail) { return @{ Status = 'Not ready'; Detail = $detail } }

$seedManifest = Get-Content $SeedManifestPath -Raw | ConvertFrom-Json
$dv = $settings.DataverseUrl.TrimEnd('/')
function DvGet([string]$path) {
    return Invoke-RestMethod -Uri "$dv/api/data/v9.2/$path" -Headers @{ Authorization = "Bearer $(Token $dv)"; Accept = 'application/json'
        'OData-MaxVersion' = '4.0'; 'OData-Version' = '4.0'; Prefer = 'odata.maxpagesize=5000' }
}
function DvCount([string]$entitySet, [string]$filter = '') {
    $f = if ($filter) { "&`$filter=$filter" } else { '' }
    return [int](DvGet "$($entitySet)?`$select=createdon&`$count=true&`$top=1$f").'@odata.count'
}

Check 'Azure resources' {
    $types = @(az resource list --resource-group $settings.ResourceGroup --query '[].type' --output json | ConvertFrom-Json)
    $required = 'Microsoft.App/containerApps', 'Microsoft.ApiManagement/service', 'Microsoft.CognitiveServices/accounts',
                'Microsoft.Search/searchServices', 'Microsoft.KeyVault/vaults', 'Microsoft.ContainerRegistry/registries'
    $missing = @($required | Where-Object { $_ -notin $types })
    if ($missing) { return NotReady "missing: $($missing -join ', ')" }
    Ready "$($types.Count) resources in $($settings.ResourceGroup)"
}

Check 'Service Desk app and data' {
    $app = (DvGet "appmodules?`$select=appmoduleid&`$filter=uniquename eq 'spk_ServiceDesk'").value
    if (-not $app) { return NotReady 'the Service Desk app is missing' }
    $c = $seedManifest.counts
    $actual = [ordered]@{
        'customer profiles' = @((DvCount 'accounts' 'spk_customercode ne null'), $c.accounts)
        'customer procedures' = @((DvCount 'spk_customerprocedures'), $c.customerprocedures)
        'knowledge articles' = @((DvCount 'spk_knowledgearticles'), $c.knowledgearticles)
        'runbooks' = @((DvCount 'spk_runbooks'), $c.runbooks)
        'technicians' = @((DvCount 'spk_technicians'), $c.technicians)
        'SLA definitions' = @((DvCount 'spk_slapolicies'), $c.slapolicies)
        'tickets' = @((DvCount 'spk_tickets'), ($c.tickets + @($seedManifest.new_incidents).Count))
    }
    $wrong = @($actual.Keys | Where-Object { $actual[$_][0] -ne $actual[$_][1] } | ForEach-Object { "$_ $($actual[$_][0]) of $($actual[$_][1])" })
    if ($wrong) { return NotReady "seeded data incomplete: $($wrong -join ', ')" }
    foreach ($number in $seedManifest.new_incidents) {
        $t = (DvGet "spk_tickets?`$select=spk_priority,spk_category,_spk_assignedtechnicianid_value&`$filter=spk_ticketnumber eq '$number'").value | Select-Object -First 1
        if (-not $t) { return NotReady "new incident $number is missing" }
    }
    Ready (($actual.Keys | ForEach-Object { "$($actual[$_][0]) $_" }) -join ', ') + "; new incidents $($seedManifest.new_incidents -join ', ')"
}

Check 'Tier 1 Technician' {
    if (-not $settings.Tier1User -and -not $settings.Tier1UserObjectId) {
        return @{ Status = 'Not configured'; Detail = 'no Tier 1 user in this deployment; Exercise 5 Task 4 needs it' }
    }
    $filter = if ($settings.Tier1UserObjectId) { "azureactivedirectoryobjectid eq $($settings.Tier1UserObjectId)" } else { "domainname eq '$($settings.Tier1User)'" }
    $user = (DvGet "systemusers?`$select=systemuserid,domainname&`$filter=$filter&`$expand=systemuserroles_association(`$select=name)").value | Select-Object -First 1
    if (-not $user) { return NotReady "$($settings.Tier1User) is not a user of the Service Desk environment" }
    $roles = @($user.systemuserroles_association.name)
    if ($roles -notcontains 'Service Desk Tier 1 Technician') { return NotReady "roles are $($roles -join ', ')" }
    if ($roles | Where-Object { $_ -in 'System Administrator', 'Service Desk Senior Technician', 'Service Desk Agent Write' }) {
        return NotReady "holds more than read-only: $($roles -join ', ')"
    }
    Ready "$($user.domainname): $($roles -join ', ')"
}

Check 'Foundry agent' {
    $agent = Invoke-RestMethod -Uri "$($settings.FoundryProjectEndpoint)/agents/$($settings.AgentName)?api-version=v1" `
        -Headers @{ Authorization = "Bearer $(Token 'https://ai.azure.com')" }
    $agentId = $agent.instance_identity.client_id
    if (-not $agentId) { return NotReady 'the agent has no Microsoft Entra Agent ID' }
    $json = $agent | ConvertTo-Json -Depth 30
    if ($json -notmatch '"server_label":\s*"servicedesk"') { return NotReady 'the Service Desk MCP tool is missing' }
    $knowledge = if ($json -match '"type":\s*"azure_ai_search"') { 'knowledge source added (Exercise 1)' } else { 'no knowledge source' }
    Ready "$($agent.name), Entra Agent ID $agentId; Service Desk MCP tool; $knowledge"
}

Check 'MCP connection' {
    $id = "/subscriptions/$($settings.SubscriptionId)/resourceGroups/$($settings.ResourceGroup)/providers/Microsoft.CognitiveServices/accounts/$($settings.FoundryResource)/projects/$($settings.FoundryProject)/connections/$($settings.McpConnectionName)"
    $conn = az rest --method get --uri "https://management.azure.com$($id)?api-version=2026-07-01" --output json 2>$null | ConvertFrom-Json
    if (-not $conn) { return NotReady "project connection $($settings.McpConnectionName) is missing" }
    if ($conn.properties.authType -ne 'OAuth2') { return NotReady "authentication is $($conn.properties.authType), not OAuth identity passthrough" }
    if ("$($conn.properties.target)".TrimEnd('/') -ne $settings.McpGatewayUrl.TrimEnd('/')) { return NotReady "target is $($conn.properties.target)" }
    Ready "$($settings.McpConnectionName): OAuth identity passthrough to $($settings.McpGatewayUrl)"
}

Check 'MCP server' {
    $health = Invoke-RestMethod -Uri "$($settings.McpServerUrl)/health?deep=true" -TimeoutSec 20
    if ($health.status -ne 'ok') { return NotReady "health is $($health.status): $($health.error)" }
    if ($health.gateway_key_source -ne 'key vault') { return NotReady "gateway key source is $($health.gateway_key_source)" }
    if (-not $health.user_impersonation) { return NotReady 'user impersonation is off' }
    Ready "version $($health.version); gateway key from Key Vault; acts for the signed-in user; Purview $($health.purview)"
}

Check 'Baseline read tool' {
    # Provisioning copies Invoke-McpTool.ps1 from the MCP server release into this folder.
    $invoke = Join-Path $PSScriptRoot 'Invoke-McpTool.ps1'
    $tools = & $invoke -List -SettingsPath $SettingsPath -Raw 6>$null
    $names = @($tools.result.tools.name)
    $response = & $invoke -Tool get_ticket -Arguments @{ ticket_number = 'TCK-10489' } -SettingsPath $SettingsPath -Raw 6>$null
    $body = $response.result.content[0].text | ConvertFrom-Json
    if ($response.result.isError -or -not $body.ok) { return NotReady "get_ticket failed: $($body.error.code) $($body.error.message)" }
    if ($body.ticket.ticket_number -ne 'TCK-10489' -or -not $body.ticket.customer.name) { return NotReady 'get_ticket returned no ticket data' }
    Ready "$($names.Count) tools listed; get_ticket TCK-10489 returned $($body.ticket.customer.name), correlation ID $($body.correlation_id)"
}

Check 'Search content' {
    $export = Get-Content (Join-Path ($settings.SearchExport ?? 'C:\LabFiles\search\export') 'export-manifest.json') -Raw | ConvertFrom-Json
    $expected = [int]$seedManifest.searchable_documents.total
    if ([int]$export.total -ne $expected) { return NotReady "export holds $($export.total) documents; expected $expected" }
    Ready "$($export.total) documents ready to load in Exercise 1"
}

$results | Format-Table -AutoSize -Wrap | Out-Host
$notReady = @($results | Where-Object { $_.Status -ne 'Ready' })
if ($notReady) {
    Write-Host "$($notReady.Count) component(s) not ready. Contact support and share this table." -ForegroundColor Yellow
}
else { Write-Host 'Every component is ready. You can start Exercise 1.' -ForegroundColor Green }
if ($PassThru) { return $results }
