<#
.SYNOPSIS
    Turns a raw capture into a CloudLabs-style lab screenshot: blur, crop, red boxes, numbered
    badges and a border.

.DESCRIPTION
    Reads a JSON spec and writes one PNG. All rectangles in the spec are in pixels of the SOURCE
    capture (x, y, width, height), so they can be read straight off the raw image; the script
    shifts and scales them after cropping.

      {
        "source": "C:/captures/raw-0007.png",
        "out":    "Instructions/media/E1T3S7.png",
        "crop":   [0, 120, 1400, 760],
        "scale":  1.0,
        "blur":   [[640, 300, 420, 28]],
        "boxes":  [ { "rect": [40, 330, 260, 44], "n": 1 },
                    { "rect": [40, 520, 300, 40], "n": 2, "badge": "right" } ]
      }

    The CloudLabs house style (Lab Builder v2.3):
      - Boxes: RGB 252, 66, 66, around only the element the step acts on (the link, the radio
        button and its label, the button), never a whole panel. "rect" is that element's tight
        bounds; the script adds an even margin on all four sides (4 px at the reference
        width, "pad" overrides it per box) so the line never touches or cuts text or a button
        edge, and keeps the box inside the image.
      - Badges: a 30 px filled circle in the same red with a white bold number, centered on a
        corner of its box, diagonally outside it so it only touches the corner (top-right unless that covers content). By default the script picks the side that covers the least content and no other box
        or badge; "badge": tr, tl, br, bl, right or left forces one. Numbers match the step's
        (1), (2) markers; a box without "n" has no badge.
      - Snap: each side of a box moves outward until its line crosses only background, so a
        rough rectangle never cuts text, an icon or a control edge ("snap": false turns it off).
      - Equal size on the page: the guide shows every screenshot at most about 1000 px wide, so
        wider images are shrunk. Line width, margin, badge diameter and numeral scale with
        max(1, width / 1000), so every badge and box line looks the same size in the guide.
      - Blur: a smooth blur (downscale and upscale) over user names, passes, keys, tenant and
        subscription IDs and anything else that identifies a tenant.
      - Border: 2 px, RGB 90, 90, 90, around the whole image.

.PARAMETER Spec
    Path to the JSON spec.

.PARAMETER Strict
    Fail (exit 1) when any check fires: a box edge that crosses content, two boxes or badges that
    touch or overlap, or a badge that covers content. Use it for every screenshot that ships.

.EXAMPLE
    pwsh tools/screenshots/Annotate-Screenshot.ps1 -Spec captures/E1T3S7.json
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Spec, [switch]$Strict)

# Every layout problem is reported; with -Strict the run fails so the screenshot is fixed, not published.
$script:Issues = 0
function Report-Issue([string]$m) { $script:Issues++; Write-Warning $m }

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# Pixel scans for box snapping and badge placement (C# so they stay fast on large captures).
Add-Type -TypeDefinition @"
using System;
public static class LabInk {
    public static byte[] Px; public static int W, H, Stride;
    static int Diff(int i, int r, int g, int b) {
        return Math.Abs(Px[i + 2] - r) + Math.Abs(Px[i + 1] - g) + Math.Abs(Px[i] - b);
    }
    static double Ink(int x0, int y0, int x1, int y1) {
        x0 = Math.Max(0, x0); y0 = Math.Max(0, y0); x1 = Math.Min(W - 1, x1); y1 = Math.Min(H - 1, y1);
        if (x1 < x0 || y1 < y0) return 1.0;
        int n = 0; long r = 0, g = 0, b = 0;
        for (int y = y0; y <= y1; y++) for (int x = x0; x <= x1; x++) { int i = y * Stride + x * 4; r += Px[i + 2]; g += Px[i + 1]; b += Px[i]; n++; }
        int mr = (int)(r / n), mg = (int)(g / n), mb = (int)(b / n), ink = 0;
        for (int y = y0; y <= y1; y++) for (int x = x0; x <= x1; x++) if (Diff(y * Stride + x * 4, mr, mg, mb) > 60) ink++;
        return (double)ink / n;
    }
    // True when a pen band crosses ink (text, icons, control edges) instead of plain background.
    public static bool LineHasInk(int x0, int y0, int x1, int y1) { return Ink(x0, y0, x1, y1) > 0; }
    // Share of pixels in a square that differ from the square's average color.
    public static double Busy(int x0, int y0, int size) { return Ink(x0, y0, x0 + size - 1, y0 + size - 1); }
}
"@

