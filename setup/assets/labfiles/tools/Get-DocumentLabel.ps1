#Requires -Version 7.0
<#
.SYNOPSIS
    Shows the Microsoft Purview sensitivity label recorded inside a Word document, and whether it is
    the label your lab's Service Desk protects (Exercise 6, Task 2).

.DESCRIPTION
    A labelled Office document carries its label with it, as metadata named after the label's ID:
      docProps/custom.xml   custom properties MSIP_Label_<label ID>_Enabled, _SiteId, _Method,
                            _SetDate, _Name (the classic location)
      LabelInfo.xml         the location Office uses when co-authoring of labelled files is on
    This script reads both without opening the document, so it needs neither Word nor a sign-in.
    The MCP server reads the same metadata before it returns a customer document to the agent, and
    refuses a document with a restricted label (CONTENT_BLOCKED_BY_LABEL).

    The script compares what it finds with the label in C:\LabFiles\lab-settings.json
    (SensitivityLabelId and SensitivityLabelName) and with your tenant ID. Read-only.

.PARAMETER Path
    The .docx file. Without it, the script looks in your Downloads folder.

.EXAMPLE
    C:\LabFiles\tools\Get-DocumentLabel.ps1 -Path "$HOME\Downloads\Woodgrove-Bank-Secure-Gateway-configuration.docx"
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)][string]$Path,
    [string]$SettingsPath = 'C:\LabFiles\lab-settings.json'
)

$ErrorActionPreference = 'Stop'

function Stop-Script([string]$Text) { Write-Host ''; Write-Host "Stopped: $Text" -ForegroundColor Red; exit 1 }

