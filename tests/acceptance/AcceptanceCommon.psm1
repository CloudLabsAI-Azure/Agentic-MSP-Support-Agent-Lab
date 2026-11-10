#Requires -Version 7.0
# Shared helpers for the acceptance tests of the Agentic MSP Support Agent Guided Lab.
# Supplier tooling: run on a test environment's lab VM, never in a participant's live environment.
# Nothing here prints or stores a token, a key or a password.

Set-StrictMode -Off
$script:IdentityRoot = Join-Path $HOME '.relecloud-acceptance'

# ==== Text, settings and identities
function Protect-Text {
    param([string]$Text, [switch]$FreeText)
    if ([string]::IsNullOrEmpty($Text)) { return $Text }
    $t = [regex]::Replace($Text, '(?i)\bBearer\s+[A-Za-z0-9\-_.=~+/]+', 'Bearer [redacted]')
    $t = [regex]::Replace($t, '\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}', '[token redacted]')
    $t = [regex]::Replace($t, '(?i)((?:x-backend-key|ocp-apim-subscription-key|api-key|client_secret|clientsecret|password|accountkey|sharedaccesskey|sig|primarykey|secondarykey)\s*["'']?\s*[:=]\s*["'']?)[^"'',;&\s}]+', '$1[redacted]')
    if ($FreeText) {
        $guid = '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
        $t = -join ([regex]::Split($t, "($guid)") | ForEach-Object {
            if ($_ -match "^$guid$") { $_ } else { [regex]::Replace($_, '(?<![\w-])\d(?:[ -]?\d){12,18}(?![\w-])', '[number withheld]') }
        })
    }
    return $t
}

function Get-First {
    foreach ($v in $args) {
        if ($null -eq $v) { continue }
        if ($v -is [string]) { if ($v -ne '') { return $v }; continue }
        if ($v -is [System.Collections.ICollection] -and $v.Count -eq 0) { continue }
        return $v
    }
    return $null
}

function Read-LabSettings {
    param([string]$Path = 'C:\LabFiles\lab-settings.json', [string[]]$Required = @())
    if (-not (Test-Path -LiteralPath $Path)) { throw "The lab settings file $Path was not found. Run the tests on the test environment's lab VM, or pass -SettingsPath." }
    $s = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $missing = @($Required | Where-Object { -not $s.PSObject.Properties[$_] -or [string]::IsNullOrWhiteSpace([string]$s.$_) })
    if ($missing.Count) { throw "$Path has no value for: $($missing -join ', ')." }
    return $s
}

function Get-SeedManifest {
    param($Settings, [string]$Path)
    $candidates = @($Path, $Settings.SeedManifest, 'C:\LabFiles\seed\data\manifest.json') | Where-Object { $_ }
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return (Get-Content -LiteralPath $c -Raw | ConvertFrom-Json) } }
    throw "The seed manifest was not found (tried: $($candidates -join ', ')). Pass -ManifestPath."
}

