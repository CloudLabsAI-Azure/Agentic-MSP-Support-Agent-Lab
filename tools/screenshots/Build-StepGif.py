"""Builds a high-quality animated GIF of one lab task from full-resolution step captures.

The browser recorder's own GIFs are built from compressed screenshots at reduced size, so text
comes out soft. This script builds the GIF from the same full-resolution captures that the
still screenshots come from: one capture per step (or the left and right halves of the screen,
joined), taken at the device's native resolution in a browser viewport sized like the lab VM.

Spec (JSON), every coordinate in pixels of the joined capture:

    {
      "out": "Instructions/Labs/Media/lab1b-task3.gif",
      "width": 1470,
      "default_ms": 1700,
      "last_ms": 4000,
      "blur": [[x, y, w, h]],
      "frames": [
        {"src": ["left.png", "right.png"], "click": [x, y]},
        {"src": "single.png", "box": [x, y, w, h], "ms": 2500, "blur": [[x, y, w, h]]},
        {"src": ["left.png", "right.png"]}
      ]
    }

- "src" is one capture, or a list joined left to right (the halves of the screen).
- "click" draws a red ring where the next click lands; "box" draws a red box (for example
  around a field just filled in). Both are optional.
- "blur" (top level, every frame) and per-frame "blur" hide accounts that are not part of the
  lab, tenant names, tenant and object IDs and domains.
- "width" is the output width (default 1470, the lab VM's browser width in CSS pixels), so text
  appears at its on-screen size; frames are downscaled from the native capture with Lanczos.
- Every frame gets the standard 2 px gray border. One palette is shared by all frames (fast
  octree over every frame at full size, so small accent colors survive; no dithering, so text
  stays crisp), and unchanged areas between frames are not repeated, which keeps the file small.

    python tools/screenshots/Build-StepGif.py captures/lab1b/task3.json

Requires Pillow (pip install pillow).
"""
import json
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFilter

RED = (252, 66, 66)
BORDER = (90, 90, 90)


def load(src, base):
    paths = src if isinstance(src, list) else [src]
    parts = [Image.open(p if pathlib.Path(p).is_absolute() else base / p).convert('RGB') for p in paths]
    if len(parts) == 1:
        return parts[0]
    w = sum(p.width for p in parts)
    h = max(p.height for p in parts)
    joined = Image.new('RGB', (w, h), 'white')
    x = 0
    for p in parts:
        joined.paste(p, (x, 0))
        x += p.width
    return joined


def blur(im, box):
    x, y, w, h = box
    box = (max(0, x), max(0, y), min(im.width, x + w), min(im.height, y + h))
    if box[2] - box[0] < 2 or box[3] - box[1] < 2:
        return
    region = im.crop(box)
    small = region.resize((max(1, region.width // 12), max(1, region.height // 12)), Image.BILINEAR)
    im.paste(small.resize(region.size, Image.BICUBIC).filter(ImageFilter.GaussianBlur(2)), box)


def mark_click(im, xy, scale):
    x, y = xy
    r = round(28 * scale)
    overlay = Image.new('RGBA', im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    d.ellipse([x - r, y - r, x + r, y + r], fill=RED + (38,), outline=RED + (255,), width=max(3, round(4 * scale)))
    dot = max(2, round(4 * scale))
    d.ellipse([x - dot, y - dot, x + dot, y + dot], fill=RED + (255,))
    return Image.alpha_composite(im.convert('RGBA'), overlay).convert('RGB')


def main():
    spec_path = pathlib.Path(sys.argv[1])
    spec = json.loads(spec_path.read_text(encoding='utf-8'))
    base = spec_path.parent
    width = spec.get('width', 1470)
    default_ms = spec.get('default_ms', 1700)
    last_ms = spec.get('last_ms', 4000)

    frames, durations = [], []
    size = None
    for i, fr in enumerate(spec['frames']):
        im = load(fr['src'], base)
        if size is None:
            size = im.size
        elif im.size != size:
            im = im.resize(size, Image.LANCZOS)
        for b in spec.get('blur', []) + fr.get('blur', []):
            blur(im, b)
        scale = size[0] / 2205
        if fr.get('box'):
            x, y, w, h = fr['box']
            ImageDraw.Draw(im).rectangle([x, y, x + w, y + h], outline=RED, width=max(2, round(3 * scale)))
        if fr.get('click'):
            im = mark_click(im, fr['click'], scale * 1.5)
        if width and im.width != width:
            im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
        ImageDraw.Draw(im).rectangle([0, 0, im.width - 1, im.height - 1], outline=BORDER, width=2)
        frames.append(im)
        last = i == len(spec['frames']) - 1
        durations.append(fr.get('ms', last_ms if last else default_ms))

    # One palette for every frame, from all of them at full size. Fast octree keeps small accent
    # colors (green status bars, colored icons) that median cut merges into gray; no dithering
    # keeps text crisp.
    mosaic = Image.new('RGB', (frames[0].width, sum(f.height for f in frames)))
    y = 0
    for f in frames:
        mosaic.paste(f, (0, y))
        y += f.height
    palette = mosaic.quantize(colors=255, method=Image.Quantize.FASTOCTREE)
    paletted = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]

    out = pathlib.Path(spec['out'])
    out.parent.mkdir(parents=True, exist_ok=True)
    paletted[0].save(out, save_all=True, append_images=paletted[1:], duration=durations, loop=0,
                     disposal=1, optimize=False)
    print(f'Wrote {out}: {len(paletted)} frames, {paletted[0].width}x{paletted[0].height}, '
          f'{out.stat().st_size / 1048576:.1f} MB')


if __name__ == '__main__':
    main()
