#!/usr/bin/env python3
"""A labelled contact sheet of the screen library: python3 -P scripts/store_art/lib_sheet.py [out.png] [name ...]"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.abspath(os.path.join(HERE, "..", "..", "build", "listing", "lib"))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(LIB, "..", "lib-sheet.png")
    names = sys.argv[2:] or sorted(f[:-4] for f in os.listdir(LIB) if f.endswith(".png"))
    cw, per = 330, 8
    f = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 22)
    rows = (len(names) + per - 1) // per
    ch = int(cw * 2622 / 1206) + 40
    sh = Image.new("RGB", (per * cw + 10, rows * ch), (120, 130, 150))
    d = ImageDraw.Draw(sh)
    for i, n in enumerate(names):
        im = Image.open(os.path.join(LIB, n + ".png")).convert("RGB")
        im = im.resize((cw - 10, int((cw - 10) * im.height / im.width)))
        x, y = (i % per) * cw + 10, (i // per) * ch
        sh.paste(im, (x, y + 34))
        d.text((x, y + 6), n, fill=(255, 255, 255), font=f)
    sh.save(out)
    print(out, sh.size)


if __name__ == "__main__":
    main()
