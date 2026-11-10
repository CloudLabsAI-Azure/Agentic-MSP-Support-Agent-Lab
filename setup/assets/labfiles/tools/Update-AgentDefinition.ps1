#Requires -Version 7.0
<#
.SYNOPSIS
    Adds the servicedesk-knowledge index to your agent as a new agent version, keeping both Service
    Desk MCP tools exactly as they are. The fallback for Exercise 1, Task 2 when the portal path to
    add knowledge differs from the guide.

.DESCRIPTION
    Without switches the script:
      1. reads the latest version of your agent (msp-support-agent),
      2. keeps its instructions, its model settings and its two MCP tools unchanged:
           servicedesk-read   read tools only, no approval, limited to its allowed_tools list
           servicedesk-write  write tools, your approval on every call
      3. adds one Azure AI Search tool on the index servicedesk-knowledge, through the project
         connection 'search' that lab provisioning created (Microsoft Entra ID, no key), and
      4. saves the result as a new agent version and prints its number.

    -Instructions  also replaces the instructions with the grounded instructions
                   (C:\LabFiles\agent\instructions-grounded.md), which tell the agent to answer from
                   the index and cite every source.
    -Reset         goes back to the baseline the lab started with: the definition of your agent's
                   first version, with both MCP tools and no knowledge tool.

    Agent versions can't be edited: every change is a new version, and by default your agent serves
    the latest one. If you pinned a version in the portal, the script tells you how to serve the new
    one. Safe to run again: when the latest version already matches, it creates nothing.

    The script refuses to copy a definition whose write tool no longer asks for approval: every
    write must be approved by the person who asks.

    Uses your own Azure CLI sign-in. Run 'az login' first and sign in as the Senior Technician
    (Foundry User on the project, Reader on the Foundry resource).

.EXAMPLE
    C:\LabFiles\tools\Update-AgentDefinition.ps1

.EXAMPLE
    C:\LabFiles\tools\Update-AgentDefinition.ps1 -Instructions

.EXAMPLE
    C:\LabFiles\tools\Update-AgentDefinition.ps1 -Reset
#>
[CmdletBinding(DefaultParameterSetName = 'Knowledge', SupportsShouldProcess)]
param(
    [Parameter(ParameterSetName = 'Knowledge')][switch]$Instructions,
    [Parameter(ParameterSetName = 'Knowledge')][string]$InstructionsPath = 'C:\LabFiles\agent\instructions-grounded.md',
    [Parameter(ParameterSetName = 'Knowledge')]
    [ValidateSet('simple', 'vector', 'semantic', 'vector_simple_hybrid', 'vector_semantic_hybrid')]
    [string]$QueryType = 'vector_semantic_hybrid',
    [Parameter(ParameterSetName = 'Knowledge')][ValidateRange(1, 50)][int]$TopK = 5,
    [Parameter(ParameterSetName = 'Knowledge')][string]$SearchConnectionName = 'search',
    [Parameter(ParameterSetName = 'Reset', Mandatory)][switch]$Reset,
    [Parameter(ParameterSetName = 'Reset')][string]$BaselineInstructionsPath = 'C:\LabFiles\agent\instructions-baseline.md',
    # Create a version even when the latest one already matches.
    [switch]$Force,
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json'
)

$ErrorActionPreference = 'Stop'
$ConnectionApiVersion = '2025-06-01'

function Write-Section([string]$Text) { Write-Host ''; Write-Host "==== $Text" -ForegroundColor Cyan }
function Write-Ok([string]$Text) { Write-Host "  [ok] $Text" -ForegroundColor Green }
function Write-Note([string]$Text) { Write-Host "  $Text" }
function Write-Caution([string]$Text) { Write-Host "  [check] $Text" -ForegroundColor Yellow }
function Stop-Script([string]$Text) { Write-Host ''; Write-Host "Stopped: $Text" -ForegroundColor Red; exit 1 }

function Read-LabSettings([string]$Path, [string[]]$Required) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "The lab settings file $Path was not found. Lab provisioning writes it; contact CloudLabs support if it is missing." }
    try { $s = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { throw "The lab settings file $Path is not valid JSON ($($_.Exception.Message)). Contact CloudLabs support." }
    $missing = @($Required | Where-Object { -not $s.PSObject.Properties[$_] -or [string]::IsNullOrWhiteSpace([string]$s.$_) })
    if ($missing.Count) { throw "The lab settings file $Path has no value for: $($missing -join ', '). Contact CloudLabs support." }
    return $s
}

