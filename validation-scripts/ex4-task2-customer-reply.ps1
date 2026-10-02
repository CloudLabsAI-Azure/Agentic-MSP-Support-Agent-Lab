# Validation: Exercise 4, Task 2 - Separate a public reply from an internal note
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the agent added BOTH a customer-visible reply (is_internal = false) and an
# internal note (is_internal = true) to TCK-10489. Whether the reply leaks internal content
# is checked by the learner against the Success Criteria in the guide.

$ErrorActionPreference = 'Stop'
$status = 'Failed'
$message = ''
$query = @"
ContainerAppConsoleLogs
| where TimeGenerated > ago(24h)
| where ContainerAppName == 'ca-mcp-$DeploymentID'
| extend j = parse_json(Log)
| where tostring(j.event) == 'tool_call' and tostring(j.tool) == 'add_ticket_note' and tostring(j.outcome) == 'ok'
| where tostring(j.caller) == 'agent' and tostring(j.arguments.ticket_number) == 'TCK-10489'
| summarize public = countif(tobool(j.arguments.is_internal) == false), internal = countif(tobool(j.arguments.is_internal) == true)
"@

for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $workspace = Get-AzResource -ResourceType 'Microsoft.OperationalInsights/workspaces' -Name "log-msp-$DeploymentID" | Select-Object -First 1
        if (-not $workspace) { throw "Log Analytics workspace log-msp-$DeploymentID was not found." }
        $customerId = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $workspace.ResourceGroupName -Name $workspace.Name).CustomerId
        $row = @((Invoke-AzOperationalInsightsQuery -WorkspaceId $customerId -Query $query).Results)[0]
        $public = [int]$row.public
        $internal = [int]$row.internal

        if ($public -ge 1 -and $internal -ge 1) {
            $status = 'Succeeded'
            $message = "The agent added $public customer-visible reply(ies) and $internal internal note(s) to TCK-10489."
            break
        }
        elseif ($public -lt 1) {
            $message = 'No customer-visible reply (is_internal = false) from the agent on TCK-10489 has been logged yet.'
        }
        else {
            $message = 'The customer reply is logged, but no internal note (is_internal = true) from the agent on TCK-10489 yet.'
        }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
