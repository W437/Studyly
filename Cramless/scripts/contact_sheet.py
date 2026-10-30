#!/usr/bin/env python3
"""Puts screenshots side by side on one sheet, to look at them together.

    python3 scripts/contact_sheet.py out.png a.png b.png c.png [--height 1000]
"""
import sys

from PIL import Image


def main():
    args = sys.argv[1:]
    height = 1000
    if "--height" in args:
        i = args.index("--height")
        height = int(args[i + 1])
        del args[i:i + 2]
    out, files = args[0], args[1:]
    tiles = []
    for f in files:
        im = Image.open(f).convert("RGB")
        w = round(im.width * height / im.height)
        tiles.append(im.resize((w, height), Image.LANCZOS))
    gap = 16
    sheet = Image.new("RGB", (sum(t.width for t in tiles) + gap * (len(tiles) + 1), height + 2 * gap), (128, 128, 128))
    x = gap
    for t in tiles:
        sheet.paste(t, (x, gap))
        x += t.width + gap
    sheet.save(out)
    print(out, sheet.size)


if __name__ == "__main__":
    main()
