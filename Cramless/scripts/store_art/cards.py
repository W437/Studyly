#!/usr/bin/env python3
"""Find the cards (flat, rounded panels) on a screenshot, to cut them out as pieces.

    python3 -P scripts/store_art/cards.py build/listing/lib/exam.png [--min 14000] [--out annotated.png]

Flood-fills the screenshot (at a quarter of its size) on near-equal colours and prints every flat region big enough to be a card as
`#n  x0,y0,x1,y1  colour`, in source pixels. The annotated picture numbers them. Text and icons on a card are holes in the fill, so the
bounding box is still the card's.
"""
import argparse
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageDraw, ImageFont


def regions(path, k=4, tol=7, min_area=14000):
    im = Image.open(path).convert("RGB")
    sm = np.asarray(im.resize((im.width // k, im.height // k), Image.BOX)).astype(int)
    h, w, _ = sm.shape
    seen = np.zeros((h, w), bool)
    out = []
    for sy in range(0, h, 3):
        for sx in range(0, w, 3):
            if seen[sy, sx]:
                continue
            base = sm[sy, sx]
            q = deque([(sy, sx)])
            seen[sy, sx] = True
            x0 = x1 = sx
            y0 = y1 = sy
            n = 0
            while q:
                y, x = q.popleft()
                n += 1
                x0, x1, y0, y1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y)
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and not seen[yy, xx] and np.abs(sm[yy, xx] - base).max() <= tol:
                        seen[yy, xx] = True
                        q.append((yy, xx))
            bw, bh = (x1 - x0 + 1) * k, (y1 - y0 + 1) * k
            if n * k * k >= min_area and bw >= 160 and bh >= 70:
                out.append(dict(box=(x0 * k, y0 * k, (x1 + 1) * k, (y1 + 1) * k), colour=tuple(int(v) for v in base), area=n * k * k))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("--min", type=int, default=14000)
    ap.add_argument("--out", default="")
    a = ap.parse_args()
    rs = regions(a.src, min_area=a.min)
    im = Image.open(a.src).convert("RGB")
    d = ImageDraw.Draw(im, "RGBA")
    f = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 34)
    for i, r in enumerate(rs):
        x0, y0, x1, y1 = r["box"]
        d.rectangle((x0, y0, x1 - 1, y1 - 1), outline=(255, 0, 90, 255), width=4)
        d.text((x0 + 8, y0 + 4), f"#{i}", fill=(255, 0, 90, 255), font=f)
        print(f"#{i:<2} {x0},{y0},{x1},{y1}  {r['colour']}  {x1 - x0}x{y1 - y0}")
    out = a.out or os.path.splitext(a.src)[0] + "-cards.png"
    im.resize((im.width // 2, im.height // 2), Image.LANCZOS).save(out)
    print(out)


if __name__ == "__main__":
    main()
