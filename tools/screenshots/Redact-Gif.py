"""Blurs regions of an animated GIF (a recorded lab task) and optionally scales it down.

Each --blur is "x,y,w,h" in pixels of the original frames, optionally followed by "@first-last"
to limit it to a range of frame numbers (0-based, inclusive). Without a range the region is
blurred in every frame. --crop trims every frame (for example the white padding the recorder adds when a frame
of another size is in the recording). --drop leaves out a frame (for example a close-up capture at another
scale). Use it for user names, tenant and object IDs, and any account that is not
part of the lab. Every frame gets the same 2 px gray border as the still screenshots. Frame durations and
looping are kept.

    python tools/screenshots/Redact-Gif.py in.gif out.gif --blur 1165,0,160,36 --blur 340,380,770,380@23-26 --scale 0.8

Requires Pillow (pip install pillow).
"""
import argparse

from PIL import Image, ImageDraw, ImageFilter, ImageSequence


def parse_blur(text):
    rect, _, frames = text.partition('@')
    x, y, w, h = (int(v) for v in rect.split(','))
    if frames:
        a, _, b = frames.partition('-')
        rng = range(int(a), int(b or a) + 1)
    else:
        rng = None
    return (x, y, x + w, y + h), rng


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument('src')
    p.add_argument('dst')
    p.add_argument('--blur', action='append', default=[], type=parse_blur)
    p.add_argument('--scale', type=float, default=1.0)
    p.add_argument('--crop', help='x,y,w,h kept from every frame, applied after blurring')
    p.add_argument('--drop', action='append', default=[], type=int, help='frame number to leave out (repeatable)')
    a = p.parse_args()

    im = Image.open(a.src)
    frames, durations = [], []
    for i, f in enumerate(ImageSequence.Iterator(im)):
        if i in a.drop:
            continue
        durations.append(f.info.get('duration', im.info.get('duration', 100)))
        f = f.convert('RGB')
        for box, rng in a.blur:
            if rng is None or i in rng:
                region = f.crop(box)
                # Strong, opaque blur: shrink then blur, so no text survives.
                small = region.resize((max(1, region.width // 12), max(1, region.height // 12)), Image.BILINEAR)
                f.paste(small.resize(region.size, Image.BICUBIC).filter(ImageFilter.GaussianBlur(2)), box)
        if a.crop:
            x, y, w, h = (int(v) for v in a.crop.split(','))
            f = f.crop((x, y, x + w, y + h))
        if a.scale != 1.0:
            f = f.resize((round(f.width * a.scale), round(f.height * a.scale)), Image.LANCZOS)
        # 2 px border, the same as the still screenshots.
        ImageDraw.Draw(f).rectangle([0, 0, f.width - 1, f.height - 1], outline=(90, 90, 90), width=2)
        frames.append(f.convert('P', palette=Image.ADAPTIVE, colors=256))
    frames[0].save(a.dst, save_all=True, append_images=frames[1:], duration=durations,
                   loop=im.info.get('loop', 0), optimize=True, disposal=1)
    print(f'Wrote {a.dst}: {len(frames)} frames, {frames[0].width}x{frames[0].height}')


if __name__ == '__main__':
    main()