function Use-LabIdentity {
    # Each identity gets its own Azure CLI profile, so the Senior and Tier 1 Technician sign-ins never
    # overwrite each other. The person running the test signs in in the browser; the script never sees
    # the password or Temporary Access Pass.
    param([ValidateSet('Senior', 'Tier1', 'Provisioning', 'Current')][string]$Name, $Settings)
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) { throw 'Azure CLI (az) was not found. Run the tests on the lab VM.' }
    if ($Name -eq 'Current') { Remove-Item Env:\AZURE_CONFIG_DIR -ErrorAction SilentlyContinue; return }
    $dir = Join-Path $script:IdentityRoot "az-$($Name.ToLowerInvariant())"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $env:AZURE_CONFIG_DIR = $dir
    $user = & az account show --query user.name --output tsv 2>$null
    $expected = switch ($Name) { 'Senior' { [string]$Settings.SeniorUser } 'Tier1' { [string]$Settings.Tier1User } default { '' } }
    if ($user -and $expected -and $user -ne $expected) {
        & az logout --output none 2>$null
        $user = $null
    }
    if (-not $user) {
        if ($Name -eq 'Provisioning') {
            & az login --identity --client-id $Settings.ProvisioningIdentityClientId --allow-no-subscriptions --output none 2>$null
            if ($LASTEXITCODE) { & az login --identity --username $Settings.ProvisioningIdentityClientId --allow-no-subscriptions --output none }
            if ($LASTEXITCODE) { throw 'The lab VM identity could not sign in.' }
        }
        else {
            Write-Host "Sign in as the $(if ($Name -eq 'Senior') { 'Senior Technician' } else { 'Tier 1 Technician' }) ($expected) in the browser window that opens." -ForegroundColor Yellow
            $loginArgs = @('login', '--output', 'none')
            if ($Settings.TenantId) { $loginArgs += @('--tenant', $Settings.TenantId) }
            & az @loginArgs
            if ($LASTEXITCODE) { throw "The $Name sign-in did not complete." }
            $user = & az account show --query user.name --output tsv 2>$null
            if ($expected -and $user -ne $expected) { throw "Signed in as $user, but the test needs $expected. Run the test again and pick the right account." }
        }
    }
    if ($Settings.SubscriptionId) { & az account set --subscription $Settings.SubscriptionId --output none 2>$null }
}

function Get-LabToken {
    param([string]$Resource, [string]$TenantId)
    $cliArgs = @('account', 'get-access-token', '--resource', $Resource, '--query', 'accessToken', '--output', 'tsv')
    if ($TenantId) { $cliArgs += @('--tenant', $TenantId) }
    $token = & az @cliArgs 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace("$token")) { throw "No token for $Resource with the current Azure CLI sign-in." }
    return ("$token").Trim()
}

function Invoke-LabRest {
    param([string]$Method = 'GET', [string]$Uri, [string]$Token, $Body, [hashtable]$Headers = @{}, [int]$TimeoutSec = 120)
    $h = @{} + $Headers
    if ($Token) { $h['Authorization'] = "Bearer $Token" }
    $params = @{ Method = $Method; Uri = $Uri; Headers = $h; SkipHttpErrorCheck = $true; StatusCodeVariable = 'httpStatus'; TimeoutSec = $TimeoutSec }
    if ($null -ne $Body) { $params.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 30 }; $params.ContentType = 'application/json' }
    try { $result = Invoke-RestMethod @params }
    catch { return [pscustomobject]@{ Status = 0; Body = $null; Error = $_.Exception.Message } }
    $err = $null
    if ([int]$httpStatus -ge 400) { $err = [string](Get-First $result.error.message $result.message $(if ($result) { ($result | ConvertTo-Json -Depth 5 -Compress) }) "HTTP $httpStatus") }
    return [pscustomobject]@{ Status = [int]$httpStatus; Body = $result; Error = $err }
}

# ==== Log Analytics and the MCP server's tool invocation log
function Invoke-LabLogQuery {
    param($Settings, [string]$Query, [string]$Timespan = 'P2D')
    $workspace = [string]$Settings.LogAnalyticsWorkspaceId
    if ($workspace -notmatch '^[0-9a-fA-F-]{36}$') {
        $workspace = & az monitor log-analytics workspace show --resource-group $Settings.ResourceGroup --workspace-name $Settings.LogAnalyticsWorkspace --query customerId --output tsv 2>$null
    }
    $r = Invoke-LabRest POST "https://api.loganalytics.io/v1/workspaces/$workspace/query" (Get-LabToken 'https://api.loganalytics.io') @{ query = $Query; timespan = $Timespan }
    if ($r.Status -ne 200) {
        if ("$($r.Error)" -match '(?i)Failed to resolve table') { return @() }
        throw "Log query failed: $($r.Error)"
    }
    $table = @($r.Body.tables)[0]
    $names = @($table.columns.name)
    foreach ($row in @($table.rows)) {
        $o = [ordered]@{}
        for ($i = 0; $i -lt $names.Count; $i++) { $o[$names[$i]] = $row[$i] }
        [pscustomobject]$o
    }
}