$s = Get-Content -Raw -LiteralPath $Spec | ConvertFrom-Json
$red = [System.Drawing.Color]::FromArgb(252, 66, 66)
$borderColor = [System.Drawing.Color]::FromArgb(90, 90, 90)

$raw = [System.Drawing.Bitmap]::FromFile((Resolve-Path $s.source).Path)
$src = New-Object System.Drawing.Bitmap($raw)
$raw.Dispose()

# ==== 1. Blur, in source coordinates, before anything is drawn on top.
foreach ($r in @($s.blur)) {
    if (-not $r) { continue }
    $rect = New-Object System.Drawing.Rectangle([int]$r[0], [int]$r[1], [int]$r[2], [int]$r[3])
    $rect.Intersect((New-Object System.Drawing.Rectangle(0, 0, $src.Width, $src.Height)))
    if ($rect.Width -lt 2 -or $rect.Height -lt 2) { continue }
    # A 24 bpp (no alpha) thumbnail and mirrored edges keep the blur fully opaque, even on
    # short strips such as one line of text.
    $tw = [Math]::Max(3, [int]($rect.Width / 12))
    $th = [Math]::Max(2, [int]($rect.Height / 12))
    $small = New-Object System.Drawing.Bitmap($tw, $th, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $attr = New-Object System.Drawing.Imaging.ImageAttributes
    $attr.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
    $gs = [System.Drawing.Graphics]::FromImage($small)
    $gs.InterpolationMode = 'HighQualityBilinear'
    $gs.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $tw, $th)), $rect.X, $rect.Y, $rect.Width, $rect.Height, [System.Drawing.GraphicsUnit]::Pixel, $attr)
    $gs.Dispose()
    $g = [System.Drawing.Graphics]::FromImage($src)
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.CompositingMode = 'SourceCopy'
    $g.DrawImage($small, $rect, 0, 0, $tw, $th, [System.Drawing.GraphicsUnit]::Pixel, $attr)
    $g.Dispose()
    $small.Dispose()
    $attr.Dispose()
}

