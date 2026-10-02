# Validation: Exercise 3, Task 2 - Invoke a read tool from the agent
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when:
#   1. the Foundry project proj-msp-<DID> has a RemoteTool (MCP) connection whose target is the
#      team's API Management MCP gateway, https://apim-msp-<DID>.azure-api.net/servicedesk/mcp, and
#   2. the MCP server logged a successful get_ticket call for TCK-10489 that came through the
#      agent API (caller = agent) in the last 24 hours.
# Container Apps console logs can take several minutes to reach Log Analytics; the retries
# below allow for that.

$ErrorActionPreference = 'Stop'
$status = 'Failed'
$message = ''
$gatewayUrl = "https://apim-msp-$DeploymentID.azure-api.net/servicedesk/mcp"
$query = @"
ContainerAppConsoleLogs
| where TimeGenerated > ago(24h)
| where ContainerAppName == 'ca-mcp-$DeploymentID'
| extend j = parse_json(Log)
| where tostring(j.event) == 'tool_call' and tostring(j.tool) == 'get_ticket' and tostring(j.outcome) == 'ok'
| where tostring(j.caller) == 'agent' and tostring(j.arguments.ticket_number) == 'TCK-10489'
| summarize calls = count(), last = max(TimeGenerated)
"@

for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $foundry = Get-AzResource -ResourceType 'Microsoft.CognitiveServices/accounts' -Name "aif-msp-$DeploymentID" | Select-Object -First 1
        if (-not $foundry) { throw "Foundry resource aif-msp-$DeploymentID was not found." }
        $connections = (Invoke-AzRestMethod -Method GET -Path "$($foundry.ResourceId)/projects/proj-msp-$DeploymentID/connections?api-version=2025-06-01").Content |
            ConvertFrom-Json
        $mcpConnection = $connections.value | Where-Object {
            $_.properties.category -eq 'RemoteTool' -and "$($_.properties.target)".TrimEnd('/') -eq $gatewayUrl
        } | Select-Object -First 1

        $workspace = Get-AzOperationalInsightsWorkspace -ResourceGroupName $foundry.ResourceGroupName -Name "log-msp-$DeploymentID"
        $result = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspace.CustomerId -Query $query
        $calls = [int](@($result.Results)[0].calls)

        if (-not $mcpConnection) {
            $message = "No MCP tool connection to $gatewayUrl was found on project proj-msp-$DeploymentID. Add the MCP tool to the agent."
        }
        elseif ($calls -lt 1) {
            $message = "The MCP connection '$($mcpConnection.name)' exists, but no get_ticket call for TCK-10489 from the agent has been logged yet. Ask the agent about TCK-10489, approve the tool call, and validate again in a few minutes."
        }
        else {
            $status = 'Succeeded'
            $message = "The agent called get_ticket for TCK-10489 through the gateway ($calls call(s)) using connection '$($mcpConnection.name)'."
            break
        }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
