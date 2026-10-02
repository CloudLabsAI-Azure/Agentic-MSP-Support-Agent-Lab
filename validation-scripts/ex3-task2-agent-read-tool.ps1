# Validation: Exercise 3, Task 2 - Call an existing read tool
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the MCP server logged a successful read tool call that came from the agent on
# behalf of a signed-in user (caller agent, user present), which is the call the learner then
# finds in the tool invocation log by its correlation ID.

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
        $reads = 'search_tickets','get_open_tickets','get_ticket','get_ticket_notes','get_customer','get_customer_contacts','get_customer_document','get_knowledge_article','list_technicians'
        $rows = Invoke-LogQuery ($toolCalls + "| where caller == 'agent' | project TimeGenerated, tool, outcome, user, correlation | order by TimeGenerated desc")
        $good = $rows | Where-Object { $_.tool -in $reads -and $_.outcome -eq 'ok' -and $_.user } | Select-Object -First 1
        if ($good) {
            $status = 'Succeeded'
            $message = "The agent called $($good.tool) for $($good.user) at $($good.TimeGenerated) UTC (correlation ID $($good.correlation))."
            break
        }
        elseif ($rows) { $message = "The agent called tools, but no read tool succeeded yet (last: $($rows[0].tool) $($rows[0].outcome)). Ask the agent again." }
        else { $message = 'No tool call from the agent has been logged yet. Logs can take a few minutes to arrive; validate again shortly.' }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
