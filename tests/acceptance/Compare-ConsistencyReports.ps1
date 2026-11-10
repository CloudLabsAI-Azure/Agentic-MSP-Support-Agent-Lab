#Requires -Version 7.0
<#
.SYNOPSIS
    Acceptance criterion 3 (part 2): baseline consistency. Compares the fingerprints (and readiness
    results) of several environments and passes when every environment is identical to the Golden
    Environment version.

.DESCRIPTION
    Reads every fingerprint-*.json in -Path (written by Export-EnvironmentFingerprint.ps1), flattens
    each into setting paths and values, and reports every setting whose value differs between
    environments. It also checks that each environment reports the Golden Environment version (v1.0)
    and, when a readiness result is included, that every component is Ready. Values that are specific
    to an environment were already replaced by placeholders, so any difference is real.

.EXAMPLE
    .\Compare-ConsistencyReports.ps1 -Path C:\Acceptance\fingerprints
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [string]$GoldenVersion = 'v1.0',
    [string[]]$Ignore = @('collectedAt', 'deploymentId', 'errors*', 'agent.latestVersion'),
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json',
    [string]$EvidencePath
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'AcceptanceCommon.psm1') -Force

function ConvertTo-Flat($Node, [string]$Prefix, [hashtable]$Into) {
    if ($null -eq $Node) { $Into[$Prefix] = ''; return }
    if ($Node -is [string] -or $Node -is [ValueType]) { $Into[$Prefix] = [string]$Node; return }
    if ($Node -is [System.Collections.IEnumerable]) {
        $items = @($Node)
        if (@($items | Where-Object { $_ -isnot [string] -and $_ -isnot [ValueType] }).Count -eq 0) { $Into[$Prefix] = ($items | ForEach-Object { [string]$_ }) -join "`n"; return }
        for ($i = 0; $i -lt $items.Count; $i++) { ConvertTo-Flat $items[$i] "$Prefix[$i]" $Into }
        return
    }
    foreach ($p in $Node.PSObject.Properties) { ConvertTo-Flat $p.Value $(if ($Prefix) { "$Prefix.$($p.Name)" } else { $p.Name }) $Into }
}

$settings = if (Test-Path $SettingsPath) { Read-LabSettings $SettingsPath } else { [pscustomobject]@{ DeploymentID = 'all' } }
$report = New-AcceptanceReport 3 'Baseline consistency across environments' $settings
try {
    $files = @(Get-ChildItem -LiteralPath $Path -Filter 'fingerprint-*.json' -File)
    if ($files.Count -lt 2) { throw "At least two fingerprint files are needed in $Path; found $($files.Count)." }
    $flat = [ordered]@{}
    foreach ($f in $files) {
        $data = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
        $h = @{}
        ConvertTo-Flat $data '' $h
        $flat[[string]$data.deploymentId] = $h
        Add-Check $report "Deployment $($data.deploymentId) reports Golden Environment version $GoldenVersion" ([string]$data.lab.goldenEnvironmentVersion -eq $GoldenVersion) "reports '$($data.lab.goldenEnvironmentVersion)'"
        if (@($data.errors).Count) { Add-Note $report "Deployment $($data.deploymentId) has unreadable sections: $(@($data.errors) -join '; ')" }
        if ($data.readiness -and $data.readiness -ne 'unavailable') {
            $notReady = @($data.readiness | Where-Object { $_ -notmatch '\|Ready$' })
            Add-Check $report "Deployment $($data.deploymentId) readiness: every component Ready" ($notReady.Count -eq 0) $(if ($notReady.Count) { $notReady -join '; ' } else { "$(@($data.readiness).Count) components" })
        }
    }
    $keys = @($flat.Values | ForEach-Object { $_.Keys } | Select-Object -Unique | Where-Object { $k = $_; -not @($Ignore | Where-Object { $k -like $_ }).Count } | Sort-Object)
    $differences = [System.Collections.Generic.List[object]]::new()
    foreach ($k in $keys) {
        $values = @($flat.Keys | ForEach-Object { [pscustomobject]@{ Deployment = $_; Value = $(if ($flat[$_].ContainsKey($k)) { $flat[$_][$k] } else { '(absent)' }) } })
        if (@($values.Value | Select-Object -Unique).Count -gt 1) {
            $groups = $values | Group-Object Value | Sort-Object Count -Descending
            $differences.Add([pscustomobject]@{ Setting = $k; Majority = $groups[0].Name; Different = (@($groups | Select-Object -Skip 1 | ForEach-Object { "$($_.Group.Deployment -join ', '): $($_.Name)" }) -join ' | ') })
        }
    }
    $report.Evidence['environments'] = @($flat.Keys)
    $report.Evidence['differences'] = $differences
    Add-Check $report "All $($files.Count) environments are configured identically" ($differences.Count -eq 0) "$($keys.Count) settings compared; $($differences.Count) differ$(if ($differences.Count) { ': ' + (@($differences | Select-Object -First 5 | ForEach-Object { $_.Setting }) -join ', ') })"
    if ($differences.Count) { $differences | Select-Object -First 20 | Format-Table -Wrap -AutoSize | Out-String -Width 220 | Write-Host }
}
catch {
    Add-Check $report 'Test ran to completion' $false $_.Exception.Message
}
exit (Complete-AcceptanceReport $report $EvidencePath)
