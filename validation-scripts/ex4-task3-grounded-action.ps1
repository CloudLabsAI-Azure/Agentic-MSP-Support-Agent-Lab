# Validation: Exercise 4, Task 3 - Chain grounding into action
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the agent read the new incident TCK-10514 and then changed it through a write
# tool (triage_ticket, set_ticket_priority or assign_ticket) with the user's approval.

$ErrorActionPreference = 'Stop'
$status = 'Failed'
$message = ''

function Invoke-LogQuery([string]$query) {
    $workspace = Get-AzResource -ResourceType 'Microsoft.OperationalInsights/workspaces' -Name "log-msp-$DeploymentID" | Select-Object -First 1
    if (-not $workspace) { throw "Log Analytics workspace log-msp-$DeploymentID was not found." }
    $customerId = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $workspace.ResourceGroupName -Name $workspace.Name).CustomerId
    return @((Invoke-AzOperationalInsightsQuery -WorkspaceId $customerId -Query $query).Results)
}
# Every tool call writes one JSON line to the MCP server's console log (the tool invocation log).
$toolCalls = @"
ContainerAppConsoleLogs
| where TimeGenerated > ago(24h)
| where ContainerAppName == 'ca-mcp-$DeploymentID'
| extend j = parse_json(Log)
| where tostring(j.event) == 'tool_call'
| extend tool = tostring(j.tool), outcome = tostring(j.outcome), code = tostring(j.error_code), caller = tostring(j.caller),
         user = tostring(j.user.name), correlation = tostring(j.correlation_id)
"@

for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $rows = Invoke-LogQuery ($toolCalls + "| where caller == 'agent' and tostring(j.arguments.ticket_number) == 'TCK-10514' | project TimeGenerated, tool, outcome, code, user, correlation | order by TimeGenerated asc")
        $read = $rows | Where-Object { $_.tool -eq 'get_ticket' -and $_.outcome -eq 'ok' } | Select-Object -First 1
        $write = $rows | Where-Object { $_.tool -in 'triage_ticket', 'set_ticket_priority', 'assign_ticket' -and $_.outcome -eq 'ok' } | Select-Object -Last 1
        if ($read -and $write) {
            $status = 'Succeeded'
            $message = "The agent read TCK-10514 and then ran $($write.tool) at $($write.TimeGenerated) UTC (correlation ID $($write.correlation))."
            break
        }
        elseif ($write) { $message = 'TCK-10514 was changed, but the agent did not read the ticket first. Ask it to retrieve the context before it acts.' }
        elseif ($rows) { $message = "The agent worked on TCK-10514 but no approved change succeeded yet (last: $($rows[-1].tool) $($rows[-1].outcome) $($rows[-1].code))." }
        else { $message = 'No tool call for TCK-10514 has been logged yet. Logs can take a few minutes to arrive; validate again shortly.' }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
