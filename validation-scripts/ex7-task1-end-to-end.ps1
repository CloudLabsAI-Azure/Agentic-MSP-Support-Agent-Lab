# Validation: Exercise 7, Task 1 - Run the end-to-end scenario
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the agent handled the second new incident TCK-10515 end to end: it read the
# ticket and the customer, then changed the ticket through an approved write tool.

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
        $rows = Invoke-LogQuery ($toolCalls + "| where caller == 'agent' | extend ticket = tostring(j.arguments.ticket_number), customer = tostring(j.arguments.customer) | project TimeGenerated, tool, outcome, code, user, ticket, customer, correlation | order by TimeGenerated asc")
        $read = $rows | Where-Object { $_.tool -eq 'get_ticket' -and $_.ticket -eq 'TCK-10515' -and $_.outcome -eq 'ok' } | Select-Object -First 1
        $context = $rows | Where-Object { $_.tool -in 'get_customer', 'search_tickets', 'get_open_tickets' -and $_.outcome -eq 'ok' -and $_.TimeGenerated -ge $read.TimeGenerated } | Select-Object -First 1
        $write = $rows | Where-Object { $_.ticket -eq 'TCK-10515' -and $_.tool -in 'triage_ticket', 'set_ticket_priority', 'assign_ticket', 'update_ticket_status', 'add_ticket_note' -and $_.outcome -eq 'ok' } | Select-Object -Last 1
        if ($read -and $context -and $write) {
            $status = 'Succeeded'
            $message = "The agent read TCK-10515 and its context, then ran $($write.tool) at $($write.TimeGenerated) UTC (correlation ID $($write.correlation))."
            break
        }
        elseif ($read -and -not $write) { $message = 'The agent read TCK-10515 but no approved change has been logged yet.' }
        else { $message = 'No end-to-end work on TCK-10515 has been logged yet. Logs can take a few minutes to arrive; validate again shortly.' }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
