# Screenshot and GIF Tools

Tools for live-captured lab screenshots and task walkthrough GIFs in the CloudLabs house style. They are
copied into each lab repository's `tools/screenshots/` with the rest of the toolkit, and the commands
below run from the lab repository root. The method is in `references/screenshots.md` §2c (live capture),
§3 (annotation) and §5 (GIF walkthroughs).

| Tool | What it does | Needs |
|---|---|---|
| `Annotate-Screenshot.ps1` | One capture to one finished screenshot: blur, crop, red boxes, numbered badges, 2 px border, from a JSON spec | PowerShell 7 (System.Drawing) |
| `Join-Captures.ps1` | Joins capture tiles (for example the left and right halves of the screen) into one PNG at full resolution | PowerShell 7 |
| `Build-StepGif.py` | Builds a task walkthrough GIF from full-resolution step captures: click rings, boxes, blur, border, one shared palette, no dithering | Python 3.11, Pillow |
| `Redact-Gif.py` | Blurs regions of an existing GIF frame by frame, drops or crops frames, adds the border (for GIFs from the browser recorder) | Python 3.11, Pillow |
| `Add-Border.py` | Adds the 2 px gray border to every screenshot that lacks it; `--check` is a QA gate step | Python 3.11, Pillow |

Install Pillow once with `python -m pip install pillow`.

## House style

- **Border:** 2 px, RGB 90, 90, 90, around every screenshot and every GIF frame, drawn as solid strips so no
  pixel offset can push it off the image. Check the edge pixels after rendering.
- **Boxes:** RGB 252, 66, 66, around only the element the step acts on, never a panel. `rect` is the
  element's tight bounds; the tool adds a 4 px margin and snaps each edge to plain background, so no
  edge cuts text or a neighboring control. Boxes never touch or overlap each other.
- **Badges:** a 30 px red circle with a white bold numeral, diagonally outside a box corner; the tool
  picks the clear corner (top-right first) or slides along the box to a spot that covers nothing.
  `"badge": "tr"` (tl, br, bl, right, left) forces one. Badge numbers match the step's **(1)**,
  **(2)** markers one to one.
- **Equal size:** line, margin and badge scale with max(1, width / 1000), so they look the same in
  the guide whatever the image width.
- **Gate:** render with `-Strict`; it exits 1 on any box edge in content, touching boxes or badges,
  or a badge over content.
- **Blur:** an opaque blur (downscale and upscale) over every account that is not part of the lab (other
  admins in member pickers), tenant names, tenant and object IDs, the domain part of user names, contact
  email addresses, and any key or pass. Never capture a secret in the first place.
- **Scale:** text is never shrunk below its on-screen size. Captures are taken at the device's native
  resolution in a viewport sized like the lab VM, so stills come out at 1.3x to 1.5x screen size.

## Annotate one screenshot

```json
{
  "source": "captures/raw-E1T3S7.png",
  "out": "Instructions/media/E1T3S7.png",
  "crop": [0, 14, 1394, 662],
  "blur": [[874, 8, 128, 26]],
  "boxes": [ { "rect": [22, 296, 1360, 44], "n": 1 },
             { "rect": [22, 486, 1360, 90], "n": 2, "badge": "right" } ]
}
```

```powershell
pwsh tools/screenshots/Annotate-Screenshot.ps1 -Spec captures/E1T3S7.json -Strict
```

Rectangles are `x, y, width, height` in pixels of the source capture: the element's own edges. A box
without `n` has no badge (use it when the step text has no numbered markers). Optional per box:
`"pad"` (margin), `"snap": false`, `"badge"`.

## Build a task GIF

```json
{
  "out": "Instructions/media/E1T3.gif",
  "width": 1470,
  "blur": [[1620, 4, 215, 46]],
  "frames": [
    { "src": ["captures/E1T3/01-left.png", "captures/E1T3/01-right.png"], "click": [92, 293] },
    { "src": ["captures/E1T3/02-left.png", "captures/E1T3/02-right.png"], "click": [673, 301] },
    { "src": ["captures/E1T3/03-left.png", "captures/E1T3/03-right.png"] }
  ]
}
```

```powershell
python tools/screenshots/Build-StepGif.py captures/E1T3.json
```

Each frame is the state before the click it marks; the last frame shows the result and holds for 4 s.
Typical size: 0.1 to 0.3 MB per frame at 1470 px.

## QA gate step

```powershell
python tools/screenshots/Add-Border.py Instructions --check
```

Exit code 1 lists every screenshot without the border; run it without `--check` to add the border.
