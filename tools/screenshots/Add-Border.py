"""Adds the standard 2 px gray border to lab screenshots that do not have it yet.

The border goes outside the existing pixels (the image grows by 2 px on each side), so no
content is covered. Images whose four edges already carry the border are left alone, so the
script is safe to run again. Diagrams are not screenshots and are skipped: only PNG files named
in a screenshot scheme are touched (E1T2S3, E1T2-1S4, E1T2S3-1, GS2, L3T2S4, lab01-e1t1p2,
lab1a-t2s3; change it with --pattern). It walks the folder recursively, so every lab's media
folder under Instructions/ is covered.

    python tools/screenshots/Add-Border.py [Instructions] [--check] [--pattern REGEX]

--check changes nothing and exits 1 when a screenshot lacks the border (use it in QA).
Requires Pillow (pip install pillow).
"""
import argparse
import pathlib
import re
import sys

from PIL import Image, ImageOps

COLOR = (90, 90, 90)
WIDTH = 2
NAME = r'(E\d+T\d+(-\d+)?S\d+(-\d+)?|GS\d+|L\d+T\d+S\d+|lab\d+-e\d+t\d+p\d+|lab\d+[a-z]?-t\d+s\d+(-\d+)?)\.png$'


def has_border(im):
    im = im.convert('RGB')
    w, h = im.size
    points = [(i, h // 2) for i in range(WIDTH)] + [(w - 1 - i, h // 2) for i in range(WIDTH)] \
        + [(w // 2, i) for i in range(WIDTH)] + [(w // 2, h - 1 - i) for i in range(WIDTH)]
    return all(im.getpixel(p) == COLOR for p in points)


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument('folder', nargs='?', default='Instructions')
    p.add_argument('--check', action='store_true')
    p.add_argument('--pattern', default=NAME, help='regular expression for screenshot file names')
    a = p.parse_args()

    name = re.compile(a.pattern, re.I)
    missing, added = [], 0
    for f in sorted(pathlib.Path(a.folder).rglob('*.png')):
        if not name.fullmatch(f.name):
            continue
        with Image.open(f) as im:
            if has_border(im):
                continue
            if a.check:
                missing.append(f.name)
                continue
            out = ImageOps.expand(im.convert('RGB'), border=WIDTH, fill=COLOR)
        out.save(f, optimize=True)
        added += 1
    if a.check:
        print(f'{len(missing)} screenshot(s) without the border' + (': ' + ' '.join(missing) if missing else ''))
        sys.exit(1 if missing else 0)
    print(f'Added the border to {added} screenshot(s)')


if __name__ == '__main__':
    main()