function Read-ZipText($Zip, $Entry) {
    $reader = [System.IO.StreamReader]::new($Entry.Open())
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    if (-not $Path) {
        $downloads = Join-Path $HOME 'Downloads'
        $candidates = @(Get-ChildItem -LiteralPath $downloads -Filter '*.docx' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        if ($candidates.Count -eq 1) { $Path = $candidates[0].FullName; Write-Host "Reading $Path" }
        elseif ($candidates.Count -gt 1) {
            Write-Host "Several Word documents are in $($downloads):"
            $candidates | Select-Object -First 10 | ForEach-Object { Write-Host "  $($_.Name)  ($($_.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))" }
            Stop-Script 'Run the script again with -Path and the document you want to check.'
        }
        else {
            Stop-Script "No .docx file was found in $downloads. Download the labelled configuration document from Woodgrove Bank's record in the Service Desk app, as the guide shows, then run the script again (or pass -Path)."
        }
    }
    if (-not (Test-Path -LiteralPath $Path)) { Stop-Script "The file $Path was not found." }
    $full = (Resolve-Path -LiteralPath $Path).Path

    # An Office document is a ZIP package. A file encrypted by its label is an OLE container instead.
    $head = [byte[]]::new(4)
    $stream = [System.IO.File]::OpenRead($full)
    try { $null = $stream.Read($head, 0, 4) } finally { $stream.Dispose() }
    if ($head[0] -eq 0xD0 -and $head[1] -eq 0xCF -and $head[2] -eq 0x11 -and $head[3] -eq 0xE0) {
        Stop-Script 'The document is encrypted by its label, so its metadata can be read only with the label''s usage rights. Open it in Word to see the label.'
    }
    if (-not ($head[0] -eq 0x50 -and $head[1] -eq 0x4B)) { Stop-Script "$full is not a Word document (.docx)." }

    $labels = [ordered]@{}
    function Get-LabelEntry([string]$Id) {
        $key = $Id.Trim('{', '}').ToLowerInvariant()
        if (-not $labels.Contains($key)) {
            $labels[$key] = [ordered]@{ 'Label ID' = $key; Name = ''; Enabled = ''; Method = ''; 'Set on' = ''; 'Tenant (site) ID' = ''; Source = [System.Collections.Generic.List[string]]::new() }
        }
        return $labels[$key]
    }

    $zip = [System.IO.Compression.ZipFile]::OpenRead($full)
    try {
        $custom = $zip.GetEntry('docProps/custom.xml')
        if ($custom) {
            [xml]$xml = Read-ZipText $zip $custom
            foreach ($property in @($xml.Properties.property)) {
                if ($property.name -match '^MSIP_Label_([0-9a-fA-F-]{36})_(\w+)$') {
                    $entry = Get-LabelEntry $Matches[1]
                    $value = $property.InnerText
                    switch ($Matches[2]) {
                        'Enabled' { $entry.Enabled = $value }
                        'Method' { $entry.Method = $value }
                        'SetDate' { $entry.'Set on' = $value }
                        'SiteId' { $entry.'Tenant (site) ID' = $value.Trim('{', '}') }
                        'Name' { $entry.Name = $value }
                    }
                    if (-not $entry.Source.Contains('custom properties')) { $entry.Source.Add('custom properties') }
                }
            }
        }
        foreach ($info in @($zip.Entries | Where-Object { $_.FullName -match '(?i)LabelInfo\.xml$' })) {
            [xml]$xml = Read-ZipText $zip $info
            foreach ($node in @($xml.SelectNodes("//*[local-name()='label']"))) {
                $id = $node.GetAttribute('id')
                if (-not $id) { continue }
                $entry = Get-LabelEntry $id
                if ($node.GetAttribute('enabled')) { $entry.Enabled = if ($node.GetAttribute('enabled') -in '1', 'true') { 'true' } else { 'false' } }
                if ($node.GetAttribute('method')) { $entry.Method = $node.GetAttribute('method') }
                if ($node.GetAttribute('siteId')) { $entry.'Tenant (site) ID' = $node.GetAttribute('siteId').Trim('{', '}') }
                if ($node.GetAttribute('removed') -in '1', 'true') { $entry.Enabled = 'false (removed)' }
                if (-not $entry.Source.Contains('LabelInfo.xml')) { $entry.Source.Add('LabelInfo.xml') }
            }
        }
    }
    finally { $zip.Dispose() }

    if (-not $labels.Count) {
        Write-Host 'The document carries no sensitivity label metadata.' -ForegroundColor Yellow
        Write-Host 'If you expected a label: labels can take up to 24 hours to reach a new tenant, and a label applied after you downloaded the file is not in your copy.'
        exit 0
    }

    $settings = $null
    if (Test-Path -LiteralPath $SettingsPath) { try { $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json } catch { $settings = $null } }
    $labId = if ($settings -and $settings.SensitivityLabelId) { ([string]$settings.SensitivityLabelId).Trim('{', '}').ToLowerInvariant() } else { '' }

    foreach ($entry in $labels.Values) {
        $row = [pscustomobject]$entry
        $row.Source = $entry.Source -join ' and '
        $row | Format-List | Out-String | Write-Host
        $isLab = $labId -and $entry.'Label ID' -eq $labId
        $enabled = $entry.Enabled -eq 'true'
        if ($isLab -and $enabled) {
            $labelName = if ($settings.SensitivityLabelName) { "'$($settings.SensitivityLabelName)' " } else { '' }
            Write-Host "This document carries your lab's label $labelName($labId)." -ForegroundColor Green
            Write-Host 'The Service Desk MCP server refuses to return a document with this label, and the agent reports CONTENT_BLOCKED_BY_LABEL instead of its content.'
        }
        elseif ($isLab) { Write-Host "This is your lab's label ID, but it is not enabled on the document ($($entry.Enabled))." -ForegroundColor Yellow }
        elseif ($labId) { Write-Host "This label is not the one your lab protects ($labId)." -ForegroundColor Yellow }
        if ($settings -and $settings.TenantId -and $entry.'Tenant (site) ID' -and $entry.'Tenant (site) ID' -ne $settings.TenantId) {
            Write-Host "The label was applied in another tenant ($($entry.'Tenant (site) ID')). Label IDs are tenant specific, so your tenant's policies don't apply to it." -ForegroundColor Yellow
        }
    }
    Write-Host ''
    Write-Host 'See the label in the Microsoft Purview portal (https://purview.microsoft.com): Solutions > Information Protection > Sensitivity labels.'
}
catch {
    Write-Verbose ($_ | Out-String)
    Stop-Script $_.Exception.Message
}
