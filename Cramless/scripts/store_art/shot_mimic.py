#!/usr/bin/env python3
"""Capling's App Store screenshots in the style of the 15 study apps' listings (the 2026-10-28 store research), to pick from.

    python3 -P scripts/store_art/shot_mimic.py [--style quizlet,kahoot,...] [--only 1,2,3] [--out DIR] [--compare]

Each style takes the composition, colour logic, type and decoration of one competitor's listing and fills it with Capling's own things: the
real screens, cards cut out of them, Cap, the app's colours and its own words. Nothing of theirs is used: no image, no logo, no wording, no
proof (laurels, user counts, reviews, awards): the claims here are only ones the app can back. Output: <out>/<style>/NN.png (1290 x 2796),
sheet.png and, with --compare, compare.png (the competitor's first three frames next to ours; their images stay on this Mac).
The styles live in mimic_a.py (Quizlet, Gizmo, Kahoot!, Solvely, Photomath) and mimic_b.py (the rest); the parts in mimic_base.py and mimickit.py.
"""
import argparse
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mimic_base  # noqa: E402
import mimic_a  # noqa: E402,F401
import mimic_b  # noqa: E402,F401
import shotkit as sk  # noqa: E402

STYLES = mimic_base.STYLES
RESEARCH = os.path.expanduser("~/Sites/capling-store-research/img")


def trio(images, path, gap=40):
    w = sum(im.width for im in images) + gap * (len(images) - 1)
    sheet = Image.new("RGB", (w, images[0].height), (235, 235, 238))
    x = 0
    for im in images:
        sheet.paste(im, (x, 0))
        x += im.width + gap
    sheet.save(path)


def compare(key, out, n=3, height=900):
    """The competitor's first n frames, then ours."""
    ref = STYLES[key]["ref"]
    fs = sorted(f for f in os.listdir(os.path.join(RESEARCH, ref)) if f[:2].isdigit())[:n]
    ims = [Image.open(os.path.join(RESEARCH, ref, f)).convert("RGB") for f in fs]
    ims += [Image.open(os.path.join(out, key, f"{j:02d}.png")).convert("RGB") for j in range(1, n + 1)]
    ims = [im.resize((round(im.width * height / im.height), height), Image.LANCZOS) for im in ims]
    gap = 10
    sheet = Image.new("RGB", (sum(im.width for im in ims) + gap * (len(ims) + 1) + 40, height + 2 * gap), (70, 76, 92))
    x = gap
    for j, im in enumerate(ims):
        sheet.paste(im, (x, gap))
        x += im.width + gap + (40 if j == n - 1 else 0)
    p = os.path.join(out, key, "compare.png")
    sheet.save(p)
    return p


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--style", default="")
    ap.add_argument("--only", default="")
    ap.add_argument("--out", default=os.path.join(sk.LISTING, "mimic"))
    ap.add_argument("--compare", action="store_true")
    a = ap.parse_args()
    keys = [k for k in STYLES if not a.style or k in a.style.split(",")]
    only = [int(v) - 1 for v in a.only.split(",") if v] or list(range(8))
    for key in keys:
        d = os.path.join(a.out, key)
        os.makedirs(d, exist_ok=True)
        ims = []
        for i in only:
            im = STYLES[key]["fn"](i)
            im.save(os.path.join(d, f"{i + 1:02d}.png"))
            ims.append(im)
        trio(ims, os.path.join(d, "sheet.png"))
        print(os.path.join(d, "sheet.png"))
        if a.compare and only[:3] == [0, 1, 2]:
            compare(key, a.out)


if __name__ == "__main__":
    main()
