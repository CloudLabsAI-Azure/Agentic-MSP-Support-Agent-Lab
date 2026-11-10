#Requires -Version 7.0
<#
.SYNOPSIS
    Acceptance criterion 8: authorization denial and least privilege. The Tier 1 Technician's priority
    change is denied by Dataverse with no change; the same request as the Senior Technician succeeds;
    both appear in the correlated log with the user's identity, and in Dataverse.

.DESCRIPTION
    Drive mode (default) signs in both technicians in separate Azure CLI profiles (you sign in each one
    in the browser) and sends the same request through the agent: change the priority of the seed's
    target (scenarios.write_targets.tier1_versus_senior, TCK-10543). Each approval is approved, so the
    decision is left to Dataverse. Verify mode skips the requests and checks a run you did in the
    playground: pass -Tier1CorrelationId and -SeniorCorrelationId.

    Evidence: both tool invocation log lines (user, agent ID, tool, authorization result, outcome),
    the gateway rows, the Agent Action rows (written for allowed and denied writes), the Dataverse
    audit record of the Senior Technician's change, and the absence of a change for the denied one
    (Dataverse audits changes only). Get-ActionTrail.ps1 exports both trails.

    It changes one ticket: run it on a test environment.

.EXAMPLE
    .\Test-UserAuthorization.ps1 -EvidencePath C:\Acceptance\evidence

.EXAMPLE
    .\Test-UserAuthorization.ps1 -Tier1CorrelationId <id> -SeniorCorrelationId <id>
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json',
    [string]$ManifestPath,
    [string]$Ticket,
    [string]$Tier1CorrelationId,
    [string]$SeniorCorrelationId,
    [string]$ActionTrailPath,
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AcceptanceCommon.psm1') -Force

