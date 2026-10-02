# Validation: Exercise 2, Task 1 - Identify similar historical incidents
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the agent read the new incident TCK-10514 through the Service Desk tools. The
# incident is not in the knowledge index, so the agent can only see it through a read tool.

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
        $rows = Invoke-LogQuery ($toolCalls + "| where caller == 'agent' and tostring(j.arguments.ticket_number) == 'TCK-10514' | project TimeGenerated, tool, outcome, code, user, correlation | order by TimeGenerated desc")
        $good = $rows | Where-Object { $_.outcome -eq 'ok' -and $_.tool -in 'get_ticket', 'get_ticket_notes' } | Select-Object -First 1
        if ($good) {
            $status = 'Succeeded'
            $message = "The agent read the new incident TCK-10514 with $($good.tool) at $($good.TimeGenerated) UTC (correlation ID $($good.correlation))."
            break
        }
        elseif ($rows) { $message = "The agent tried to read TCK-10514 but the tool returned $($rows[0].outcome) $($rows[0].code). Ask it again." }
        else { $message = 'The agent has not read TCK-10514 yet. Ask it to open the new incident with the Service Desk tools. Logs can take a few minutes to arrive; validate again shortly.' }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
