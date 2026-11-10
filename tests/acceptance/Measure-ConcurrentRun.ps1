#Requires -Version 7.0
<#
.SYNOPSIS
    Acceptance criterion 13 (evidence): 25 concurrent participants without degradation. Summarizes the
    Test-GroundedRetrieval.ps1 results that every environment produced during one concurrent run.

.DESCRIPTION
    Reads every criterion-05-*.json in -Path (one or more per environment, all from the same time
    window), and passes when every environment answered every question with the expected sources and
    the median answer time across all environments stays within -Tolerance times the single-environment
    baseline (-BaselineMedianSeconds, measured the day before on one environment alone).

.EXAMPLE
    .\Measure-ConcurrentRun.ps1 -Path C:\Acceptance\concurrency -BaselineMedianSeconds 14 -ExpectedEnvironments 25
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [double]$BaselineMedianSeconds,
    [double]$Tolerance = 1.5,
    [int]$ExpectedEnvironments = 25,
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json',
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AcceptanceCommon.psm1') -Force

$settings = if (Test-Path $SettingsPath) { Read-LabSettings $SettingsPath } else { [pscustomobject]@{ DeploymentID = 'all' } }
$report = New-AcceptanceReport 13 'Concurrent participants without degradation' $settings
try {
    $runs = @(Get-ChildItem -LiteralPath $Path -Filter 'criterion-05-*.json' -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json })
    if (-not $runs.Count) { throw "No criterion-05-*.json results in $Path." }
    $environments = @($runs | Group-Object DeploymentId)
    Add-Check $report "Results from $ExpectedEnvironments environments" ($environments.Count -ge $ExpectedEnvironments) "$($environments.Count) environment(s): $(@($environments.Name) -join ', ')"
    $failedRuns = @($runs | Where-Object { @($_.Checks | Where-Object { $_.Result -eq 'FAIL' }).Count })
    Add-Check $report 'Every environment answered every question with the expected sources' ($failedRuns.Count -eq 0) "$($runs.Count) run(s); failed: $(if ($failedRuns.Count) { @($failedRuns.DeploymentId | Select-Object -Unique) -join ', ' } else { 'none' })"
    $times = @($runs | ForEach-Object { @($_.Evidence.questions) } | ForEach-Object { [double]$_.Seconds } | Sort-Object)
    if ($times.Count) {
        $median = $times[[int][Math]::Floor(($times.Count - 1) / 2)]
        $p95 = $times[[int][Math]::Min($times.Count - 1, [Math]::Ceiling(0.95 * $times.Count) - 1)]
        $report.Evidence['timing'] = [pscustomobject]@{ Answers = $times.Count; MedianSeconds = $median; P95Seconds = $p95; MaxSeconds = $times[-1] }
        if ($BaselineMedianSeconds -gt 0) {
            Add-Check $report "Median answer time within $Tolerance x the single-environment baseline" ($median -le $Tolerance * $BaselineMedianSeconds) "median $median s (p95 $p95 s) against a baseline of $BaselineMedianSeconds s"
        }
        else { Add-Note $report "Median $median s, p95 $p95 s over $($times.Count) answers. Pass -BaselineMedianSeconds to compare with the single-environment run." }
    }
    $errors = @($runs | ForEach-Object { @($_.Checks) } | Where-Object { $_.Detail -match '(?i)HTTP 429|HTTP 5\d\d|rate limit' })
    Add-Check $report 'No throttling or server errors' ($errors.Count -eq 0) "$($errors.Count) check(s) mention HTTP 429 or 5xx"
}
catch {
    Add-Check $report 'Test ran to completion' $false $_.Exception.Message
}
exit (Complete-AcceptanceReport $report $EvidencePath)