function Get-McpToolCalls {
    # Same normalization as the validation steps: one object per tool_call line.
    param($Settings, [string]$Filter = '', [string]$Timespan = 'P2D')
    $q = "ContainerAppConsoleLogs | where ContainerAppName =~ '$($Settings.ContainerApp)' | where Log contains 'tool_call' $Filter | project TimeGenerated, RevisionName, ContainerImage, Log | order by TimeGenerated desc | take 5000"
    foreach ($row in @(Invoke-LabLogQuery $Settings $q $Timespan)) {
        $e = $null
        try { $e = $row.Log | ConvertFrom-Json } catch { $e = $null }
        if (-not $e -or [string]$e.event -ne 'tool_call') { continue }
        $auth = $e.authorization
        $authText = [string](Get-First $e.authorization_result $(if ($auth -is [string]) { $auth } else { $auth.result }))
        if ($auth -isnot [string] -and $auth.decided_by -and $authText -notmatch [regex]::Escape([string]$auth.decided_by)) { $authText = "$authText, decided by $($auth.decided_by)" }
        [pscustomobject]@{
            Time = $row.TimeGenerated; Image = [string]$row.ContainerImage; Revision = [string]$row.RevisionName
            Tool = [string]$e.tool; Endpoint = [string](Get-First $e.endpoint $e.gateway $e.api); Outcome = [string]$e.outcome
            ErrorCode = [string](Get-First $e.error_code $e.error.code); Authorization = $authText
            UserOid = [string](Get-First $e.user.oid $e.user.object_id $e.user_oid)
            UserName = [string](Get-First $e.user.upn $e.user.preferred_username $e.user.name $e.user_name)
            AgentId = [string](Get-First $e.agent.id $e.agent_id); Ticket = [string](Get-First $e.arguments.ticket_number $e.arguments.ticket)
            Arguments = $e.arguments; Correlation = [string]$e.correlation_id; Duration = Get-First $e.duration_ms $e.latency_ms
            Backend = @(Get-First $e.backend_calls $e.backend $e.dataverse); Entry = $e
        }
    }
}

function Wait-McpToolCall {
    # Polls the tool invocation log until a line with the correlation ID arrives (console logs take minutes).
    param($Settings, [string]$CorrelationId, [int]$TimeoutMinutes = 12)
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    do {
        $hit = @(Get-McpToolCalls $Settings "| where Log contains '$CorrelationId'" 'PT6H') | Select-Object -First 1
        if ($hit) { return $hit }
        Write-Host "  Waiting for the MCP server log line $CorrelationId (console logs take a few minutes)..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 30
    } while ((Get-Date) -lt $deadline)
    return $null
}

# ==== Dataverse
function Invoke-LabDataverse {
    param($Settings, [string]$PathAndQuery)
    $dv = ([string]$Settings.DataverseUrl).TrimEnd('/')
    return Invoke-LabRest GET "$dv/api/data/v9.2/$PathAndQuery" (Get-LabToken $dv) $null @{
        Accept = 'application/json'; 'OData-MaxVersion' = '4.0'; 'OData-Version' = '4.0'
        Prefer = 'odata.include-annotations="OData.Community.Display.V1.FormattedValue",odata.maxpagesize=5000' }
}

