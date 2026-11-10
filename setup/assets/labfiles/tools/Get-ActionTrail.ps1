#Requires -Version 7.0
<#
.SYNOPSIS
    Assembles the full audit trail of one agent action from its correlation ID, as one timeline,
    and exports it as evidence (Exercises 6 and 7).

.DESCRIPTION
    API Management gives every Service Desk tool call a correlation ID, and the MCP server returns
    it at the end of every tool result. This script looks that one value up in every place the
    action left a record and prints them as one timeline:

      Application Insights   the agent run: your request, the model's tool decision, the tool
                             result and the answer (tables AppDependencies, AppRequests,
                             AppGenAIContent)
      Foundry conversation   the approval request (server, tool, full arguments), your decision
                             and the tool call (items mcp_approval_request, mcp_approval_response,
                             mcp_call). A rejected call never reaches the gateway, so its only
                             record is here.
      API Management         the gateway rows (ApiManagementGatewayLogs, ApiManagementGatewayMCPLog)
      MCP server             the tool invocation log line (ContainerAppConsoleLogs): user, agent ID,
                             tool, argument summary, authorization result, backend calls, outcome,
                             duration
      Dataverse              the audit record of the change (who, and which application acted for
                             them, with old and new values) and the Agent Action row

    It then answers: who asked, which agent, which tool, what was authorized, what changed and what
    was returned. -OutFile exports the evidence as JSON and Markdown.

    Latency: the agent's traces usually appear 2 to 5 minutes after the action, and gateway and
    console logs reach Log Analytics within minutes (usually 3 to 10). A hop that hasn't arrived yet
    is listed as not found yet; run the script again a few minutes later, or add -WaitMinutes 10 to
    keep checking. A read or a denied call leaves no Dataverse audit record, because Dataverse audits
    changes only.

    Read-only. Uses your own Azure CLI sign-in (the Senior Technician holds Log Analytics Reader on
    the workspace, Foundry User on the project and the Service Desk roles in Dataverse). Your
    conversations are visible only to you, so approvals made by another user (for example the Tier 1
    Technician) appear only in their own trail.

.PARAMETER CorrelationId
    The correlation_id at the end of a tool result (or in the MCP server log).

.PARAMETER ConversationId
    The conversation to read approvals from. Optional with -CorrelationId (the script finds the
    conversation itself when it can); on its own, it lists every approval and tool call in that
    conversation, including rejected ones. In the Foundry portal: your agent > Traces > open the run.

.PARAMETER From
    Start of the time window to search, in UTC. Default: -LookbackHours before now.

.PARAMETER WaitMinutes
    Keep checking for hops that haven't arrived yet, for up to this many minutes.

.PARAMETER OutFile
    Base path for the evidence files; the script writes <OutFile>.json and <OutFile>.md.

.EXAMPLE
    C:\LabFiles\tools\Get-ActionTrail.ps1 -CorrelationId 0b6f3c9e-6d2a-4f55-9a43-2d7c1e8b5a10

.EXAMPLE
    C:\LabFiles\tools\Get-ActionTrail.ps1 0b6f3c9e-6d2a-4f55-9a43-2d7c1e8b5a10 -WaitMinutes 10 -OutFile "$HOME\Documents\trail-priority-change"

.EXAMPLE
    C:\LabFiles\tools\Get-ActionTrail.ps1 -ConversationId conv_0123456789abcdef
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$CorrelationId,
    [string]$ConversationId,
    [Nullable[datetime]]$From,
    [Nullable[datetime]]$To,
    [ValidateRange(1, 168)][int]$LookbackHours = 24,
    [ValidateRange(0, 30)][int]$WaitMinutes = 0,
    [string]$OutFile,
    [switch]$PassThru,
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json'
)

$ErrorActionPreference = 'Stop'

# ==== Output and text helpers
function Write-Section([string]$Text) { Write-Host ''; Write-Host "==== $Text" -ForegroundColor Cyan }
function Stop-Script([string]$Text) { Write-Host ''; Write-Host "Stopped: $Text" -ForegroundColor Red; exit 1 }
function Get-First {
    # The first argument that holds a value: not null, not an empty string, not an empty list.
    foreach ($v in $args) {
        if ($null -eq $v) { continue }
        if ($v -is [string]) { if ($v -ne '') { return $v }; continue }
        if ($v -is [System.Collections.ICollection] -and $v.Count -eq 0) { continue }
        return $v
    }
    return $null
}

function Protect-Text([string]$Text, [switch]$FreeText) {
    # Never let a credential reach the screen or the evidence files. Free text (prompts, answers,
    # tool results) also gets card-like numbers withheld.
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $t = [regex]::Replace($Text, '(?i)\bBearer\s+[A-Za-z0-9\-_.=~+/]+', 'Bearer [redacted]')
    $t = [regex]::Replace($t, '\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}', '[token redacted]')
    $t = [regex]::Replace($t, '(?i)((?:x-backend-key|ocp-apim-subscription-key|api-key|client_secret|clientsecret|password|accountkey|sharedaccesskey|sig)\s*["'']?\s*[:=]\s*["'']?)[^"'',;&\s}]+', '$1[redacted]')
    if ($FreeText) {
        # Card-like numbers: 13 to 19 digits, single spaces or dashes allowed between them. GUIDs
        # (correlation IDs, object IDs) are split out first so they are never touched.
        $guid = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
        $t = -join ([regex]::Split($t, "($guid)") | ForEach-Object {
            if ($_ -match "^$guid$") { $_ } else { [regex]::Replace($_, '(?<![\w-])\d(?:[ -]?\d){12,18}(?![\w-])', '[number withheld]') }
        })
    }
    return $t
}

function Limit-Text($Value, [int]$Max = 240) {
    if ($null -eq $Value) { return '' }
    $s = if ($Value -is [string]) { $Value } else { $Value | ConvertTo-Json -Depth 8 -Compress }
    $s = ($s -replace '\s+', ' ').Trim()
    if ($s.Length -gt $Max) { return $s.Substring(0, $Max - 3) + '...' }
    return $s
}

function ConvertTo-Utc($Value) {
    if ($null -eq $Value -or "$Value" -eq '') { return $null }
    if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime }
    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [DateTimeKind]::Local) { return $Value.ToUniversalTime() }
        return [datetime]::SpecifyKind($Value, [DateTimeKind]::Utc)
    }
    if ("$Value" -match '^\d{9,11}$') { return [DateTimeOffset]::FromUnixTimeSeconds([long]$Value).UtcDateTime }
    try { return ([datetimeoffset]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture)).UtcDateTime } catch { return $null }
}

function Get-Text($Content) {
    # Text out of a message: a plain string, a list of parts, or OpenAI style content items.
    if ($null -eq $Content) { return '' }
    if ($Content -is [string]) { return $Content }
    $parts = foreach ($c in @($Content)) {
        if ($c -is [string]) { $c } else { Get-First $c.text $c.content $c.value }
    }
    return (@($parts | Where-Object { $_ -is [string] }) -join ' ')
}

function Get-MessageText([string]$Json, [string]$Role) {
    # gen_ai.input.messages / gen_ai.output.messages: [{"role": "...", "parts": [{"type": "text", "content": "..."}]}]
    if ([string]::IsNullOrWhiteSpace($Json)) { return '' }
    try { $messages = @($Json | ConvertFrom-Json) } catch { return '' }
    $texts = foreach ($m in $messages) {
        if ($Role -and $m.role -ne $Role) { continue }
        Get-Text (Get-First $m.parts $m.content)
    }
    return (@($texts | Where-Object { $_ }) | Select-Object -Last 1)
}

