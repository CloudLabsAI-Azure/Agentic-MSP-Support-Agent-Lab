#requires -Version 7.2

<#
.SYNOPSIS
Renders the animated SVG diagrams in a media folder to verified animated PNG (APNG) files.

.DESCRIPTION
Lab guide pages embed a PNG render of each diagram, because not every renderer serves SVG as an
image (some show it as text). The SVG beside it stays the editable source, and the repository
README embeds the SVG files themselves, which GitHub animates.

How it works:
  1. The loop length and frame rate come from two attributes on the svg root, which svgkit.py
     writes: data-loop-seconds and data-frames-per-second. Frames = loop seconds x frames per
     second (10 s at 12 fps = 120 frames). Every animation period in the file should divide the
     loop so the loop is seamless.
  2. Each frame is a screenshot of the SVG paused at its time in headless Microsoft Edge (or
     Chrome). Several frames share one browser launch: copies of the SVG are stacked on one page,
     each paused at its own time, and the screenshot is sliced, which is about ten times faster
     than one launch per frame. Every copy gets its own element ids, so references such as the
     typing terminal's clip path follow that copy's clock. Frames are sampled from the second
     loop, so animations with a delayed start are already under way.
  3. The frames are packed into one animated PNG next to the source: the first frame in full,
     then for each later frame only the rectangle of pixels that changed by more than the
     tolerance, blended over the previous frame. Browsers play the animation; viewers without
     APNG support show the first frame.
  4. The file is decoded again and every frame is compared with its screenshot. The run fails
     unless every pixel of every frame is within the tolerance.

Why there is a tolerance: Edge rasterizes identical static content with differences of 1 to 3
levels per color channel between frames rendered in one batch, mostly in gradients, shadows and
the dotted background. Without a tolerance that noise is encoded as change in every frame, and a
diagram that should be about 1 to 2 MB grows to 5 to 13 MB. The encoder compares each new frame
with the canvas the viewer is already showing (not with the previous screenshot), so the error of
every pixel stays within the tolerance for the whole loop instead of accumulating. The default of
4 levels is invisible.

Size budget: aim for under 2.5 MB per PNG. The script warns above that; README.md in this folder
lists ways to shrink a diagram.

.PARAMETER Path
Folder that holds the SVG sources and receives the PNG renders. Default: Instructions/media in
the lab repository, resolved from this script's place in tools/diagrams/ (..\..\Instructions\media).

.PARAMETER Name
Base names to render, without extension. Default: every .svg in the folder that carries the two
timing attributes (other SVG files are skipped with a warning).

.PARAMETER Scale
Device scale factor for the screenshots. 1.2 gives 1440 x 810 for a 1200 x 675 diagram, which
keeps text crisp at the width a lab guide shows and keeps files small. Height x scale must be a
whole number for frames to be batched; otherwise each frame gets its own browser launch.

.PARAMETER Batch
Frames rendered per browser launch (1 to 24). 12 is fast and reliable.

.PARAMETER Tolerance
Largest per-channel color difference, out of 255, that still counts as unchanged (0 to 16).
The default of 4 is invisible and is what the verification checks. Use 0 for an exact encoding.

.PARAMETER EdgePath
Path to msedge.exe or chrome.exe (or the Edge or Chrome binary on macOS and Linux).
Default: the standard install locations.

.PARAMETER Snapshot
Times in seconds (inside one loop) to capture as still PNG files for review, instead of rendering
the animation. Use it to check a frame for overlaps, clipping or legibility. From PowerShell write
-Snapshot 0, 2.5; from another shell quote the list: -Snapshot "0,2.5". -Name accepts lists the
same way.

.PARAMETER SnapshotPath
Folder for the stills. Default: diagram-snapshots in the system temp folder, never the media
folder, so review images are not committed by accident.

.EXAMPLE
pwsh tools/diagrams/Render-Diagrams.ps1
Renders every diagram in Instructions/media.

.EXAMPLE
pwsh tools/diagrams/Render-Diagrams.ps1 -Name architecture
Renders one diagram. Run up to three of these in parallel, one -Name each, to save time.

