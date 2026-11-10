#Requires -Version 7.0
<#
.SYNOPSIS
    Lab readiness check: confirms that every component of your environment is ready (Golden
    Environment v1.0), prints one row per component and writes a consistency report.

.DESCRIPTION
    Uses the lab VM's own identity (the provisioning identity, read-only after provisioning), so it
    needs no sign-in: double-click Lab readiness check on the desktop. It changes nothing.

    Components, in this order:
      Golden Environment         built from v1.0; provisioning finished; the resource group's
                                 Golden Environment tags match the seed and the MCP release
      Azure resources            Container App, API Management, Foundry with both model deployments,
                                 AI Search, storage, Key Vault, container registry, monitoring
      Service Desk app and data  the app, every seeded table at its manifest count, the two new
                                 incidents, the labeled configuration document
      Tier 1 Technician          the account exists with its licenses and no directory role, and is a
                                 Dataverse user holding only Service Desk Tier 1 Technician
      Foundry agent              msp-support-agent has its Entra Agent ID and both MCP tools
                                 (servicedesk-read without approval, servicedesk-write with approval)
      MCP connections            servicedesk-read and servicedesk-write: OAuth identity passthrough to
                                 the read and write gateways, with the gateway app consented
      MCP server                 /health ok, gateway key read from Key Vault, user impersonation on
      Baseline read tool         get_ticket on TCK-10524 (seed manifest role key) through the
                                 diagnostics API returns the real ticket and a correlation ID
      Search export              753 documents in the export container, matching the export manifest
      Microsoft Purview          the sensitivity label and the DLP policy are in place

    -Mode Participant (default) runs after provisioning and accepts the work an exercise adds later
    (a knowledge tool, edited instructions, a redeployed 3.0.x revision). -Mode Provisioning is run
    by Provision-ServiceDesk.ps1 before its last step and requires the exact baseline.

    Writes C:\LabFiles\readiness\readiness-report.json (one object per component: Component, Status,
    Detail) and consistency-report.json (the same plus the Golden Environment facts and their
    SHA-256 fingerprint, identical for every environment built from v1.0). Other folders, such as
    C:\LabFiles\evidence for your exported evidence, are not checked. Exit code 0 when every
    component is ready, 1 otherwise; -PassThru returns the result instead.
#>
[CmdletBinding()]
param(
    [ValidateSet('Participant', 'Provisioning')][string]$Mode = 'Participant',
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json',
    [string]$SeedFolder = 'C:\LabFiles\seed\data',
    [string]$ReportFolder = 'C:\LabFiles\readiness',
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$provisionFolder = Join-Path (Split-Path $PSScriptRoot -Parent) 'provision'
Import-Module (Join-Path $provisionFolder 'MspLab.Common.psm1') -Force
$config = Get-LabConfig
$results = New-Object System.Collections.Generic.List[object]
$facts = [ordered]@{}
$script:current = $null
$started = Get-Date

function Problem([string]$Text) { $script:current.Problems.Add($Text) }
function Note([string]$Text) { $script:current.Notes.Add($Text) }
function Fact([string]$Key, $Value) { $facts[$Key] = $Value }

function Test-Component {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$Check)
    $script:current = @{ Problems = New-Object System.Collections.Generic.List[string]; Notes = New-Object System.Collections.Generic.List[string] }
    try { & $Check }
    catch { Problem (ConvertTo-SafeText ($_.Exception.Message -replace '\s+', ' ') 300) }
    $ready = $script:current.Problems.Count -eq 0
    $detail = if ($ready) { $script:current.Notes -join '; ' } else { $script:current.Problems -join '; ' }
    $row = [pscustomobject]@{ Component = $Name; Status = $(if ($ready) { 'Ready' } else { 'Not ready' }); Detail = $detail }
    $results.Add($row)
    $color = if ($ready) { 'Green' } else { 'Red' }
    $shown = if ($detail.Length -gt 150) { $detail.Substring(0, 147) + '...' } else { $detail }
    Write-Host ('  {0,-26} ' -f $Name) -NoNewline
    Write-Host ('{0,-10}' -f $row.Status) -ForegroundColor $color -NoNewline
    Write-Host " $shown"
}

function Get-Arm([string]$Path, [string]$ApiVersion) {
    $r = Invoke-Arm -Method GET -Path $Path -ApiVersion $ApiVersion -AllowNotFound
    if ($r.Status -eq 404) { return $null }
    return $r.Body
}

function Get-Dv([string]$Path) { return (Invoke-Dataverse -OrgUrl $settings.DataverseUrl -Method GET -Path $Path).Body }

function Get-DvCount([string]$Entity, [string]$EntitySet, [string]$Conditions = '') {
    # FetchXML aggregate count: exact, and not capped at 5,000 like $count.
    $filter = if ($Conditions) { "<filter>$Conditions</filter>" } else { '' }
    $fetch = "<fetch aggregate='true'><entity name='$Entity'><attribute name='$($Entity)id' alias='n' aggregate='count'/>$filter</entity></fetch>"
    $body = Get-Dv "$($EntitySet)?fetchXml=$([uri]::EscapeDataString($fetch))"
    return [int](@($body.value)[0].n)
}