function Get-AzCliToken([string]$Resource, [string]$TenantId) {
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) was not found on this machine. Use the lab VM, where it is installed.' }
    $cliArgs = @('account', 'get-access-token', '--resource', $Resource, '--query', 'accessToken', '--output', 'tsv')
    if ($TenantId) { $cliArgs += @('--tenant', $TenantId) }
    $token = & az @cliArgs 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace("$token")) {
        throw "Azure CLI has no sign-in for your lab tenant. Run 'az login', sign in as the Senior Technician, and run this script again."
    }
    return ("$token").Trim()
}

function Invoke-Foundry([string]$Method, [string]$Path, $Body) {
    $params = @{ Method = $Method; Uri = "$($script:ProjectEndpoint)/$Path"; Headers = @{ Authorization = "Bearer $($script:FoundryToken)" }
                 SkipHttpErrorCheck = $true; StatusCodeVariable = 'httpStatus'; TimeoutSec = 120 }
    if ($null -ne $Body) { $params.Body = ($Body | ConvertTo-Json -Depth 50); $params.ContentType = 'application/json; charset=utf-8' }
    try { $result = Invoke-RestMethod @params }
    catch { throw "The Foundry project endpoint could not be reached: $($_.Exception.Message)" }
    return [pscustomobject]@{ Status = [int]$httpStatus; Body = $result }
}

function Get-ErrorText($Response) {
    if ($Response.Body.error.message) { return [string]$Response.Body.error.message }
    if ($Response.Body) { return (($Response.Body | ConvertTo-Json -Depth 5 -Compress) -replace '\s+', ' ') }
    return "HTTP $($Response.Status)"
}

function Copy-Json($Object) { return ($Object | ConvertTo-Json -Depth 50 | ConvertFrom-Json) }
function Set-Property($Object, [string]$Name, $Value) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }

function ConvertTo-Canonical($Value) {
    # Same content, same text: properties sorted by name, empty values dropped, so a definition
    # the service returns with another property order or added nulls still compares equal.
    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [ValueType]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) { $Value = [pscustomobject]$Value }
    if ($Value -is [System.Collections.IEnumerable]) { return ,@($Value | ForEach-Object { ConvertTo-Canonical $_ }) }
    $ordered = [ordered]@{}
    foreach ($p in ($Value.PSObject.Properties | Sort-Object Name)) {
        $v = ConvertTo-Canonical $p.Value
        if ($null -eq $v -or ($v -is [string] -and $v -eq '')) { continue }
        $ordered[$p.Name] = $v
    }
    return [pscustomobject]$ordered
}

function Get-SearchSummary($Definition) {
    $t = @($Definition.tools) | Where-Object { $_ -and $_.type -eq 'azure_ai_search' } | Select-Object -First 1
    if (-not $t) { return '' }
    $ix = @($t.azure_ai_search.indexes) | Select-Object -First 1
    return "$(([string]$ix.project_connection_id).Split('/')[-1])|$($ix.index_name)|$($ix.query_type)|$($ix.top_k)"
}

function Test-SameDefinition($A, $B) {
    # Equal when everything except the search tool is identical and the search tool points at the
    # same connection and index with the same query type and result count.
    $strip = { param($d) $c = Copy-Json $d; Set-Property $c 'tools' @(@($c.tools) | Where-Object { $_ -and $_.type -ne 'azure_ai_search' }); ConvertTo-Canonical $c }
    $left = (& $strip $A) | ConvertTo-Json -Depth 50 -Compress
    $right = (& $strip $B) | ConvertTo-Json -Depth 50 -Compress
    return ($left -eq $right) -and ((Get-SearchSummary $A) -eq (Get-SearchSummary $B))
}

function Get-ToolNames($Value) {
    # allowed_tools and approval lists come as a plain list or as {"tool_names": [...]}.
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) { return @($Value) }
    if ($Value.PSObject.Properties['tool_names']) { return @($Value.tool_names) }
    return @($Value)
}

function Format-Approval($Value) {
    if ($null -eq $Value) { return 'always (default)' }
    if ($Value -is [string]) { return $Value }
    $parts = @()
    if ($Value.PSObject.Properties['always']) { $parts += "always for $(@(Get-ToolNames $Value.always).Count) tool(s)" }
    if ($Value.PSObject.Properties['never']) { $parts += "never for $(@(Get-ToolNames $Value.never).Count) tool(s)" }
    if ($parts.Count) { return ($parts -join ', ') }
    return ($Value | ConvertTo-Json -Depth 5 -Compress)
}

