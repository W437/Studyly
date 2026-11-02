#!/usr/bin/env python3
"""Contact sheets of the 15 study apps' listing screenshots saved by the 2026-10-28 store research (~/Sites/capling-store-research/img).

    python3 -P scripts/store_art/competitor_sheet.py [out-dir] [--frames 6] [--width 320] [--per 3]

One row per app (its icon, name and the first N screenshots), <per> apps to a sheet. These are other companies' store images: look at them
to learn the structure of their listings, never ship or publish them.
"""
import argparse
import os

from PIL import Image, ImageDraw, ImageFont

RESEARCH = os.path.expanduser("~/Sites/capling-store-research/img")
APPS = [("quizlet", "Quizlet"), ("gizmo", "Gizmo"), ("knowt", "Knowt"), ("anki", "AnkiMobile"), ("brainscape", "Brainscape"),
        ("solvely", "Solvely"), ("gauth", "Gauth"), ("photomath", "Photomath"), ("studyfetch", "StudyFetch"), ("turbo-ai", "Turbo AI"),
        ("coconote", "Coconote"), ("knowunity", "Knowunity"), ("kahoot", "Kahoot!"), ("duolingo", "Duolingo"), ("brilliant", "Brilliant")]


def frames(app):
    d = os.path.join(RESEARCH, app)
    return sorted(f for f in os.listdir(d) if f[:2].isdigit())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out", nargs="?", default="build/listing/competitors")
    ap.add_argument("--frames", type=int, default=6)
    ap.add_argument("--width", type=int, default=320)
    ap.add_argument("--per", type=int, default=3)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 26)
    for s in range(0, len(APPS), a.per):
        group = APPS[s:s + a.per]
        cw = a.width
        ch = round(cw * 1067 / 600)
        sheet = Image.new("RGB", (a.frames * (cw + 8) + 8, len(group) * (ch + 50) + 8), (92, 100, 120))
        d = ImageDraw.Draw(sheet)
        for r, (key, name) in enumerate(group):
            y = 8 + r * (ch + 50)
            d.text((10, y + 8), f"{s + r + 1}. {name}  ({len(frames(key))} shots)", fill=(255, 255, 255), font=font)
            for c, fn in enumerate(frames(key)[:a.frames]):
                im = Image.open(os.path.join(RESEARCH, key, fn)).convert("RGB")
                im = im.resize((cw, round(cw * im.height / im.width)), Image.LANCZOS)
                sheet.paste(im, (8 + c * (cw + 8), y + 44))
        p = os.path.join(a.out, f"sheet{s // a.per + 1}.png")
        sheet.save(p)
        print(p, sheet.size)


if __name__ == "__main__":
    main()