function Get-LabDataverseRows {
    param($Settings, [string]$PathAndQuery)
    $rows = [System.Collections.Generic.List[object]]::new()
    $r = Invoke-LabDataverse $Settings $PathAndQuery
    while ($true) {
        if ($r.Status -ne 200) { throw "Dataverse query failed (HTTP $($r.Status)): $($r.Error)" }
        foreach ($v in @($r.Body.value)) { $rows.Add($v) }
        $next = $r.Body.'@odata.nextLink'
        if (-not $next) { break }
        $dv = ([string]$Settings.DataverseUrl).TrimEnd('/')
        $r = Invoke-LabRest GET $next (Get-LabToken $dv) $null @{ Accept = 'application/json'; Prefer = 'odata.include-annotations="OData.Community.Display.V1.FormattedValue",odata.maxpagesize=5000' }
    }
    return $rows
}

function Get-TicketState {
    param($Settings, [string]$TicketNumber)
    $r = Invoke-LabDataverse $Settings "spk_tickets?`$select=spk_ticketid,spk_ticketnumber,spk_priority,spk_status,spk_category&`$filter=spk_ticketnumber eq '$TicketNumber'"
    if ($r.Status -ne 200) { throw "Reading $TicketNumber failed (HTTP $($r.Status)): $($r.Error)" }
    $t = @($r.Body.value) | Select-Object -First 1
    if (-not $t) { throw "$TicketNumber was not found in Dataverse." }
    return [pscustomobject]@{
        Id = $t.spk_ticketid; Number = $t.spk_ticketnumber
        Priority = [string](Get-First $t.'spk_priority@OData.Community.Display.V1.FormattedValue' $t.spk_priority)
        Status = [string](Get-First $t.'spk_status@OData.Community.Display.V1.FormattedValue' $t.spk_status)
        Category = [string](Get-First $t.'spk_category@OData.Community.Display.V1.FormattedValue' $t.spk_category)
    }
}

function Get-AgentActionRows {
    # Rows the MCP server writes to spk_agentaction for every write tool call, allowed or denied.
    param($Settings, [string]$CorrelationId)
    $attrs = Invoke-LabDataverse $Settings "EntityDefinitions(LogicalName='spk_agentaction')/Attributes?`$select=LogicalName"
    if ($attrs.Status -ne 200) { return $null }
    $corr = @($attrs.Body.value.LogicalName) | Where-Object { $_ -match 'correlation' } | Select-Object -First 1
    if (-not $corr) { return $null }
    $r = Invoke-LabDataverse $Settings "spk_agentactions?`$filter=$corr eq '$CorrelationId'"
    if ($r.Status -eq 400) { $r = Invoke-LabDataverse $Settings "spk_agentactions?`$filter=$corr eq $CorrelationId" }
    if ($r.Status -ne 200) { return $null }
    return @($r.Body.value)
}

