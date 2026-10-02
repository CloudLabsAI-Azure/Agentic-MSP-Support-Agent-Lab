# Validation: Exercise 4, Task 1 - Call a write tool with approval
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the MCP server logged a successful set_ticket_priority or update_ticket_status
# call from the agent on behalf of a signed-in user. The agent sends a write only after the
# user approves it, so the call is the evidence of the approved write; a declined call never
# reaches the server.

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
        $rows = Invoke-LogQuery ($toolCalls + "| where tool in ('set_ticket_priority', 'update_ticket_status') and caller == 'agent' | extend ticket = tostring(j.arguments.ticket_number) | project TimeGenerated, tool, outcome, code, user, ticket, correlation | order by TimeGenerated desc")
        $good = $rows | Where-Object { $_.outcome -eq 'ok' -and $_.user } | Select-Object -First 1
        if ($good) {
            $status = 'Succeeded'
            $message = "$($good.user) approved $($good.tool) on $($good.ticket) at $($good.TimeGenerated) UTC (correlation ID $($good.correlation))."
            break
        }
        elseif ($rows) { $message = "The write tool returned $($rows[0].code) for $($rows[0].ticket). Read the error in the playground and try again." }
        else { $message = 'No approved priority or status change has been logged yet. Logs can take a few minutes to arrive; validate again shortly.' }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
