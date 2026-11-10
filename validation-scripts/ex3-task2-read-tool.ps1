# Validation: Exercise 3, Task 2: Call an Existing Read Tool
# Script Type: PowerShellV2   Run As: System
# Parameters: GET-DEPLOYMENT-ID mapped to $DeploymentID; GET-AZUSER-OBJECTID mapped to $AzureUserObjectId;
#             GET-AZUSER-UPN mapped to $AzureUserName
# No authentication code: CloudLabs prepends the Azure sign-in when the step is deployed.
#
# Passes when the MCP server's tool invocation log shows a successful read tool call that came through
# the read gateway (servicedesk-read) with the Senior Technician's validated token. Calls through the
# diagnostics API carry no user and don't count. The participant calls a read tool in Task 2.
#
# Permissions for the CloudLabs service principal (all read only):
#   Azure RBAC Reader on the participant's resource group (part of its subscription role)
#       Required. Finds log-msp-<DID> and reads the resource group tags.
#   Read access to the Log Analytics workspace log-msp-<DID> (part of its subscription role)
#       Required. Queries ContainerAppConsoleLogs, where the MCP server writes one JSON line per tool call.

$ErrorActionPreference = 'Stop'
$status = 'Failed'
$message = ''

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

for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
        $calls = Get-ToolCalls
        $reads = @($calls | Where-Object { Test-ReadCall $_ })
        $good = $reads | Where-Object { $_.Outcome -eq 'ok' -and (Test-Senior $_) -and $_.Endpoint -notmatch '(?i)diag' -and $_.Caller -ne 'operator' } | Select-Object -First 1
        if ($good) {
            $status = 'Succeeded'
            $message = "$($good.UserName) called the read tool $($good.Tool) through the read gateway at $($good.Time) UTC; it succeeded (correlation ID $($good.Correlation))."
            break
        }
        $diag = $reads | Where-Object { $_.Outcome -eq 'ok' -and -not (Test-HasUser $_) } | Select-Object -First 1
        $other = $reads | Where-Object { $_.Outcome -eq 'ok' -and (Test-HasUser $_) -and -not (Test-Senior $_) } | Select-Object -First 1
        $failed = $reads | Where-Object { (Test-Senior $_) -and $_.Outcome -ne 'ok' } | Select-Object -First 1
        if ($failed) {
            $message = "Your last read tool call, $($failed.Tool), returned $($failed.Outcome) $($failed.ErrorCode). Read the error, correct the request and call the tool again."
        }
        elseif ($other) {
            $message = "A read tool call by $($other.UserName) was logged, but not one by you. Sign in with your own lab account and call the read tool again, as Task 2 shows."
        }
        elseif ($diag) {
            $message = "Only read tool calls through the diagnostics API (no signed-in user) have been logged. Call the read tool through the agent, signed in with your lab account, as Task 2 shows."
        }
        else {
            $message = 'No read tool call has been logged yet. Call a read tool as Task 2 shows. Logs take a few minutes to arrive; validate again shortly.'
        }
    }
    catch { $message = "Validation could not complete: $($_.Exception.Message)" }
    if ($attempt -lt 3) { Start-Sleep -Seconds 60 }
}

$body = @{ Status = $status; Message = $message } | ConvertTo-Json
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body       = $body })
