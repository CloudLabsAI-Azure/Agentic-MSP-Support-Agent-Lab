#Requires -Version 7.0
<#
.SYNOPSIS
    Creates the Foundry agent msp-support-agent with the baseline instructions and the two Service
    Desk MCP tools, and returns its Microsoft Entra Agent ID.

.DESCRIPTION
    Version 1 of the agent is the lab's baseline (Update-AgentDefinition.ps1 -Reset returns to it):
      model             gpt-5.1, reasoning effort low, no knowledge tool (Exercise 1 adds it)
      servicedesk-read  MCP tool, server_url the read gateway, project_connection_id servicedesk-read,
                        allowed_tools the read catalog in LabConfig.psd1, require_approval never
      servicedesk-write MCP tool, server_url the write gateway, project_connection_id servicedesk-write,
                        no allowed_tools (every tool the write endpoint lists, including a tool a
                        participant adds in Exercise 4), require_approval always
    Both connections use OAuth identity passthrough, so every call carries the signed-in technician.

    Identity: the provisioning identity (id-prov), Foundry User on the project, through the project
    data plane (POST {project endpoint}/agents?api-version=v1). Agents have no ARM resource type.

    An existing agent is kept when its latest version still has both MCP tools as described (a re-run
    keeps a participant's later versions). Otherwise, or with -Reset, a new version with the baseline
    definition is created. The script waits for instance_identity, the agent's own Entra Agent ID:
    client_id is the Agent ID the gateway forwards (x-agent-id) and the lab records.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectEndpoint,
    [Parameter(Mandatory)][string]$AgentName,
    [Parameter(Mandatory)][string]$ModelDeployment,
    [Parameter(Mandatory)][string]$InstructionsPath,
    [Parameter(Mandatory)][string]$ReadGatewayUrl,
    [Parameter(Mandatory)][string]$WriteGatewayUrl,
    [Parameter(Mandatory)][string]$ReadConnection,
    [Parameter(Mandatory)][string]$WriteConnection,
    [Parameter(Mandatory)][string[]]$ReadTools,
    [ValidateSet('none', 'low', 'medium', 'high')][string]$ReasoningEffort = 'low',
    [switch]$Reset
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MspLab.Common.psm1') -Force
$endpoint = $ProjectEndpoint.TrimEnd('/')

function Invoke-Foundry([string]$Method, [string]$Path, $Body = $null, [int[]]$AllowStatus = @()) {
    $uri = "$endpoint/$Path" + $(if ($Path.Contains('?')) { '&' } else { '?' }) + 'api-version=v1'
    return Invoke-LabRest -Method $Method -Uri $uri -Token (Get-ManagedIdentityToken 'https://ai.azure.com') -Body $Body -AllowNotFound -AllowStatus $AllowStatus
}

function Get-ToolNames($Value) {
    # allowed_tools comes back as a list of names or as {"tool_names": [...]}.
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) { return @($Value) }
    if ($Value.PSObject.Properties['tool_names']) { return @($Value.tool_names) }
    return @($Value)
}

function Test-Baseline($Definition) {
    # True when the definition still has both Service Desk MCP tools as the lab defines them.
    $tools = @($Definition.tools)
    $read = $tools | Where-Object { $_.type -eq 'mcp' -and $_.server_label -eq $ReadConnection } | Select-Object -First 1
    $write = $tools | Where-Object { $_.type -eq 'mcp' -and $_.server_label -eq $WriteConnection } | Select-Object -First 1
    if (-not $read -or -not $write) { return $false }
    $allowed = @(Get-ToolNames $read.allowed_tools)
    return ($read.server_url -eq $ReadGatewayUrl -and $read.project_connection_id -eq $ReadConnection -and $read.require_approval -eq 'never' -and
            $allowed.Count -gt 0 -and $write.server_url -eq $WriteGatewayUrl -and $write.project_connection_id -eq $WriteConnection -and
            $write.require_approval -eq 'always' -and -not @(Get-ToolNames $write.allowed_tools).Count)
}

