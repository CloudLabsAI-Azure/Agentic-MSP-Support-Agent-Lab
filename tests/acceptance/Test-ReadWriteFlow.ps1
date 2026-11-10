#Requires -Version 7.0
<#
.SYNOPSIS
    Acceptance criterion 6: MCP read and controlled write, end to end, through the agent.

.DESCRIPTION
    As the Senior Technician, through the Foundry Responses API:
      1. a read: the agent reads the write target with a read tool, with no approval request;
      2. an approved write: the agent asks to change the ticket's priority; the request names the
         server (servicedesk-write), the tool and the full arguments; the test approves it; the call
         succeeds and Dataverse shows the new priority;
      3. a rejected write: the agent asks to change the ticket's status; the test rejects it; the
         tool is not called, the agent says so, and Dataverse is unchanged;
      4. the evidence: the MCP server's log lines (user, tool, authorization, outcome) and the Agent
         Action row for the approved write.
    The write target comes from the seed manifest (scenarios.write_targets.approved_priority_change,
    TCK-10544). The test flips the priority between P3 and P4, so it can run again.

    It changes one ticket: run it on a test environment, never in a participant's environment.

.EXAMPLE
    .\Test-ReadWriteFlow.ps1 -EvidencePath C:\Acceptance\evidence
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json',
    [string]$ManifestPath,
    [string]$Ticket,
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AcceptanceCommon.psm1') -Force

