#Requires -Version 7.0
<#
.SYNOPSIS
    Acceptance criterion 11: correlated audit evidence. One correlation ID links the user's request, the
    agent, the MCP tool, the authorization result, the backend call, the action and the outcome.

.DESCRIPTION
    Runs C:\LabFiles\tools\Get-ActionTrail.ps1 for one approved write (by default the Senior
    Technician's most recent successful write in the MCP log) and checks that the trail holds every hop
    with the same correlation ID: the agent run in Application Insights, the approval in the Foundry
    conversation, the API Management rows, the MCP server log line with all its fields (user, agent ID,
    tool, argument summary, authorization result, backend call, outcome, duration), the Dataverse audit
    record and the Agent Action row, and that the user is the same at the gateway, the MCP server and
    Dataverse. The trail is exported as JSON and Markdown next to this test's evidence, as participants
    do in Exercises 6 and 7.

    Run it as the Senior Technician at least five minutes after the write (traces take 2 to 5 minutes);
    -WaitMinutes keeps checking for late hops.

.EXAMPLE
    .\Test-CorrelatedAudit.ps1 -EvidencePath C:\Acceptance\evidence
#>
[CmdletBinding()]
param(
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json',
    [string]$CorrelationId,
    [string]$ConversationId,
    [ValidateRange(0, 30)][int]$WaitMinutes = 10,
    [string]$ActionTrailPath,
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AcceptanceCommon.psm1') -Force

$settings = Read-LabSettings $SettingsPath @('ContainerApp', 'SeniorUser')
$report = New-AcceptanceReport 11 'Correlated audit evidence' $settings
try {
    Use-LabIdentity Senior $settings
    if (-not $ActionTrailPath) { $ActionTrailPath = @('C:\LabFiles\tools\Get-ActionTrail.ps1', (Join-Path $PSScriptRoot '..\..\setup\assets\labfiles\tools\Get-ActionTrail.ps1')) | Where-Object { Test-Path $_ } | Select-Object -First 1 }
    if (-not $ActionTrailPath) { throw 'Get-ActionTrail.ps1 was not found; pass -ActionTrailPath.' }

    if (-not $CorrelationId) {
        $writes = @(Get-McpToolCalls $settings '' 'P1D' | Where-Object { $_.Outcome -eq 'ok' -and $_.Endpoint -match '(?i)write' -and ($_.UserName -eq $settings.SeniorUser -or $_.UserOid) })
        if (-not $writes.Count) { throw 'No successful write by the Senior Technician in the last day. Run Test-ReadWriteFlow.ps1 first, or pass -CorrelationId.' }
        $CorrelationId = $writes[0].Correlation
        Add-Note $report "Using the latest successful write: $($writes[0].Tool) on $($writes[0].Ticket) at $($writes[0].Time), correlation ID $CorrelationId."
    }

    $dir = if ($EvidencePath) { $EvidencePath } else { Join-Path $HOME 'acceptance-evidence' }
    $trailArgs = @{ CorrelationId = $CorrelationId; SettingsPath = $SettingsPath; WaitMinutes = $WaitMinutes; OutFile = (Join-Path $dir "criterion-11-trail-$CorrelationId"); PassThru = $true }
    if ($ConversationId) { $trailArgs.ConversationId = $ConversationId }
    $trail = & $ActionTrailPath @trailArgs
    if (-not $trail) { throw 'Get-ActionTrail.ps1 returned no evidence.' }
    $trail = @($trail)[-1]

    $status = @{}
    foreach ($s in @($trail.sources)) { $status[$s.Source] = $s }
    foreach ($hop in 'Application Insights', 'Foundry conversation', 'API Management', 'MCP server log', 'Dataverse audit', 'Agent Action row') {
        $s = $status[$hop]
        Add-Check $report "Hop found: $hop" ([bool]$s -and $s.Status -eq 'Found') $(if ($s) { "$($s.Status): $($s.Detail)" } else { 'not checked' })
    }
    $line = @($trail.records.mcpServerLog) | Select-Object -First 1
    $fields = [ordered]@{
        'correlation ID'       = [string]$line.correlation_id -eq $CorrelationId
        'user'                 = [bool](Get-First $line.user.oid $line.user.upn $line.user.name)
        'agent ID'             = [bool](Get-First $line.agent.id $line.agent_id)
        'tool'                 = [bool]$line.tool
        'argument summary'     = $null -ne (Get-First $line.arguments $line.argument_summary)
        'authorization result' = [bool](Get-First $line.authorization_result $line.authorization)
        'backend call'         = @(Get-First $line.backend_calls $line.backend $line.dataverse).Count -gt 0
        'outcome'              = [bool]$line.outcome
        'duration'             = $null -ne (Get-First $line.duration_ms $line.latency_ms)
    }
    $absent = @($fields.Keys | Where-Object { -not $fields[$_] })
    Add-Check $report 'The MCP log line carries every Exhibit C field' ($line -and $absent.Count -eq 0) $(if ($line) { "missing: $(if ($absent.Count) { $absent -join ', ' } else { 'none' })" } else { 'no MCP log line' })

    $lineOid = [string](Get-First $line.user.oid $line.user.object_id)
    $audit = @($trail.records.dataverseAudit) | Select-Object -First 1
    Add-Check $report 'The same user at the MCP server and in the Dataverse audit' ($lineOid -and $audit -and [string]$audit.ChangedByObjectId -eq $lineOid) "MCP log user object ID $lineOid; audit changed by $($audit.ChangedBy) ($($audit.ChangedByObjectId))"
    Add-Check $report 'The approval is in the trail' ([string]$trail.summary.'What was authorized' -match 'approval: approved') ([string]$trail.summary.'What was authorized')
    foreach ($p in $trail.summary.PSObject.Properties) {
        Add-Check $report "Summary answers: $($p.Name)" ([string]$p.Value -notmatch 'not known yet') ([string]$p.Value)
    }
    $report.Evidence['trailSummary'] = $trail.summary
    Add-Note $report "The full trail is in criterion-11-trail-$CorrelationId.json and .md."
}
catch {
    Add-Check $report 'Test ran to completion' $false $_.Exception.Message
}
exit (Complete-AcceptanceReport $report $EvidencePath)
