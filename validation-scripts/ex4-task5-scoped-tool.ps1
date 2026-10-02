# Validation: Exercise 4, Task 5 - Design and add a scoped tool
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the agent successfully called a tool that is not one of the fourteen baseline
# tools, which means the team's new tool is deployed and reachable through the gateway.

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
        $baseline = 'search_tickets','get_open_tickets','get_ticket','get_ticket_notes','get_customer','get_customer_contacts','get_customer_document','get_knowledge_article','list_technicians','triage_ticket','set_ticket_priority','update_ticket_status','assign_ticket','add_ticket_note'
        $rows = Invoke-LogQuery ($toolCalls + "| where caller == 'agent' | project TimeGenerated, tool, outcome, code, user, correlation | order by TimeGenerated desc")
        $new = @($rows | Where-Object { $_.tool -notin $baseline })
        $good = $new | Where-Object { $_.outcome -eq 'ok' } | Select-Object -First 1
        if ($good) {
            $status = 'Succeeded'
            $message = "The agent called the new tool $($good.tool) for $($good.user) at $($good.TimeGenerated) UTC (correlation ID $($good.correlation))."
            break
        }
        elseif ($new) { $message = "The new tool $($new[0].tool) returned $($new[0].outcome) $($new[0].code). Fix it, redeploy and try again." }
        else { $message = 'No call to a new tool has been logged yet. Logs can take a few minutes to arrive; validate again shortly.' }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