function Invoke-McpRpc([string]$Url, [hashtable]$Headers, [string]$Method, [hashtable]$Params) {
    # One JSON-RPC request to a stateless MCP endpoint (streamable HTTP, JSON or event-stream response).
    $payload = @{ jsonrpc = '2.0'; id = 1; method = $Method; params = $Params } | ConvertTo-Json -Depth 10 -Compress
    $h = @{ Accept = 'application/json, text/event-stream' }
    foreach ($k in $Headers.Keys) { $h[$k] = $Headers[$k] }
    $response = Invoke-WebRequest -Method Post -Uri $Url -Headers $h -Body $payload -ContentType 'application/json' -SkipHttpErrorCheck -TimeoutSec 90
    $text = if ($response.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($response.Content) } else { [string]$response.Content }
    if ($response.StatusCode -ge 400) { throw "HTTP $($response.StatusCode) from $(($Url -split '\?')[0]): $(ConvertTo-SafeText $text 200)" }
    if ("$($response.Headers['Content-Type'])" -match 'event-stream') {
        $text = (@($text -split "`n" | Where-Object { $_ -like 'data:*' }) | Select-Object -Last 1).Substring(5)
    }
    $json = $text | ConvertFrom-Json
    if ($json.error) { throw "MCP error $($json.error.code): $($json.error.message)" }
    return @{ Result = $json.result; CorrelationId = [string]($response.Headers['x-correlation-id'] | Select-Object -First 1) }
}

function Get-ToolNames($Value) {
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) { return @($Value) }
    if ($Value.PSObject.Properties['tool_names']) { return @($Value.tool_names) }
    return @($Value)
}

# ==== Inputs
Write-Host ''
Write-Host "Lab readiness check ($Mode) $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
$settings = Read-LabSettings -Path $SettingsPath
$seedManifestPath = Join-Path $SeedFolder 'manifest.json'
$seed = if (Test-Path $seedManifestPath) { Get-Content $seedManifestPath -Raw | ConvertFrom-Json -AsHashtable } else { $null }
$status = Get-StepStatus
$rgPath = "/subscriptions/$($settings.SubscriptionId)/resourceGroups/$($settings.ResourceGroup)"
$foundryPath = "$rgPath/providers/Microsoft.CognitiveServices/accounts/$($settings.FoundryResource)"
$projectPath = "$foundryPath/projects/$($settings.FoundryProject)"
$health = $null
$roleKeyTicket = if ($seed -and $seed.role_keys.humongous_claims_certificate) { [string]$seed.role_keys.humongous_claims_certificate } else { 'TCK-10524' }
$names = @('Golden Environment', 'Azure resources', 'Service Desk app and data', 'Tier 1 Technician', 'Foundry agent', 'MCP connections',
           'MCP server', 'Baseline read tool', 'Search export', 'Microsoft Purview')
