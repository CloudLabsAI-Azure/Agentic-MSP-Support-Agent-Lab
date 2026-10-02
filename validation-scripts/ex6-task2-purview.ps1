# Validation: Exercise 6, Task 2 - Apply Microsoft Purview data protection
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID -> $DeploymentID
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when data protection withheld content from the agent: Microsoft Purview blocked or
# redacted a tool result (purview.action block or redact), or a document's sensitivity label
# blocked it (CONTENT_BLOCKED_BY_LABEL).

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
        $rows = Invoke-LogQuery ($toolCalls + "| extend action = tostring(j.purview.action), checked = tobool(j.purview.checked) | where action in ('block', 'redact') or code in ('CONTENT_BLOCKED_BY_POLICY', 'CONTENT_BLOCKED_BY_LABEL') | project TimeGenerated, tool, code, action, checked, user, correlation | order by TimeGenerated desc")
        $purview = $rows | Where-Object { $_.checked -and $_.action -in 'block', 'redact' } | Select-Object -First 1
        $label = $rows | Where-Object { $_.code -eq 'CONTENT_BLOCKED_BY_LABEL' } | Select-Object -First 1
        if ($purview) {
            $status = 'Succeeded'
            $message = "Microsoft Purview $($purview.action)ed the result of $($purview.tool) for $($purview.user) at $($purview.TimeGenerated) UTC (correlation ID $($purview.correlation))."
            break
        }
        elseif ($label) {
            $status = 'Succeeded'
            $message = "The sensitivity label blocked $($label.tool) at $($label.TimeGenerated) UTC (correlation ID $($label.correlation))."
            break
        }
        else { $message = 'No content has been withheld by Purview or a sensitivity label yet. Ask the agent for the seeded sensitive value or the labelled document. Logs can take a few minutes to arrive; validate again shortly.' }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
