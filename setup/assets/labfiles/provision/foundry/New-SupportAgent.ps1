#Requires -Version 7.0
<#
.SYNOPSIS
    Creates the team's Foundry agent with the baseline instructions and the Service Desk MCP
    tool (no knowledge source), and returns its Microsoft Entra Agent ID.

.DESCRIPTION
    Agents have no ARM resource type, so the agent is created through the project data plane:
      POST {project endpoint}/agents?api-version=v1
    The baseline definition has one tool: the Service Desk MCP server behind API Management,
    reached through the project connection 'servicedesk-mcp' (OAuth identity passthrough, so
    every call carries the signed-in technician's identity). Approval is safe by default: only
    the read tools are listed as never needing approval, so every write tool, and any tool a
    team adds later, asks the user to approve each call.

    A new agent gets its own Entra Agent ID at creation; GET {project endpoint}/agents/{name}
    returns it as instance_identity (principal_id = object ID, client_id = application ID).
    The script waits until the identity is present.

    An existing agent is left as it is (a re-run keeps the team's work) unless -Reset is given,
    which creates a new version with the baseline definition.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectEndpoint,
    [Parameter(Mandatory)][string]$AgentName,
    [Parameter(Mandatory)][string]$ModelDeployment,
    [Parameter(Mandatory)][string]$InstructionsPath,
    [Parameter(Mandatory)][string]$McpServerUrl,
    [Parameter(Mandatory)][string]$McpConnectionName,
    [Parameter(Mandatory)][string[]]$ReadTools,
    [switch]$Reset
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MspLab.Common.psm1') -Force

function Invoke-Foundry([string]$Method, [string]$Path, $Body = $null) {
    $headers = @{ Authorization = "Bearer $(Get-AzCliToken -Resource 'https://ai.azure.com')" }
    $params = @{ Method = $Method; Uri = "$($ProjectEndpoint.TrimEnd('/'))/$Path"; Headers = $headers
                 SkipHttpErrorCheck = $true; StatusCodeVariable = 'status' }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 20); $params.ContentType = 'application/json' }
    $result = Invoke-RestMethod @params
    return @{ Status = $status; Body = $result }
}

$definition = @{
    kind = 'prompt'
    model = $ModelDeployment
    instructions = (Get-Content $InstructionsPath -Raw)
    tools = @(@{
        type = 'mcp'
        server_label = 'servicedesk'
        server_url = $McpServerUrl
        project_connection_id = $McpConnectionName
        require_approval = @{ never = @{ tool_names = @($ReadTools) } }
    })
}

$existing = Invoke-WithRetry -What 'read agent' -Action { Invoke-Foundry GET "agents/$($AgentName)?api-version=v1" }
if ($existing.Status -eq 404) {
    Write-Step "Creating agent $AgentName on $ModelDeployment with the Service Desk MCP tool"
    Invoke-WithRetry -What 'create agent' -DelaySeconds 30 -Action {
        $r = Invoke-Foundry POST 'agents?api-version=v1' @{
            name = $AgentName
            description = 'Relecloud service desk agent for the Agentic MSP Support Agent lab.'
            definition = $definition
        }
        if ($r.Status -ge 400) { throw "HTTP $($r.Status): $($r.Body | ConvertTo-Json -Depth 5 -Compress)" }
    } | Out-Null
}
elseif ($existing.Status -ge 400) { throw "Reading agent $AgentName failed: HTTP $($existing.Status)" }
elseif ($Reset) {
    Write-Step "Resetting agent $AgentName to the baseline definition"
    $r = Invoke-Foundry POST "agents/$AgentName/versions?api-version=v1" @{ definition = $definition }
    if ($r.Status -ge 400) { throw "HTTP $($r.Status): $($r.Body | ConvertTo-Json -Depth 5 -Compress)" }
}
else { Write-Step "Agent $AgentName exists; kept as it is" }

$deadline = (Get-Date).AddMinutes(10)
do {
    $agent = (Invoke-Foundry GET "agents/$($AgentName)?api-version=v1").Body
    $identity = $agent.instance_identity
    if (-not $identity -or -not $identity.client_id) { Write-Step '  waiting for the agent identity'; Start-Sleep -Seconds 20 }
} until (($identity -and $identity.client_id) -or (Get-Date) -gt $deadline)
if (-not $identity -or -not $identity.client_id) {
    throw "Agent $AgentName has no instance_identity after 10 minutes. Check that agent identities are not blocked in the tenant."
}
Write-Step "Agent $AgentName Entra Agent ID: object ID $($identity.principal_id), client ID $($identity.client_id)"
[pscustomobject]@{ AgentName = $AgentName; AgentId = $agent.id; ObjectId = $identity.principal_id; ClientId = $identity.client_id }
