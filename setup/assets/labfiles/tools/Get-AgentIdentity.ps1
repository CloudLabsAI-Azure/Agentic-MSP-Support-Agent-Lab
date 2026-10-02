#Requires -Version 7.0
<#
.SYNOPSIS
    Shows your Foundry agent's Microsoft Entra agent identity (object ID and client ID).

.DESCRIPTION
    Reads the agent from the Foundry project data plane:
      GET {project endpoint}/agents/{agent name}?api-version=v1
    and prints instance_identity. principal_id is the agent identity's OBJECT ID, the value you
    search for in the Microsoft Entra admin center; client_id is the application ID that
    appears as appid/azp in the tokens the agent presents to API Management.
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
    'Agent name'                 = $agent.name
    'Agent ID'                   = $agent.id
    'Agent identity object ID'   = $agent.instance_identity.principal_id
    'Agent identity client ID'   = $agent.instance_identity.client_id
    'Blueprint'                  = ($agent.blueprint_reference ?? $agent.blueprint | ConvertTo-Json -Compress -Depth 4)
} | Format-List
