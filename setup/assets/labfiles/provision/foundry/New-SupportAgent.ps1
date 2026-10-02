#Requires -Version 7.0
<#
.SYNOPSIS
    Creates the team's Foundry agent with no knowledge and no tools, and returns its Microsoft
    Entra agent identity.

.DESCRIPTION
    Agents have no ARM resource type, so the agent is created through the project data plane:
      POST {project endpoint}/agents?api-version=v1
    In the current Foundry agent model a new agent gets its own Entra agent identity at
    creation; GET {project endpoint}/agents/{name} returns it as instance_identity
    (principal_id = object ID, client_id = application ID). The script waits until the
    identity is present, because the gateway policy needs the client ID.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectEndpoint,
    [Parameter(Mandatory)][string]$AgentName,
    [Parameter(Mandatory)][string]$ModelDeployment
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MspLab.Common.psm1') -Force

$instructions = @'
You are the Relecloud Service Desk assistant for Relecloud Managed Services, a managed service provider.
You have no knowledge sources and no tools yet. If you are asked about Relecloud customers, tickets or
knowledge articles, say that you do not have access to that information yet.
'@

function Invoke-Foundry([string]$Method, [string]$Path, $Body = $null) {
    $headers = @{ Authorization = "Bearer $(Get-AzCliToken -Resource 'https://ai.azure.com')" }
    $params = @{ Method = $Method; Uri = "$($ProjectEndpoint.TrimEnd('/'))/$Path"; Headers = $headers
                 SkipHttpErrorCheck = $true; StatusCodeVariable = 'status' }
    if ($Body) { $params.Body = ($Body | ConvertTo-Json -Depth 20); $params.ContentType = 'application/json' }
    $result = Invoke-RestMethod @params
    return @{ Status = $status; Body = $result }
}

$existing = Invoke-WithRetry -What 'read agent' -Action { Invoke-Foundry GET "agents/$($AgentName)?api-version=v1" }
if ($existing.Status -eq 404) {
    Write-Step "Creating agent $AgentName on $ModelDeployment"
    $created = Invoke-WithRetry -What 'create agent' -DelaySeconds 30 -Action {
        $r = Invoke-Foundry POST 'agents?api-version=v1' @{
            name = $AgentName
            description = 'Relecloud service desk agent for the Agentic MSP Support Agent lab.'
            definition = @{ kind = 'prompt'; model = $ModelDeployment; instructions = $instructions }
        }
        if ($r.Status -ge 400) { throw "HTTP $($r.Status): $($r.Body | ConvertTo-Json -Depth 5 -Compress)" }
        $r
    }
}
elseif ($existing.Status -ge 400) { throw "Reading agent $AgentName failed: HTTP $($existing.Status)" }

$deadline = (Get-Date).AddMinutes(10)
do {
    $agent = (Invoke-Foundry GET "agents/$($AgentName)?api-version=v1").Body
    $identity = $agent.instance_identity
    if (-not $identity -or -not $identity.client_id) { Write-Step '  waiting for the agent identity'; Start-Sleep -Seconds 20 }
} until (($identity -and $identity.client_id) -or (Get-Date) -gt $deadline)
if (-not $identity -or -not $identity.client_id) {
    throw "Agent $AgentName has no instance_identity after 10 minutes. Check that agent identities are not blocked in the tenant."
}
Write-Step "Agent $AgentName identity: object ID $($identity.principal_id), client ID $($identity.client_id)"
[pscustomobject]@{ AgentName = $AgentName; AgentId = $agent.id; ObjectId = $identity.principal_id; ClientId = $identity.client_id }
