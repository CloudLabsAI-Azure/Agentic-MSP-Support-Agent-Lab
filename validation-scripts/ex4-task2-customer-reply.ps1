# Validation: Exercise 4, Task 2 - Separate a public reply from an internal note
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the agent added both a customer-visible reply (is_internal false) and an
# internal note (is_internal true) to the same ticket through add_ticket_note.

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
        $rows = Invoke-LogQuery ($toolCalls + "| where tool == 'add_ticket_note' and outcome == 'ok' and caller == 'agent' | extend ticket = tostring(j.arguments.ticket_number), internal = tobool(j.arguments.is_internal) | project TimeGenerated, ticket, internal")
        $both = $rows | Group-Object ticket | Where-Object { ($_.Group.internal -contains $true) -and ($_.Group.internal -contains $false) } | Select-Object -First 1
        if ($both) {
            $status = 'Succeeded'
            $message = "Ticket $($both.Name) has an agent-written customer-visible reply and an internal note."
            break
        }
        elseif ($rows) { $message = "The agent added notes, but not both a customer-visible reply and an internal note on one ticket yet." }
        else { $message = 'No note from the agent has been logged yet. Logs can take a few minutes to arrive; validate again shortly.' }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
