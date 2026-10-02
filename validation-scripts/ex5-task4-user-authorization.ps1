# Validation: Exercise 5, Task 4 - Apply user-level authorization
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the same write tool was refused by Dataverse for one signed-in user (the Tier 1
# Technician) and succeeded for another (the Senior Technician), both through the agent.

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
        $writes = 'triage_ticket','set_ticket_priority','update_ticket_status','assign_ticket','add_ticket_note'
        $rows = Invoke-LogQuery ($toolCalls + "| where caller == 'agent' and isnotempty(user) | project TimeGenerated, tool, outcome, code, user, correlation | order by TimeGenerated desc")
        $denied = @($rows | Where-Object { $_.tool -in $writes -and $_.code -eq 'DATAVERSE_ACCESS_DENIED' })
        $pair = foreach ($d in $denied) {
            $ok = $rows | Where-Object { $_.tool -eq $d.tool -and $_.outcome -eq 'ok' -and $_.user -ne $d.user } | Select-Object -First 1
            if ($ok) { [pscustomobject]@{ Denied = $d; Allowed = $ok }; break }
        }
        if ($pair) {
            $status = 'Succeeded'
            $message = "$($pair.Denied.tool) was denied for $($pair.Denied.user) and allowed for $($pair.Allowed.user) through the same agent and MCP server."
            break
        }
        elseif ($denied) { $message = "$($denied[0].tool) was denied for $($denied[0].user). Now make the same change as the Senior Technician." }
        else { $message = 'No write denied for the Tier 1 Technician has been logged yet. Sign in as Tier 1 and ask for the change. Logs can take a few minutes to arrive; validate again shortly.' }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