# ==== 2. Crop and scale.
$crop = if ($s.crop) { @([int]$s.crop[0], [int]$s.crop[1], [int]$s.crop[2], [int]$s.crop[3]) } else { @(0, 0, $src.Width, $src.Height) }
$scale = if ($s.scale) { [double]$s.scale } else { 1.0 }
$w = [int][Math]::Round($crop[2] * $scale)
$h = [int][Math]::Round($crop[3] * $scale)
$img = New-Object System.Drawing.Bitmap($w, $h)
$g = [System.Drawing.Graphics]::FromImage($img)
$g.InterpolationMode = 'HighQualityBicubic'
$g.PixelOffsetMode = 'HighQuality'
$g.DrawImage($src, (New-Object System.Drawing.Rectangle(0, 0, $w, $h)), (New-Object System.Drawing.Rectangle($crop[0], $crop[1], $crop[2], $crop[3])), 'Pixel')
$src.Dispose()
$bits = $img.LockBits((New-Object System.Drawing.Rectangle(0, 0, $w, $h)), 'ReadOnly', [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
[LabInk]::Stride = $bits.Stride; [LabInk]::W = $w; [LabInk]::H = $h
[LabInk]::Px = New-Object byte[] ($bits.Stride * $h)
[System.Runtime.InteropServices.Marshal]::Copy($bits.Scan0, [LabInk]::Px, 0, [LabInk]::Px.Length)
$img.UnlockBits($bits)

# ==== 3. Boxes and numbered badges, scaled so they look the same size in the guide.
$k = [Math]::Max(1.0, $w / 1000.0)
$g.SmoothingMode = 'AntiAlias'
$g.TextRenderingHint = 'AntiAliasGridFit'
$penW = [Math]::Max(2, [int][Math]::Round(2 * $k))
$pen = New-Object System.Drawing.Pen($red, $penW)
$pen.Alignment = 'Inset'
$brush = New-Object System.Drawing.SolidBrush($red)
$white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
$d = [Math]::Round(30 * $k)
$font = New-Object System.Drawing.Font('Segoe UI', [float](17 * $k), [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$fmt = New-Object System.Drawing.StringFormat
$fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
$o = 0.3 * $d   # corner badge: center this far out on both axes, so the circle just touches the corner
$placed = New-Object System.Collections.ArrayList   # boxes and badges already drawn
foreach ($b in @($s.boxes)) {
    if (-not $b) { continue }
    $pad = if ($null -ne $b.pad) { [double]$b.pad * $scale } else { 4 * $k }
    $l = ([double]$b.rect[0] - $crop[0]) * $scale - $pad
    $t = ([double]$b.rect[1] - $crop[1]) * $scale - $pad
    $r = $l + [double]$b.rect[2] * $scale + 2 * $pad
    $bt = $t + [double]$b.rect[3] * $scale + 2 * $pad
    # Snap: push each side outward until its pen band crosses only background, so the line never
    # cuts text, an icon or a control edge ("snap": false keeps the rectangle as given).
    if ($b.snap -ne $false) {
        # Sides may travel the length of a text line; top and bottom only a few pixels, so a box
        # never swallows the row above or below. If moving out fails, try moving in instead.
        $limV = [int](16 * $k); $limH = [int](60 * $k)
        $ok = $false; $v = $l
        for ($i = 0; $i -le $limH; $i++) { if (-not [LabInk]::LineHasInk([int]($l - $i) - $penW, [int]$t, [int]($l - $i), [int]$bt)) { $v = $l - $i; $ok = $true; break } }
        if (-not $ok) { for ($i = 1; $i -le $limV; $i++) { if (-not [LabInk]::LineHasInk([int]($l + $i) - $penW, [int]$t, [int]($l + $i), [int]$bt)) { $v = $l + $i; break } } }
        if (-not $ok) { Report-Issue "$($s.out): box $($b.n) left edge crosses content; widen its rect" }
        $l = $v
        $ok = $false; $v = $r
        for ($i = 0; $i -le $limH; $i++) { if (-not [LabInk]::LineHasInk([int]($r + $i), [int]$t, [int]($r + $i) + $penW, [int]$bt)) { $v = $r + $i; $ok = $true; break } }
        if (-not $ok) { for ($i = 1; $i -le $limV; $i++) { if (-not [LabInk]::LineHasInk([int]($r - $i), [int]$t, [int]($r - $i) + $penW, [int]$bt)) { $v = $r - $i; break } } }
        if (-not $ok) { Report-Issue "$($s.out): box $($b.n) right edge crosses content; widen its rect" }
        $r = $v
        # Top and bottom: the nearest clean line, in or out, so the box hugs its own row.
        $v = $t
        for ($i = 0; $i -le $limV; $i++) {
            if (-not [LabInk]::LineHasInk([int]$l, [int]($t - $i) - $penW, [int]$r, [int]($t - $i))) { $v = $t - $i; break }
            if ($i -gt 0 -and -not [LabInk]::LineHasInk([int]$l, [int]($t + $i) - $penW, [int]$r, [int]($t + $i))) { $v = $t + $i; break }
        }
        $t = $v
        $v = $bt
        for ($i = 0; $i -le $limV; $i++) {
            if (-not [LabInk]::LineHasInk([int]$l, [int]($bt + $i), [int]$r, [int]($bt + $i) + $penW)) { $v = $bt + $i; break }
            if ($i -gt 0 -and -not [LabInk]::LineHasInk([int]$l, [int]($bt - $i), [int]$r, [int]($bt - $i) + $penW)) { $v = $bt - $i; break }
        }
        $bt = $v
    }
    $x = [Math]::Max($l - $penW, 3); $y = [Math]::Max($t - $penW, 3)
    $bw = [Math]::Min($r + $penW, $w - 3) - $x; $bh = [Math]::Min($bt + $penW, $h - 3) - $y
    $g.SmoothingMode = 'None'
    $g.DrawRectangle($pen, [int][Math]::Round($x), [int][Math]::Round($y), [int][Math]::Round($bw), [int][Math]::Round($bh))
    $g.SmoothingMode = 'AntiAlias'
    # Two boxes must never touch, cross or share a line: keep a clear gap and report it.
    foreach ($q in $placed) {
        $gap = 4 * $k
        if ($x - $gap -lt $q[2] -and $x + $bw + $gap -gt $q[0] -and $y - $gap -lt $q[3] -and $y + $bh + $gap -gt $q[1]) {
            Report-Issue "$($s.out): box $($b.n) touches or overlaps another box or badge; tighten its rect"
        }
    }
    $placed.Add(@($x, $y, ($x + $bw), ($y + $bh))) | Out-Null
    if ($null -eq $b.n) { continue }
    # Badge position: the one given, or ("badge" omitted or "auto") the candidate that covers the
    # least content and no other box or badge.
    $cands = [ordered]@{
        # Corner badges sit diagonally outside the corner and just touch it, so they never reach
        # into the box or over the control's text.
        'tr' = @(($x + $bw + $o), ($y - $o)); 'tl' = @(($x - $o), ($y - $o))
        'br' = @(($x + $bw + $o), ($y + $bh + $o)); 'bl' = @(($x - $o), ($y + $bh + $o))
        'right' = @(($x + $bw + $d / 2 + 4 * $k), ($y + $bh / 2)); 'left' = @(($x - $d / 2 - 4 * $k), ($y + $bh / 2))
    }
    $pos = if ($b.badge -and $b.badge -ne 'auto') { [string]$b.badge } else { $null }
    if (-not $pos) {
        # Slide along the outside of the box (top edge and right edge first, then bottom and left)
        # and take the clear spot nearest the top-right corner.
        $sg = 3 * $k; $step = [Math]::Max(4, [int](6 * $k)); $i = 0
        $out = $d / 2 + $sg
        for ($t2 = 0; $t2 -le $bw + $bh; $t2 += $step) {
            if ($t2 -le $bw) { $cands["s$i"] = @(($x + $bw - $t2), ($y - $out)) } else { $cands["s$i"] = @(($x - $out), ($y + $t2 - $bw)) }
            $i++
            if ($t2 -le $bh) { $cands["s$i"] = @(($x + $bw + $out), ($y + $t2)) } else { $cands["s$i"] = @(($x + $bw - ($t2 - $bh)), ($y + $bh + $out)) }
            $i++
        }
        $best = [double]::MaxValue; $n0 = 0
        foreach ($c in $cands.Keys) {
            $px = $cands[$c][0]; $py = $cands[$c][1]
            $cost = 4 * [LabInk]::Busy([int]($px - $d / 2), [int]($py - $d / 2), [int]$d)
            if ($px - $d / 2 -lt 3 -or $py - $d / 2 -lt 3 -or $px + $d / 2 -gt $w - 3 -or $py + $d / 2 -gt $h - 3) { $cost += 2 }
            foreach ($q in ($placed | Select-Object -SkipLast 1)) {
                if ($px + $d / 2 -gt $q[0] -and $px - $d / 2 -lt $q[2] -and $py + $d / 2 -gt $q[1] -and $py - $d / 2 -lt $q[3]) { $cost += 1 }
            }
            # Prefer the top-right corner, then the nearest point to it.
            $cost += [Math]::Sqrt([Math]::Pow($px - ($x + $bw + $o), 2) + [Math]::Pow($py - ($y - $o), 2)) / (20 * $d)
            if ($cost -lt $best) { $best = $cost; $pos = $c }
        }
    }
    $cx = $cands[$pos][0]; $cy = $cands[$pos][1]
    if ([LabInk]::Busy([int]($cx - $d / 2), [int]($cy - $d / 2), [int]$d) -gt 0.02) {
        Report-Issue "$($s.out): badge $($b.n) covers content at '$pos'; set ""badge"" or adjust the rect"
    }
    # Keep the whole badge inside the image.
    $cx = [Math]::Min([Math]::Max($cx, $d / 2 + 3), $w - $d / 2 - 3)
    $cy = [Math]::Min([Math]::Max($cy, $d / 2 + 3), $h - $d / 2 - 3)
    $placed.Add(@(($cx - $d / 2), ($cy - $d / 2), ($cx + $d / 2), ($cy + $d / 2))) | Out-Null
    $g.FillEllipse($brush, [float]($cx - $d / 2), [float]($cy - $d / 2), [float]$d, [float]$d)
    $g.DrawString([string]$b.n, $font, $white, (New-Object System.Drawing.RectangleF([float]($cx - $d / 2), [float]($cy - $d / 2 + $k), [float]$d, [float]$d)), $fmt)
}

# ==== 4. Border: solid strips, so no pixel offset can push it off the image.
$g.SmoothingMode = 'None'
$g.PixelOffsetMode = 'None'
$bw = 2
$borderBrush = New-Object System.Drawing.SolidBrush($borderColor)
$g.FillRectangle($borderBrush, 0, 0, $w, $bw)
$g.FillRectangle($borderBrush, 0, $h - $bw, $w, $bw)
$g.FillRectangle($borderBrush, 0, 0, $bw, $h)
$g.FillRectangle($borderBrush, $w - $bw, 0, $bw, $h)
$g.Dispose()

$out = $s.out
$outDir = Split-Path -Parent $out
if ($outDir) { New-Item -ItemType Directory -Force -Path $outDir | Out-Null }
$out = [System.IO.Path]::GetFullPath($out)
$img.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$img.Dispose()
"Wrote $out ($w x $h)"
if ($script:Issues -gt 0) {
    Write-Warning "$($script:Issues) layout issue(s) in $out"
    if ($Strict) { exit 1 }
}
