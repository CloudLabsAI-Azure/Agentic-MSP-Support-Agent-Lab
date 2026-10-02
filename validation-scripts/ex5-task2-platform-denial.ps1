# Validation: Exercise 5, Task 2 - Enforce a least-privilege boundary in Dataverse
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the MCP server logged a tool call that Dataverse refused
# (error_code DATAVERSE_ACCESS_DENIED), which only happens after the team replaced the
# application user's System Administrator role with a least-privilege role, AND a later
# allowed action (add_ticket_note) still succeeded.

$ErrorActionPreference = 'Stop'
$status = 'Failed'
$message = ''
$query = @"
ContainerAppConsoleLogs
| where TimeGenerated > ago(24h)
| where ContainerAppName == 'ca-mcp-$DeploymentID'
| extend j = parse_json(Log)
| where tostring(j.event) == 'tool_call'
| project TimeGenerated, tool = tostring(j.tool), outcome = tostring(j.outcome), error = tostring(j.error_code)
| order by TimeGenerated asc
"@

for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $workspace = Get-AzResource -ResourceType 'Microsoft.OperationalInsights/workspaces' -Name "log-msp-$DeploymentID" | Select-Object -First 1
        if (-not $workspace) { throw "Log Analytics workspace log-msp-$DeploymentID was not found." }
        $customerId = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $workspace.ResourceGroupName -Name $workspace.Name).CustomerId
        $rows = @((Invoke-AzOperationalInsightsQuery -WorkspaceId $customerId -Query $query).Results)
        $denied = $rows | Where-Object { $_.error -eq 'DATAVERSE_ACCESS_DENIED' } | Select-Object -First 1
        $allowedAfter = if ($denied) {
            $rows | Where-Object { $_.tool -eq 'add_ticket_note' -and $_.outcome -eq 'ok' -and [datetime]$_.TimeGenerated -gt [datetime]$denied.TimeGenerated } |
                Select-Object -First 1
        }

        if (-not $denied) {
            $message = 'No DATAVERSE_ACCESS_DENIED result has been logged. Assign the least-privilege role to the application user, remove System Administrator, and attempt the forbidden action again.'
        }
        elseif (-not $allowedAfter) {
            $message = "Dataverse refused $($denied.tool) at $($denied.TimeGenerated) UTC. Now confirm that an allowed action still works: add an internal note through the agent."
        }
        else {
            $status = 'Succeeded'
            $message = "Dataverse refused $($denied.tool) at $($denied.TimeGenerated) UTC and add_ticket_note still succeeded afterwards."
            break
        }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
