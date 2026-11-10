# Validation: Exercise 4, Task 4: Tighten a Tool Boundary
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID mapped to $DeploymentID; GET-AZUSER-OBJECTID mapped to $AzureUserObjectId;
#             GET-AZUSER-UPN mapped to $AzureUserName
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the MCP server's tool invocation log shows a get_open_tickets call with a limit above 20
# that was rejected with INVALID_ARGUMENT by an image other than the release image, so after the
# participant's redeploy (for example tag 3.0.2). When the log line names the violated maximum, it must
# be 20. The participant lowers the limit, redeploys and tests it in Task 4.
#
# The release tag comes from the resource group tag lab-mcp-release, else $ReleaseVersion below.
#
# Permissions for the CloudLabs service principal (all read only):
#   Azure RBAC Reader on the participant's resource group (part of its subscription role)
#       Required. Finds log-msp-<DID> and reads the resource group tags.
#   Read access to the Log Analytics workspace log-msp-<DID> (part of its subscription role)
#       Required. Queries ContainerAppConsoleLogs, where the MCP server writes one JSON line per tool call.

$ErrorActionPreference = 'Stop'
$status = 'Failed'
$message = ''
$ReleaseVersion = '3.0.0'         # The MCP server release that provisioning deploys.

# ==== Shared: read the MCP server's tool invocation log (identical in every log-based step)
$ReadTools = @('get_customer', 'search_customers', 'search_tickets', 'get_ticket', 'get_open_tickets', 'get_ticket_history',
    'search_kb_articles', 'get_kb_article', 'get_sla_status', 'get_assignment', 'list_technicians', 'get_similar_tickets',
    'get_ticket_notes', 'get_customer_contacts', 'get_customer_document', 'search_customer_documents')
$WriteTools = @('update_ticket_status', 'update_ticket_priority', 'update_ticket_category', 'link_kb_article', 'assign_ticket',
    'add_internal_note', 'add_public_reply')

function Get-First {
    foreach ($v in $args) {
        if ($null -eq $v) { continue }
        if ($v -is [string]) { if ($v -ne '') { return $v }; continue }
        if ($v -is [System.Collections.ICollection] -and $v.Count -eq 0) { continue }
        return $v
    }
    return $null
}

