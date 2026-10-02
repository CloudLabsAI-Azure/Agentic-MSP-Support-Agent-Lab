# Validation: Exercise 4, Task 3 - Chain grounding into an action
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the agent triaged TCK-10511 as Network and VPN, P2, and assigned it to the
# available Network technician Lucas Moreau (TECH-08). Marcus Webb (TECH-02, L3) is on leave,
# so assigning him is refused by the tool.

$ErrorActionPreference = 'Stop'
$status = 'Failed'
$message = ''
$query = @"
ContainerAppConsoleLogs
| where TimeGenerated > ago(24h)
| where ContainerAppName == 'ca-mcp-$DeploymentID'
| extend j = parse_json(Log)
| where tostring(j.event) == 'tool_call' and tostring(j.outcome) == 'ok' and tostring(j.caller) == 'agent'
| where tostring(j.arguments.ticket_number) == 'TCK-10511'
| where tostring(j.tool) in ('triage_ticket', 'assign_ticket', 'set_ticket_priority')
| project TimeGenerated, tool = tostring(j.tool), category = tostring(j.arguments.category),
          priority = toint(j.arguments.priority), technician = tostring(j.arguments.technician)
| order by TimeGenerated desc
"@

for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $workspace = Get-AzResource -ResourceType 'Microsoft.OperationalInsights/workspaces' -Name "log-msp-$DeploymentID" | Select-Object -First 1
        if (-not $workspace) { throw "Log Analytics workspace log-msp-$DeploymentID was not found." }
        $customerId = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $workspace.ResourceGroupName -Name $workspace.Name).CustomerId
        $rows = @((Invoke-AzOperationalInsightsQuery -WorkspaceId $customerId -Query $query).Results)
        $triage = $rows | Where-Object { $_.tool -eq 'triage_ticket' } | Select-Object -First 1
        $assign = $rows | Where-Object { $_.tool -eq 'assign_ticket' } | Select-Object -First 1

        if (-not $triage) {
            $message = 'TCK-10511 has not been triaged by the agent yet (no successful triage_ticket call logged).'
        }
        elseif ($triage.category -ne 'Network and VPN' -or [int]$triage.priority -ne 2) {
            $message = "TCK-10511 was triaged as $($triage.category), P$($triage.priority). Review the priority rules and KB0058, then triage it again."
        }
        elseif (-not $assign) {
            $message = 'TCK-10511 is triaged, but the agent has not assigned it yet.'
        }
        elseif ($assign.technician -notmatch '(?i)moreau|tech-08') {
            $message = "TCK-10511 was assigned to $($assign.technician). It should go to the available Network technician Lucas Moreau (TECH-08)."
        }
        else {
            $status = 'Succeeded'
            $message = "TCK-10511 was triaged as Network and VPN, P2, and assigned to $($assign.technician)."
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
