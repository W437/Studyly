#!/usr/bin/env python3
"""The finished Gizmo set (gizmo_final.py) on other grounds than Gizmo's purple: Capling's own colours and a few of the app's skies.

    python3 -P scripts/store_art/gizmo_colours.py [--theme sky,sun,… | all] [--frames 1,2,3] [--out build/listing/gizmo-colours] [--jobs 3]

Writes <out>/<theme>/01.png … 08.png. A ground is a dict (see mimic_a.GZ_PURPLE): gradient, pixel fields, the small line's ink, the 3D word's
face and edge, the shadow, the sparkles, the glow behind the button and a die-cut edge for Cap where his fur would blend in.
"""
import argparse
import os
import sys
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gizmo_final  # noqa: E402
import mimic_a  # noqa: E402
from mimic_a import sk, WHITE, NIGHT, TANGERINE  # noqa: E402


def ground(name, note, bg, pix, small, word, shadow, spark, glow=TANGERINE, cap_outline=0):
    return dict(name=name, note=note, bg=bg, pix=pix, small=small, word=word, shadow=shadow, spark=spark, glow=glow, cap_outline=cap_outline)


THEMES = {
    "sky": ground("Sky", "Capling's own sky blue, deep at the top and light at the bottom.",
                  [(0, (22, 92, 220)), (0.55, (62, 148, 250)), (1, (138, 206, 255))],
                  [((255, 255, 255), (8, 26)), ((6, 30, 120), (12, 34))], WHITE, (WHITE, (208, 236, 255), (8, 58, 170)), (4, 30, 116), WHITE),
    "sunrise": ground("Sunrise", "Sky blue at the top turning to warm sun at the bottom.",
                      [(0, (34, 110, 232)), (0.48, (120, 184, 255)), (0.8, (255, 226, 150)), (1, (255, 196, 84))],
                      [((255, 255, 255), (8, 26)), ((14, 70, 190), (10, 28))], WHITE, (WHITE, (222, 240, 255), (10, 64, 176)), (24, 54, 130), WHITE),
    "mint": ground("Mint", "The app's go-colour: fresh green, light at the bottom.",
                   [(0, (3, 104, 80)), (0.55, (18, 164, 122)), (1, (92, 226, 178))],
                   [((255, 255, 255), (6, 22)), ((0, 60, 44), (12, 34))], WHITE, (WHITE, (204, 255, 236), (2, 78, 58)), (2, 46, 36), WHITE),
    "ocean": ground("Ocean", "Deep teal rising to a bright aqua.",
                    [(0, (1, 54, 86)), (0.55, (6, 116, 148)), (1, (36, 190, 198))],
                    [((255, 255, 255), (6, 22)), ((0, 30, 50), (14, 38))], WHITE, (WHITE, (196, 250, 255), (0, 58, 80)), (0, 36, 52), WHITE),
    "sun": ground("Sun", "Warm yellow, with a navy-edged lettering and a white edge round Cap.",
                  [(0, (255, 166, 0)), (0.55, (255, 200, 38)), (1, (255, 230, 120))],
                  [((255, 255, 255), (16, 50)), ((255, 130, 0), (12, 34))], NIGHT, (WHITE, (255, 244, 210), NIGHT), (150, 84, 0), NIGHT, cap_outline=14),
    "rose": ground("Rose", "The app's rose, from deep to soft pink, with a white edge round Cap.",
                   [(0, (176, 16, 74)), (0.55, (250, 60, 108)), (1, (255, 138, 160))],
                   [((255, 255, 255), (6, 22)), ((100, 0, 40), (12, 34))], WHITE, (WHITE, (255, 224, 232), (110, 8, 44)), (84, 0, 28), WHITE, cap_outline=14),
    "night": ground("Night", "The app's night navy, with a gold lettering.",
                    [(0, (5, 9, 22)), (0.55, (16, 27, 52)), (1, (34, 52, 98))],
                    [((255, 255, 255), (4, 14)), ((0, 0, 10), (14, 40))], WHITE, ((255, 240, 190), (255, 196, 92), (150, 60, 6)), (1, 4, 14), (255, 226, 140)),
    "aurora": ground("Aurora", "The app's aurora sky: near-black teal glowing green at the bottom.",
                     [(0, (3, 16, 22)), (0.55, (10, 60, 64)), (1, (28, 160, 132))],
                     [((255, 255, 255), (4, 16)), ((0, 10, 14), (14, 40))], WHITE, ((232, 255, 246), (150, 244, 212), (4, 66, 66)), (1, 16, 20), (200, 255, 236)),
    "cream": ground("Cream", "Warm paper, with an orange lettering edged in navy: the brand's three colours.",
                    [(0, (255, 250, 238)), (0.55, (255, 240, 214)), (1, (255, 226, 180))],
                    [((255, 255, 255), (30, 90)), ((255, 150, 50), (8, 22))], NIGHT, ((255, 168, 70), (255, 122, 26), NIGHT), (140, 92, 40), TANGERINE),
}
# One colour per frame, as Duolingo and Kahoot do it: the search trio then shows three colours.
RAINBOW = ["sky", "sun", "mint", "rose", "ocean", "sky", "sun", "mint"]
ORDER = ["sky", "sunrise", "mint", "ocean", "sun", "rose", "night", "aurora", "cream", "rainbow"]
NAMES = {k: THEMES[k]["name"] for k in THEMES}
NAMES["rainbow"] = "One colour per frame"
NOTES = {k: THEMES[k]["note"] for k in THEMES}
NOTES["rainbow"] = "Blue, yellow, green, pink, teal, then round again: every frame its own colour."


def theme_for(key, i):
    return THEMES[RAINBOW[i] if key == "rainbow" else key]


def render(key, i, out):
    """Frame i (0 to 7) of ground `key`, saved as <out>/<key>/NN.png."""
    d = os.path.join(out, key)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, f"{i + 1:02d}.png")
    gizmo_final.frame(i, theme_for(key, i)).save(path)
    return path


def _job(args):
    return render(*args)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--theme", default="all")
    ap.add_argument("--frames", default="1,2,3,4,5,6,7,8")
    ap.add_argument("--out", default=os.path.join(sk.LISTING, "gizmo-colours"))
    ap.add_argument("--jobs", type=int, default=3)
    a = ap.parse_args()
    keys = ORDER if a.theme == "all" else [k for k in a.theme.split(",") if k]
    frames = [int(n) - 1 for n in a.frames.split(",") if n]
    todo = [(k, i, a.out) for k in keys for i in frames]
    if a.jobs > 1:
        with ProcessPoolExecutor(a.jobs) as ex:
            for p in ex.map(_job, todo):
                print(p, flush=True)
    else:
        for t in todo:
            print(_job(t), flush=True)


if __name__ == "__main__":
    main()
