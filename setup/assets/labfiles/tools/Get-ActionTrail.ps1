#Requires -Version 7.0
<#
.SYNOPSIS
    Shows the end-to-end trail of one agent action from its correlation ID: the agent run in
    Application Insights, the API Management gateway, the MCP server's tool invocation log and
    the Dataverse record and audit history.

.DESCRIPTION
    Every tool result ends with a correlation_id: the request ID API Management gave the call.
    The same value is the CorrelationId in ApiManagementGatewayLogs, the correlation_id in the
    MCP server's log line, the ticket's Last Correlation ID after a write, and it appears in the
    agent's tool output that Foundry traces to Application Insights. This script looks it up at
    every hop and prints one timeline.

    Log Analytics ingestion takes a few minutes, so run it about five minutes after the action.
    Uses your own Azure CLI sign-in (Log Analytics Reader on the workspace, and your Dataverse
    access for the audit history). Run 'az login' first.

.EXAMPLE
    C:\LabFiles\tools\Get-ActionTrail.ps1 -CorrelationId 0b6f3c9e-6d2a-4f55-9a43-2d7c1e8b5a10
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$CorrelationId,
    [int]$LookbackHours = 24,
    [string]$SettingsPath = 'C:\LabFiles\team-settings.json'
)

$ErrorActionPreference = 'Stop'
if ($CorrelationId -notmatch '^[0-9a-fA-F-]{36}$') { throw 'A correlation ID is a GUID, for example 0b6f3c9e-6d2a-4f55-9a43-2d7c1e8b5a10.' }
$settings = Get-Content $SettingsPath -Raw | ConvertFrom-Json
function Token([string]$resource) {
    $t = az account get-access-token --resource $resource --query accessToken --output tsv 2>$null
    if (-not $t) { throw "Run 'az login' first (no token for $resource)." }
    return $t
}
$workspaceId = az monitor log-analytics workspace show --resource-group $settings.ResourceGroup --workspace-name $settings.LogAnalyticsWorkspace `
    --query customerId --output tsv 2>$null
if (-not $workspaceId) { throw "Could not read the Log Analytics workspace $($settings.LogAnalyticsWorkspace). Run 'az login' first." }
$laToken = Token 'https://api.loganalytics.io'
function Query([string]$kql) {
    $body = @{ query = $kql; timespan = "PT$($LookbackHours)H" } | ConvertTo-Json
    $r = Invoke-RestMethod -Method Post -Uri "https://api.loganalytics.io/v1/workspaces/$workspaceId/query" `
        -Headers @{ Authorization = "Bearer $laToken" } -ContentType 'application/json' -Body $body
    $table = $r.tables[0]
    foreach ($row in $table.rows) {
        $o = [ordered]@{}
        for ($i = 0; $i -lt $table.columns.Count; $i++) { $o[$table.columns[$i].name] = $row[$i] }
        [pscustomobject]$o
    }
}

$trail = [System.Collections.Generic.List[object]]::new()
function Add-Hop($time, [string]$hop, [string]$what, [string]$who, [string]$result) {
    $trail.Add([pscustomobject]@{ Time = ([datetime]$time).ToUniversalTime().ToString('HH:mm:ss.fff'); Hop = $hop; What = $what; Identity = $who; Result = $result })
}

