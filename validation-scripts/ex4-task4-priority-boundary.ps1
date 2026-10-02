# Validation: Exercise 4, Task 4 - Apply the guided fix to an argument boundary
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the MCP server logged a set_ticket_priority call for TCK-10501 with priority 1
# that was ACCEPTED before the fix and a later one that was REJECTED with
# PRIORITY_NOT_ALLOWED after the fix, and TCK-10501 was then set back to P4.

$ErrorActionPreference = 'Stop'
$status = 'Failed'
$message = ''
$query = @"
ContainerAppConsoleLogs
| where TimeGenerated > ago(24h)
| where ContainerAppName == 'ca-mcp-$DeploymentID'
| extend j = parse_json(Log)
| where tostring(j.event) == 'tool_call' and tostring(j.tool) == 'set_ticket_priority'
| where tostring(j.arguments.ticket_number) == 'TCK-10501'
| project TimeGenerated, priority = toint(j.arguments.priority), outcome = tostring(j.outcome), error = tostring(j.error_code)
| order by TimeGenerated asc
"@

for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $workspace = Get-AzResource -ResourceType 'Microsoft.OperationalInsights/workspaces' -Name "log-msp-$DeploymentID" | Select-Object -First 1
        if (-not $workspace) { throw "Log Analytics workspace log-msp-$DeploymentID was not found." }
        $customerId = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $workspace.ResourceGroupName -Name $workspace.Name).CustomerId
        $rows = @((Invoke-AzOperationalInsightsQuery -WorkspaceId $customerId -Query $query).Results)
        $accepted = $rows | Where-Object { [int]$_.priority -eq 1 -and $_.outcome -eq 'ok' } | Select-Object -First 1
        $rejected = $rows | Where-Object { [int]$_.priority -eq 1 -and $_.error -eq 'PRIORITY_NOT_ALLOWED' } | Select-Object -Last 1
        $restored = if ($rejected) {
            $rows | Where-Object { [int]$_.priority -eq 4 -and $_.outcome -eq 'ok' -and [datetime]$_.TimeGenerated -gt [datetime]$rejected.TimeGenerated } |
                Select-Object -First 1
        }

        if (-not $accepted) {
            $message = 'No accepted P1 call for TCK-10501 was logged. Run the boundary test before applying the fix, as described in the guide.'
        }
        elseif (-not $rejected) {
            $message = 'The P1 call was accepted before the fix, but no PRIORITY_NOT_ALLOWED rejection is logged yet. Apply the fix, redeploy, and repeat the call.'
        }
        elseif ([datetime]$rejected.TimeGenerated -lt [datetime]$accepted.TimeGenerated) {
            $message = 'The rejection was logged before the accepted call. Repeat the P1 call after the fix is deployed.'
        }
        elseif (-not $restored) {
            $message = 'The boundary now rejects P1. Set TCK-10501 back to P4 to finish the task.'
        }
        else {
            $status = 'Succeeded'
            $message = "P1 on TCK-10501 was accepted at $($accepted.TimeGenerated) UTC, rejected with PRIORITY_NOT_ALLOWED at $($rejected.TimeGenerated) UTC, and the ticket was set back to P4."
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
