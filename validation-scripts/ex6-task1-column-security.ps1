# Validation: Exercise 6, Task 1 - Restrict what the agent can return
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the MCP server logged a successful get_customer_contacts call from the agent
# that saw at least one secured contact column (record.secured_columns is not empty), which
# means column security is on for the contact table and the call ran after it was enabled.

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
        $rows = Invoke-LogQuery ($toolCalls + "| where tool == 'get_customer_contacts' and outcome == 'ok' and caller == 'agent' | extend secured = j.record.secured_columns | where array_length(secured) > 0 | project TimeGenerated, customer = tostring(j.arguments.customer), secured = tostring(secured) | order by TimeGenerated desc | take 1")
        if ($rows) {
            $status = 'Succeeded'
            $message = "The agent's get_customer_contacts call for $($rows[0].customer) at $($rows[0].TimeGenerated) UTC saw secured columns $($rows[0].secured)."
            break
        }
        else { $message = 'No get_customer_contacts call has seen a secured contact column yet. Turn on column security for the contact e-mail and mobile columns, then ask the agent for contact details again. Logs can take a few minutes to arrive; validate again shortly.' }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