function Test-WriteApproval($Tool) {
    # True when every call on the tool needs approval: "always", the default, or an "always" list
    # with no "never" exemptions.
    $value = $Tool.require_approval
    if ($null -eq $value) { return $true }
    if ($value -is [string]) { return ($value -eq 'always') }
    if ($value.PSObject.Properties['never'] -and @(Get-ToolNames $value.never).Count) { return $false }
    return [bool]$value.PSObject.Properties['always']
}

function Show-Tools($Definition) {
    $rows = foreach ($t in @($Definition.tools)) {
        switch ($t.type) {
            'mcp' {
                $allowed = @(Get-ToolNames $t.allowed_tools)
                [pscustomobject]@{
                    Tool       = $t.server_label
                    Type       = 'MCP'
                    Connection = $t.project_connection_id
                    Approval   = Format-Approval $t.require_approval
                    Scope      = if ($allowed.Count) { "$($allowed.Count) allowed tools: $($allowed -join ', ')" } else { 'every tool the endpoint lists' }
                }
            }
            'azure_ai_search' {
                $ix = @($t.azure_ai_search.indexes) | Select-Object -First 1
                [pscustomobject]@{
                    Tool       = 'Azure AI Search'
                    Type       = 'Knowledge'
                    Connection = ([string]$ix.project_connection_id).Split('/')[-1]
                    Approval   = 'not used'
                    Scope      = "index $($ix.index_name), $($ix.query_type), top $($ix.top_k)"
                }
            }
            default { [pscustomobject]@{ Tool = $t.type; Type = $t.type; Connection = ''; Approval = ''; Scope = '' } }
        }
    }
    $rows | Format-Table -Wrap -AutoSize | Out-String -Width 220 | Write-Host
}

function Find-SearchConnection($Settings) {
    $projectId = "/subscriptions/$($Settings.SubscriptionId)/resourceGroups/$($Settings.ResourceGroup)/providers/Microsoft.CognitiveServices/accounts/$($Settings.FoundryResource)/projects/$($Settings.FoundryProject)"
    $target = ([string]$Settings.SearchEndpoint).TrimEnd('/')
    $json = & az rest --method get --uri "https://management.azure.com$projectId/connections/$($SearchConnectionName)?api-version=$ConnectionApiVersion" --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and $json) {
        $c = ($json -join "`n") | ConvertFrom-Json
        if ($c.properties.category -eq 'CognitiveSearch') {
            if (([string]$c.properties.target).TrimEnd('/') -ne $target) { Write-Caution "Connection '$($c.name)' targets $($c.properties.target), not $target." }
            return [pscustomobject]@{ Id = [string]$c.id; Name = [string]$c.name; AuthType = [string]$c.properties.authType; Checked = $true }
        }
    }
    $json = & az rest --method get --uri "https://management.azure.com$projectId/connections?api-version=$ConnectionApiVersion" --output json 2>$null
    if ($LASTEXITCODE -eq 0 -and $json) {
        $list = ($json -join "`n") | ConvertFrom-Json
        $c = @($list.value) | Where-Object { $_.properties.category -eq 'CognitiveSearch' -and ([string]$_.properties.target).TrimEnd('/') -eq $target } | Select-Object -First 1
        if ($c) { return [pscustomobject]@{ Id = [string]$c.id; Name = [string]$c.name; AuthType = [string]$c.properties.authType; Checked = $true } }
        throw "The project $($Settings.FoundryProject) has no Azure AI Search connection to $target. Lab provisioning creates it (named '$SearchConnectionName'); contact CloudLabs support."
    }
    Write-Caution "Could not read the project's connections (Reader on the Foundry resource is needed for that check). Using the connection ID of '$SearchConnectionName' as provisioning creates it."
    return [pscustomobject]@{ Id = "$projectId/connections/$SearchConnectionName"; Name = $SearchConnectionName; AuthType = ''; Checked = $false }
}