# 1. The agent run (Application Insights, in the same workspace).
# The agent's tool output, which ends with the correlation ID, is in AppGenAIContent.
$agentSpans = @(Query @"
union isfuzzy=true
    (AppGenAIContent | where ToolCallResult has '$CorrelationId' or ToolCallArguments has '$CorrelationId'
     | project TimeGenerated, OperationId = tostring(TraceId)),
    (AppDependencies | where * has '$CorrelationId' | project TimeGenerated, OperationId)
| take 1
| join kind=inner (union isfuzzy=true AppDependencies, AppRequests | project TimeGenerated, OperationId, Name, Success, ResultCode) on OperationId
| project TimeGenerated=TimeGenerated1, Name, Success, ResultCode, OperationId
| order by TimeGenerated asc
"@)
foreach ($s in $agentSpans) { Add-Hop $s.TimeGenerated '1 Agent (App Insights)' $s.Name $settings.AgentName "success=$($s.Success) trace=$($s.OperationId)" }
if (-not $agentSpans) { Add-Hop (Get-Date) '1 Agent (App Insights)' 'no trace found yet (tracing can take several minutes)' '' '' }

# 2. The gateway.
foreach ($g in @(Query @"
ApiManagementGatewayLogs
| where CorrelationId == '$CorrelationId'
| project TimeGenerated, Method, Url, ResponseCode, BackendResponseCode, TotalTime, ApiId
"@)) { Add-Hop $g.TimeGenerated '2 API Management' "$($g.Method) $($g.ApiId)" 'token validated (user)' "HTTP $($g.ResponseCode), backend $($g.BackendResponseCode), $($g.TotalTime) ms" }

# 3. The MCP server's tool invocation log.
foreach ($m in @(Query @"
ContainerAppConsoleLogs
| where Log has '$CorrelationId'
| extend e = parse_json(Log)
| where e.event == 'tool_call'
| project TimeGenerated, tool = tostring(e.tool), outcome = tostring(e.outcome), code = tostring(e.error_code),
          user = tostring(e.user.name), decided = tostring(e.authorization.decided_by), acting = tostring(e.authorization.acting_as),
          dataverse = e.dataverse
"@)) {
    Add-Hop $m.TimeGenerated '3 MCP server' "tool $($m.tool)" "$($m.user) (acting as $($m.acting))" "$($m.outcome) $($m.code), decided by $($m.decided)"
    foreach ($call in @($m.dataverse | ConvertFrom-Json -ErrorAction SilentlyContinue)) {
        if ($call) { Add-Hop $m.TimeGenerated '4 Dataverse call' "$($call.method) $($call.path)" "on behalf of user: $($call.on_behalf_of_user)" "HTTP $($call.status) request $($call.request_id)" }
    }
}

# 4. The Dataverse record and its audit history.
$dv = $settings.DataverseUrl.TrimEnd('/')
$dvHeaders = @{ Authorization = "Bearer $(Token $dv)"; Accept = 'application/json'
                Prefer = 'odata.include-annotations="OData.Community.Display.V1.FormattedValue"' }
$ticket = (Invoke-RestMethod -Headers $dvHeaders -Uri "$dv/api/data/v9.2/spk_tickets?`$select=spk_ticketid,spk_ticketnumber,spk_correlationid,modifiedon&`$filter=spk_correlationid eq '$CorrelationId'").value |
    Select-Object -First 1
if ($ticket) {
    $audits = (Invoke-RestMethod -Headers $dvHeaders -Uri ("$dv/api/data/v9.2/audits?`$select=createdon,action,_userid_value,_callinguserid_value" +
        "&`$filter=_objectid_value eq $($ticket.spk_ticketid)&`$orderby=createdon desc&`$top=3")).value
    foreach ($a in $audits) {
        $user = $a.'_userid_value@OData.Community.Display.V1.FormattedValue'
        $caller = $a.'_callinguserid_value@OData.Community.Display.V1.FormattedValue'
        Add-Hop $a.createdon '5 Dataverse audit' "$($ticket.spk_ticketnumber) $($a.'action@OData.Community.Display.V1.FormattedValue')" `
            "$user$(if ($caller) { " (called by $caller)" })" 'recorded'
    }
    Add-Hop $ticket.modifiedon '5 Dataverse record' "$($ticket.spk_ticketnumber) Last Correlation ID" '' $ticket.spk_correlationid
}
else { Add-Hop (Get-Date) '5 Dataverse record' 'no ticket carries this correlation ID (a read, or a refused write)' '' '' }

$trail | Sort-Object Hop, Time | Format-Table -AutoSize -Wrap
