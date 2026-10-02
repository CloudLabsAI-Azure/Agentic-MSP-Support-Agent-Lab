#Requires -Version 7.0
<#
.SYNOPSIS
    Tells the team's API Management gateway which agent identity it may accept, and refreshes
    the Key Vault backed gateway key.

.DESCRIPTION
    The agent-facing MCP API validates every request with validate-azure-ad-token: the token
    must be issued for the MCP gateway audience and its client application (appid/azp claim)
    must equal the named value 'agent-client-id'. ARM cannot know that value, because the
    agent identity only exists once the agent is created, so this script sets it.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SubscriptionId,
    [Parameter(Mandatory)][string]$ResourceGroup,
    [Parameter(Mandatory)][string]$ApimName,
    [Parameter(Mandatory)][string]$AgentClientId
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path $PSScriptRoot -Parent) 'MspLab.Common.psm1') -Force

$base = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName"
$body = @{ properties = @{ displayName = 'agent-client-id'; value = $AgentClientId; secret = $false; tags = @('set-by-provisioning') } } |
    ConvertTo-Json -Depth 5 -Compress
$bodyFile = New-TemporaryFile
Set-Content -Path $bodyFile -Value $body -Encoding utf8
Invoke-WithRetry -What 'set agent-client-id' -Action {
    az rest --method put --uri "$base/namedValues/agent-client-id?api-version=2024-05-01" --body "@$bodyFile" --output none
    if ($LASTEXITCODE) { throw "az rest put namedValues failed ($LASTEXITCODE)" }
}
Remove-Item $bodyFile -Force
Write-Step "Gateway now accepts agent client ID $AgentClientId"

Invoke-WithRetry -What 'refresh mcp-backend-key' -Action {
    az rest --method post --uri "$base/namedValues/mcp-backend-key/refreshSecret?api-version=2024-05-01" --output none
    if ($LASTEXITCODE) { throw "refreshSecret failed ($LASTEXITCODE)" }
}
Write-Step 'Gateway key refreshed from Key Vault'