try {
    Write-Host 'Update-AgentDefinition: saves a new version of your agent from known parts, keeping its Service Desk MCP tools as they are.' -ForegroundColor Cyan
    $settings = Read-LabSettings $SettingsPath @('FoundryProjectEndpoint', 'AgentName', 'SubscriptionId', 'ResourceGroup', 'FoundryResource', 'FoundryProject',
                                                 'SearchEndpoint', 'SearchIndex', 'McpReadConnection', 'McpWriteConnection')
    $script:ProjectEndpoint = ([string]$settings.FoundryProjectEndpoint).TrimEnd('/')
    $script:FoundryToken = Get-AzCliToken 'https://ai.azure.com' $settings.TenantId
    $agentName = [string]$settings.AgentName

    Write-Section "1. Read the agent $agentName"
    $r = Invoke-Foundry GET "agents/$($agentName)?api-version=v1"
    if ($r.Status -eq 404) { throw "The agent $agentName was not found in your project. Lab provisioning creates it; contact CloudLabs support." }
    if ($r.Status -eq 401 -or $r.Status -eq 403) { throw "Your account may not read agents in this project (HTTP $($r.Status)). You need Foundry User on the project, which provisioning assigns. Sign in as the Senior Technician with 'az login'." }
    if ($r.Status -ge 400) { throw "Reading the agent failed: $(Get-ErrorText $r)" }
    $agent = $r.Body
    $latest = $agent.versions.latest
    if (-not $latest -or -not $latest.definition) { throw "The agent $agentName has no readable latest version. Contact CloudLabs support." }
    Write-Note "Latest version: $($latest.version). Tools now:"
    Show-Tools $latest.definition

    if ($Reset) {
        # ==== -Reset: the definition of the first version is the baseline provisioning created.
        Write-Section '2. Find the baseline (your agent''s first version)'
        $baseline = $null
        $list = Invoke-Foundry GET "agents/$agentName/versions?api-version=v1&order=asc&limit=1"
        $first = if ($list.Status -lt 400) { @($list.Body.data) | Select-Object -First 1 } else { $null }
        if ($first) {
            $v = Invoke-Foundry GET "agents/$agentName/versions/$($first.version)?api-version=v1"
            if ($v.Status -lt 400 -and $v.Body.definition) { $baseline = Copy-Json $v.Body.definition; Write-Ok "Baseline: version $($first.version), the version lab provisioning created." }
        }
        if (-not $baseline) {
            Write-Caution 'The first version could not be read, so the baseline is rebuilt from the latest version''s MCP tools and the baseline instructions file.'
            $baseline = Copy-Json $latest.definition
            if (-not (Test-Path -LiteralPath $BaselineInstructionsPath)) { throw "The baseline instructions $BaselineInstructionsPath were not found. Contact CloudLabs support." }
            Set-Property $baseline 'instructions' (Get-Content -LiteralPath $BaselineInstructionsPath -Raw)
        }
        Set-Property $baseline 'tools' @(@($baseline.tools) | Where-Object { $_ -and $_.type -ne 'azure_ai_search' })
        $target = $baseline
        $description = 'Baseline restored by Update-AgentDefinition.ps1 -Reset: both Service Desk MCP tools, no knowledge tool.'
    }
    else {
        # ==== Default: keep everything, add or replace the Azure AI Search tool.
        Write-Section '2. Check the Service Desk MCP tools that the new version keeps'
        $tools = @($latest.definition.tools)
        $read = $tools | Where-Object { $_.type -eq 'mcp' -and $_.server_label -eq 'servicedesk-read' } | Select-Object -First 1
        $write = $tools | Where-Object { $_.type -eq 'mcp' -and $_.server_label -eq 'servicedesk-write' } | Select-Object -First 1
        if (-not $read -or -not $write) {
            throw "The latest version has no $(if (-not $read) { 'servicedesk-read' } else { 'servicedesk-write' }) MCP tool. Run this script with -Reset to restore the baseline, then run it again without -Reset."
        }
        if (-not (Test-WriteApproval $write)) {
            throw 'In the latest version the servicedesk-write tool no longer asks for approval on every call. The script will not copy that. Run it with -Reset to restore the baseline (approval on every write), then run it again.'
        }
        Write-Ok "servicedesk-write asks for approval on every call ($(Format-Approval $write.require_approval)); kept as it is."
        $allowed = @(Get-ToolNames $read.allowed_tools)
        if ($read.require_approval -ne 'never') { Write-Caution "servicedesk-read approval is '$(Format-Approval $read.require_approval)', not 'never' as in the baseline; kept as it is." }
        if (-not $allowed.Count) { Write-Caution 'servicedesk-read has no allowed_tools list, so every tool on the read endpoint is available without approval; kept as it is. -Reset restores the list.' }
        else { Write-Ok "servicedesk-read runs without approval and is limited to $($allowed.Count) read tools; kept as it is." }
        if ($read.project_connection_id -ne $settings.McpReadConnection) { Write-Caution "servicedesk-read uses the connection '$($read.project_connection_id)', not '$($settings.McpReadConnection)'." }
        if ($write.project_connection_id -ne $settings.McpWriteConnection) { Write-Caution "servicedesk-write uses the connection '$($write.project_connection_id)', not '$($settings.McpWriteConnection)'." }

        Write-Section "3. Add the Azure AI Search tool on $($settings.SearchIndex)"
        $connection = Find-SearchConnection $settings
        Write-Ok "Project connection '$($connection.Name)'$(if ($connection.AuthType) { " ($($connection.AuthType))" }) to $($settings.SearchEndpoint)."
        $searchTool = [pscustomobject]@{
            type            = 'azure_ai_search'
            azure_ai_search = [pscustomobject]@{
                indexes = @([pscustomobject]@{
                    project_connection_id = $connection.Id
                    index_name            = [string]$settings.SearchIndex
                    query_type            = $QueryType
                    top_k                 = $TopK
                })
            }
        }
        $target = Copy-Json $latest.definition
        $hadSearch = @(@($target.tools) | Where-Object { $_ -and $_.type -eq 'azure_ai_search' }).Count -gt 0
        Set-Property $target 'tools' (@(@($target.tools) | Where-Object { $_ -and $_.type -ne 'azure_ai_search' }) + @($searchTool))
        Write-Note "$(if ($hadSearch) { 'Replaces the existing Azure AI Search tool with' } else { 'Adds' }) index $($settings.SearchIndex), query type $QueryType, top $TopK results."
        if ($Instructions) {
            if (-not (Test-Path -LiteralPath $InstructionsPath)) { throw "The grounded instructions $InstructionsPath were not found. Contact CloudLabs support." }
            Set-Property $target 'instructions' (Get-Content -LiteralPath $InstructionsPath -Raw)
            Write-Note "Instructions: replaced with $InstructionsPath."
        }
        else { Write-Note 'Instructions: kept as they are (add -Instructions to use the grounded instructions).' }
        $description = "Azure AI Search tool on $($settings.SearchIndex) added by Update-AgentDefinition.ps1$(if ($Instructions) { ' with the grounded instructions' }); both Service Desk MCP tools kept."
    }

    Write-Section '4. Save the new version'
    if (-not $Force -and (Test-SameDefinition $target $latest.definition)) {
        Write-Ok "Version $($latest.version) already has exactly this definition, so no new version is needed. Use -Force to create one anyway."
        exit 0
    }
    Write-Note 'The new version will have these tools:'
    Show-Tools $target
    if (-not $PSCmdlet.ShouldProcess("$agentName (new version after $($latest.version))", 'Create agent version')) { exit 0 }
    $body = [ordered]@{ definition = $target; description = $description; metadata = @{ changed_by = 'Update-AgentDefinition.ps1' } }
    $r = Invoke-Foundry POST "agents/$agentName/versions?api-version=v1" $body
    if ($r.Status -eq 400 -and (Get-ErrorText $r) -match '(?i)description|metadata') {
        $r = Invoke-Foundry POST "agents/$agentName/versions?api-version=v1" @{ definition = $target }
    }
    if ($r.Status -eq 401 -or $r.Status -eq 403) { throw "Your account may not create agent versions (HTTP $($r.Status)). You need Foundry User on the project." }
    if ($r.Status -ge 400) { throw "Creating the version failed: $(Get-ErrorText $r)" }
    $newVersion = [string]$r.Body.version
    Write-Ok "Created version $newVersion of $agentName."

    $rules = @($agent.agent_endpoint.version_selector.version_selection_rules) | Where-Object { $_ -and $_.agent_version }
    if ($rules.Count -and -not (@($rules.agent_version) -contains $newVersion)) {
        Write-Caution "Your agent's endpoint is pinned to version $(@($rules.agent_version) -join ', '), so it does not serve version $newVersion yet. In the Foundry portal, expand Publish, open the version selector and choose Always use latest (or version $newVersion)."
    }
    else { Write-Note "Your agent serves the latest version, so the playground uses version $newVersion from your next message." }
    Write-Host ''
    if ($Reset) { Write-Host 'Done. The agent is back to its baseline.' -ForegroundColor Green }
    else { Write-Host 'Done. In the playground, ask a question only the index can answer, and check that the answer cites a source whose link opens the Service Desk record.' -ForegroundColor Green }
    exit 0
}
catch {
    Write-Verbose ($_ | Out-String)
    Stop-Script $_.Exception.Message
}