# ==== Settings, tokens and REST
function Read-LabSettings([string]$Path, [string[]]$Required) {
    if (-not (Test-Path -LiteralPath $Path)) { throw "The lab settings file $Path was not found. Lab provisioning writes it; contact CloudLabs support if it is missing." }
    try { $s = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json }
    catch { throw "The lab settings file $Path is not valid JSON ($($_.Exception.Message)). Contact CloudLabs support." }
    $missing = @($Required | Where-Object { -not $s.PSObject.Properties[$_] -or [string]::IsNullOrWhiteSpace([string]$s.$_) })
    if ($missing.Count) { throw "The lab settings file $Path has no value for: $($missing -join ', '). Contact CloudLabs support." }
    return $s
}

function Get-AzCliToken([string]$Resource) {
    $cliArgs = @('account', 'get-access-token', '--resource', $Resource, '--query', 'accessToken', '--output', 'tsv')
    if ($script:Settings.TenantId) { $cliArgs += @('--tenant', $script:Settings.TenantId) }
    $token = & az @cliArgs 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace("$token")) { return $null }
    return ("$token").Trim()
}

function Invoke-Rest([string]$Method, [string]$Uri, [string]$Token, $Body, [hashtable]$Headers = @{}) {
    $h = @{ Authorization = "Bearer $Token" } + $Headers
    $params = @{ Method = $Method; Uri = $Uri; Headers = $h; SkipHttpErrorCheck = $true; StatusCodeVariable = 'httpStatus'; TimeoutSec = 120 }
    if ($null -ne $Body) { $params.Body = ($Body | ConvertTo-Json -Depth 20); $params.ContentType = 'application/json' }
    try { $result = Invoke-RestMethod @params }
    catch { return [pscustomobject]@{ Status = 0; Body = $null; Error = $_.Exception.Message } }
    $err = if ([int]$httpStatus -ge 400) { Get-First $result.error.innererror.message $result.error.message ($(if ($result) { Limit-Text $result 300 })) "HTTP $httpStatus" } else { $null }
    return [pscustomobject]@{ Status = [int]$httpStatus; Body = $result; Error = $err }
}

function Invoke-LogQuery([string]$Kql) {
    $body = @{ query = $Kql; timespan = "$($script:FromIso)/$($script:ToIso)" }
    $r = Invoke-Rest POST "https://api.loganalytics.io/v1/workspaces/$($script:WorkspaceId)/query" $script:LaToken $body
    if ($r.Status -eq 0) { throw "Log Analytics could not be reached: $($r.Error)" }
    if ($r.Status -eq 401 -or $r.Status -eq 403) { throw "Your account may not query the workspace $($script:Settings.LogAnalyticsWorkspace) (HTTP $($r.Status)). The Senior Technician holds Log Analytics Reader on it." }
    if ($r.Status -ge 400) {
        if ("$($r.Error)" -match '(?i)Failed to resolve (table|scalar|column)') { throw [System.IO.FileNotFoundException]::new('table not present yet') }
        throw "The log query failed: $($r.Error)"
    }
    $table = @($r.Body.tables)[0]
    $names = @($table.columns.name)
    foreach ($row in @($table.rows)) {
        $o = [ordered]@{}
        for ($i = 0; $i -lt $names.Count; $i++) { $o[$names[$i]] = $row[$i] }
        [pscustomobject]$o
    }
}

# ==== Trail model
$script:Events = [System.Collections.Generic.List[object]]::new()
$script:Sources = [ordered]@{}
$script:Raw = [ordered]@{}
$script:Sequence = 0

function Add-Event($Time, [string]$Source, [string]$Step, [string]$Identity, [string]$Result, [switch]$Approximate) {
    $script:Sequence++
    $script:Events.Add([pscustomobject]@{
        Time = ConvertTo-Utc $Time; Approximate = [bool]$Approximate; Order = $script:Sequence
        Source = $Source; Step = (Protect-Text $Step -FreeText); Identity = (Protect-Text $Identity -FreeText); Result = (Protect-Text $Result -FreeText)
    })
}

function Set-Source([string]$Name, [string]$Status, [string]$Detail) {
    $script:Sources[$Name] = [pscustomobject]@{ Source = $Name; Status = $Status; Detail = $Detail }
}

# ==== 1. MCP server tool invocation log
function ConvertFrom-McpLine($Row) {
    try { $e = $Row.Log | ConvertFrom-Json -ErrorAction Stop } catch { return $null }
    if ($e -isnot [pscustomobject]) { return $null }
    $auth = $e.authorization
    $authText = if ($auth -is [string]) { $auth } else { Get-First $e.authorization_result $auth.result }
    [pscustomobject]@{
        Time      = ConvertTo-Utc (Get-First $e.time $e.timestamp $Row.TimeGenerated)
        Event     = [string]$e.event
        Message   = [string]$e.message
        Tool      = [string]$e.tool
        Endpoint  = [string](Get-First $e.endpoint $e.gateway $e.api $e.caller)
        Outcome   = [string]$e.outcome
        ErrorCode = [string](Get-First $e.error_code $e.error.code)
        AuthResult = [string]$authText
        DecidedBy = [string](Get-First $e.authorization_decided_by $(if ($auth -isnot [string]) { $auth.decided_by }))
        ActingAs  = [string](Get-First $e.acting_as $(if ($auth -isnot [string]) { $auth.acting_as }))
        UserName  = [string](Get-First $e.user.upn $e.user.preferred_username $e.user.name $e.user_name)
        UserOid   = [string](Get-First $e.user.oid $e.user.object_id $e.user_oid)
        AgentName = [string](Get-First $e.agent.name $e.agent_name)
        AgentId   = [string](Get-First $e.agent.id $e.agent_id)
        Arguments = Get-First $e.arguments $e.argument_summary $e.args
        Duration  = Get-First $e.duration_ms $e.latency_ms
        Backend   = @(Get-First $e.backend_calls $e.backend $e.dataverse)
        Purview   = $e.purview
        Record    = Get-First $e.record $e.result_summary
        Approval  = Get-First $e.approval $e.approval_id
        Revision  = [string]$Row.RevisionName
        Image     = [string]$Row.ContainerImage
        Raw       = $e
    }
}