$instructions = (Get-Content $InstructionsPath -Raw).Trim()
$definition = [ordered]@{
    kind         = 'prompt'
    model        = $ModelDeployment
    instructions = $instructions
    reasoning    = @{ effort = $ReasoningEffort }
    tools        = @(
        [ordered]@{
            type                  = 'mcp'
            server_label          = $ReadConnection
            server_description    = 'Relecloud Service Desk read tools: customers, tickets, notes, knowledge articles, SLA status, assignments and similar tickets.'
            server_url            = $ReadGatewayUrl
            project_connection_id = $ReadConnection
            allowed_tools         = @($ReadTools)
            require_approval      = 'never'
        },
        [ordered]@{
            type                  = 'mcp'
            server_label          = $WriteConnection
            server_description    = 'Relecloud Service Desk write tools: ticket changes, assignments, article links, internal notes and customer replies. Every call needs the user''s approval.'
            server_url            = $WriteGatewayUrl
            project_connection_id = $WriteConnection
            require_approval      = 'always'
        }
    )
}
$description = 'Relecloud Service Desk agent (Agentic MSP Support Agent Guided Lab, Golden Environment baseline).'

function Submit-Definition([string]$Path, [hashtable]$Body) {
    $r = Invoke-Foundry POST $Path $Body -AllowStatus 400
    if ($r.Status -eq 400 -and (Get-RestErrorText $r.Body) -match '(?i)reasoning') {
        # Fallback when the service refuses the reasoning setting: the model default applies.
        Write-Step "  the reasoning setting was refused ($(ConvertTo-SafeText (Get-RestErrorText $r.Body) 200)); creating the agent without it"
        $Body.definition.Remove('reasoning')
        $r = Invoke-Foundry POST $Path $Body -AllowStatus 400
    }
    if ($r.Status -ge 400) { throw "POST $Path returned HTTP $($r.Status): $(Get-RestErrorText $r.Body)" }
    return $r.Body
}

# ==== Create, keep or reset
$existing = Invoke-WithRetry -What 'read the agent' -Attempts 10 -DelaySeconds 30 -Action { Invoke-Foundry GET "agents/$AgentName" }
$action = 'kept'
if ($existing.Status -eq 404) {
    Write-Step "Creating agent $AgentName ($ModelDeployment, reasoning $ReasoningEffort) with the tools $ReadConnection and $WriteConnection"
    $null = Invoke-WithRetry -What 'create the agent' -Attempts 6 -DelaySeconds 30 -Action {
        Submit-Definition 'agents' @{ name = $AgentName; description = $description; definition = $definition }
    }
    $action = 'created'
}
else {
    $latest = $existing.Body.versions.latest
    if ($Reset -or -not (Test-Baseline $latest.definition)) {
        Write-Step "Agent $AgentName exists; adding a version with the baseline definition$(if ($Reset) { ' (-Reset)' } else { ' (its MCP tools differ from the baseline)' })"
        $null = Submit-Definition "agents/$AgentName/versions" @{ description = $description; definition = $definition }
        $action = 'baseline version added'
    }
    else { Write-Step "Agent $AgentName exists with both Service Desk MCP tools; kept as it is" }
}

# ==== The agent's Entra Agent ID
$deadline = (Get-Date).AddMinutes(10)
do {
    $agent = (Invoke-Foundry GET "agents/$AgentName").Body
    $identity = $agent.instance_identity
    if (-not $identity) { $identity = $agent.versions.latest.instance_identity }
    if (-not $identity -or -not $identity.client_id) { Write-Step '  waiting for the agent identity'; Start-Sleep -Seconds 20 }
} until (($identity -and $identity.client_id) -or (Get-Date) -gt $deadline)
if (-not $identity -or -not $identity.client_id) {
    throw "Agent $AgentName has no instance_identity after 10 minutes. Check that agent identities are not blocked in the tenant (Conditional Access policies for agents)."
}
$latest = $agent.versions.latest
if (-not (Test-Baseline $latest.definition)) { Write-Step '  WARNING: the latest agent version does not have both MCP tools as the baseline defines them' }
Write-Step "Agent $AgentName version $($latest.version): Entra Agent ID client ID $($identity.client_id), object ID $($identity.principal_id)"
[pscustomobject]@{
    AgentName     = $AgentName
    AgentObjectId = $agent.id
    Version       = $latest.version
    ClientId      = [string]$identity.client_id
    ObjectId      = [string]$identity.principal_id
    Action        = $action
    ReadTools     = @($ReadTools)
}