# ==== The agent, through the Foundry Responses API
function Invoke-AgentTurn {
    # Sends one prompt to the agent as the signed-in user and answers every approval request with
    # $Decide (a script block that receives the request and returns $true to approve). The default
    # rejects every approval, so a test can never change data by accident.
    param($Settings, [string]$Prompt, [string]$ConversationId, [scriptblock]$Decide = { param($request) $false }, [int]$MaxRounds = 6)
    $endpoint = ([string]$Settings.FoundryProjectEndpoint).TrimEnd('/')
    $token = Get-LabToken 'https://ai.azure.com'
    $agentBase = "$endpoint/agents/$($Settings.AgentName)/endpoint/protocols/openai"
    $mode = 'agent'
    if (-not $ConversationId) {
        $c = Invoke-LabRest POST "$agentBase/conversations?api-version=v1" $token @{}
        if ($c.Status -eq 404) { $mode = 'project'; $c = Invoke-LabRest POST "$endpoint/openai/v1/conversations" $token @{} }
        if ($c.Status -in 401, 403) { throw "The signed-in user may not use the agent (HTTP $($c.Status)): $($c.Error)" }
        if ($c.Status -ge 400 -or -not $c.Body.id) { throw "Creating a conversation failed (HTTP $($c.Status)): $($c.Error)" }
        $ConversationId = [string]$c.Body.id
    }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $requestInput = $Prompt
    $responses = [System.Collections.Generic.List[object]]::new()
    $approvals = [System.Collections.Generic.List[object]]::new()
    $consent = $false
    for ($round = 0; $round -lt $MaxRounds; $round++) {
        if ($mode -eq 'agent') { $r = Invoke-LabRest POST "$agentBase/responses?api-version=v1" $token @{ conversation = $ConversationId; input = $requestInput } -TimeoutSec 300 }
        else { $r = Invoke-LabRest POST "$endpoint/openai/v1/responses" $token @{ conversation = $ConversationId; input = $requestInput; agent_reference = @{ type = 'agent_reference'; name = $Settings.AgentName } } -TimeoutSec 300 }
        if ($r.Status -in 401, 403) { throw "The signed-in user may not use the agent (HTTP $($r.Status)): $($r.Error)" }
        if ($r.Status -ge 400 -or $r.Status -eq 0) { throw "The agent call failed (HTTP $($r.Status)): $($r.Error)" }
        $responses.Add($r.Body)
        $output = @($r.Body.output)
        if ($output | Where-Object { $_.type -eq 'oauth_consent_request' }) { $consent = $true; break }
        $pending = @($output | Where-Object { $_.type -eq 'mcp_approval_request' })
        if (-not $pending.Count) { break }
        $requestInput = @(foreach ($p in $pending) {
            $approve = [bool](& $Decide $p)
            $approvals.Add([pscustomobject]@{ Id = $p.id; Server = $p.server_label; Tool = $p.name; Arguments = $p.arguments; Approved = $approve })
            @{ type = 'mcp_approval_response'; approval_request_id = $p.id; approve = $approve }
        })
    }
    $timer.Stop()
    $all = @($responses | ForEach-Object { @($_.output) })
    $messages = @($all | Where-Object { $_.type -eq 'message' -and $_.role -ne 'user' })
    $text = (@($messages | ForEach-Object { @($_.content) } | Where-Object { $_.text } | ForEach-Object { $_.text }) -join "`n")
    $citations = @($messages | ForEach-Object { @($_.content) } | ForEach-Object { @($_.annotations) } | Where-Object { $_ -and $_.type -eq 'url_citation' } |
        ForEach-Object { [pscustomobject]@{ Url = [string]$_.url; Title = [string]$_.title } })
    $calls = @($all | Where-Object { $_.type -eq 'mcp_call' } | ForEach-Object {
        $cid = ''
        $raw = "$($_.output)$($_.error)"
        if ($raw -match '"correlation_id"\s*:\s*"([^"]+)"') { $cid = $Matches[1] }
        [pscustomobject]@{ Server = $_.server_label; Tool = $_.name; Arguments = $_.arguments; Status = $_.status; Output = [string]$_.output; Error = [string]$_.error; CorrelationId = $cid; ApprovalRequestId = $_.approval_request_id }
    })
    return [pscustomobject]@{
        ConversationId = $ConversationId; Text = $text; Citations = $citations; McpCalls = $calls; Approvals = @($approvals)
        ConsentNeeded = $consent; Seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 1); ResponseIds = @($responses | ForEach-Object { $_.id })
    }
}

function Assert-NoConsentNeeded {
    param($Turn)
    if ($Turn.ConsentNeeded) {
        throw 'The agent asked for OAuth consent for a Service Desk connection. Open the agent in the Foundry portal playground as this user, ask a question that uses the Service Desk tools, select Open Consent and sign in, then run the test again.'
    }
}

# ==== Results and evidence
function New-AcceptanceReport {
    param([int]$Criterion, [string]$Title, $Settings)
    return [pscustomobject]@{
        Criterion = $Criterion; Title = $Title; DeploymentId = [string]$Settings.DeploymentID
        Started = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'); Finished = ''
        Checks = [System.Collections.Generic.List[object]]::new(); Notes = [System.Collections.Generic.List[string]]::new()
        Evidence = [ordered]@{}
    }
}

