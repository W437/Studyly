#!/usr/bin/env python3
"""Draw a labelled pixel grid over a screenshot, to read off the boxes of the pieces to cut from it.

    python3 -P scripts/store_art/grid.py build/listing/lib/today.png [out.png] [--step 100] [--crop x0,y0,x1,y1] [--width 720]

Lines every <step> px (labels in source px). --crop shows only that box (labels stay in source px), --width sets the size of the picture.
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFont


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--step", type=int, default=100)
    ap.add_argument("--crop", default="")
    ap.add_argument("--width", type=int, default=720)
    a = ap.parse_args()
    im = Image.open(a.src).convert("RGB")
    x0, y0, x1, y1 = (int(v) for v in a.crop.split(",")) if a.crop else (0, 0, im.width, im.height)
    im = im.crop((x0, y0, x1, y1))
    k = a.width / im.width
    im = im.resize((a.width, round(im.height * k)), Image.LANCZOS)
    d = ImageDraw.Draw(im, "RGBA")
    f = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 13)
    start_x = (x0 // a.step + (1 if x0 % a.step else 0)) * a.step
    for x in range(start_x, x1, a.step):
        X = (x - x0) * k
        d.line((X, 0, X, im.height), fill=(255, 0, 80, 150), width=1)
        d.text((X + 2, 2), str(x), fill=(255, 0, 80, 255), font=f)
    start_y = (y0 // a.step + (1 if y0 % a.step else 0)) * a.step
    for y in range(start_y, y1, a.step):
        Y = (y - y0) * k
        d.line((0, Y, im.width, Y), fill=(0, 120, 255, 150), width=1)
        d.text((2, Y + 1), str(y), fill=(0, 100, 255, 255), font=f)
    out = a.out or os.path.splitext(a.src)[0] + "-grid.png"
    im.save(out)
    print(out)


if __name__ == "__main__":
    main()
