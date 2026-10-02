# Validation: Exercise 4, Task 4 - Tighten a tool boundary
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when a get_open_tickets call above the new limit was rejected by input validation:
# outcome rejected, INVALID_ARGUMENT, and the violation names the new maximum of 20.

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
        $rows = Invoke-LogQuery ($toolCalls + "| where tool == 'get_open_tickets' and outcome == 'rejected' | extend le = toint(j.record.violations[0].constraint.le), received = tostring(j.record.violations[0].received) | project TimeGenerated, code, le, received | order by TimeGenerated desc")
        $good = $rows | Where-Object { $_.code -eq 'INVALID_ARGUMENT' -and $_.le -eq 20 } | Select-Object -First 1
        if ($good) {
            $status = 'Succeeded'
            $message = "get_open_tickets rejected limit $($good.received) at $($good.TimeGenerated) UTC: the maximum is now 20."
            break
        }
        elseif ($rows) { $message = "get_open_tickets rejected a call, but against a maximum of $($rows[0].le), not 20. Set MAX_OPEN_TICKETS_LIMIT to 20, redeploy and try again." }
        else { $message = 'No rejected get_open_tickets call has been logged yet. Call it with a limit above 20 after you redeploy. Logs can take a few minutes to arrive; validate again shortly.' }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