function Get-McpTrail {
    $kql = @"
ContainerAppConsoleLogs
| where ContainerAppName =~ '$($script:Settings.ContainerApp)'
| where Log contains '$CorrelationId'
| project TimeGenerated, RevisionName, ContainerImage, Log
| order by TimeGenerated asc
| take 50
"@
    try { $rows = @(Invoke-LogQuery $kql) }
    catch [System.IO.FileNotFoundException] { Set-Source 'MCP server log' 'Not found yet' 'No Container Apps console logs have reached the workspace yet (usually minutes after the first call).'; return @() }
    catch { Set-Source 'MCP server log' 'Unavailable' $_.Exception.Message; return @() }
    $lines = @($rows | ForEach-Object { ConvertFrom-McpLine $_ } | Where-Object { $_ })
    $script:Raw['mcpServerLog'] = @($lines | ForEach-Object { $_.Raw })
    $calls = @($lines | Where-Object { $_.Event -eq 'tool_call' -or $_.Tool })
    if (-not $lines.Count) { Set-Source 'MCP server log' 'Not found yet' 'No log line carries this correlation ID yet. Console logs reach Log Analytics within minutes.'; return @() }
    foreach ($l in $lines) {
        if ($l.Tool) {
            $who = if ($l.UserName -or $l.UserOid) { "$($l.UserName)$(if ($l.UserOid) { " (object ID $($l.UserOid))" })" } else { 'no signed-in user (diagnostics API)' }
            $auth = (@($l.AuthResult, $(if ($l.DecidedBy) { "decided by $($l.DecidedBy)" }), $(if ($l.ActingAs) { "acting as $($l.ActingAs)" })) | Where-Object { $_ }) -join ', '
            $res = "$($l.Outcome)$(if ($l.ErrorCode) { " $($l.ErrorCode)" }); authorization: $(if ($auth) { $auth } else { 'not logged' })$(if ($null -ne $l.Duration) { "; $([Math]::Round([double]$l.Duration)) ms" })"
            Add-Event $l.Time 'MCP server' "Tool $($l.Tool)$(if ($l.Endpoint) { " ($($l.Endpoint))" }) with $(Limit-Text $l.Arguments 160)" $who $res
            foreach ($call in @($l.Backend | Where-Object { $_ })) {
                $obo = Get-First $call.on_behalf_of_user $call.as_user
                Add-Event $l.Time 'Dataverse call (MCP log)' "$($call.method) $([string](Get-First $call.path $call.url) -replace '\?.*$', '')" `
                    $(if ($null -ne $obo) { "on behalf of the user: $obo" } else { '' }) `
                    "HTTP $($call.status)$(if ($call.request_id) { ", request $($call.request_id)" })$(if ($call.duration_ms) { ", $([Math]::Round([double]$call.duration_ms)) ms" })$(if ($call.error_code) { ", $($call.error_code)" })"
            }
            if ($l.Purview) { Add-Event $l.Time 'MCP server' 'Microsoft Purview check of the result' '' (Limit-Text $l.Purview 200) }
        }
        else { Add-Event $l.Time 'MCP server' ("$($l.Event) $($l.Message)".Trim()) '' '' }
    }
    Set-Source 'MCP server log' 'Found' "$($calls.Count) tool call line(s), $($lines.Count - $calls.Count) other line(s), revision $(@($lines.Revision | Select-Object -Unique) -join ', ')"
    return $calls
}

