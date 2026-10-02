# Validation: Exercise 5, Task 3 - Protect contact data
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
$query = @"
ContainerAppConsoleLogs
| where TimeGenerated > ago(24h)
| where ContainerAppName == 'ca-mcp-$DeploymentID'
| extend j = parse_json(Log)
| where tostring(j.event) == 'tool_call' and tostring(j.tool) == 'get_customer_contacts' and tostring(j.outcome) == 'ok'
| where tostring(j.caller) == 'agent'
| extend secured = j.record.secured_columns
| where array_length(secured) > 0
| project TimeGenerated, customer = tostring(j.arguments.customer), secured = tostring(secured)
| order by TimeGenerated desc
| take 1
"@

for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $workspace = Get-AzResource -ResourceType 'Microsoft.OperationalInsights/workspaces' -Name "log-msp-$DeploymentID" | Select-Object -First 1
        if (-not $workspace) { throw "Log Analytics workspace log-msp-$DeploymentID was not found." }
        $customerId = (Get-AzOperationalInsightsWorkspace -ResourceGroupName $workspace.ResourceGroupName -Name $workspace.Name).CustomerId
        $row = @((Invoke-AzOperationalInsightsQuery -WorkspaceId $customerId -Query $query).Results) | Select-Object -First 1

        if ($row) {
            $status = 'Succeeded'
            $message = "get_customer_contacts for '$($row.customer)' ran with secured columns $($row.secured) at $($row.TimeGenerated) UTC."
            break
        }
        $message = 'No contact lookup by the agent has seen a secured column yet. Enable column security on the contact columns, then ask the agent for the contacts again.'
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
