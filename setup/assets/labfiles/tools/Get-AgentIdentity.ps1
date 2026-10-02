#Requires -Version 7.0
<#
.SYNOPSIS
    Shows your Foundry agent's Microsoft Entra Agent ID (object ID and client ID) and its tools.

.DESCRIPTION
    Reads the agent from the Foundry project data plane:
      GET {project endpoint}/agents/{agent name}?api-version=v1
    and prints instance_identity. principal_id is the Agent ID's OBJECT ID, the value you search
    for in the Microsoft Entra admin center; client_id is its application ID, which the MCP
    server writes into every tool invocation log line (agent.id).

    The Agent ID is the agent's own identity. Calls from the agent to the Service Desk gateway
    carry the signed-in technician's token instead (OAuth identity passthrough), so Dataverse
    decides each call for that technician.
    Uses your own Azure CLI sign-in: run 'az login' first.
#>
[CmdletBinding()]
param([string]$SettingsPath = 'C:\LabFiles\team-settings.json')

$ErrorActionPreference = 'Stop'
$settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
$token = az account get-access-token --resource 'https://ai.azure.com' --query accessToken --output tsv
if (-not $token) { throw "Run 'az login' first." }
$agent = Invoke-RestMethod -Uri "$($settings.FoundryProjectEndpoint)/agents/$($settings.AgentName)?api-version=v1" `
    -Headers @{ Authorization = "Bearer $token" }
[pscustomobject]@{
    'Agent name'               = $agent.name
    'Agent ID'                 = $agent.id
    'Entra Agent ID object ID' = $agent.instance_identity.principal_id
    'Entra Agent ID client ID' = $agent.instance_identity.client_id
    'MCP connection'           = $settings.McpConnectionName
    'MCP gateway'              = $settings.McpGatewayUrl
} | Format-List
