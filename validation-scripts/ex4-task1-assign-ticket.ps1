# Validation: Exercise 4, Task 1 - Use a write tool to assign a ticket
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the MCP server logged a successful assign_ticket call from the agent for
# TCK-10507 to the available Network technician Lucas Moreau (TECH-08). The call is the
# platform evidence; the Dataverse audit record is checked by the learner in the guide.

$ErrorActionPreference = 'Stop'
$status = 'Failed'
$message = ''
$query = @"
ContainerAppConsoleLogs
| where TimeGenerated > ago(24h)
| where ContainerAppName == 'ca-mcp-$DeploymentID'
| extend j = parse_json(Log)
| where tostring(j.event) == 'tool_call' and tostring(j.tool) == 'assign_ticket'
| where tostring(j.arguments.ticket_number) == 'TCK-10507'
| project TimeGenerated, outcome = tostring(j.outcome), error = tostring(j.error_code),
          caller = tostring(j.caller), technician = tostring(j.arguments.technician)
| order by TimeGenerated desc
"@

for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $workspace = Get-AzResource -ResourceType 'Microsoft.OperationalInsights/workspaces' -Name "log-msp-$DeploymentID" | Select-Object -First 1
        if (-not $workspace) { throw "Log Analytics workspace log-msp-$DeploymentID was not found." }
        $customerId = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $workspace.ResourceGroupName -Name $workspace.Name).CustomerId
        $rows = @((Invoke-AzOperationalInsightsQuery -WorkspaceId $customerId -Query $query).Results)
        $good = $rows | Where-Object { $_.outcome -eq 'ok' -and $_.caller -eq 'agent' -and $_.technician -match '(?i)moreau|tech-08' } | Select-Object -First 1

        if ($good) {
            $status = 'Succeeded'
            $message = "The agent assigned TCK-10507 to $($good.technician) at $($good.TimeGenerated) UTC."
            break
        }
        elseif ($rows | Where-Object { $_.outcome -eq 'ok' }) {
            $message = 'TCK-10507 was assigned, but not by the agent to the available Network technician Lucas Moreau (TECH-08). Ask the agent to reassign it.'
        }
        elseif ($rows) {
            $message = "The agent tried to assign TCK-10507 but the tool returned $($rows[0].error). Read the error in the playground and retry."
        }
        else {
            $message = 'No assign_ticket call for TCK-10507 has been logged yet. Logs can take a few minutes to arrive; validate again shortly.'
        }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