Write-Host ''
if (-not $settings.DeploymentID -or -not $seed) {
    $why = if (-not $settings.DeploymentID) { "$SettingsPath is missing: provisioning has not finished" } else { "$seedManifestPath is missing: the seed step has not run" }
    foreach ($n in $names) { $script:current = $null; $results.Add([pscustomobject]@{ Component = $n; Status = 'Not ready'; Detail = $why }) }
    $results | ForEach-Object { Write-Host ('  {0,-26} ' -f $_.Component) -NoNewline; Write-Host 'Not ready ' -ForegroundColor Red -NoNewline; Write-Host " $($_.Detail)" }
}
else {
    # ==== 1. Golden Environment
    Test-Component 'Golden Environment' {
        $golden = $config.GoldenEnvironmentVersion
        Fact 'goldenEnvironmentVersion' $golden
        if ($settings.GoldenEnvironmentVersion -ne $golden) { Problem "lab-settings.json records '$($settings.GoldenEnvironmentVersion)', not $golden" }
        $vmTag = Get-LabTag 'msplab-golden-version'
        if ($vmTag -and $vmTag -ne $golden) { Problem "the lab VM was deployed from template version $vmTag, not $golden" }
        $tags = (Get-Arm $rgPath '2021-04-01').tags
        $expected = [ordered]@{
            'lab-golden-environment'   = $golden
            'lab-searchable-documents' = [string]$seed.searchable_documents.total
            'lab-new-incident-1'       = [string]@($seed.new_incidents)[0]
            'lab-new-incident-2'       = [string]@($seed.new_incidents)[1]
            'lab-mcp-release'          = [string]$config.McpRelease
        }
        foreach ($key in $expected.Keys) {
            $actual = if ($tags -and $tags.PSObject.Properties[$key]) { [string]$tags.$key } else { '' }
            if ($actual -ne $expected[$key]) { Problem "resource group tag $key is '$actual', expected '$($expected[$key])'" }
        }
        Fact 'resourceGroupTags' (($expected.Keys | ForEach-Object { "$_=$($expected[$_])" }) -join ',')
        $steps = @($status.Keys | Where-Object { $_ -ne 'overall' })
        $pending = if ($Mode -eq 'Provisioning') { @('readiness', 'finalize') } else { @() }
        $bad = @($steps | Where-Object { $_ -notin $pending -and $status[$_].state -ne 'Succeeded' })
        if ($bad.Count) { Problem "provisioning steps not succeeded: $(($bad | ForEach-Object { "$_ ($($status[$_].state))" }) -join ', ')" }
        if ($Mode -eq 'Participant') {
            if ($status['finalize'].state -ne 'Succeeded') { Problem 'the last provisioning step (finalize) has not succeeded' }
            $graph = Get-ManagedIdentityToken 'https://graph.microsoft.com'
            $held = @(Invoke-Graph -Method GET -Path "roleManagement/directory/roleAssignments?`$filter=principalId eq '$($settings.SeniorUserObjectId)'" -Token $graph -All)
            if ($held.Count) { Problem "the Senior Technician still holds $($held.Count) directory role assignment(s); provisioning removes them" }
        }
        Note "$golden; $($steps.Count) provisioning steps succeeded; resource group tags match the seed and MCP release $($config.McpRelease)"
    }

    # ==== 2. Azure resources
    Test-Component 'Azure resources' {
        $list = @((Invoke-Arm -Method GET -Path "$rgPath/resources" -ApiVersion '2021-04-01').Body.value)
        $want = [ordered]@{
            'Container App'              = @('Microsoft.App/containerApps', $settings.ContainerApp)
            'Container Apps environment' = @('Microsoft.App/managedEnvironments', '')
            'API Management'             = @('Microsoft.ApiManagement/service', $settings.ApimName)
            'Foundry'                    = @('Microsoft.CognitiveServices/accounts', $settings.FoundryResource)
            'AI Search'                  = @('Microsoft.Search/searchServices', $settings.SearchService)
            'storage account'            = @('Microsoft.Storage/storageAccounts', $settings.StorageAccount)
            'Key Vault'                  = @('Microsoft.KeyVault/vaults', $settings.KeyVault)
            'container registry'         = @('Microsoft.ContainerRegistry/registries', $settings.ContainerRegistry)
            'Log Analytics'              = @('Microsoft.OperationalInsights/workspaces', $settings.LogAnalyticsWorkspace)
            'Application Insights'       = @('Microsoft.Insights/components', $settings.AppInsights)
        }
        foreach ($label in $want.Keys) {
            $type, $name = $want[$label]
            if (-not ($list | Where-Object { $_.type -eq $type -and (-not $name -or $_.name -eq $name) })) { Problem "$label $name not found" }
        }
        $apim = Get-Arm "$rgPath/providers/Microsoft.ApiManagement/service/$($settings.ApimName)" $config.ApimApiVersion
        if ($apim.properties.provisioningState -ne 'Succeeded') { Problem "API Management is $($apim.properties.provisioningState)" }
        Fact 'apim.sku' "$($apim.sku.name) $($apim.sku.capacity)"
        $apis = @((Get-Arm "$rgPath/providers/Microsoft.ApiManagement/service/$($settings.ApimName)/apis" $config.ApimApiVersion).value.name | Sort-Object)
        foreach ($api in $config.ReadApi, $config.WriteApi, $config.DiagApi) { if ($apis -notcontains $api) { Problem "API Management has no API $api" } }
        Fact 'apim.apis' ($apis -join ',')
        $deployments = @((Get-Arm "$foundryPath/deployments" '2025-06-01').value)
        foreach ($d in @(@{ Name = $settings.ChatDeployment; Model = 'gpt-5.1' }, @{ Name = $settings.EmbeddingDeployment; Model = 'text-embedding-3-small' })) {
            $dep = $deployments | Where-Object { $_.name -eq $d.Name } | Select-Object -First 1
            if (-not $dep) { Problem "model deployment $($d.Name) not found" }
            elseif ($dep.properties.provisioningState -ne 'Succeeded') { Problem "model deployment $($d.Name) is $($dep.properties.provisioningState)" }
            else { Fact "deployment.$($d.Name)" "$($dep.properties.model.name) $($dep.properties.model.version) $($dep.sku.name)" }
        }
        if (-not (Get-Arm $projectPath '2025-06-01')) { Problem "Foundry project $($settings.FoundryProject) not found" }
        $search = Get-Arm "$rgPath/providers/Microsoft.Search/searchServices/$($settings.SearchService)" '2025-05-01'
        if ("$($search.properties.provisioningState)" -ne 'succeeded') { Problem "AI Search is $($search.properties.provisioningState)" }
        Fact 'search' "$($search.sku.name) localAuth=$(-not $search.properties.disableLocalAuth)"
        $app = Get-Arm "$rgPath/providers/Microsoft.App/containerApps/$($settings.ContainerApp)" '2026-07-01'
        if ($app.properties.provisioningState -ne 'Succeeded') { Problem "the Container App is $($app.properties.provisioningState)" }
        $vm = $list | Where-Object { $_.type -eq 'Microsoft.Compute/virtualMachines' } | Select-Object -First 1
        Fact 'region' $settings.Region
        Note "$($list.Count) resources in $($settings.ResourceGroup) ($($settings.Region)); $($settings.ChatDeployment) and $($settings.EmbeddingDeployment) deployed; API Management $($apim.sku.name) with $($apis.Count) APIs; lab VM $($vm.name)"
    }

    # ==== 3. Service Desk app and data
    Test-Component 'Service Desk app and data' {
        $null = Get-Dv 'WhoAmI'
        $app = @((Get-Dv "appmodules?`$select=uniquename&`$filter=uniquename eq '$($config.Dataverse.AppUniqueName)'").value)
        if (-not $app.Count) { Problem "the app $($config.Dataverse.AppUniqueName) is not in the environment" }
        $newIncidents = @($seed.new_incidents)
        $values = ($newIncidents | ForEach-Object { "<value>$_</value>" }) -join ''
        $annotationFile = ''
        $annotationsPath = Join-Path $SeedFolder 'annotations.json'
        if (Test-Path $annotationsPath) { $annotationFile = [string](@(Get-Content $annotationsPath -Raw | ConvertFrom-Json)[0]._match.filename) }
        $tables = [ordered]@{
            businesscalendars  = @('spk_businesscalendar', 'spk_businesscalendars', "<condition attribute='spk_calendarcode' operator='not-null'/>")
            slapolicies        = @('spk_slapolicy', 'spk_slapolicies', "<condition attribute='spk_policycode' operator='not-null'/>")
            technicians        = @('spk_technician', 'spk_technicians', "<condition attribute='spk_techniciancode' operator='not-null'/>")
            accounts           = @('account', 'accounts', "<condition attribute='spk_customercode' operator='not-null'/>")
            contacts           = @('contact', 'contacts', "<condition attribute='spk_contactcode' operator='not-null'/>")
            customerprocedures = @('spk_customerprocedure', 'spk_customerprocedures', "<condition attribute='spk_procedurecode' operator='not-null'/>")
            customerdocuments  = @('spk_customerdocument', 'spk_customerdocuments', "<condition attribute='spk_documentcode' operator='not-null'/>")
            runbooks           = @('spk_runbook', 'spk_runbooks', "<condition attribute='spk_runbookcode' operator='not-null'/>")
            knowledgearticles  = @('spk_knowledgearticle', 'spk_knowledgearticles', "<condition attribute='spk_articlenumber' operator='not-null'/>")
            tickets            = @('spk_ticket', 'spk_tickets', "<condition attribute='spk_ticketnumber' operator='not-null'/><condition attribute='spk_ticketnumber' operator='not-in'>$values</condition>")
            ticketnotes        = @('spk_ticketnote', 'spk_ticketnotes', "<condition attribute='spk_notecode' operator='like' value='%-N%'/>")
            annotations        = @('annotation', 'annotations', "<condition attribute='filename' operator='eq' value='$([Security.SecurityElement]::Escape($annotationFile))'/>")
        }
        $differences = @()
        foreach ($key in $tables.Keys) {
            $entity, $set, $conditions = $tables[$key]
            $actual = Get-DvCount $entity $set $conditions
            $expectedCount = [int]$seed.counts[$key]
            Fact "count.$key" $actual
            if ($actual -ne $expectedCount) { $differences += "$key $actual (expected $expectedCount)" }
        }
        if ($differences.Count) { Problem "seeded rows differ from the manifest: $($differences -join ', ')" }
        $loaded = Get-DvCount 'spk_ticket' 'spk_tickets' "<condition attribute='spk_ticketnumber' operator='in'>$values</condition>"
        if ($loaded -ne $newIncidents.Count) { Problem "new incidents $($newIncidents -join ', '): $loaded of $($newIncidents.Count) loaded" }
        Fact 'newIncidents' ($newIncidents -join ',')
        Note "app $($config.Dataverse.AppUniqueName); $($seed.counts.tickets) tickets, $($seed.counts.ticketnotes) notes, $($seed.counts.knowledgearticles) articles, $($seed.counts.customerdocuments) customer documents and every other seeded table at its manifest count; new incidents $($newIncidents -join ' and ')"
    }

    # ==== 4. Tier 1 Technician
    Test-Component 'Tier 1 Technician' {
        $graph = Get-ManagedIdentityToken 'https://graph.microsoft.com'
        $upn = $settings.Tier1User
        $user = Invoke-Graph -Method GET -Path "users/$([uri]::EscapeDataString($upn))?`$select=id,userPrincipalName,accountEnabled" -Token $graph -AllowNotFound
        if ($user.Status -eq 404) { Problem "the account $upn does not exist"; return }
        $oid = [string]$user.Body.id
        if (-not $user.Body.accountEnabled) { Problem "the account $upn is disabled" }
        $licenses = @(Invoke-Graph -Method GET -Path "users/$oid/licenseDetails?`$select=skuPartNumber" -Token $graph -All)
        if (-not $licenses.Count) { Problem "$upn has no license" }
        $held = @(Invoke-Graph -Method GET -Path "roleManagement/directory/roleAssignments?`$filter=principalId eq '$oid'" -Token $graph -All)
        if ($held.Count) { Problem "$upn holds a directory role" }
        $dvUser = Invoke-Dataverse -OrgUrl $settings.DataverseUrl -Method GET -Path "systemusers(azureactivedirectoryobjectid=$oid)?`$select=systemuserid,isdisabled" -AllowNotFound
        if (-not $dvUser) { Problem "$upn is not a user of the Service Desk environment"; return }
        if ($dvUser.Body.isdisabled) { Problem "$upn is disabled in the Service Desk environment" }
        $roles = @((Get-Dv "systemusers($($dvUser.Body.systemuserid))/systemuserroles_association?`$select=name").value.name)
        $wanted = 'Service Desk Tier 1 Technician'
        if ($roles -notcontains $wanted) { Problem "$upn does not hold $wanted (holds: $($roles -join ', '))" }
        $extra = @($roles | Where-Object { $_ -ne $wanted })
        if ($extra.Count) { Problem "$upn also holds $($extra -join ', ')" }
        $foundryRole = Get-LabTag 'msplab-tier1-foundry-role' 'Foundry Agent Consumer'
        $foundryRoleId = if ($foundryRole -eq 'Foundry User') { '53ca6127-db72-4b80-b1b0-d745d6d5456d' } else { 'eed3b665-ab3a-47b6-8f48-c9382fb1dad6' }
        $assignments = @((Invoke-Arm -Method GET -Path "$projectPath/providers/Microsoft.Authorization/roleAssignments?`$filter=principalId eq '$oid'" -ApiVersion '2022-04-01').Body.value)
        if (-not ($assignments | Where-Object { $_.properties.roleDefinitionId -like "*/$foundryRoleId" })) { Problem "$upn has no $foundryRole role on the Foundry project" }
        Fact 'tier1' "$wanted;$foundryRole"
        Note "$upn ($(@($licenses.skuPartNumber) -join ', ')): Dataverse role $wanted only, $foundryRole on the project, no directory role"
    }

    # ==== 5. Foundry agent
    Test-Component 'Foundry agent' {
        $r = Invoke-LabRest -Method GET -Uri "$($settings.FoundryProjectEndpoint.TrimEnd('/'))/agents/$($settings.AgentName)?api-version=v1" `
            -Token (Get-ManagedIdentityToken 'https://ai.azure.com') -AllowNotFound
        if ($r.Status -eq 404) { Problem "the agent $($settings.AgentName) does not exist"; return }
        $agent = $r.Body
        $identity = if ($agent.instance_identity) { $agent.instance_identity } else { $agent.versions.latest.instance_identity }
        if (-not $identity -or -not $identity.client_id) { Problem 'the agent has no Microsoft Entra Agent ID (instance_identity)' }
        elseif ($settings.AgentId -and $identity.client_id -ne $settings.AgentId) { Problem "the Agent ID is $($identity.client_id), but lab-settings.json records $($settings.AgentId)" }
        $definition = $agent.versions.latest.definition
        $tools = @($definition.tools)
        $read = $tools | Where-Object { $_.type -eq 'mcp' -and $_.server_label -eq $settings.McpReadConnection } | Select-Object -First 1
        $write = $tools | Where-Object { $_.type -eq 'mcp' -and $_.server_label -eq $settings.McpWriteConnection } | Select-Object -First 1
        $allowed = @()
        if (-not $read) { Problem "the MCP tool $($settings.McpReadConnection) is missing" }
        else {
            $allowed = @(Get-ToolNames $read.allowed_tools)
            if ($read.require_approval -ne 'never') { Problem "$($settings.McpReadConnection) approval is '$($read.require_approval)', not never" }
            if ($read.project_connection_id -ne $settings.McpReadConnection) { Problem "$($settings.McpReadConnection) uses the connection $($read.project_connection_id)" }
            if ($read.server_url -ne $settings.McpReadGatewayUrl) { Problem "$($settings.McpReadConnection) calls $($read.server_url), not the read gateway" }
            $missing = @($config.ReadTools | Where-Object { $_ -notin $allowed })
            $added = @($allowed | Where-Object { $_ -notin $config.ReadTools })
            if (-not $allowed.Count) { Problem "$($settings.McpReadConnection) has no allowed_tools list, so any tool on the read endpoint would run without approval" }
            elseif ($Mode -eq 'Provisioning' -and ($missing.Count -or $added.Count)) { Problem "allowed_tools differ from the read catalog: missing $($missing -join ', '); extra $($added -join ', ')" }
        }
        if (-not $write) { Problem "the MCP tool $($settings.McpWriteConnection) is missing" }
        else {
            if ($write.require_approval -ne 'always') { Problem "$($settings.McpWriteConnection) does not ask for approval on every call ($($write.require_approval | ConvertTo-Json -Compress))" }
            if ($write.project_connection_id -ne $settings.McpWriteConnection) { Problem "$($settings.McpWriteConnection) uses the connection $($write.project_connection_id)" }
            if ($write.server_url -ne $settings.McpWriteGatewayUrl) { Problem "$($settings.McpWriteConnection) calls $($write.server_url), not the write gateway" }
            if ($Mode -eq 'Provisioning' -and @(Get-ToolNames $write.allowed_tools).Count) { Problem "$($settings.McpWriteConnection) lists allowed_tools; the baseline lists none" }
        }
        $knowledge = @($tools | Where-Object { $_.type -eq 'azure_ai_search' })
        if ($Mode -eq 'Provisioning' -and $knowledge.Count) { Problem 'the baseline agent must have no knowledge tool' }
        $named = Get-Arm "$rgPath/providers/Microsoft.ApiManagement/service/$($settings.ApimName)/namedValues/agent-id" $config.ApimApiVersion
        if ($identity.client_id -and [string]$named.properties.value -ne [string]$identity.client_id) { Problem "the API Management named value agent-id is '$($named.properties.value)', not the Agent ID" }
        Fact 'agent' "$($definition.model);reasoning=$($definition.reasoning.effort);read=$((@($allowed) | Sort-Object) -join ',');readApproval=$($read.require_approval);writeApproval=$($write.require_approval)"
        Note ("$($settings.AgentName) version $($agent.versions.latest.version), Agent ID $($identity.client_id); $($settings.McpReadConnection) ($($allowed.Count) read tools, no approval) and " +
              "$($settings.McpWriteConnection) (approval on every call); $(if ($knowledge.Count) { 'knowledge source added' } else { 'no knowledge source yet' })")
    }

    # ==== 6. MCP connections
    Test-Component 'MCP connections' {
        foreach ($c in @(@{ Name = $settings.McpReadConnection; Target = $settings.McpReadGatewayUrl }, @{ Name = $settings.McpWriteConnection; Target = $settings.McpWriteGatewayUrl })) {
            $connection = $null
            foreach ($apiVersion in $config.ConnectionApiVersions) {
                try { $connection = Get-Arm "$projectPath/connections/$($c.Name)" $apiVersion } catch { $connection = $null }
                if ($connection) { break }
            }
            if (-not $connection) { Problem "the connection $($c.Name) does not exist"; continue }
            $p = $connection.properties
            if ($p.category -ne 'RemoteTool' -or $p.authType -ne 'OAuth2') { Problem "$($c.Name) is $($p.category)/$($p.authType), not RemoteTool with OAuth identity passthrough" }
            if ($p.target -ne $c.Target) { Problem "$($c.Name) points at $($p.target), not $($c.Target)" }
        }
        $graph = Get-ManagedIdentityToken 'https://graph.microsoft.com'
        $app = @(Invoke-Graph -Method GET -Path "applications?`$filter=appId eq '$($settings.McpGatewayAppId)'&`$select=id,appId,identifierUris,web,api" -Token $graph -All) | Select-Object -First 1
        if (-not $app) { Problem "the gateway app $($settings.McpGatewayAppId) does not exist" }
        else {
            if (@($app.identifierUris) -notcontains $settings.McpGatewayAudience) { Problem "the gateway app does not have the identifier URI $($settings.McpGatewayAudience)" }
            if (-not (@($app.api.oauth2PermissionScopes) | Where-Object { $_.value -eq $settings.McpGatewayScope -and $_.isEnabled })) { Problem "the gateway app has no enabled scope $($settings.McpGatewayScope)" }
            if (-not @($app.web.redirectUris).Count) { Problem 'the gateway app has no redirect URI, so consent would fail (setup/tenant/RUNBOOK.md, Register the OAuth redirect URL)' }
            $sp = @(Invoke-Graph -Method GET -Path "servicePrincipals?`$filter=appId eq '$($settings.McpGatewayAppId)'&`$select=id" -Token $graph -All) | Select-Object -First 1
            $grants = if ($sp) { @(Invoke-Graph -Method GET -Path "oauth2PermissionGrants?`$filter=clientId eq '$($sp.id)'" -Token $graph -All) } else { @() }
            if (-not ($grants | Where-Object { $_.consentType -eq 'AllPrincipals' -and " $($_.scope) " -like "* $($settings.McpGatewayScope) *" })) {
                Problem "no tenant-wide consent for $($settings.McpGatewayScope) on the gateway app"
            }
        }
        $named = Get-Arm "$rgPath/providers/Microsoft.ApiManagement/service/$($settings.ApimName)/namedValues/mcp-gateway-app-id" $config.ApimApiVersion
        if ([string]$named.properties.value -ne [string]$settings.McpGatewayAppId) { Problem "the API Management named value mcp-gateway-app-id is '$($named.properties.value)', not the gateway app" }
        Fact 'connections' "$($settings.McpReadConnection),$($settings.McpWriteConnection);RemoteTool;OAuth2;scope=$($settings.McpGatewayScope)"
        Note "$($settings.McpReadConnection) and $($settings.McpWriteConnection): OAuth identity passthrough to the read and write gateways; gateway app consented for $($settings.McpGatewayScope); $(@($app.web.redirectUris).Count) redirect URI(s)"
    }

    # ==== 7. MCP server
    Test-Component 'MCP server' {
        $script:health = Invoke-RestMethod -Uri "$($settings.McpServerUrl.TrimEnd('/'))/health" -TimeoutSec 30
        $h = $script:health
        if ($h.status -ne 'ok') { Problem "/health reports status '$($h.status)'" }
        if ("$($h.gateway_key_source)" -ne 'key vault') { Problem "the gateway key came from '$($h.gateway_key_source)', not Key Vault" }
        if ($h.user_impersonation -ne $true) { Problem 'user impersonation is off, so writes would not run as the signed-in user' }
        $version = [string]$h.version
        $line = ($config.McpRelease -split '\.')[0..1] -join '.'
        if ($Mode -eq 'Provisioning' -and $version -ne $config.McpRelease) { Problem "version $version is running, expected $($config.McpRelease)" }
        elseif ($version -notlike "$line.*") { Problem "version $version is not a $line.x release" }
        $app = Get-Arm "$rgPath/providers/Microsoft.App/containerApps/$($settings.ContainerApp)" '2026-07-01'
        $revision = [string]$app.properties.latestReadyRevisionName
        if ($Mode -eq 'Provisioning' -and $revision -notlike "$($settings.ContainerApp)--$($config.McpBaselineRevisionPrefix)-*") { Problem "the active revision $revision is not the baseline revision" }
        Fact 'mcpServer' "keySource=$($h.gateway_key_source);impersonation=$($h.user_impersonation);release=$($config.McpRelease)"
        Note "version $version on revision $revision; gateway key from Key Vault; acts on behalf of the signed-in user"
    }

    # ==== 8. Baseline read tool
    Test-Component 'Baseline read tool' {
        $secretName = if ($settings.ApimDiagnosticsKeySecret) { $settings.ApimDiagnosticsKeySecret } else { 'apim-diagnostics-key' }
        $key = Get-KeyVaultSecret -VaultUri $settings.KeyVaultUrl -Name $secretName
        if (-not $key) { Problem "the diagnostics subscription key is not in Key Vault ($secretName)"; return }
        $headers = @{ 'Ocp-Apim-Subscription-Key' = [Net.NetworkCredential]::new('', $key).Password; 'x-correlation-id' = [guid]::NewGuid().ToString() }
        $call = Invoke-McpRpc $settings.McpDiagnosticsUrl $headers 'tools/call' @{ name = 'get_ticket'; arguments = @{ ticket_number = $roleKeyTicket } }
        $result = $call.Result
        $payload = if ($result.structuredContent) { $result.structuredContent } else { @($result.content | Where-Object { $_.type -eq 'text' })[0].text | ConvertFrom-Json }
        if ($result.isError -or $payload.ok -ne $true) { Problem "get_ticket returned an error: $($payload.error.code) $($payload.error.message)"; return }
        $text = $payload | ConvertTo-Json -Depth 12 -Compress
        $customer = [string]$seed.scenarios.humongous_claims_certificate.customer
        if ($text -notmatch [regex]::Escape($roleKeyTicket)) { Problem "the result does not contain $roleKeyTicket" }
        if ($customer -and $text -notmatch [regex]::Escape($customer)) { Problem "the result does not name the customer $customer" }
        $correlationId = [string]$payload.correlation_id
        if (-not $correlationId) { Problem 'the result has no correlation_id' }
        Fact 'baselineRead' "get_ticket;$roleKeyTicket;$customer"
        Note "get_ticket $roleKeyTicket returned $customer through the diagnostics API (correlation ID $correlationId)"
    }

    # ==== 9. Search export
    Test-Component 'Search export' {
        $expectedTotal = [int]$seed.searchable_documents.total
        $blobs = @(Get-BlobNames -Account $settings.StorageAccount -Container $settings.ExportContainer)
        if ($blobs.Count -ne $expectedTotal) { Problem "the export container holds $($blobs.Count) documents, expected $expectedTotal" }
        foreach ($n in @($seed.new_incidents)) { if ($blobs -contains "ticket-$n.json") { Problem "the new incident $n was exported; it must never be indexed" } }
        $manifestPath = if ($settings.ExportManifest) { $settings.ExportManifest } else { 'C:\LabFiles\search\export-manifest.json' }
        $byType = ''
        if (-not (Test-Path $manifestPath)) { Problem "the export manifest $manifestPath is missing" }
        else {
            $m = Get-Content $manifestPath -Raw | ConvertFrom-Json -AsHashtable
            if ([int]$m.total -ne $expectedTotal) { Problem "the export manifest total is $($m.total), expected $expectedTotal" }
            foreach ($key in @($seed.searchable_documents.Keys | Where-Object { $_ -ne 'total' })) {
                if ([int]$m.countsByKey[$key] -ne [int]$seed.searchable_documents[$key]) { Problem "export manifest $key is $($m.countsByKey[$key]), expected $($seed.searchable_documents[$key])" }
            }
            $byType = ($m.counts.Keys | ForEach-Object { "$($m.counts[$_]) $_" }) -join ', '
        }
        if (-not (Test-Path 'C:\LabFiles\search\sample-documents\kb-KB0058.json')) { Problem 'C:\LabFiles\search\sample-documents\kb-KB0058.json is missing' }
        Fact 'export' "total=$expectedTotal;$((@($seed.searchable_documents.Keys | Sort-Object) | ForEach-Object { "$_=$($seed.searchable_documents[$_])" }) -join ';')"
        Note "$($blobs.Count) documents in $($settings.StorageAccount)/$($settings.ExportContainer) ($byType); the new incidents are not exported"
    }

    # ==== 10. Microsoft Purview
    Test-Component 'Microsoft Purview' {
        if ($status['purview'].state -ne 'Succeeded') { Problem "the Purview provisioning step is $(if ($status['purview']) { $status['purview'].state } else { 'missing' })" }
        if (-not $settings.SensitivityLabelId) { Problem 'no sensitivity label was recorded by provisioning'; return }
        if (-not $settings.PurviewDlpPolicy) { Problem 'no DLP policy was recorded by provisioning' }
        $graph = Get-ManagedIdentityToken 'https://graph.microsoft.com'
        $labels = @(Invoke-Graph -Method GET -Path 'security/informationProtection/sensitivityLabels' -Token $graph -All -Version 'beta')
        $published = @($labels | Where-Object { $_.id -eq $settings.SensitivityLabelId }).Count -gt 0
        # Publishing a new label takes up to 24 hours; only a label still missing after that is a problem.
        $createdOn = [datetime]::MinValue
        $time = $status['purview'].time
        if ($time -is [datetime]) { $createdOn = $time.ToUniversalTime() }
        elseif ($time) { $createdOn = [datetime]::Parse([string]$time, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal) }
        $hours = ((Get-Date).ToUniversalTime() - $createdOn).TotalHours
        if (-not $published -and $Mode -eq 'Participant' -and $hours -gt 24) { Problem "the label $($settings.SensitivityLabelName) is not published to the tenant $([int]$hours) hours after provisioning created it" }
        $annotationsPath = Join-Path $SeedFolder 'annotations.json'
        $file = if (Test-Path $annotationsPath) { [string](@(Get-Content $annotationsPath -Raw | ConvertFrom-Json)[0]._match.filename) } else { '' }
        if ($file) {
            $doc = @((Get-Dv "annotations?`$select=notetext&`$filter=filename eq '$($file.Replace("'", "''"))'").value) | Select-Object -First 1
            if (-not $doc) { Problem "the configuration document $file is missing" }
            elseif ("$($doc.notetext)" -notlike "*Sensitivity label: $($settings.SensitivityLabelName)*") { Problem "the configuration document $file carries no sensitivity label" }
        }
        $serverView = if ($script:health -and $script:health.purview) { ConvertTo-SafeText ($script:health.purview | ConvertTo-Json -Depth 3 -Compress) 120 } else { 'not reported' }
        Fact 'purview' "label=$($settings.SensitivityLabelName);dlp=$($settings.PurviewDlpPolicy)"
        Note ("label $($settings.SensitivityLabelName) $(if ($published) { 'published' } else { "created $([int]$hours) hours ago (publishing takes up to 24 hours)" }); " +
              "DLP policy '$($settings.PurviewDlpPolicy)' for the MCP server's app; configuration document labeled; MCP server Purview status: $serverView")
    }
}

# ==== Reports
New-Item -ItemType Directory -Path $ReportFolder -Force | Out-Null
$ready = @($results | Where-Object { $_.Status -ne 'Ready' }).Count -eq 0
$canonical = ($facts.Keys | Sort-Object | ForEach-Object { "$_=$($facts[$_])" }) -join "`n"
$fingerprint = ([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($canonical)) | ForEach-Object { $_.ToString('x2') }) -join ''
$resultsPath = Join-Path $ReportFolder 'readiness-report.json'
$reportPath = Join-Path $ReportFolder 'consistency-report.json'
ConvertTo-Json -InputObject @($results) -Depth 4 | Set-Content -Path $resultsPath -Encoding utf8NoBOM
$report = [ordered]@{
    deploymentId             = $settings.DeploymentID
    goldenEnvironmentVersion = $config.GoldenEnvironmentVersion
    mode                     = $Mode
    ready                    = $ready
    checkedOnUtc             = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    durationSeconds          = [math]::Round(((Get-Date) - $started).TotalSeconds)
    seedAnchor               = if ($seed) { $seed.anchor } else { $null }
    fingerprint              = $fingerprint
    fingerprintNote          = 'SHA-256 of the sorted facts below; identical for every environment built from the same Golden Environment, until the participant changes it'
    components               = @($results)
    facts                    = $facts
}
$report | ConvertTo-Json -Depth 6 | Set-Content -Path $reportPath -Encoding utf8NoBOM

Write-Host ''
Write-Host "Golden Environment $($config.GoldenEnvironmentVersion), fingerprint $($fingerprint.Substring(0, 12)). Report: $reportPath"
if ($ready) { Write-Host 'Every component is ready. You can start Exercise 1.' -ForegroundColor Green }
else {
    $names = (@($results | Where-Object { $_.Status -ne 'Ready' }).Component) -join ', '
    Write-Host "Not ready: $names. Run the check again in five minutes. If a component is still not ready, contact CloudLabs support and quote your Deployment ID $($settings.DeploymentID)." -ForegroundColor Red
}

if ($PassThru) {
    return [pscustomobject]@{
        Ready                    = $ready
        Components               = @($results)
        GoldenEnvironmentVersion = $config.GoldenEnvironmentVersion
        Fingerprint              = $fingerprint
        ShortFingerprint         = $fingerprint.Substring(0, 12)
        ReportPath               = $reportPath
        ResultsPath              = $resultsPath
    }
}
exit $(if ($ready) { 0 } else { 1 })
