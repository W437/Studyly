#!/usr/bin/env python3
"""A sheet of every piece in shotkit.PIECES (and the medals), on a sky-blue ground with its name, to check the boxes.

    python3 -P scripts/store_art/pieces_sheet.py [out.png]
"""
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import shotkit as sk  # noqa: E402


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(sk.LISTING, "pieces.png")
    names = list(sk.PIECES)
    cell_w = 560
    items = []
    for n in names:
        try:
            items.append((n, sk.piece(n, width=cell_w - 30)))
        except FileNotFoundError as e:
            print("missing", n, e)
    for i in range(3):
        items.append((f"medal{i}", sk.medal(i, 330)))
    cols = 4
    rows = []
    col_h = [0] * cols
    pos = []
    for n, im in items:
        c = col_h.index(min(col_h))
        pos.append((c, col_h[c]))
        col_h[c] += im.height + 70
    sheet = Image.new("RGB", (cols * cell_w + 30, max(col_h) + 30), (124, 160, 200))
    d = ImageDraw.Draw(sheet)
    for (n, im), (c, y) in zip(items, pos):
        x = 30 + c * cell_w
        sheet.paste(im, (x, y + 40), im)
        d.text((x, y + 12), n, fill=(255, 255, 255), font=sk.font(sk.ROUNDED, 24))
    sheet.save(out)
    print(out, sheet.size)


if __name__ == "__main__":
    main()