$settings = Read-LabSettings $SettingsPath @('FoundryProjectEndpoint', 'AgentName', 'DataverseUrl', 'ContainerApp', 'SeniorUser', 'Tier1User')
$report = New-AcceptanceReport 8 'Authorization denial and least privilege' $settings
try {
    $manifest = Get-SeedManifest $settings $ManifestPath
    $targetInfo = $manifest.scenarios.write_targets.tier1_versus_senior
    if (-not $Ticket) { $Ticket = [string]$targetInfo.ticket }
    $verify = [bool]($Tier1CorrelationId -and $SeniorCorrelationId)

    if (-not $verify) {
        if (-not $PSCmdlet.ShouldProcess("$Ticket in deployment $($settings.DeploymentID)", 'Request a priority change as the Tier 1 and the Senior Technician')) { exit 0 }
        Use-LabIdentity Senior $settings
        $before = Get-TicketState $settings $Ticket
        $target = if ($before.Priority -match '^P2') { 'P3 Medium' } else { [string](Get-First $targetInfo.to_priority 'P2 High') }
        $prompt = "Change the priority of $Ticket to $target. Reason: acceptance test of user-level authorization."
        $approve = { param($request) $request.name -eq 'update_ticket_priority' }

        Use-LabIdentity Tier1 $settings
        try { $tier1Turn = Invoke-AgentTurn $settings $prompt -Decide $approve }
        catch { throw "The Tier 1 Technician could not use the agent: $($_.Exception.Message). The account needs Foundry Agent Consumer on the project (a pilot item says it may need Foundry User for the playground). Or run the request in the playground and use Verify mode." }
        Assert-NoConsentNeeded $tier1Turn
        $tier1Call = $tier1Turn.McpCalls | Where-Object { $_.Tool -eq 'update_ticket_priority' } | Select-Object -First 1
        $Tier1CorrelationId = if ($tier1Call) { $tier1Call.CorrelationId } else { '' }
        $tier1Result = if ($tier1Call) { "$($tier1Call.Error) $($tier1Call.Output)".Trim() } else { '' }
        if ($tier1Result.Length -gt 240) { $tier1Result = $tier1Result.Substring(0, 240) }
        Add-Check $report 'Tier 1: the approved call was refused' ([bool]$tier1Call -and ($tier1Result -match '(?i)denied|"ok"\s*:\s*false|privilege|not allowed')) $(if ($tier1Call) { "correlation ID $Tier1CorrelationId; $tier1Result" } else { 'the agent made no update_ticket_priority call' })

        Use-LabIdentity Senior $settings
        $afterTier1 = Get-TicketState $settings $Ticket
        Add-Check $report 'Tier 1: no change in Dataverse' ($afterTier1.Priority -eq $before.Priority) "priority stays '$($afterTier1.Priority)'"

        $seniorTurn = Invoke-AgentTurn $settings $prompt -Decide $approve
        Assert-NoConsentNeeded $seniorTurn
        $seniorCall = $seniorTurn.McpCalls | Where-Object { $_.Tool -eq 'update_ticket_priority' } | Select-Object -First 1
        $SeniorCorrelationId = if ($seniorCall) { $seniorCall.CorrelationId } else { '' }
        Add-Check $report 'Senior: the same request succeeded' ([bool]$seniorCall -and -not $seniorCall.Error -and $seniorCall.Output -notmatch '"ok"\s*:\s*false') $(if ($seniorCall) { "correlation ID $SeniorCorrelationId" } else { 'the agent made no update_ticket_priority call' })
        $afterSenior = Get-TicketState $settings $Ticket
        Add-Check $report 'Senior: Dataverse shows the change' ($afterSenior.Priority -match [regex]::Escape($target.Split(' ')[0])) "priority '$($before.Priority)' -> '$($afterSenior.Priority)'"
    }
    else { Use-LabIdentity Senior $settings }

    # ==== Evidence: the correlated log and Dataverse
    foreach ($pair in @(@{ Who = 'Tier 1'; Id = $Tier1CorrelationId; Expect = 'denied'; User = [string]$settings.Tier1User }, @{ Who = 'Senior'; Id = $SeniorCorrelationId; Expect = 'ok'; User = [string]$settings.SeniorUser })) {
        if (-not $pair.Id) { Add-Check $report "$($pair.Who): correlation ID known" $false 'no correlation ID from the tool result'; continue }
        $line = Wait-McpToolCall $settings $pair.Id
        $okOutcome = if ($pair.Expect -eq 'ok') { $line.Outcome -eq 'ok' -and $line.Authorization -match '(?i)allowed' } else { $line.Outcome -ne 'ok' -and $line.Authorization -match '(?i)denied.*dataverse' }
        Add-Check $report "$($pair.Who): the MCP log shows the user and the decision" ([bool]$line -and $okOutcome -and ($line.UserName -eq $pair.User -or $line.UserOid)) $(if ($line) { "user $($line.UserName) ($($line.UserOid)), agent ID $($line.AgentId), $($line.Tool) on $($line.Ticket): $($line.Outcome), '$($line.Authorization)' $($line.ErrorCode)" } else { 'no log line within 12 minutes' })
        $gateway = @(Invoke-LabLogQuery $settings "ApiManagementGatewayLogs | where CorrelationId == '$($pair.Id)' or tostring(column_ifexists('BackendRequestHeaders', '')) contains '$($pair.Id)' | project TimeGenerated, ResponseCode, ApiId | take 5" 'PT6H')
        Add-Check $report "$($pair.Who): the gateway logged the call" ($gateway.Count -ge 1) "$($gateway.Count) gateway row(s)$(if ($gateway.Count) { ", HTTP $($gateway[0].ResponseCode) on $($gateway[0].ApiId)" })"
        $rows = Get-AgentActionRows $settings $pair.Id
        if ($null -eq $rows) { Add-Note $report "$($pair.Who): the Agent Action table could not be read with this account." }
        else { Add-Check $report "$($pair.Who): an Agent Action row records the decision" ($rows.Count -ge 1) "$($rows.Count) row(s)" }
        $report.Evidence["$($pair.Who)LogLine"] = if ($line) { $line.Entry } else { $null }
    }

    $ticketState = Get-TicketState $settings $Ticket
    $audits = Invoke-LabDataverse $settings "audits?`$select=createdon,action,_userid_value,_callinguserid_value&`$filter=_objectid_value eq $($ticketState.Id)&`$orderby=createdon desc&`$top=10"
    if ($audits.Status -eq 200) {
        $recent = @($audits.Body.value | Where-Object { [datetime]$_.createdon -gt [datetime]::UtcNow.AddHours(-6) })
        $users = @($recent | ForEach-Object { [string]$_.'_userid_value@OData.Community.Display.V1.FormattedValue' })
        Add-Check $report 'Dataverse audit records the allowed change' ($recent.Count -ge 1) "$($recent.Count) audit record(s) in the last 6 hours, changed by: $($users -join ', '); called by: $(@($recent | ForEach-Object { [string]$_.'_callinguserid_value@OData.Community.Display.V1.FormattedValue' } | Select-Object -Unique) -join ', ')"
        Add-Note $report 'Dataverse audits changes only, so the denied request leaves no audit record; its Dataverse evidence is the Agent Action row, and the MCP and gateway logs carry it with the user''s identity.'
    }
    else { Add-Note $report "Dataverse audit could not be read with this account (HTTP $($audits.Status)); the Senior Technician needs the View Audit Summary privilege." }

    if (-not $ActionTrailPath) { $ActionTrailPath = @('C:\LabFiles\tools\Get-ActionTrail.ps1', (Join-Path $PSScriptRoot '..\..\setup\assets\labfiles\tools\Get-ActionTrail.ps1')) | Where-Object { Test-Path $_ } | Select-Object -First 1 }
    if ($ActionTrailPath) {
        $dir = if ($EvidencePath) { $EvidencePath } else { Join-Path $HOME 'acceptance-evidence' }
        foreach ($id in @($Tier1CorrelationId, $SeniorCorrelationId) | Where-Object { $_ }) {
            & $ActionTrailPath -CorrelationId $id -SettingsPath $SettingsPath -OutFile (Join-Path $dir "criterion-08-trail-$id") | Out-Null
        }
        Add-Note $report "Both action trails were exported next to this report (criterion-08-trail-<correlation ID>.json and .md)."
    }
}
catch {
    Add-Check $report 'Test ran to completion' $false $_.Exception.Message
}
exit (Complete-AcceptanceReport $report $EvidencePath)
