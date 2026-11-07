#!/usr/bin/env python3
"""Capling's App Store screenshots for the launch: the Gizmo set on the Sky ground, from today's screens (scripts/store_art/capture_launch.sh).

    python3 -P scripts/store_art/launch_set.py [--out build/listing/launch/final/en-US] [--only 01,05-cards,x-mock]

Writes 01.png .. 08.png (the set), 05-cards.png and 05-help.png (other words for the Ask frame) and x-notice.png, x-mock.png, x-loud.png
(frames for what the first set never showed; Apple takes ten, so at most two of them). 1290 x 2796, RGB. Words, Cap and the ground are the
Gizmo frames' own code: gizmo_final.py and gizmo_colours.py stay as they are and their old renders stay reproducible from the old captures.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gizmo_colours  # noqa: E402
import gizmo_final  # noqa: E402
import mimic_a  # noqa: E402
from mimic_a import mk, sk, W, H, put, STORY, GZ_COPY  # noqa: E402

SKY = gizmo_colours.THEMES["sky"]
SRC = os.path.join(sk.LISTING, "launch", "src")
sk.LIB = sk.SRC = SRC

# Where things are in the launch captures (1206 wide). Boxes from scripts/store_art/cards.py.
sk.PIECES.update({
    "plancard": ("plan", (60, 504, 1144, 1356), 84),
    "pathcard": ("plan", (60, 1404, 1144, 2140), 84),
    "playerbar": ("lecture-notes", (0, 2092, 1206, 2366), 72),
})
gizmo_final.CTA_ICON = (392, 1622, 452, 1694)   # the sparkles in Today's button
VERDICT_ROW = 1650                              # graded.png: the card's bottom edge, a few rows above the verdict sheet

# One row per frame: the small line, the giant word, Cap's pose, the capture, and the first row of the capture to show.
FRAMES = {
    "01": dict(i=0),
    "02": dict(i=1, shot="graded", cap="listen"),
    "03": dict(i=2, shot="exam-bio", cap="point"),
    "04": dict(i=3, shot="capture-checking", cap="scan"),
    "05": dict(i=4, copy=("Ask Cap for", "Quizzes"), shot="ask-quiz", cap="ask"),
    "06": dict(i=5, shot="lecture-notes", cap="mic", top=178, bottom=H - 150),
    "07": dict(i=6, shot="sky", cap="stargaze"),
    "08": dict(i=7, shot="streak", cap="nice"),
    "05-cards": dict(i=4, copy=("Ask Cap for", "Cards"), shot="ask-cards", cap="ask"),
    "05-help": dict(i=4, copy=("Ask Cap for", "Help"), shot="ask-problem", cap="ask"),
    "x-notice": dict(i=8, copy=("Cap spots your", "Mix-ups"), shot="notice-mixup", cap="think", top=300),
    "x-mock": dict(i=9, copy=("Take a free", "Mock"), shot="mock-mcq", cap="study"),
    "x-loud": dict(i=10, copy=("Study out", "Loud"), shot="outloud", cap="relax", top=740),
}


def setup(spec):
    """Point the shared Gizmo tables at this frame's words and pose."""
    i = spec["i"]
    while len(GZ_COPY) <= i:
        GZ_COPY.append(("", ""))
        STORY.append(dict(key="", shot="", cap=""))
    if "copy" in spec:
        GZ_COPY[i] = spec["copy"]
    STORY[i] = dict(STORY[i], shot=spec.get("shot", STORY[i]["shot"]), cap=spec.get("cap", STORY[i]["cap"]))


def screen_frame(spec):
    i, t = spec["i"], SKY
    c, wbot, cp = mimic_a.gizmo_top(i, t)
    y0 = int(wbot + 10 + cp.height - 150)
    pn = mk.panel(spec["shot"], 1060, top=spec.get("top", 152), height=spec.get("bottom", H) - y0 + 20)
    put(c, pn, W / 2, y0 + pn.height / 2, blur=34, dy=20, alpha=0.30, colour=t["shadow"])
    return c, y0


def words_frame(spec):
    """Answer in your own words: a full-marks answer, cut above the verdict sheet so nothing covers the card."""
    i, t = spec["i"], SKY
    c, _, _ = mimic_a.gizmo_top(i, t)
    k = 1060 / 1206
    pn = mk.panel(spec["shot"], 1060, height=round((VERDICT_ROW - 152) * k))
    y0 = H - pn.height
    put(c, pn, W / 2, y0 + pn.height / 2, blur=34, dy=20, alpha=0.30, colour=t["shadow"])
    return c


def lecture_frame(spec):
    """The notes with the player: the page's own bar, lifted over the bottom of its screen (it sits below the part of the screen that fits)."""
    c, _ = screen_frame(spec)
    bar = sk.piece("playerbar", width=1176)
    put(c, bar, W / 2, H - 28 - bar.height / 2, blur=30, dy=14, alpha=0.34, colour=SKY["shadow"])
    return c


def render(name):
    spec = FRAMES[name]
    setup(spec)
    if name == "01":
        return gizmo_final.ready_a(theme=SKY)
    if name == "02":
        return words_frame(spec).convert("RGB")
    if name == "06":
        return lecture_frame(spec).convert("RGB")
    return screen_frame(spec)[0].convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(sk.LISTING, "launch", "final", "en-US"))
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    only = {s for s in a.only.split(",") if s}
    for name in FRAMES:
        if only and name not in only:
            continue
        im = render(name)
        assert im.size == (W, H) and im.mode == "RGB"
        p = os.path.join(a.out, f"{name}.png")
        im.save(p)
        print(p, flush=True)


if __name__ == "__main__":
    main()
