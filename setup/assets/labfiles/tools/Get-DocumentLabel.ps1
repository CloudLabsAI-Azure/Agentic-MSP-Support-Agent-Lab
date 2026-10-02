#Requires -Version 7.0
<#
.SYNOPSIS
    Shows the Microsoft Purview sensitivity label recorded in a Word document.

.DESCRIPTION
    Office records the label it applies in the document's custom properties
    (docProps/custom.xml, MSIP_Label_<label ID>_*), so the label travels with the file. This
    script reads those properties without opening the document, so it works without Word.
    The MCP server reads the same properties before it returns a document to the agent.

.EXAMPLE
    C:\LabFiles\tools\Get-DocumentLabel.ps1 -Path "$HOME\Downloads\Woodgrove-Bank-Secure-Gateway-configuration.docx"
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $Path))
try {
    $entry = $zip.GetEntry('docProps/custom.xml')
    if (-not $entry) { Write-Host 'The document has no custom properties, so no sensitivity label.' -ForegroundColor Yellow; return }
    $reader = [System.IO.StreamReader]::new($entry.Open())
    try { [xml]$custom = $reader.ReadToEnd() } finally { $reader.Dispose() }
}
finally { $zip.Dispose() }

$labels = @{}
foreach ($property in $custom.Properties.property) {
    if ($property.name -match '^MSIP_Label_([0-9a-fA-F-]{36})_(\w+)$') {
        if (-not $labels[$Matches[1]]) { $labels[$Matches[1]] = [ordered]@{ 'Label ID' = $Matches[1] } }
        $labels[$Matches[1]][$Matches[2]] = $property.InnerText
    }
}
if (-not $labels.Count) { Write-Host 'The document carries no sensitivity label.' -ForegroundColor Yellow; return }
foreach ($label in $labels.Values) { [pscustomobject]$label | Format-List 'Label ID', Name, Enabled, Method, SetDate, SiteId }