function Add-Check {
    param($Report, [string]$Name, [bool]$Passed, [string]$Detail = '')
    $Report.Checks.Add([pscustomobject]@{ Check = $Name; Result = $(if ($Passed) { 'PASS' } else { 'FAIL' }); Detail = (Protect-Text $Detail -FreeText) })
    Write-Host ("  [{0}] {1}{2}" -f $(if ($Passed) { 'PASS' } else { 'FAIL' }), $Name, $(if ($Detail) { ": $(Protect-Text $Detail -FreeText)" })) -ForegroundColor $(if ($Passed) { 'Green' } else { 'Red' })
}

function Add-Note { param($Report, [string]$Text) $Report.Notes.Add($Text); Write-Host "  [note] $Text" -ForegroundColor Yellow }

function Complete-AcceptanceReport {
    # Prints the result, writes <criterion>-<deployment>-<time>.json and .md, returns 0 (pass) or 1.
    param($Report, [string]$EvidencePath)
    $Report.Finished = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $failed = @($Report.Checks | Where-Object { $_.Result -eq 'FAIL' }).Count
    $passed = ($Report.Checks.Count -gt 0 -and $failed -eq 0)
    if (-not $EvidencePath) { $EvidencePath = Join-Path $HOME 'acceptance-evidence' }
    New-Item -ItemType Directory -Path $EvidencePath -Force | Out-Null
    $stamp = [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $base = Join-Path $EvidencePath ("criterion-{0:D2}-{1}-{2}" -f $Report.Criterion, $Report.DeploymentId, $stamp)
    Protect-Text ($Report | ConvertTo-Json -Depth 20) -FreeText | Set-Content -LiteralPath "$base.json" -Encoding utf8
    $cell = { param($v) ([string]$v -replace '\|', '\|' -replace '\r?\n', ' ') }
    $md = @("# Acceptance criterion $($Report.Criterion): $($Report.Title)", '',
        "Deployment $($Report.DeploymentId), run $($Report.Started) to $($Report.Finished). Result: **$(if ($passed) { 'PASS' } else { 'FAIL' })** ($($Report.Checks.Count - $failed) of $($Report.Checks.Count) checks passed).", '',
        '| Check | Result | Detail |', '|---|---|---|')
    $md += @($Report.Checks | ForEach-Object { "| $(& $cell $_.Check) | $($_.Result) | $(& $cell $_.Detail) |" })
    if ($Report.Notes.Count) { $md += @('', '## Notes', '') + @($Report.Notes | ForEach-Object { "- $(& $cell $_)" }) }
    $md += @('', "The full evidence is in $(Split-Path -Leaf "$base.json").")
    Protect-Text ($md -join [Environment]::NewLine) -FreeText | Set-Content -LiteralPath "$base.md" -Encoding utf8
    Write-Host ''
    Write-Host "Criterion $($Report.Criterion), $($Report.Title): $(if ($passed) { 'PASS' } else { 'FAIL' }) ($($Report.Checks.Count - $failed) of $($Report.Checks.Count) checks)." -ForegroundColor $(if ($passed) { 'Green' } else { 'Red' })
    Write-Host "Evidence: $base.json and $base.md"
    return $(if ($passed) { 0 } else { 1 })
}

Export-ModuleMember -Function Protect-Text, Get-First, Read-LabSettings, Get-SeedManifest, Use-LabIdentity, Get-LabToken, Invoke-LabRest,
    Invoke-LabLogQuery, Get-McpToolCalls, Wait-McpToolCall, Invoke-LabDataverse, Get-LabDataverseRows, Get-TicketState, Get-AgentActionRows,
    Invoke-AgentTurn, Assert-NoConsentNeeded, New-AcceptanceReport, Add-Check, Add-Note, Complete-AcceptanceReport
