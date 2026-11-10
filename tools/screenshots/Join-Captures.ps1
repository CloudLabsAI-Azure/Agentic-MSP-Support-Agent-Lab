<#
.SYNOPSIS
    Joins two or more captures side by side (or top to bottom) into one PNG at full resolution.

.DESCRIPTION
    Browser region captures are capped at about 1,568 pixels wide, so a full-width portal page
    loses sharpness when it is captured in one piece. Capture it in halves instead (for example
    the left and right half of the same band of the screen) and join them here; then annotate the
    joined image with Annotate-Screenshot.ps1.

.EXAMPLE
    pwsh tools/screenshots/Join-Captures.ps1 -Path left.png, right.png -Out joined.png
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Path,
    [Parameter(Mandatory)][string]$Out,
    [switch]$Vertical
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$Path = @($Path | ForEach-Object { $_ -split "," } | Where-Object { $_ })
$parts = @($Path | ForEach-Object { [System.Drawing.Bitmap]::FromFile((Resolve-Path $_).Path) })
if ($Vertical) {
    $w = ($parts | Measure-Object Width -Maximum).Maximum
    $h = ($parts | Measure-Object Height -Sum).Sum
} else {
    $w = ($parts | Measure-Object Width -Sum).Sum
    $h = ($parts | Measure-Object Height -Maximum).Maximum
}
$img = New-Object System.Drawing.Bitmap([int]$w, [int]$h)
$g = [System.Drawing.Graphics]::FromImage($img)
$g.Clear([System.Drawing.Color]::White)
$offset = 0
foreach ($p in $parts) {
    if ($Vertical) { $g.DrawImage($p, 0, $offset, $p.Width, $p.Height); $offset += $p.Height }
    else { $g.DrawImage($p, $offset, 0, $p.Width, $p.Height); $offset += $p.Width }
    $p.Dispose()
}
$g.Dispose()
$img.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
$img.Dispose()
"Wrote $Out ($w x $h)"
