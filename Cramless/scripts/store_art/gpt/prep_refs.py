#!/usr/bin/env python3
"""Builds the reference images the GPT Image 2.5 edit endpoint is shown: Cap (so he stays on-model), the bundled sample page, and the
app's real screens. Small JPEGs on a flat light ground (a model reads a transparent PNG unpredictably), sent as data URIs, so each
one stays under about 250 KB.

    python3 -P prep_refs.py            ->  build/store-art/gpt/refs/<name>.jpg
"""
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
OUT = os.path.join(REPO, "build", "store-art", "gpt", "refs")
ASSETS = os.path.join(REPO, "Cramless", "Resources", "Assets.xcassets")
SHOTS = os.path.join(REPO, "build", "store-art", "shots")
PANELS = os.path.join(REPO, "docs", "cap", "panels")

GROUND = (238, 241, 246)        # a flat, light, neutral ground under Cap's transparent poses


def pose(name):
    return os.path.join(ASSETS, f"Cap-{name}.imageset", f"cap-{name}.png")


# name -> (source, width in px)
REFS = {
    # Cap, as the character sheet draws him (neutral ground, no text)
    "cap_front": (os.path.join(PANELS, "turn-front-2.jpg"), 768),
    "cap_threeq": (os.path.join(PANELS, "turn-threeq-1.jpg"), 768),
    # Cap's poses as the app draws them
    "cap_stargaze": (pose("stargaze"), 600),
    "cap_celebrate": (pose("celebrate"), 600),
    "cap_point": (pose("point"), 600),
    "cap_scan": (pose("scan"), 600),
    "cap_study": (pose("study"), 600),
    "cap_proud": (pose("proud"), 600),
    # the bundled sample page
    "page": (os.path.join(REPO, "Cramless", "Resources", "Sample", "sample-mitosis-p87.jpg"), 900),
    # the app's real screens, captured from the Simulator
    "screen_scan": (os.path.join(SHOTS, "w-done", "review.png"), 900),          # questions fly out of the page, tagged p. 87
    "screen_ideas": (os.path.join(SHOTS, "w-ideas", "review.png"), 900),        # the page with its key ideas found
    "screen_answer": (os.path.join(SHOTS, "graded-w9", "session.png"), 900),    # an own-words answer, graded: "Almost."
    "screen_ready": (os.path.join(SHOTS, "exameve", "session.png"), 900),       # readiness 42% to 78%, on track for 80%
    "screen_sky": (os.path.join(SHOTS, "light", "sky.png"), 900),               # the memory sky
    "screen_today": (os.path.join(SHOTS, "light", "today.png"), 900),           # Today: the sky, Cap, "Relight"
}


def build():
    os.makedirs(OUT, exist_ok=True)
    for name, (src, width) in REFS.items():
        if not os.path.exists(src):
            print("missing", src)
            continue
        im = Image.open(src)
        if im.mode in ("RGBA", "LA") or "transparency" in im.info:
            im = im.convert("RGBA")
            base = Image.new("RGB", im.size, GROUND)
            base.paste(im, mask=im.split()[3])
            im = base
        im = im.convert("RGB")
        if im.width > width:
            im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
        path = os.path.join(OUT, f"{name}.jpg")
        im.save(path, quality=88, optimize=True)
        print(f"{name:14s} {im.size[0]}x{im.size[1]}  {os.path.getsize(path) // 1024} KB")


if __name__ == "__main__":
    sys.exit(build())