$settings = Read-LabSettings $SettingsPath @('FoundryProjectEndpoint', 'AgentName', 'DataverseUrl', 'ContainerApp', 'SeniorUser')
$report = New-AcceptanceReport 6 'MCP read and controlled write end to end' $settings
try {
    $manifest = Get-SeedManifest $settings $ManifestPath
    if (-not $Ticket) { $Ticket = [string]$manifest.scenarios.write_targets.approved_priority_change.ticket }
    if ($Ticket -notmatch '^TCK-\d{5}$') { throw 'No write target: pass -Ticket.' }
    if (-not $PSCmdlet.ShouldProcess("$Ticket in deployment $($settings.DeploymentID)", 'Change the priority through the agent (approved) and attempt a status change (rejected)')) { exit 0 }
    Use-LabIdentity Senior $settings

    $before = Get-TicketState $settings $Ticket
    $target = if ($before.Priority -match '^P3') { 'P4 Low' } else { 'P3 Medium' }
    Add-Note $report "Write target $Ticket starts at priority '$($before.Priority)', status '$($before.Status)'; the approved write sets $target."

    # ==== 1. Read
    $read = Invoke-AgentTurn $settings "Show me ticket $Ticket with its customer, status, priority and SLA. Use the Service Desk tools."
    Assert-NoConsentNeeded $read
    $readCall = $read.McpCalls | Where-Object { $_.Server -eq $settings.McpReadConnection -or $_.Server -eq 'servicedesk-read' } | Select-Object -First 1
    Add-Check $report 'Read through servicedesk-read without approval' ([bool]$readCall -and $read.Approvals.Count -eq 0) $(if ($readCall) { "$($readCall.Tool) $($readCall.Status), correlation ID $($readCall.CorrelationId); approvals requested: $($read.Approvals.Count)" } else { "no read tool call (calls: $(@($read.McpCalls | ForEach-Object { $_.Tool }) -join ', '))" })
    Add-Check $report 'The read returned the ticket' ($read.Text -match [regex]::Escape($Ticket)) "answer mentions $Ticket"

    # ==== 2. Approved write
    $approveOnlyPriority = { param($request) $request.server_label -eq 'servicedesk-write' -and $request.name -eq 'update_ticket_priority' -and "$($request.arguments)" -match [regex]::Escape($Ticket) }
    $write = Invoke-AgentTurn $settings "Change the priority of $Ticket to $target. Reason: acceptance test of the approved write path." -Decide $approveOnlyPriority
    $request = $write.Approvals | Where-Object { $_.Tool -eq 'update_ticket_priority' } | Select-Object -First 1
    Add-Check $report 'The write asked for approval with server, tool and full arguments' ([bool]$request -and $request.Server -eq 'servicedesk-write' -and "$($request.Arguments)" -match [regex]::Escape($Ticket)) $(if ($request) { "server $($request.Server), tool $($request.Tool), arguments $($request.Arguments)" } else { "no approval request for update_ticket_priority (approvals: $(@($write.Approvals | ForEach-Object { $_.Tool }) -join ', '))" })
    $writeCall = $write.McpCalls | Where-Object { $_.Tool -eq 'update_ticket_priority' } | Select-Object -First 1
    Add-Check $report 'The approved write ran and succeeded' ([bool]$writeCall -and -not $writeCall.Error -and $writeCall.Output -notmatch '"ok"\s*:\s*false') $(if ($writeCall) { "status $($writeCall.Status), correlation ID $($writeCall.CorrelationId)" } else { 'no mcp_call for update_ticket_priority' })
    $afterWrite = Get-TicketState $settings $Ticket
    Add-Check $report 'Dataverse shows the new priority' ($afterWrite.Priority -match [regex]::Escape($target.Split(' ')[0])) "priority '$($before.Priority)' -> '$($afterWrite.Priority)'"

    # ==== 3. Rejected write
    $rejectStart = [datetime]::UtcNow
    $declined = Invoke-AgentTurn $settings "Set the status of $Ticket to In Progress." -Decide { param($request) $false }
    $statusRequest = $declined.Approvals | Where-Object { $_.Tool -eq 'update_ticket_status' } | Select-Object -First 1
    Add-Check $report 'The status change asked for approval and was rejected' ([bool]$statusRequest -and -not $statusRequest.Approved) $(if ($statusRequest) { "arguments $($statusRequest.Arguments)" } else { 'no approval request for update_ticket_status' })
    Add-Check $report 'A rejected call is not executed' (-not ($declined.McpCalls | Where-Object { $_.Tool -eq 'update_ticket_status' })) "tool calls in that turn: $(if ($declined.McpCalls.Count) { @($declined.McpCalls | ForEach-Object { $_.Tool }) -join ', ' } else { 'none' })"
    Add-Check $report 'The agent says the change was not approved' ($declined.Text -match '(?i)not (been )?approved|declined|rejected|did not approve|didn''t approve|wasn''t approved|no changes? (was|were|has been) made') (Protect-Text ($declined.Text.Substring(0, [Math]::Min(300, $declined.Text.Length))) -FreeText)
    $afterReject = Get-TicketState $settings $Ticket
    Add-Check $report 'Dataverse status is unchanged' ($afterReject.Status -eq $afterWrite.Status) "status '$($afterWrite.Status)' -> '$($afterReject.Status)'"

    # ==== 4. Evidence in the logs and in Dataverse
    if ($writeCall -and $writeCall.CorrelationId) {
        $line = Wait-McpToolCall $settings $writeCall.CorrelationId
        Add-Check $report 'The MCP log records the write with the user and the decision' ([bool]$line -and $line.Outcome -eq 'ok' -and ($line.UserName -eq $settings.SeniorUser -or $line.UserOid)) $(if ($line) { "user $($line.UserName) ($($line.UserOid)), agent $($line.AgentId), $($line.Tool) $($line.Outcome), authorization '$($line.Authorization)', $($line.Duration) ms" } else { 'no log line within 12 minutes' })
        $report.Evidence['writeLogLine'] = if ($line) { $line.Entry } else { $null }
        $rows = Get-AgentActionRows $settings $writeCall.CorrelationId
        if ($null -eq $rows) { Add-Note $report 'The Agent Action table (spk_agentaction) could not be read with this account; check it in the Service Desk app.' }
        else { Add-Check $report 'An Agent Action row records the write' ($rows.Count -ge 1) "$($rows.Count) row(s) for correlation ID $($writeCall.CorrelationId)" }
        if ($line) {
            $since = $rejectStart.ToString('yyyy-MM-ddTHH:mm:ssZ')
            $stray = @(Get-McpToolCalls $settings "| where TimeGenerated >= datetime($since) | where Log contains 'update_ticket_status' and Log contains '$Ticket'" 'PT6H')
            Add-Check $report 'No MCP log line for the rejected status change' ($stray.Count -eq 0) "$($stray.Count) line(s) for update_ticket_status on $Ticket since $since"
        }
    }
    if ($readCall -and $readCall.CorrelationId) {
        $readLine = Wait-McpToolCall $settings $readCall.CorrelationId 5
        Add-Check $report 'The MCP log records the read on the read endpoint' ([bool]$readLine -and $readLine.Outcome -eq 'ok') $(if ($readLine) { "$($readLine.Tool) on '$($readLine.Endpoint)', user $($readLine.UserName)" } else { 'no log line within 5 minutes' })
    }
    $report.Evidence['turns'] = @(
        [pscustomobject]@{ Step = 'read'; Conversation = $read.ConversationId; Calls = $read.McpCalls; Approvals = $read.Approvals }
        [pscustomobject]@{ Step = 'approved write'; Conversation = $write.ConversationId; Calls = $write.McpCalls; Approvals = $write.Approvals }
        [pscustomobject]@{ Step = 'rejected write'; Conversation = $declined.ConversationId; Calls = $declined.McpCalls; Approvals = $declined.Approvals; Answer = (Protect-Text $declined.Text -FreeText) }
    )
    Add-Note $report 'Duplicate submission (same correlation ID within 10 minutes returns the first result) and approval expiry are checked manually: see README.md, criterion 6.'
}
catch {
    Add-Check $report 'Test ran to completion' $false $_.Exception.Message
}
exit (Complete-AcceptanceReport $report $EvidencePath)