# ==== 2. API Management
function Get-GatewayTrail {
    $kql = @"
let cid = '$CorrelationId';
union isfuzzy=true
  (ApiManagementGatewayLogs
   | where CorrelationId == cid or tostring(column_ifexists('BackendRequestHeaders', '')) contains cid or tostring(column_ifexists('RequestHeaders', '')) contains cid or tostring(column_ifexists('ResponseHeaders', '')) contains cid
   | project TimeGenerated, Kind = 'request', ApiId = tostring(column_ifexists('ApiId', '')), Method = tostring(column_ifexists('Method', '')),
             Url = tostring(column_ifexists('Url', '')), ResponseCode = tostring(column_ifexists('ResponseCode', '')), BackendResponseCode = tostring(column_ifexists('BackendResponseCode', '')),
             TotalTime = tostring(column_ifexists('TotalTime', '')), LastError = tostring(column_ifexists('LastErrorReason', '')), ToolName = '', AuthenticationMethod = '', ClientName = '', McpError = ''),
  (ApiManagementGatewayMCPLog
   | where CorrelationId == cid
   | project TimeGenerated, Kind = 'mcp', ApiId = '', Method = tostring(column_ifexists('Method', '')), Url = '', ResponseCode = '', BackendResponseCode = '', TotalTime = '', LastError = '',
             ToolName = tostring(column_ifexists('ToolName', '')), AuthenticationMethod = tostring(column_ifexists('AuthenticationMethod', '')),
             ClientName = tostring(column_ifexists('ClientName', '')), McpError = tostring(column_ifexists('Error', '')))
| order by TimeGenerated asc
| take 50
"@
    try { $rows = @(Invoke-LogQuery $kql) }
    catch [System.IO.FileNotFoundException] { Set-Source 'API Management' 'Not found yet' 'No gateway logs have reached the workspace yet.'; return @() }
    catch { Set-Source 'API Management' 'Unavailable' $_.Exception.Message; return @() }
    $script:Raw['gateway'] = $rows
    if (-not $rows.Count) { Set-Source 'API Management' 'Not found yet' 'No gateway row carries this correlation ID yet. Gateway logs usually reach Log Analytics in 3 to 10 minutes.'; return @() }
    foreach ($g in $rows) {
        if ($g.Kind -eq 'mcp') {
            Add-Event $g.TimeGenerated 'API Management (MCP log)' ("MCP $($g.Method) $($g.ToolName)".Trim()) "authentication: $($g.AuthenticationMethod)$(if ($g.ClientName) { ", client $($g.ClientName)" })" $(if ($g.McpError) { "error: $($g.McpError)" } else { 'ok' })
        }
        else {
            $path = try { ([uri]$g.Url).AbsolutePath } catch { $g.Url }
            $caller = if ("$($g.ApiId)" -match '(?i)diag') { 'subscription key of the diagnostics API (no signed-in user)' } else { 'the signed-in user''s token, validated by the gateway' }
            Add-Event $g.TimeGenerated 'API Management' "$($g.Method) $path (API $($g.ApiId))" $caller `
                "HTTP $($g.ResponseCode)$(if ($g.BackendResponseCode) { ", backend $($g.BackendResponseCode)" })$(if ($g.TotalTime) { ", $($g.TotalTime) ms" })$(if ($g.LastError) { ", $($g.LastError)" })"
        }
    }
    Set-Source 'API Management' 'Found' "$(@($rows | Where-Object Kind -eq 'request').Count) gateway request row(s), $(@($rows | Where-Object Kind -eq 'mcp').Count) MCP log row(s)"
    return $rows
}

# ==== 3. Application Insights (the agent run)
function Get-AgentTrail {
    $findKql = @"
let cid = '$CorrelationId';
union isfuzzy=true
  (AppGenAIContent
   | where tostring(column_ifexists('ToolCallResult', '')) contains cid or tostring(column_ifexists('ToolCallArguments', '')) contains cid
        or tostring(column_ifexists('OutputMessages', '')) contains cid or tostring(column_ifexists('InputMessages', '')) contains cid
   | project TraceId = tostring(column_ifexists('TraceId', ''))),
  (AppDependencies | where tostring(Properties) contains cid | project TraceId = OperationId),
  (AppTraces | where Message contains cid or tostring(Properties) contains cid | project TraceId = OperationId)
| where isnotempty(TraceId)
| distinct TraceId
| take 5
"@
    try { $traceIds = @(Invoke-LogQuery $findKql | ForEach-Object { $_.TraceId } | Where-Object { $_ -match '^[A-Za-z0-9-]+$' }) }
    catch [System.IO.FileNotFoundException] { Set-Source 'Application Insights' 'Not found yet' 'No agent traces have reached the workspace yet.'; return $null }
    catch { Set-Source 'Application Insights' 'Unavailable' $_.Exception.Message; return $null }
    if (-not $traceIds.Count) {
        Set-Source 'Application Insights' 'Not found yet' 'No agent trace mentions this correlation ID yet. Agent traces usually appear 2 to 5 minutes after the action.'
        return $null
    }
    $list = ($traceIds | ForEach-Object { "'$_'" }) -join ', '
    $spanKql = @"
union isfuzzy=true
  (AppDependencies | where OperationId in ($list) | project TimeGenerated, Name, OperationId, Success = tostring(Success), ResultCode = tostring(ResultCode), DurationMs, Properties),
  (AppRequests | where OperationId in ($list) | project TimeGenerated, Name, OperationId, Success = tostring(Success), ResultCode = tostring(ResultCode), DurationMs, Properties)
| order by TimeGenerated asc
| take 100
"@
    $contentKql = @"
AppGenAIContent
| where tostring(column_ifexists('TraceId', '')) in ($list)
| project TimeGenerated, SpanId = tostring(column_ifexists('SpanId', '')), AgentName = tostring(column_ifexists('AgentName', '')), AgentId = tostring(column_ifexists('AgentId', '')),
          ModelName = tostring(column_ifexists('ModelName', '')), InputMessages = tostring(column_ifexists('InputMessages', '')), OutputMessages = tostring(column_ifexists('OutputMessages', '')),
          ToolCallArguments = tostring(column_ifexists('ToolCallArguments', '')), ToolCallResult = tostring(column_ifexists('ToolCallResult', ''))
| order by TimeGenerated asc
| take 50
"@
    $spans = @(); $content = @()
    try { $spans = @(Invoke-LogQuery $spanKql) } catch { $spans = @() }
    try { $content = @(Invoke-LogQuery $contentKql) } catch { $content = @() }
    $script:Raw['agentSpans'] = $spans
    $conversation = $null
    $agentFound = $null
    foreach ($s in $spans) {
        $p = $s.Properties
        if ($p -is [string]) { try { $p = $p | ConvertFrom-Json } catch { $p = $null } }
        $op = if ($p) { Get-First $p.'gen_ai.operation.name' $s.Name } else { $s.Name }
        $tool = if ($p) { $p.'gen_ai.tool.name' } else { $null }
        $agentName = if ($p) { Get-First $p.'gen_ai.agent.name' $p.'gen_ai.agent.id' } else { $null }
        if ($p) { $conversation = Get-First $conversation $p.'gen_ai.conversation.id' $p.'gen_ai.thread.id' }
        if ($agentName) { $agentFound = Get-First $agentFound $agentName }
        $what = (@($op, $(if ($tool) { "tool $tool" }), $(if ($agentName) { "agent $agentName" })) | Where-Object { $_ }) -join ', '
        Add-Event $s.TimeGenerated 'Application Insights' "Span $what" '' "success $($s.Success)$(if ($s.ResultCode) { ", code $($s.ResultCode)" })$(if ($s.DurationMs) { ", $([Math]::Round([double]$s.DurationMs)) ms" })"
    }
    $script:Raw['agentContent'] = @($content | ForEach-Object {
        [pscustomobject]@{ TimeGenerated = $_.TimeGenerated; AgentName = $_.AgentName; ModelName = $_.ModelName
            Input = Protect-Text (Limit-Text (Get-MessageText $_.InputMessages 'user') 1000) -FreeText
            ToolCallArguments = Protect-Text (Limit-Text $_.ToolCallArguments 1000) -FreeText
            ToolCallResult = Protect-Text (Limit-Text $_.ToolCallResult 1000) -FreeText
            Output = Protect-Text (Limit-Text (Get-MessageText $_.OutputMessages 'assistant') 1000) -FreeText }
    })
    $request = $null; $answer = $null; $result = $null
    foreach ($c in $content) {
        $u = Get-MessageText $c.InputMessages 'user'
        if ($u -and -not $request) { $request = $u; Add-Event $c.TimeGenerated 'Application Insights' 'Request to the agent' $(if ($c.AgentName) { "agent $($c.AgentName)" }) (Limit-Text $u 200) }
        if ($c.ToolCallArguments) { Add-Event $c.TimeGenerated 'Application Insights' 'Model decided to call a tool' '' "arguments $(Limit-Text $c.ToolCallArguments 200)" }
        if ($c.ToolCallResult -and $c.ToolCallResult.Contains($CorrelationId)) { $result = $c.ToolCallResult; Add-Event $c.TimeGenerated 'Application Insights' 'Tool result returned to the agent' '' (Limit-Text $c.ToolCallResult 200) }
        $a = Get-MessageText $c.OutputMessages 'assistant'
        if ($a) { $answer = $a }
        if ($c.AgentName) { $agentFound = Get-First $agentFound $c.AgentName }
    }
    if ($answer) { Add-Event (@($content)[-1].TimeGenerated) 'Application Insights' 'Answer from the agent' '' (Limit-Text $answer 200) }
    Set-Source 'Application Insights' 'Found' "trace $($traceIds -join ', '): $($spans.Count) span(s), $($content.Count) content row(s)"
    return [pscustomobject]@{ TraceIds = $traceIds; ConversationId = $conversation; Request = $request; Answer = $answer; ToolResult = $result; Agent = $agentFound }
}

# ==== 4. Foundry conversation items (approvals)
function Get-ConversationItems([string]$Id) {
    $paths = @("$($script:Endpoint)/openai/v1/conversations/$Id/items?limit=100&order=asc",
               "$($script:Endpoint)/agents/$($script:Settings.AgentName)/endpoint/protocols/openai/conversations/$Id/items?api-version=v1&limit=100&order=asc")
    foreach ($base in $paths) {
        $items = [System.Collections.Generic.List[object]]::new()
        $uri = $base
        for ($page = 0; $page -lt 10 -and $uri; $page++) {
            $r = Invoke-Rest GET $uri $script:FoundryToken $null
            if ($r.Status -ne 200) { break }
            foreach ($i in @($r.Body.data)) { $items.Add($i) }
            $uri = if ($r.Body.has_more -and $r.Body.last_id) { "$base&after=$($r.Body.last_id)" } else { $null }
        }
        if ($items.Count) { return $items }
        if ($r.Status -in 401, 403) { throw "Your account may not read this conversation (HTTP $($r.Status)). Conversations are visible only to the user who had them." }
    }
    return $null
}

function Find-ConversationByCorrelation {
    # Recent responses of your agent, newest first; the tool result inside carries the correlation ID.
    $r = Invoke-Rest GET "$($script:Endpoint)/openai/v1/responses?agent_name=$($script:Settings.AgentName)&limit=50&order=desc" $script:FoundryToken $null
    if ($r.Status -ne 200) { return $null }
    foreach ($resp in @($r.Body.data)) {
        $created = ConvertTo-Utc $resp.created_at
        if ($created -and $created -lt $script:FromUtc) { break }
        if ((($resp.output | ConvertTo-Json -Depth 20 -Compress) ?? '').Contains($CorrelationId)) {
            $conv = $resp.conversation
            return [string](Get-First $conv.id $conv)
        }
    }
    return $null
}

function Get-ApprovalTrail([string]$Id) {
    if (-not $script:FoundryToken) { Set-Source 'Foundry conversation' 'Unavailable' 'No Foundry token (sign in with az login).'; return $null }
    if (-not $Id -and $CorrelationId) { $Id = Find-ConversationByCorrelation }
    if (-not $Id) {
        Set-Source 'Foundry conversation' 'Not found' 'The conversation was not identified. Pass -ConversationId (Foundry portal: your agent > Traces > open the run) to include the approval items.'
        return $null
    }
    try { $items = Get-ConversationItems $Id }
    catch { Set-Source 'Foundry conversation' 'Unavailable' $_.Exception.Message; return $null }
    if (-not $items) { Set-Source 'Foundry conversation' 'Not found' "The conversation $Id has no readable items (it may belong to another user)."; return $null }
    $script:Raw['conversationItems'] = @($items | ForEach-Object {
        [pscustomobject]@{ id = $_.id; type = $_.type; role = $_.role; server_label = $_.server_label; name = $_.name
            arguments = Protect-Text $_.arguments -FreeText; approve = $_.approve; reason = $_.reason; approval_request_id = $_.approval_request_id
            status = $_.status; error = Protect-Text (Limit-Text $_.error 500); output = Protect-Text (Limit-Text $_.output 1000) -FreeText; response_id = $_.response_id }
    })

    # Times: an item's own created_at, else its response's creation time, else its neighbours'.
    $responseTimes = @{}
    $times = @()
    foreach ($i in $items) {
        $t = ConvertTo-Utc $i.created_at
        if (-not $t -and $i.response_id) {
            if (-not $responseTimes.ContainsKey($i.response_id)) {
                $rr = Invoke-Rest GET "$($script:Endpoint)/openai/v1/responses/$($i.response_id)" $script:FoundryToken $null
                $responseTimes[$i.response_id] = if ($rr.Status -eq 200) { ConvertTo-Utc $rr.Body.created_at } else { $null }
            }
            $t = $responseTimes[$i.response_id]
        }
        $times += , $t
    }
    $approx = @(for ($k = 0; $k -lt $times.Count; $k++) { $null -eq $times[$k] })
    for ($k = $times.Count - 1; $k -ge 0; $k--) { if (-not $times[$k] -and $k + 1 -lt $times.Count) { $times[$k] = $times[$k + 1] } }
    for ($k = 0; $k -lt $times.Count; $k++) { if (-not $times[$k] -and $k -gt 0) { $times[$k] = $times[$k - 1] } }

    $list = @($items)
    $targetCall = $null
    $targetIndex = -1
    if ($CorrelationId) {
        for ($k = 0; $k -lt $list.Count; $k++) {
            if ($list[$k].type -eq 'mcp_call' -and ("$($list[$k].output)$($list[$k].error)").Contains($CorrelationId)) { $targetCall = $list[$k]; $targetIndex = $k; break }
        }
    }
    $requests = @{}
    foreach ($i in $list | Where-Object { $_.type -eq 'mcp_approval_request' }) { $requests[$i.id] = $i }
    $decisions = @{}
    foreach ($i in $list | Where-Object { $_.type -eq 'mcp_approval_response' }) { $decisions[[string]$i.approval_request_id] = $i }
    $relevantRequest = if ($targetCall -and $targetCall.approval_request_id) { [string]$targetCall.approval_request_id } else { $null }
    $decision = 'not required (read tool or no approval)'
    $userPrompt = $null

    for ($k = 0; $k -lt $list.Count; $k++) {
        $i = $list[$k]
        $show = (-not $CorrelationId) -or ($targetCall -and ($i.id -eq $targetCall.id -or $i.id -eq $relevantRequest -or $i.approval_request_id -eq $relevantRequest))
        $isApprox = [bool]$approx[$k]
        if ($i.type -eq 'message' -and $i.role -eq 'user') {
            if (($targetIndex -gt $k) -or -not $CorrelationId) { $userPrompt = Get-Text $i.content }
            if (-not $CorrelationId) { Add-Event $times[$k] 'Foundry conversation' 'Message from you' 'the signed-in user (conversation owner)' (Limit-Text (Get-Text $i.content) 200) -Approximate:$isApprox }
            continue
        }
        if (-not $show) { continue }
        switch ($i.type) {
            'mcp_approval_request' {
                Add-Event $times[$k] 'Foundry conversation' "Approval requested: server $($i.server_label), tool $($i.name)" '' "arguments $(Limit-Text $i.arguments 300)" -Approximate:$isApprox
                if (-not $decisions.ContainsKey([string]$i.id)) { Add-Event $times[$k] 'Foundry conversation' "No decision recorded for $($i.name)" '' 'the tool was not called' -Approximate:$isApprox }
            }
            'mcp_approval_response' {
                $verdict = if ($i.approve -eq $true) { 'approved' } else { 'rejected' }
                $req = $requests[[string]$i.approval_request_id]
                if ($i.approval_request_id -eq $relevantRequest) { $decision = $verdict }
                Add-Event $times[$k] 'Foundry conversation' "Decision: $verdict$(if ($req) { " ($($req.server_label)/$($req.name))" })" 'the signed-in user (conversation owner)' $(if ($i.reason) { "reason: $($i.reason)" } else { '' }) -Approximate:$isApprox
                if ($verdict -eq 'rejected' -and -not ($list | Where-Object { $_.type -eq 'mcp_call' -and $_.approval_request_id -eq $i.approval_request_id })) {
                    Add-Event $times[$k] 'Foundry conversation' "Not called: $(if ($req) { $req.name } else { 'tool' })" '' 'rejected, so no gateway, MCP server or Dataverse record exists for it' -Approximate:$isApprox
                }
            }
            'mcp_call' {
                Add-Event $times[$k] 'Foundry conversation' "Tool call $($i.server_label)/$($i.name), status $($i.status)" '' $(if ($i.error) { "error: $(Limit-Text $i.error 200)" } else { "output: $(Limit-Text $i.output 200)" }) -Approximate:$isApprox
            }
            default {
                if ($i.type -eq 'message' -and $i.role -eq 'assistant') { Add-Event $times[$k] 'Foundry conversation' 'Answer from the agent' '' (Limit-Text (Get-Text $i.content) 200) -Approximate:$isApprox }
            }
        }
    }
    if ($CorrelationId -and -not $targetCall) {
        Set-Source 'Foundry conversation' 'Not found' "Conversation $Id has no tool call whose result carries this correlation ID."
        return [pscustomobject]@{ ConversationId = $Id; Decision = $null; Call = $null; Prompt = $null; Request = $null }
    }
    $requestItem = if ($relevantRequest) { $requests[$relevantRequest] } else { $null }
    Set-Source 'Foundry conversation' 'Found' "conversation $Id, $($items.Count) item(s); approval: $decision"
    return [pscustomobject]@{ ConversationId = $Id; Decision = $decision; Call = $targetCall; Prompt = $userPrompt; Request = $requestItem }
}

# ==== 5. Dataverse: audit records and the Agent Action row
function Invoke-Dataverse([string]$PathAndQuery) {
    return Invoke-Rest GET "$($script:DvUrl)/api/data/v9.2/$PathAndQuery" $script:DvToken $null @{
        Accept = 'application/json'; 'OData-MaxVersion' = '4.0'; 'OData-Version' = '4.0'
        Prefer = 'odata.include-annotations="OData.Community.Display.V1.FormattedValue"' }
}

function Get-Formatted($Row, [string]$Name) { return Get-First $Row."$Name@OData.Community.Display.V1.FormattedValue" $Row.$Name }

function Get-DataverseTrail($McpCalls) {
    if (-not $script:DvToken) { Set-Source 'Dataverse audit' 'Unavailable' 'No Dataverse token (sign in with az login).'; return @() }
    $changes = [System.Collections.Generic.List[object]]::new()
    $targets = [System.Collections.Generic.List[object]]::new()
    foreach ($m in @($McpCalls)) {
        # Only Dataverse changes are audited there; Microsoft Graph calls (Purview checks) are not write targets.
        $dataverseWrites = @($m.Backend | Where-Object {
                $_ -and "$($_.method)" -match '^(PATCH|POST|PUT|DELETE)$' -and (-not $_.system -or "$($_.system)" -eq 'dataverse')
            })
        foreach ($call in $dataverseWrites) {
            $path = [string](Get-First $call.path $call.url)
            $id = Get-First $call.record_id $call.entity_id $call.id
            if (-not $id -and $path -match '\(([0-9a-fA-F-]{36})\)') { $id = $Matches[1] }
            $set = if ($call.entity_set) { [string]$call.entity_set } elseif ($path -match '/?([a-z_]+)(\(|$|\?)') { $Matches[1] } else { '' }
            $targets.Add([pscustomobject]@{ Time = $m.Time; Id = $id; EntitySet = $set; Method = [string]$call.method; Status = [int](Get-First $call.status 0) })
        }
    }
    if (-not $targets.Count) {
        $legacy = Invoke-Dataverse "spk_tickets?`$select=spk_ticketid,spk_ticketnumber,modifiedon&`$filter=spk_correlationid eq '$CorrelationId'&`$top=1"
        $t = if ($legacy.Status -eq 200) { @($legacy.Body.value) | Select-Object -First 1 } else { $null }
        if ($t) { $targets.Add([pscustomobject]@{ Time = $t.modifiedon; Id = $t.spk_ticketid; EntitySet = 'spk_tickets'; Method = 'PATCH'; Status = 204 }) }
    }
    $writeTargets = @($targets | Where-Object { $_.Status -lt 400 })
    if (-not $writeTargets.Count) {
        $why = if ($targets.Count) { 'The change was refused, so nothing changed and Dataverse wrote no audit record (it audits changes only).' }
               elseif ($McpCalls) { 'This call made no change in Dataverse (a read, or a call refused before any change), so there is no audit record.' }
               else { 'The MCP server log line has not arrived yet, so the changed record is not known yet.' }
        Set-Source 'Dataverse audit' $(if ($McpCalls) { 'Not applicable' } else { 'Not found yet' }) $why
        return @()
    }
    foreach ($t in $writeTargets) {
        $time = ConvertTo-Utc $t.Time
        if (-not $time) { $time = $script:ToUtc }
        $from = $time.AddMinutes(-5).ToString('yyyy-MM-ddTHH:mm:ssZ')
        $to = $time.AddMinutes(15).ToString('yyyy-MM-ddTHH:mm:ssZ')
        $filter = if ($t.Id) { "_objectid_value eq $($t.Id) and createdon ge $from and createdon le $to" }
                  else { "objecttypecode eq '$($t.EntitySet -replace 's$', '')' and operation eq 1 and createdon ge $from and createdon le $to" }
        $r = Invoke-Dataverse "audits?`$select=auditid,action,operation,createdon,objecttypecode,_objectid_value,_userid_value,_callinguserid_value&`$filter=$filter&`$orderby=createdon asc&`$top=10"
        if ($r.Status -in 401, 403) { Set-Source 'Dataverse audit' 'Unavailable' 'Your Dataverse role can''t read audit records. Open the record in the Service Desk app and use its Audit History instead.'; return @() }
        if ($r.Status -ne 200) { Set-Source 'Dataverse audit' 'Unavailable' "The audit query failed: $($r.Error)"; return @() }
        foreach ($a in @($r.Body.value)) {
            $user = Get-Formatted $a '_userid_value'
            $caller = Get-Formatted $a '_callinguserid_value'
            $userOid = $null
            if ($a._userid_value) {
                $u = Invoke-Dataverse "systemusers($($a._userid_value))?`$select=fullname,domainname,azureactivedirectoryobjectid"
                if ($u.Status -eq 200) { $userOid = $u.Body.azureactivedirectoryobjectid; $user = Get-First $u.Body.domainname $user }
            }
            $detail = Invoke-Dataverse "audits($($a.auditid))/Microsoft.Dynamics.CRM.RetrieveAuditDetails()"
            $changed = @()
            if ($detail.Status -eq 200 -and $detail.Body.AuditDetail.NewValue) {
                $old = $detail.Body.AuditDetail.OldValue
                foreach ($p in $detail.Body.AuditDetail.NewValue.PSObject.Properties) {
                    if ($p.Name -match '@' -or $p.Name -in 'modifiedon', '_modifiedby_value', '_modifiedonbehalfby_value', 'versionnumber') { continue }
                    $newValue = Get-First $detail.Body.AuditDetail.NewValue."$($p.Name)@OData.Community.Display.V1.FormattedValue" $p.Value
                    $oldValue = if ($old) { Get-First $old."$($p.Name)@OData.Community.Display.V1.FormattedValue" $old.($p.Name) } else { $null }
                    $changed += "$($p.Name): $(if ($null -ne $oldValue) { Limit-Text $oldValue 60 } else { '(empty)' }) -> $(Limit-Text $newValue 60)"
                }
            }
            $entry = [pscustomobject]@{ Time = ConvertTo-Utc $a.createdon; Table = $a.objecttypecode; RecordId = $a._objectid_value
                Action = Get-Formatted $a 'action'; ChangedBy = $user; ChangedByObjectId = $userOid; CalledBy = $caller; Changes = $changed }
            $changes.Add($entry)
            Add-Event $entry.Time 'Dataverse audit' "$($entry.Action) $($entry.Table) $($entry.RecordId)" "$user$(if ($caller) { ", through $caller" })" (Limit-Text ($changed -join '; ') 300)
        }
    }
    $script:Raw['dataverseAudit'] = $changes
    if ($changes.Count) { Set-Source 'Dataverse audit' 'Found' "$($changes.Count) audit record(s)" }
    else { Set-Source 'Dataverse audit' 'Not found yet' 'No audit record yet. Audit History can show changes with a delay; check the record''s Audit History in the Service Desk app.' }
    return $changes
}

function Get-AgentActionTrail {
    if (-not $script:DvToken) { Set-Source 'Agent Action row' 'Unavailable' 'No Dataverse token.'; return @() }
    $table = $null
    foreach ($name in 'spk_agentaction', 'spk_agentactionlog') {
        $d = Invoke-Dataverse "EntityDefinitions(LogicalName='$name')?`$select=LogicalName,EntitySetName"
        if ($d.Status -eq 200) { $table = $d.Body; break }
    }
    if (-not $table) { Set-Source 'Agent Action row' 'Not available' 'This environment has no Agent Action table.'; return @() }
    $attrs = Invoke-Dataverse "EntityDefinitions(LogicalName='$($table.LogicalName)')/Attributes?`$select=LogicalName"
    $corr = @($attrs.Body.value.LogicalName) | Where-Object { $_ -match 'correlation' } | Select-Object -First 1
    if (-not $corr) { Set-Source 'Agent Action row' 'Not available' "The table $($table.LogicalName) has no correlation ID column."; return @() }
    $r = Invoke-Dataverse "$($table.EntitySetName)?`$filter=$corr eq '$CorrelationId'&`$top=10"
    if ($r.Status -eq 400 -and $CorrelationId -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') {
        # The column may hold the ID as a uniqueidentifier, which OData compares without quotes.
        $r = Invoke-Dataverse "$($table.EntitySetName)?`$filter=$corr eq $CorrelationId&`$top=10"
    }
    if ($r.Status -in 401, 403) { Set-Source 'Agent Action row' 'Unavailable' "Your Dataverse role can't read $($table.LogicalName)."; return @() }
    if ($r.Status -ne 200) { Set-Source 'Agent Action row' 'Unavailable' "The query failed: $($r.Error)"; return @() }
    $rows = @($r.Body.value)
    $out = foreach ($row in $rows) {
        $fields = [ordered]@{}
        foreach ($p in $row.PSObject.Properties) {
            if ($p.Name -match '@' -or $null -eq $p.Value -or "$($p.Value)" -eq '') { continue }
            if ($p.Name -notmatch '^(spk_|_spk_|createdon$|_createdby_value$)') { continue }
            if ($p.Name -match 'id$' -and "$($p.Value)" -match '^[0-9a-f-]{36}$' -and $p.Name -notmatch 'correlation|agent') { continue }
            $label = $p.Name -replace '^_', '' -replace '_value$', ''
            $fields[$label] = Protect-Text ([string](Get-Formatted $row $p.Name)) -FreeText
        }
        Add-Event $row.createdon 'Agent Action row' "Recorded by the MCP server in $($table.LogicalName)" '' (Limit-Text (($fields.GetEnumerator() | Where-Object { $_.Key -ne 'createdon' } | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join '; ') 300)
        [pscustomobject]$fields
    }
    $script:Raw['agentAction'] = @($out)
    if ($rows.Count) { Set-Source 'Agent Action row' 'Found' "$($rows.Count) row(s) in $($table.LogicalName)" }
    else { Set-Source 'Agent Action row' 'Not found' "No $($table.LogicalName) row carries this correlation ID (the MCP server writes one for each write tool call)." }
    return @($out)
}

# ==== Evidence files
function Write-Evidence($Evidence, [string]$Base) {
    $Base = $Base -replace '\.(json|md)$', ''
    $dir = Split-Path -Parent ([System.IO.Path]::GetFullPath($Base))
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $jsonPath = [System.IO.Path]::GetFullPath("$Base.json")
    $mdPath = [System.IO.Path]::GetFullPath("$Base.md")
    Protect-Text ($Evidence | ConvertTo-Json -Depth 20) -FreeText | Set-Content -LiteralPath $jsonPath -Encoding utf8
    $cell = { param($v) ([string]$v -replace '\|', '\|' -replace '\r?\n', ' ') }
    $md = [System.Collections.Generic.List[string]]::new()
    $md.Add("# Action trail for correlation ID $($Evidence.correlationId)")
    $md.Add('')
    $md.Add("Generated $($Evidence.generatedAt) by Get-ActionTrail.ps1 for deployment $($Evidence.deploymentId). Time window $($Evidence.window.from) to $($Evidence.window.to) (UTC).")
    $md.Add('')
    $md.Add('## Summary')
    $md.Add('')
    foreach ($p in $Evidence.summary.PSObject.Properties) { $md.Add("- **$($p.Name):** $(& $cell $p.Value)") }
    $md.Add('')
    $md.Add('## Timeline (UTC)')
    $md.Add('')
    $md.Add('| Time | Source | Step | Identity | Result |')
    $md.Add('|---|---|---|---|---|')
    foreach ($e in $Evidence.timeline) { $md.Add("| $($e.time) | $(& $cell $e.source) | $(& $cell $e.step) | $(& $cell $e.identity) | $(& $cell $e.result) |") }
    $md.Add('')
    $md.Add('## Sources checked')
    $md.Add('')
    $md.Add('| Source | Status | Detail |')
    $md.Add('|---|---|---|')
    foreach ($s in $Evidence.sources) { $md.Add("| $(& $cell $s.Source) | $(& $cell $s.Status) | $(& $cell $s.Detail) |") }
    $md.Add('')
    $md.Add('Times marked with ~ are approximate: the conversation item carries no time of its own. Latency: agent traces usually appear 2 to 5 minutes after the action and gateway and console logs within minutes; Dataverse audits changes only, so a read or a refused write has no audit record. The full records are in the JSON file next to this one.')
    Protect-Text ($md -join [Environment]::NewLine) -FreeText | Set-Content -LiteralPath $mdPath -Encoding utf8
    return @($jsonPath, $mdPath)
}

# ==== Main
try {
    if (-not $CorrelationId -and -not $ConversationId) {
        Stop-Script 'Give a correlation ID (the correlation_id at the end of a tool result) or a conversation ID. Example: Get-ActionTrail.ps1 -CorrelationId 0b6f3c9e-6d2a-4f55-9a43-2d7c1e8b5a10'
    }
    if ($CorrelationId) {
        $CorrelationId = $CorrelationId.Trim()
        if ($CorrelationId -notmatch '^[A-Za-z0-9-]{8,80}$') { Stop-Script "'$CorrelationId' is not a correlation ID. It is a GUID such as 0b6f3c9e-6d2a-4f55-9a43-2d7c1e8b5a10, shown at the end of every tool result." }
    }
    if ($ConversationId -and $ConversationId -notmatch '^[A-Za-z0-9_\-]{4,120}$') { Stop-Script "'$ConversationId' is not a conversation ID." }
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { Stop-Script 'Azure CLI (az) was not found. Run this script on the lab VM.' }

    $script:Settings = Read-LabSettings $SettingsPath @('FoundryProjectEndpoint', 'AgentName', 'ContainerApp', 'DataverseUrl')
    $script:Endpoint = ([string]$script:Settings.FoundryProjectEndpoint).TrimEnd('/')
    $script:DvUrl = ([string]$script:Settings.DataverseUrl).TrimEnd('/')
    $script:ToUtc = if ($To) { ConvertTo-Utc $To } else { [datetime]::UtcNow }
    $script:FromUtc = if ($From) { ConvertTo-Utc $From } else { $script:ToUtc.AddHours(-$LookbackHours) }
    if ($script:FromUtc -ge $script:ToUtc) { Stop-Script '-From must be earlier than -To.' }
    $script:FromIso = $script:FromUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $script:ToIso = $script:ToUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')

    $script:LaToken = Get-AzCliToken 'https://api.loganalytics.io'
    if (-not $script:LaToken) { Stop-Script "Azure CLI has no sign-in for your lab tenant. Run 'az login', sign in as the Senior Technician, and run this script again." }
    $script:FoundryToken = Get-AzCliToken 'https://ai.azure.com'
    $script:DvToken = Get-AzCliToken $script:DvUrl
    $script:WorkspaceId = [string]$script:Settings.LogAnalyticsWorkspaceId
    if ($script:WorkspaceId -like '/subscriptions/*') {
        $script:WorkspaceId = & az monitor log-analytics workspace show --ids $script:WorkspaceId --query customerId --output tsv 2>$null
    }
    elseif (-not $script:WorkspaceId) {
        $script:WorkspaceId = & az monitor log-analytics workspace show --resource-group $script:Settings.ResourceGroup --workspace-name $script:Settings.LogAnalyticsWorkspace --query customerId --output tsv 2>$null
    }
    if ("$($script:WorkspaceId)".Trim() -notmatch '^[0-9a-fA-F-]{36}$') { Stop-Script 'The Log Analytics workspace ID could not be read from lab-settings.json or Azure. Contact CloudLabs support.' }
    $script:WorkspaceId = "$($script:WorkspaceId)".Trim()

    Write-Host 'Get-ActionTrail: follows one agent action through every record it left, by its correlation ID.' -ForegroundColor Cyan
    Write-Host "Correlation ID: $(if ($CorrelationId) { $CorrelationId } else { '(none: listing the conversation)' })$(if ($ConversationId) { "   Conversation: $ConversationId" })"
    Write-Host "Time window: $($script:FromIso) to $($script:ToIso) (UTC)"

    $deadline = (Get-Date).AddMinutes($WaitMinutes)
    $attempt = 0
    do {
        $attempt++
        $script:Events.Clear(); $script:Sources.Clear(); $script:Raw.Clear(); $script:Sequence = 0
        $mcp = @(); $gateway = @(); $agentRun = $null
        if ($CorrelationId) {
            $mcp = @(Get-McpTrail)
            $gateway = @(Get-GatewayTrail)
            $agentRun = Get-AgentTrail
        }
        $conv = if ($ConversationId) { $ConversationId } elseif ($agentRun -and $agentRun.ConversationId) { [string]$agentRun.ConversationId } else { $null }
        $approval = Get-ApprovalTrail $conv
        $audit = @(); $actions = @()
        if ($CorrelationId) {
            $audit = @(Get-DataverseTrail $mcp)
            $actions = @(Get-AgentActionTrail)
        }
        $pending = @($script:Sources.Values | Where-Object { $_.Status -eq 'Not found yet' })
        if (-not $pending.Count -or (Get-Date) -ge $deadline) { break }
        Write-Host "Still waiting for: $(@($pending.Source) -join ', '). Checking again in 60 seconds (until $($deadline.ToString('HH:mm')))." -ForegroundColor DarkYellow
        Start-Sleep -Seconds 60
    } while ($true)

    # ==== Summary
    $firstCall = @($mcp) | Select-Object -First 1
    $userText = if ($firstCall -and ($firstCall.UserName -or $firstCall.UserOid)) { "$($firstCall.UserName)$(if ($firstCall.UserOid) { " (object ID $($firstCall.UserOid)), from the token the gateway validated" })" }
                elseif ($firstCall) { 'no signed-in user: the call came through the diagnostics API' }
                elseif ($approval) { 'the signed-in owner of the conversation (the MCP log line has not arrived yet)' } else { 'not known yet' }
    $agentText = (@(
        $(if ($firstCall -and ($firstCall.AgentName -or $firstCall.AgentId)) { "$($firstCall.AgentName) (Agent ID $($firstCall.AgentId)), from the MCP log" }),
        $(if ($agentRun -and $agentRun.Agent) { "$($agentRun.Agent) in the agent trace" })
    ) | Where-Object { $_ }) -join '; '
    $toolText = if ($firstCall) { "$($firstCall.Tool)$(if ($firstCall.Endpoint) { " on the $($firstCall.Endpoint) endpoint" }) with $(Limit-Text $firstCall.Arguments 160)" }
                elseif ($approval -and $approval.Call) { "$($approval.Call.server_label)/$($approval.Call.name)" } else { 'not known yet' }
    $gwRow = @($gateway) | Where-Object { $_.Kind -eq 'request' } | Select-Object -First 1
    $authorized = @(
        $(if ($approval -and $approval.Decision) { "approval: $($approval.Decision)" }),
        $(if ($gwRow) { "gateway: token validated, HTTP $($gwRow.ResponseCode)" }),
        $(if ($firstCall) { "MCP server and Dataverse: $(Get-First $firstCall.AuthResult 'not logged')$(if ($firstCall.DecidedBy) { " (decided by $($firstCall.DecidedBy))" })$(if ($firstCall.ActingAs) { ", acting as the $($firstCall.ActingAs)" })" })
    ) | Where-Object { $_ }
    $changedText = if (@($audit).Count) { (@($audit | ForEach-Object { "$($_.Action) $($_.Table) by $($_.ChangedBy)$(if ($_.CalledBy) { " through $($_.CalledBy)" }): $(Limit-Text ($_.Changes -join '; ') 200)" })) -join ' | ' }
                   else { "$($script:Sources['Dataverse audit'].Detail)" }
    $returnedText = (@(
        $(if ($firstCall) { "outcome $($firstCall.Outcome)$(if ($firstCall.ErrorCode) { " ($($firstCall.ErrorCode))" })" }),
        $(if ($approval -and $approval.Call) { "tool result: $(Limit-Text (Get-First $approval.Call.error $approval.Call.output) 160)" } elseif ($agentRun -and $agentRun.ToolResult) { "tool result: $(Limit-Text $agentRun.ToolResult 160)" }),
        $(if ($agentRun -and $agentRun.Answer) { "answer: $(Limit-Text $agentRun.Answer 160)" })
    ) | Where-Object { $_ }) -join '; '
    $asked = Get-First $(if ($approval) { $approval.Prompt }) $(if ($agentRun) { $agentRun.Request })
    $summary = [pscustomobject][ordered]@{
        'Who asked'           = Protect-Text "$userText$(if ($asked) { "; request: $(Limit-Text $asked 160)" })" -FreeText
        'Which agent'         = if ($agentText) { $agentText } else { "$($script:Settings.AgentName) (from lab-settings.json)" }
        'Which tool'          = Protect-Text $toolText -FreeText
        'What was authorized' = if ($authorized.Count) { $authorized -join '; ' } else { 'not known yet' }
        'What changed'        = Protect-Text $(if ($changedText) { $changedText } else { 'not known yet' }) -FreeText
        'What was returned'   = if ($returnedText) { Protect-Text $returnedText -FreeText } else { 'not known yet' }
    }

    # ==== Print
    Write-Section 'Timeline (UTC; ~ marks a time taken from the surrounding conversation)'
    $ordered = @($script:Events | Sort-Object @{ Expression = { if ($_.Time) { $_.Time } else { [datetime]::MaxValue } } }, Order)
    if ($ordered.Count) {
        $indent = ' ' * 43
        foreach ($e in $ordered) {
            $time = if ($e.Time) { "$(if ($e.Approximate) { '~' } else { ' ' })$($e.Time.ToString('HH:mm:ss.fff'))" } else { ' (no time)' }
            Write-Host ('{0,-14} {1,-27} {2}' -f $time, $e.Source, $e.Step)
            if ($e.Identity) { Write-Host "$($indent)who: $($e.Identity)" -ForegroundColor DarkGray }
            if ($e.Result) { Write-Host "$indent$($e.Result)" -ForegroundColor DarkGray }
        }
    }
    else { Write-Host '  Nothing found yet in any source.' -ForegroundColor Yellow }

    Write-Section 'Summary'
    $summary | Format-List | Out-String -Width 220 | Write-Host

    Write-Section 'Sources checked'
    @($script:Sources.Values) | Format-Table -Wrap -AutoSize | Out-String -Width 220 | Write-Host
    $pending = @($script:Sources.Values | Where-Object { $_.Status -eq 'Not found yet' })
    if ($pending.Count) {
        Write-Host "Not arrived yet: $(@($pending.Source) -join ', '). Agent traces usually appear 2 to 5 minutes after the action, and gateway and console logs within minutes. Run the script again in a few minutes, or add -WaitMinutes 10." -ForegroundColor Yellow
    }

    $evidence = [pscustomobject][ordered]@{
        generatedAt    = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
        deploymentId   = $script:Settings.DeploymentID
        correlationId  = $CorrelationId
        conversationId = if ($approval) { $approval.ConversationId } else { $conv }
        window         = [pscustomobject]@{ from = $script:FromIso; to = $script:ToIso }
        summary        = $summary
        timeline       = @($ordered | ForEach-Object { [pscustomobject]@{ time = if ($_.Time) { "$(if ($_.Approximate) { '~' })$($_.Time.ToString('yyyy-MM-ddTHH:mm:ss.fffZ'))" } else { '' }; source = $_.Source; step = $_.Step; identity = $_.Identity; result = $_.Result } })
        sources        = @($script:Sources.Values)
        records        = [pscustomobject]$script:Raw
    }
    if ($OutFile) {
        $files = Write-Evidence $evidence $OutFile
        Write-Host ''
        Write-Host "Evidence written to $($files[0]) and $($files[1])." -ForegroundColor Green
    }
    if ($PassThru) { return $evidence }
}
catch {
    Write-Verbose ($_ | Out-String)
    Stop-Script $_.Exception.Message
}
