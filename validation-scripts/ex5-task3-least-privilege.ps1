# Validation: Exercise 5, Task 3 - Enforce a least-privilege boundary
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when Dataverse refused an agent write on a regulated customer's ticket (TCK-10479 or
# TCK-10491, owned by the Relecloud Regulated Accounts business unit): DATAVERSE_ACCESS_DENIED
# with HTTP 403 from Dataverse, after the team narrowed the Service Desk Agent Write role.

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
        $rows = Invoke-LogQuery ($toolCalls + "| where caller == 'agent' and tostring(j.arguments.ticket_number) in ('TCK-10479', 'TCK-10491') | mv-expand call = j.dataverse | extend status = toint(call.status) | summarize statuses = make_set(status) by TimeGenerated, tool, outcome, code, ticket = tostring(j.arguments.ticket_number), correlation | order by TimeGenerated desc")
        $good = $rows | Where-Object { $_.code -eq 'DATAVERSE_ACCESS_DENIED' -and "$($_.statuses)" -match '403' } | Select-Object -First 1
        if ($good) {
            $status = 'Succeeded'
            $message = "Dataverse refused $($good.tool) on $($good.ticket) with HTTP 403 at $($good.TimeGenerated) UTC (correlation ID $($good.correlation))."
            break
        }
        elseif ($rows | Where-Object { $_.outcome -eq 'ok' -and $_.tool -notmatch '^(get|search|list)' }) {
            $message = 'A write on a regulated ticket succeeded: the boundary is not narrowed yet. Set Ticket Write, Append and Append To to Business Unit on Service Desk Agent Write and try again.'
        }
        else { $message = 'No write attempt on TCK-10479 or TCK-10491 has been logged yet. Logs can take a few minutes to arrive; validate again shortly.' }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