function Invoke-LogQuery([string]$Query) {
    $ws = Get-AzResource -ResourceType 'Microsoft.OperationalInsights/workspaces' -Name "log-msp-$DeploymentID" | Select-Object -First 1
    if (-not $ws) { throw "The Log Analytics workspace log-msp-$DeploymentID was not found in this subscription." }
    $script:ResourceGroupName = $ws.ResourceGroupName
    $customerId = ((Invoke-AzRestMethod -Method GET -Path "$($ws.ResourceId)?api-version=2023-09-01").Content | ConvertFrom-Json).properties.customerId
    if (Get-Command Invoke-AzOperationalInsightsQuery -ErrorAction SilentlyContinue) {
        return @((Invoke-AzOperationalInsightsQuery -WorkspaceId $customerId -Query $Query -Timespan (New-TimeSpan -Days 3)).Results)
    }
    $token = (Get-AzAccessToken -ResourceUrl 'https://api.loganalytics.io').Token
    if ($token -is [System.Security.SecureString]) { $token = [System.Net.NetworkCredential]::new('', $token).Password }
    $result = Invoke-RestMethod -Method Post -Uri "https://api.loganalytics.io/v1/workspaces/$customerId/query" -Headers @{ Authorization = "Bearer $token" } `
        -ContentType 'application/json' -Body (@{ query = $Query; timespan = 'P3D' } | ConvertTo-Json)
    $table = $result.tables[0]
    $rows = foreach ($row in $table.rows) {
        $o = [ordered]@{}
        for ($i = 0; $i -lt $table.columns.Count; $i++) { $o[$table.columns[$i].name] = $row[$i] }
        [pscustomobject]$o
    }
    return @($rows)
}

function Get-ToolCalls {
    # One JSON line per tool call, newest first, normalized so the checks don't depend on the exact layout.
    $query = "ContainerAppConsoleLogs | where TimeGenerated > ago(48h) | where ContainerAppName =~ 'ca-mcp-$DeploymentID' | where Log contains 'tool_call' | project TimeGenerated, RevisionName, ContainerImage, Log | order by TimeGenerated desc | take 5000"
    $calls = foreach ($row in (Invoke-LogQuery $query)) {
        $e = $null
        try { $e = $row.Log | ConvertFrom-Json } catch { $e = $null }
        if (-not $e -or [string]$e.event -ne 'tool_call') { continue }
        $auth = $e.authorization
        $authText = [string](Get-First $e.authorization_result $(if ($auth -is [string]) { $auth } else { $auth.result }))
        if ($auth -isnot [string] -and $auth.decided_by -and $authText -notmatch [regex]::Escape([string]$auth.decided_by)) { $authText = "$authText, decided by $($auth.decided_by)" }
        $when = $row.TimeGenerated
        if ($when -isnot [datetime]) {
            try { $when = [datetime]::Parse([string]$when, [Globalization.CultureInfo]::InvariantCulture, ([Globalization.DateTimeStyles]::AdjustToUniversal -bor [Globalization.DateTimeStyles]::AssumeUniversal)) } catch { }
        }
        [pscustomobject]@{
            Time          = $(if ($when -is [datetime]) { $when.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss') } else { [string]$when })
            Image         = [string]$row.ContainerImage
            Tool          = [string]$e.tool
            Endpoint      = [string](Get-First $e.endpoint $e.gateway $e.api)
            Caller        = [string]$e.caller
            Outcome       = [string]$e.outcome
            ErrorCode     = [string](Get-First $e.error_code $e.error.code)
            Authorization = [string]$authText
            UserOid       = [string](Get-First $e.user.oid $e.user.object_id $e.user_oid)
            UserName      = [string](Get-First $e.user.upn $e.user.preferred_username $e.user.name $e.user_name)
            Ticket        = [string](Get-First $e.arguments.ticket_number $e.arguments.ticket $e.arguments.ticket_id)
            Arguments     = $e.arguments
            Correlation   = [string]$e.correlation_id
            Entry         = $e
        }
    }
    return @($calls)
}

function Test-ReadCall($Call) {
    if ($Call.Endpoint -match '(?i)read') { return $true }
    if ($Call.Endpoint -match '(?i)write') { return $false }
    return ($Call.Tool -in $ReadTools -or ($Call.Tool -notin $WriteTools -and $Call.Tool -match '^(get|search|list)_'))
}

function Test-WriteCall($Call) { return -not (Test-ReadCall $Call) }

function Test-HasUser($Call) { return [bool]($Call.UserOid -or $Call.UserName) }

function Test-Tier1($Call) {
    if (-not (Test-HasUser $Call)) { return $false }
    if ($Call.UserName -like 'tier1.technician@*' -or $Call.UserName -eq 'Tier 1 Technician') { return $true }
    if ($AzureUserObjectId -and $Call.UserOid) { return ($Call.UserOid -ne $AzureUserObjectId) }
    return $false
}

function Test-Senior($Call) {
    if (-not (Test-HasUser $Call)) { return $false }
    if ($AzureUserObjectId -and $Call.UserOid) { return ($Call.UserOid -eq $AzureUserObjectId) }
    if ($AzureUserName -and $Call.UserName -like '*@*') { return ($Call.UserName -eq $AzureUserName) }
    return -not (Test-Tier1 $Call)
}

function Test-Denied($Call) {
    if ($Call.Outcome -eq 'ok') { return $false }
    return ($Call.Outcome -match '(?i)denied|rejected|blocked' -or $Call.Authorization -match '(?i)denied|rejected' -or $Call.ErrorCode -match '(?i)DENIED|NOT_ALLOWED|FORBIDDEN|0x80040220|0x80048306')
}

function Test-DeniedByDataverse($Call) {
    if ($Call.Outcome -eq 'ok') { return $false }
    if ($Call.Authorization -match '(?i)denied.*dataverse') { return $true }
    return ($Call.ErrorCode -match '(?i)DATAVERSE_ACCESS_DENIED|0x80048306|0x80040220|PrivilegeDenied|AccessDenied')
}

function Get-LabFact([string]$Tag, [string]$Default) {
    # Provisioning records values from the seed manifest as tags on the resource group (lab-*).
    try {
        if ($script:ResourceGroupName) {
            $tags = (Get-AzResourceGroup -Name $script:ResourceGroupName).Tags
            if ($tags -and $tags[$Tag]) { return [string]$tags[$Tag] }
        }
    }
    catch { }
    return $Default
}
# ==== End of the shared part

function Get-Violation($Call, [string]$What) {
    # The input validation details of a rejected call: the value received and the maximum allowed.
    $lists = @($Call.Entry.record.violations, $Call.Entry.violations, $Call.Entry.error.violations, $Call.Entry.details.violations) | Where-Object { $_ }
    foreach ($v in @($lists | ForEach-Object { $_ })) {
        if ($What -eq 'maximum') {
            $m = Get-First $v.constraint.le $v.constraint.maximum $v.maximum $v.le $v.max
            if ($null -ne $m) { return [string]$m }
        }
        elseif ("$($v.received)" -match '^\d+$') { return [string]$v.received }
    }
    return ''
}

for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $calls = Get-ToolCalls
        $release = (Get-LabFact 'lab-mcp-release' $ReleaseVersion).TrimStart('v')
        $boundary = foreach ($c in @($calls | Where-Object { $_.Tool -eq 'get_open_tickets' })) {
            $limitText = [string](Get-First $c.Arguments.limit (Get-Violation $c 'received'))
            $tag = if ($c.Image -match ':([^:/]+)$') { $Matches[1].TrimStart('v') } else { '' }
            [pscustomobject]@{ Call = $c; Limit = $(if ($limitText -match '^\d+$') { [int]$limitText } else { 0 }); Maximum = (Get-Violation $c 'maximum'); Tag = $tag }
        }
        $boundary = @($boundary)
        $rejected = @($boundary | Where-Object { $_.Call.ErrorCode -eq 'INVALID_ARGUMENT' -and $_.Limit -gt 20 })
        $good = $rejected | Where-Object { $_.Tag -and $_.Tag -ne $release -and (-not $_.Maximum -or $_.Maximum -eq '20') } | Select-Object -First 1
        if ($good) {
            $status = 'Succeeded'
            $message = "get_open_tickets rejected limit $($good.Limit) with INVALID_ARGUMENT on image tag $($good.Tag) at $($good.Call.Time) UTC$(if ($good.Maximum) { "; the maximum is now $($good.Maximum)" })."
            break
        }
        $wrongMax = $rejected | Where-Object { $_.Tag -ne $release -and $_.Maximum -and $_.Maximum -ne '20' } | Select-Object -First 1
        $onRelease = $rejected | Where-Object { $_.Tag -eq $release -or -not $_.Tag } | Select-Object -First 1
        $accepted = $boundary | Where-Object { $_.Call.Outcome -eq 'ok' -and $_.Limit -gt 20 -and $_.Tag -and $_.Tag -ne $release } | Select-Object -First 1
        if ($wrongMax) {
            $message = "get_open_tickets rejected limit $($wrongMax.Limit) against a maximum of $($wrongMax.Maximum), not 20. Set the maximum to 20, redeploy and try again."
        }
        elseif ($accepted) {
            $message = "get_open_tickets accepted limit $($accepted.Limit) on image tag $($accepted.Tag), so the maximum is not 20 yet. Lower it to 20, redeploy and try again."
        }
        elseif ($onRelease) {
            $message = "get_open_tickets rejected limit $($onRelease.Limit), but on the release image. Redeploy your change with the new maximum of 20 first, then call it again with a limit above 20."
        }
        else {
            $message = 'No get_open_tickets call with a limit above 20 has been rejected yet. After you redeploy with the maximum of 20, call get_open_tickets with a limit above 20 (for example 25), as Task 4 shows. Logs take a few minutes to arrive; validate again shortly.'
        }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