.EXAMPLE
pwsh tools/diagrams/Render-Diagrams.ps1 -Name architecture -Snapshot 0, 2.5, 7.5
Writes three stills of the architecture diagram to the snapshot folder and prints their paths.
#>
[CmdletBinding()]
param(
    [string]$Path = (Join-Path $PSScriptRoot '..' '..' 'Instructions' 'media'),
    [string[]]$Name,
    [ValidateRange(0.25, 4.0)][double]$Scale = 1.2,
    [ValidateRange(1, 24)][int]$Batch = 12,
    [ValidateRange(0, 16)][int]$Tolerance = 4,
    [string]$EdgePath,
    [string[]]$Snapshot,
    [string]$SnapshotPath = (Join-Path ([IO.Path]::GetTempPath()) 'diagram-snapshots')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$invariant = [Globalization.CultureInfo]::InvariantCulture
$budgetBytes = 2.5 * 1024 * 1024

# Lists also arrive as one comma-separated string when the script is started with pwsh -File
# from another shell (for example -Name "a,b" or -Snapshot "0,2.5"), so split them here.
if ($Name) { $Name = @($Name | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
$snapTimes = @()
if ($Snapshot) {
    $snapTimes = @($Snapshot | ForEach-Object { $_ -split '[,\s]+' } | Where-Object { $_ } | ForEach-Object {
            $value = 0.0
            if (-not [double]::TryParse($_, [Globalization.NumberStyles]::Float, $invariant, [ref]$value)) { throw "-Snapshot: '$_' is not a number of seconds." }
            $value
        })
}

if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    throw "No media folder at '$Path'. Pass -Path with the folder that holds the diagram SVG files (in a lab repository: Instructions/media)."
}
$assetDir = (Resolve-Path -LiteralPath $Path).Path

if (-not $EdgePath) {
    $candidates = @()
    if ($IsWindows) {
        $candidates = @(
            "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
            "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
            "$env:LOCALAPPDATA\Microsoft\Edge\Application\msedge.exe",
            "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
            "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe")
    }
    elseif ($IsMacOS) {
        $candidates = @('/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge',
            '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
    }
    else {
        $candidates = @(foreach ($cmd in 'microsoft-edge', 'microsoft-edge-stable', 'google-chrome', 'google-chrome-stable', 'chromium', 'chromium-browser') {
                Get-Command $cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
            })
    }
    $EdgePath = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $EdgePath) { throw 'Microsoft Edge or Google Chrome was not found. Pass -EdgePath.' }
}

# ==== PNG decoding, frame differencing and APNG writing, compiled once per session =============
if (-not ('LabDiagramApng' -as [type])) {
    Add-Type -ReferencedAssemblies 'System.Runtime', 'System.Collections', 'System.IO.Compression' -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Text;

public static class LabDiagramApng
{
    static readonly uint[] CrcTable = BuildCrcTable();

    static uint[] BuildCrcTable()
    {
        var t = new uint[256];
        for (uint n = 0; n < 256; n++) { uint c = n; for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1; t[n] = c; }
        return t;
    }

    static uint Crc(byte[] type, byte[] data)
    {
        uint c = 0xFFFFFFFFu;
        for (int i = 0; i < 4; i++) c = CrcTable[(c ^ type[i]) & 0xFF] ^ (c >> 8);
        for (int i = 0; i < data.Length; i++) c = CrcTable[(c ^ data[i]) & 0xFF] ^ (c >> 8);
        return c ^ 0xFFFFFFFFu;
    }

    static void WriteU32(Stream s, uint v) { s.WriteByte((byte)(v >> 24)); s.WriteByte((byte)(v >> 16)); s.WriteByte((byte)(v >> 8)); s.WriteByte((byte)v); }
    static void PutU32(byte[] b, int o, uint v) { b[o] = (byte)(v >> 24); b[o + 1] = (byte)(v >> 16); b[o + 2] = (byte)(v >> 8); b[o + 3] = (byte)v; }
    static void PutU16(byte[] b, int o, int v) { b[o] = (byte)(v >> 8); b[o + 1] = (byte)v; }
    static uint GetU32(byte[] b, int o) { return ((uint)b[o] << 24) | ((uint)b[o + 1] << 16) | ((uint)b[o + 2] << 8) | b[o + 3]; }

    static void WriteChunk(Stream s, string type, byte[] data)
    {
        var t = Encoding.ASCII.GetBytes(type);
        WriteU32(s, (uint)data.Length); s.Write(t, 0, 4); s.Write(data, 0, data.Length); WriteU32(s, Crc(t, data));
    }

    static readonly byte[] Signature = { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };

    class Chunk { public string Type; public byte[] Data; }

    static List<Chunk> ReadChunks(string path)
    {
        var bytes = File.ReadAllBytes(path);
        if (bytes.Length < 8 || bytes[0] != 0x89 || bytes[1] != 0x50) throw new Exception("Not a PNG file: " + path);
        var list = new List<Chunk>();
        int p = 8;
        while (p + 8 <= bytes.Length)
        {
            int len = (int)GetU32(bytes, p);
            string type = Encoding.ASCII.GetString(bytes, p + 4, 4);
            var data = new byte[len];
            Buffer.BlockCopy(bytes, p + 8, data, 0, len);
            list.Add(new Chunk { Type = type, Data = data });
            p += 12 + len;
            if (type == "IEND") break;
        }
        return list;
    }

    static byte[] Inflate(byte[] z)
    {
        using (var ms = new MemoryStream(z))
        using (var d = new ZLibStream(ms, CompressionMode.Decompress))
        using (var o = new MemoryStream()) { d.CopyTo(o); return o.ToArray(); }
    }

    static byte[] Deflate(byte[] raw)
    {
        using (var o = new MemoryStream())
        {
            using (var z = new ZLibStream(o, CompressionLevel.SmallestSize, true)) z.Write(raw, 0, raw.Length);
            return o.ToArray();
        }
    }

    // Reverses the per row PNG filters. Rows carry one filter byte followed by w * bpp bytes.
    static byte[] Unfilter(byte[] raw, int w, int h, int bpp)
    {
        int stride = w * bpp;
        var outp = new byte[h * stride];
        var prev = new byte[stride];
        for (int y = 0; y < h; y++)
        {
            int f = raw[y * (stride + 1)], src = y * (stride + 1) + 1, dst = y * stride;
            for (int i = 0; i < stride; i++)
            {
                int x = raw[src + i], a = i >= bpp ? outp[dst + i - bpp] : 0, b = prev[i], c = i >= bpp ? prev[i - bpp] : 0, v;
                switch (f)
                {
                    case 0: v = x; break;
                    case 1: v = x + a; break;
                    case 2: v = x + b; break;
                    case 3: v = x + ((a + b) >> 1); break;
                    case 4: { int p = a + b - c, pa = Math.Abs(p - a), pb = Math.Abs(p - b), pc = Math.Abs(p - c); v = x + ((pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)); break; }
                    default: throw new Exception("Unknown PNG filter " + f);
                }
                outp[dst + i] = (byte)v;
            }
            Buffer.BlockCopy(outp, dst, prev, 0, stride);
        }
        return outp;
    }

    // Decodes an 8 bit RGB or RGBA PNG without interlacing, which is what headless Edge and Chrome write, to RGBA.
    public static byte[] DecodePng(string path, out int w, out int h)
    {
        var chunks = ReadChunks(path);
        var ihdr = chunks[0];
        if (ihdr.Type != "IHDR") throw new Exception("IHDR missing: " + path);
        w = (int)GetU32(ihdr.Data, 0); h = (int)GetU32(ihdr.Data, 4);
        int depth = ihdr.Data[8], ctype = ihdr.Data[9], interlace = ihdr.Data[12];
        if (depth != 8 || (ctype != 2 && ctype != 6) || interlace != 0) throw new Exception("Unsupported PNG layout, need 8 bit RGB or RGBA without interlace: " + path);
        var idat = new MemoryStream();
        foreach (var c in chunks) if (c.Type == "IDAT") idat.Write(c.Data, 0, c.Data.Length);
        int bpp = ctype == 6 ? 4 : 3;
        var px = Unfilter(Inflate(idat.ToArray()), w, h, bpp);
        if (bpp == 4) return px;
        var rgba = new byte[w * h * 4];
        for (int i = 0, j = 0; i < px.Length; i += 3, j += 4) { rgba[j] = px[i]; rgba[j + 1] = px[i + 1]; rgba[j + 2] = px[i + 2]; rgba[j + 3] = 255; }
        return rgba;
    }

    // Picks the filter with the smallest absolute sum per row, as the PNG specification suggests, then compresses the rows.
    static byte[] CompressRegion(byte[] rgba, int imgW, int x0, int y0, int rw, int rh)
    {
        const int bpp = 4;
        int stride = rw * bpp;
        var raw = new byte[rh * (stride + 1)];
        var prev = new byte[stride];
        var cur = new byte[stride];
        var cand = new byte[5][];
        for (int f = 0; f < 5; f++) cand[f] = new byte[stride];
        for (int y = 0; y < rh; y++)
        {
            Buffer.BlockCopy(rgba, ((y0 + y) * imgW + x0) * bpp, cur, 0, stride);
            int best = 0;
            long bestSum = long.MaxValue;
            for (int f = 0; f < 5; f++)
            {
                long sum = 0;
                var o = cand[f];
                for (int i = 0; i < stride; i++)
                {
                    int a = i >= bpp ? cur[i - bpp] : 0, b = prev[i], c = i >= bpp ? prev[i - bpp] : 0, v = cur[i], p;
                    switch (f)
                    {
                        case 0: p = 0; break;
                        case 1: p = a; break;
                        case 2: p = b; break;
                        case 3: p = (a + b) >> 1; break;
                        default: { int pp = a + b - c, pa = Math.Abs(pp - a), pb = Math.Abs(pp - b), pc = Math.Abs(pp - c); p = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c); break; }
                    }
                    byte e = (byte)(v - p);
                    o[i] = e;
                    sum += e < 128 ? e : 256 - e;
                }
                if (sum < bestSum) { bestSum = sum; best = f; }
            }
            raw[y * (stride + 1)] = (byte)best;
            Buffer.BlockCopy(cand[best], 0, raw, y * (stride + 1) + 1, stride);
            Buffer.BlockCopy(cur, 0, prev, 0, stride);
        }
        return Deflate(raw);
    }

    class Region { public int X, Y, W, H, Delay; public byte[] Zlib; }

    // The frames in order. Each batch screenshot holds `count` frames stacked from top to bottom;
    // only one batch is decoded at a time, so memory stays small however long the loop is.
    static IEnumerable<byte[]> Frames(string[] batches, int[] counts, int fw, int fh)
    {
        int frameBytes = fw * fh * 4;
        for (int b = 0; b < batches.Length; b++)
        {
            int w, h;
            var px = DecodePng(batches[b], out w, out h);
            if (w != fw || h != fh * counts[b])
                throw new Exception(string.Format(CultureInfo.InvariantCulture, "Screenshot {0} is {1}x{2}, expected {3}x{4}", batches[b], w, h, fw, fh * counts[b]));
            for (int k = 0; k < counts[b]; k++)
            {
                var f = new byte[frameBytes];
                Buffer.BlockCopy(px, k * frameBytes, f, 0, frameBytes);
                yield return f;
            }
        }
    }

    // True when any color channel differs by more than the tolerance, or the alpha differs at all.
    static bool Exceeds(byte[] a, byte[] b, int o, int t)
    {
        return Math.Abs(a[o] - b[o]) > t || Math.Abs(a[o + 1] - b[o + 1]) > t || Math.Abs(a[o + 2] - b[o + 2]) > t || a[o + 3] != b[o + 3];
    }

    // Writes the animated PNG: the first frame in full, then one region per frame holding only the pixels that
    // moved further than the tolerance from what the viewer already shows. Comparing against the displayed
    // canvas, not the previous screenshot, keeps the error of every pixel within the tolerance for the whole loop.
    public static string Build(string[] batches, int[] counts, int fw, int fh, int fps, string outPath, int tolerance)
    {
        var regions = new List<Region>();
        byte[] canvas = null;
        int frameCount = 0;
        foreach (var b in Frames(batches, counts, fw, fh))
        {
            frameCount++;
            if (canvas == null)
            {
                canvas = (byte[])b.Clone();
                regions.Add(new Region { X = 0, Y = 0, W = fw, H = fh, Delay = 1, Zlib = CompressRegion(b, fw, 0, 0, fw, fh) });
                continue;
            }
            int minX = fw, minY = fh, maxX = -1, maxY = -1;
            for (int y = 0; y < fh; y++)
                for (int x = 0; x < fw; x++)
                    if (Exceeds(canvas, b, (y * fw + x) * 4, tolerance)) { if (x < minX) minX = x; if (x > maxX) maxX = x; if (y < minY) minY = y; if (y > maxY) maxY = y; }
            if (maxX < 0) { regions[regions.Count - 1].Delay++; continue; }
            int rw = maxX - minX + 1, rh = maxY - minY + 1;
            var reg = new byte[rw * rh * 4];
            for (int y = 0; y < rh; y++)
                for (int x = 0; x < rw; x++)
                {
                    int o = ((minY + y) * fw + minX + x) * 4, d = (y * rw + x) * 4;
                    if (!Exceeds(canvas, b, o, tolerance)) continue;
                    if (b[o + 3] != 255) throw new Exception("Frame " + frameCount + " has a translucent pixel; render on an opaque background.");
                    reg[d] = b[o]; reg[d + 1] = b[o + 1]; reg[d + 2] = b[o + 2]; reg[d + 3] = 255;
                    canvas[o] = b[o]; canvas[o + 1] = b[o + 1]; canvas[o + 2] = b[o + 2]; canvas[o + 3] = 255;
                }
            regions.Add(new Region { X = minX, Y = minY, W = rw, H = rh, Delay = 1, Zlib = CompressRegion(reg, rw, 0, 0, rw, rh) });
        }
        if (canvas == null) throw new Exception("No frames to encode.");
        using (var s = new FileStream(outPath, FileMode.Create))
        {
            s.Write(Signature, 0, 8);
            var ihdr = new byte[13];
            PutU32(ihdr, 0, (uint)fw); PutU32(ihdr, 4, (uint)fh); ihdr[8] = 8; ihdr[9] = 6;
            WriteChunk(s, "IHDR", ihdr);
            var actl = new byte[8];
            PutU32(actl, 0, (uint)regions.Count);
            WriteChunk(s, "acTL", actl);
            uint seq = 0;
            for (int k = 0; k < regions.Count; k++)
            {
                var r = regions[k];
                var fctl = new byte[26];
                PutU32(fctl, 0, seq++); PutU32(fctl, 4, (uint)r.W); PutU32(fctl, 8, (uint)r.H); PutU32(fctl, 12, (uint)r.X); PutU32(fctl, 16, (uint)r.Y);
                PutU16(fctl, 20, r.Delay); PutU16(fctl, 22, fps);
                fctl[24] = 0;
                fctl[25] = (byte)(k == 0 ? 0 : 1);
                WriteChunk(s, "fcTL", fctl);
                if (k == 0) WriteChunk(s, "IDAT", r.Zlib);
                else
                {
                    var fdat = new byte[4 + r.Zlib.Length];
                    PutU32(fdat, 0, seq++);
                    Buffer.BlockCopy(r.Zlib, 0, fdat, 4, r.Zlib.Length);
                    WriteChunk(s, "fdAT", fdat);
                }
            }
            WriteChunk(s, "IEND", new byte[0]);
        }
        long size = new FileInfo(outPath).Length;
        return string.Format(CultureInfo.InvariantCulture, "{0} frames in {1} regions, {2:#,0} bytes ({3:0.00} MB)",
            frameCount, regions.Count, size, size / 1048576.0);
    }

    // Decodes the animated PNG again and compares every frame with the screenshot it came from. A pixel counts as
    // mismatched when it is further from the screenshot than the tolerance the file was built with.
    public static string Verify(string apngPath, string[] batches, int[] counts, int fw, int fh, int tolerance)
    {
        int expected = 0;
        foreach (var c in counts) expected += c;
        var frames = Frames(batches, counts, fw, fh).GetEnumerator();
        var chunks = ReadChunks(apngPath);
        if (chunks[0].Type != "IHDR" || (int)GetU32(chunks[0].Data, 0) != fw || (int)GetU32(chunks[0].Data, 4) != fh)
            throw new Exception("The animated PNG does not have the expected size.");
        var canvas = new byte[fw * fh * 4];
        int frameIndex = 0, regions = 0, declared = -1, W = 0, H = 0, X = 0, Y = 0, delay = 0, blend = 0;
        long bad = 0;
        var data = new MemoryStream();
        bool pending = false;
        Action flush = () =>
        {
            var px = Unfilter(Inflate(data.ToArray()), W, H, 4);
            for (int y = 0; y < H; y++)
                for (int x = 0; x < W; x++)
                {
                    int o = ((Y + y) * fw + X + x) * 4, d = (y * W + x) * 4;
                    if (blend == 0 || px[d + 3] == 255) { canvas[o] = px[d]; canvas[o + 1] = px[d + 1]; canvas[o + 2] = px[d + 2]; canvas[o + 3] = px[d + 3]; }
                    else if (px[d + 3] != 0) throw new Exception("Unexpected partial alpha in region " + regions);
                }
            for (int n = 0; n < delay; n++)
            {
                if (!frames.MoveNext()) throw new Exception("More frames in the file than screenshots.");
                var f = frames.Current;
                frameIndex++;
                for (int o = 0; o < canvas.Length; o += 4) if (Exceeds(canvas, f, o, tolerance)) bad++;
            }
            regions++;
        };
        foreach (var c in chunks)
        {
            if (c.Type == "acTL") declared = (int)GetU32(c.Data, 0);
            else if (c.Type == "fcTL")
            {
                if (pending) flush();
                W = (int)GetU32(c.Data, 4); H = (int)GetU32(c.Data, 8); X = (int)GetU32(c.Data, 12); Y = (int)GetU32(c.Data, 16);
                delay = (c.Data[20] << 8) | c.Data[21];
                blend = c.Data[25];
                data = new MemoryStream();
                pending = true;
            }
            else if (c.Type == "IDAT") data.Write(c.Data, 0, c.Data.Length);
            else if (c.Type == "fdAT") data.Write(c.Data, 4, c.Data.Length - 4);
        }
        if (pending) flush();
        if (declared != regions) throw new Exception(string.Format(CultureInfo.InvariantCulture, "acTL declares {0} frames but the file has {1}.", declared, regions));
        if (frameIndex != expected) throw new Exception(string.Format(CultureInfo.InvariantCulture, "The file covers {0} frames, expected {1}.", frameIndex, expected));
        return string.Format(CultureInfo.InvariantCulture, "{0} regions cover {1} frames, {2} mismatched pixels", regions, frameIndex, bad);
    }

    // Writes frame `index` of a batch screenshot as a plain PNG, for review snapshots.
    public static void WriteStill(string batch, int index, int count, int fw, int fh, string outPath)
    {
        int w, h;
        var px = DecodePng(batch, out w, out h);
        if (w != fw || h != fh * count)
            throw new Exception(string.Format(CultureInfo.InvariantCulture, "Screenshot {0} is {1}x{2}, expected {3}x{4}", batch, w, h, fw, fh * count));
        var frame = new byte[fw * fh * 4];
        Buffer.BlockCopy(px, index * frame.Length, frame, 0, frame.Length);
        using (var s = new FileStream(outPath, FileMode.Create))
        {
            s.Write(Signature, 0, 8);
            var ihdr = new byte[13];
            PutU32(ihdr, 0, (uint)fw); PutU32(ihdr, 4, (uint)fh); ihdr[8] = 8; ihdr[9] = 6;
            WriteChunk(s, "IHDR", ihdr);
            WriteChunk(s, "IDAT", CompressRegion(frame, fw, 0, 0, fw, fh));
            WriteChunk(s, "IEND", new byte[0]);
        }
    }
}
'@
}

# ==== Helpers ==================================================================================

function Get-RootAttribute([string]$Root, [string]$Attribute) {
    # The lookbehind keeps 'width' from matching inside 'stroke-width'.
    $m = [regex]::Match($Root, "(?<![\w:-])$Attribute\s*=\s*`"([^`"]+)`"")
    if ($m.Success) { $m.Groups[1].Value.Trim() -replace 'px$', '' } else { $null }
}

# Start-Process joins arguments with spaces, so values that contain spaces need quotes.
function Format-Argument([string]$Value) {
    if ($Value -match '\s') { '"' + $Value + '"' } else { $Value }
}

# Screenshots copies of one SVG paused at the given times, stacked top to bottom, in one launch.
function Invoke-Screenshot {
    param([string]$Svg, [int]$Width, [int]$Height, [double[]]$Times, [string]$OutFile, [string]$Label)
    $copies = for ($k = 0; $k -lt $Times.Count; $k++) {
        # Element ids are global to the page. Without a prefix per copy, url(#...) and href="#..." in
        # later copies would resolve into the first copy and show its clock (a typing terminal's
        # clip path, for example).
        $p = "f$k-"
        $copy = $Svg -replace '(?<=\s)id="', "id=`"$p"
        $copy = $copy.Replace('url(#', "url(#$p").Replace('href="#', "href=`"#$p")
        "<div class=`"f`">$copy</div>"
    }
    $ts = ($Times | ForEach-Object { $_.ToString('0.######', $invariant) }) -join ','
    $html = @"
<!doctype html>
<html><head><meta charset="utf-8"><style>html,body{margin:0;padding:0;background:#fff}.f{width:${Width}px;height:${Height}px;overflow:hidden}svg{display:block}</style></head>
<body>
$($copies -join "`n")
<script>const ts=[$ts];document.querySelectorAll('body > div.f > svg').forEach((s,i)=>{s.pauseAnimations();s.setCurrentTime(ts[i]);});</script>
</body></html>
"@
    $htmlPath = Join-Path $tmp "$Label.html"
    [IO.File]::WriteAllText($htmlPath, $html, [Text.UTF8Encoding]::new($false))
    $edgeArgs = @(
        '--headless=new', '--disable-gpu', '--disable-lcd-text', '--force-color-profile=srgb', '--hide-scrollbars',
        '--no-first-run', '--no-default-browser-check', '--disable-extensions',
        (Format-Argument "--user-data-dir=$(Join-Path $tmp 'profile')"),
        "--force-device-scale-factor=$($Scale.ToString($invariant))",
        "--window-size=$Width,$($Height * $Times.Count)",
        (Format-Argument "--screenshot=$OutFile"),
        [Uri]::new($htmlPath).AbsoluteUri
    )
    $errLog = Join-Path $tmp 'browser.err'
    foreach ($attempt in 1..3) {
        Start-Process -FilePath $EdgePath -ArgumentList $edgeArgs -Wait -NoNewWindow -RedirectStandardError $errLog -RedirectStandardOutput (Join-Path $tmp 'browser.out')
        if (Test-Path -LiteralPath $OutFile) { break }
    }
    if (-not (Test-Path -LiteralPath $OutFile)) {
        $detail = ((Get-Content -LiteralPath $errLog -Raw -ErrorAction SilentlyContinue) ?? '').Trim() -replace '\s+', ' '
        if ($detail.Length -gt 600) { $detail = $detail.Substring(0, 600) }
        throw "${Label}: the browser wrote no screenshot after three attempts. $detail"
    }
    Remove-Item -LiteralPath $htmlPath -Force -ErrorAction SilentlyContinue
}

# ==== Render ===================================================================================

$all = @(Get-ChildItem -LiteralPath $assetDir -Filter '*.svg' -File | Sort-Object Name)
if ($Name) {
    $unknown = @($Name | Where-Object { $n = $_; -not ($all | Where-Object { $_.BaseName -eq $n }) })
    if ($unknown) { throw "No SVG named $($unknown -join ', ') in $assetDir." }
    $targets = @($all | Where-Object { $Name -contains $_.BaseName })
}
else { $targets = $all }
if (-not $targets) { throw "No .svg files in $assetDir." }

Add-Type -AssemblyName System.IO.Compression
$tmp = Join-Path ([IO.Path]::GetTempPath()) "diagram-render-$PID"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
Write-Host "Rendering from $assetDir with $EdgePath"
$failed = 0
try {
    foreach ($file in $targets) {
        $base = $file.BaseName
        $svg = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
        $root = [regex]::Match($svg, '<svg\b[^>]*>').Value
        $loopText = Get-RootAttribute $root 'data-loop-seconds'
        $fpsText = Get-RootAttribute $root 'data-frames-per-second'
        $wText = Get-RootAttribute $root 'width'
        $hText = Get-RootAttribute $root 'height'
        if (-not ($loopText -and $fpsText -and $wText -and $hText)) {
            $why = "$base.svg has no width, height, data-loop-seconds or data-frames-per-second on its svg root, so it is not an animated diagram."
            if ($Name) { throw $why }
            Write-Warning "Skipped: $why"
            continue
        }
        $w = [int][double]::Parse($wText, $invariant)
        $h = [int][double]::Parse($hText, $invariant)
        $loop = [double]::Parse($loopText, $invariant)
        $fps = [int]$fpsText
        $count = [int][math]::Round($loop * $fps)
        if ([math]::Abs($loop * $fps - $count) -gt 1e-6) { throw "$base.svg: loop seconds times frames per second must be a whole number." }

        $fw = [int][math]::Round($w * $Scale)
        $fh = [int][math]::Round($h * $Scale)
        $batchSize = $Batch
        if ([math]::Abs($w * $Scale - $fw) -gt 1e-6 -or [math]::Abs($h * $Scale - $fh) -gt 1e-6) {
            # Stacked frames must land on whole device pixels; otherwise render one frame per launch.
            Write-Warning "$base.svg: width or height x scale is not a whole number, so each frame gets its own browser launch."
            $batchSize = 1
        }

        if ($snapTimes) {
            New-Item -ItemType Directory -Force -Path $SnapshotPath | Out-Null
            for ($start = 0; $start -lt $snapTimes.Count; $start += $batchSize) {
                $chunk = @($snapTimes[$start..([math]::Min($start + $batchSize, $snapTimes.Count) - 1)])
                $times = @($chunk | ForEach-Object { $loop + ((($_ % $loop) + $loop) % $loop) })
                $shot = Join-Path $tmp "$base-snapshot-$start.png"
                Invoke-Screenshot -Svg $svg -Width $w -Height $h -Times $times -OutFile $shot -Label "$base-snapshot-$start"
                for ($k = 0; $k -lt $chunk.Count; $k++) {
                    $still = Join-Path $SnapshotPath ('{0}-t{1}s.png' -f $base, $chunk[$k].ToString('0.###', $invariant))
                    [LabDiagramApng]::WriteStill($shot, $k, $chunk.Count, $fw, $fh, $still)
                    Write-Host "Snapshot: $still"
                }
            }
            continue
        }

        $batches = [Collections.Generic.List[string]]::new()
        $counts = [Collections.Generic.List[int]]::new()
        for ($start = 0; $start -lt $count; $start += $batchSize) {
            $n = [math]::Min($batchSize, $count - $start)
            # Sample the second loop so every animation, including ones with a delayed start, is under way.
            $times = @(foreach ($k in 0..($n - 1)) { $loop + ($start + $k) / $fps })
            $shot = Join-Path $tmp "$base-batch-$start.png"
            Invoke-Screenshot -Svg $svg -Width $w -Height $h -Times $times -OutFile $shot -Label "$base-batch-$start"
            $batches.Add($shot)
            $counts.Add($n)
            Write-Progress -Activity "Rendering $base" -Status "frame $($start + $n) of $count" -PercentComplete (100 * ($start + $n) / $count)
        }
        Write-Progress -Activity "Rendering $base" -Completed

        $outPath = Join-Path $assetDir "$base.png"
        $summary = [LabDiagramApng]::Build($batches.ToArray(), $counts.ToArray(), $fw, $fh, $fps, $outPath, $Tolerance)
        $check = [LabDiagramApng]::Verify($outPath, $batches.ToArray(), $counts.ToArray(), $fw, $fh, $Tolerance)
        foreach ($b in $batches) { Remove-Item -LiteralPath $b -Force -ErrorAction SilentlyContinue }
        if ($check -notmatch ', 0 mismatched pixels$') {
            Write-Error "$base.png failed verification: $check" -ErrorAction Continue
            $failed++
            continue
        }
        Write-Host "$base.png: ${fw}x${fh}, $summary, $fps fps; verified: $check (tolerance $Tolerance)"
        $size = (Get-Item -LiteralPath $outPath).Length
        if ($size -gt $budgetBytes) {
            Write-Warning ("$base.png is {0} MB, over the 2.5 MB budget. See 'Size budget' in tools/diagrams/README.md." -f ($size / 1MB).ToString('0.00', $invariant))
        }
    }
}
finally {
    Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
}
if ($failed) { throw "$failed diagram(s) failed verification." }
