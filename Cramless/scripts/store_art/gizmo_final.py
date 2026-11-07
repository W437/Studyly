#!/usr/bin/env python3
"""The Gizmo set, finished: its first frame drawn from the app's own elements (three options) and its second without the verdict sheet.

    python3 -P scripts/store_art/gizmo_final.py [--pick a|b|c] [--out build/listing/gizmo] [--only ready-a,02,05]

Writes <out>/ready-a.png, ready-b.png, ready-c.png (the three first frames), then the set: 01.png (the pick), 02.png (answer in your own
words, a full-marks answer cut above the verdict sheet) and 03.png to 08.png (the Gizmo frames of mimic_a.py, unchanged).
The cards are cut from the app's own captures (shotkit.PIECES); nothing in them is drawn here.
"""
import argparse
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mimic_a  # noqa: E402
from mimic_a import mk, sk, W, H, put, WHITE  # noqa: E402

SH = dict(blur=34, dy=22, alpha=0.34, colour=(30, 6, 90))

SHEET_ROW = 1768      # in graded-full.png: the card's bottom edge; the verdict sheet starts a few rows below it
CTA_ICON = (60 + 332, 1368 + 36, 60 + 392, 1368 + 108)   # the sparkles in the Today capture's button; launch_set.py names its own


def card(name, width):
    return sk.piece(name, width=width)


def shadow(theme=None):
    """The soft shadow of a floating card on this ground."""
    return dict(SH, colour=(theme or mimic_a.GZ_PURPLE)["shadow"])


def start(i=0, theme=None):
    """The Gizmo ground, word and Cap of frame i, and the y where the elements may start (over Cap's feet a little)."""
    c, wbot, cp = mimic_a.gizmo_top(i, theme)
    return c, int(wbot + 10 + cp.height - 70)


def sparkles(c, spots, theme=None, seed=500):
    """A solid cluster at each spot, with its own random size, turn and make-up (so the frames' sparkles are never copies of each other)."""
    rng = random.Random(seed)
    for x, y, s in spots:
        mk.draw_cluster(c, x + rng.uniform(-24, 24), y + rng.uniform(-24, 24), s * 1.35 * rng.uniform(0.8, 1.25), mk.cluster_pattern(rng),
                        (theme or mimic_a.GZ_PURPLE)["spark"], rng.uniform(0.35, 0.65))


# ======================================================================================================================== the big button

def big_cta(width=1000, height=228, lip=18, text="Study \u00b7 15 min", size=96):
    """The app's own primary button (tangerine, Night label, raised lip) drawn larger. The label and the little sparkles icon are the
    app's (the icon is cut from its Today screen); only the size is new."""
    import numpy as np
    from PIL import Image, ImageDraw
    k = 3
    w, h, lp = width * k, height * k, lip * k
    im = Image.new("RGBA", (w, h + lp), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, lp, w - 1, h + lp - 1), h // 2, fill=sk.TANGERINE_EDGE)
    d.rounded_rectangle((0, 0, w - 1, h - 1), h // 2, fill=sk.TANGERINE)
    # the real icon: the dark glyph left of the label in the Today screen's button, as a mask
    real = sk._open("today").crop(CTA_ICON).convert("RGB")
    a = np.asarray(real).astype(float)
    fill, ink = np.array(sk.TANGERINE, float), np.array(sk.NIGHT, float)
    m = np.clip(np.abs(a - fill).sum(axis=2) / np.abs(ink - fill).sum(), 0, 1)
    ys, xs = np.where(m > 0.35)
    icon_m = Image.fromarray((m[ys.min():ys.max() + 1, xs.min():xs.max() + 1] * 255).astype("uint8"))
    f = mk.sf(size * k, 650)
    tw_ = mk.tw(text, f)
    ih = int(size * k * 0.80)
    iw = round(icon_m.width * ih / icon_m.height)
    icon_m = icon_m.resize((iw, ih), Image.LANCZOS)
    gap = int(size * k * 0.34)
    x0 = (w - (iw + gap + tw_)) / 2
    cy = h / 2
    glyph = Image.new("RGBA", icon_m.size, sk.NIGHT + (0,))
    glyph.putalpha(icon_m)
    im.alpha_composite(glyph, (int(x0), int(cy - ih / 2)))
    d.text((x0 + iw + gap, cy + size * k * 0.36), text, font=f, fill=sk.NIGHT, anchor="ls")
    return im.resize((width, height + lip), Image.LANCZOS)


# ======================================================================================================================== frame 1, three options

def ready_a(cta="big", theme=None):
    """The plan: what the app builds for the exam, the path to 90%, and the big button that starts the studying: the app's own 'Study
    \u00b7 15 min' drawn larger in its style ('big'), or its real pixels as 'study' (Today screen) or 'startplan' (plan screen)."""
    t = theme or mimic_a.GZ_PURPLE
    sh = shadow(t)
    c, y = start(0, t)
    big = cta == "big"
    y -= 100 if big else 30
    plan = card("plancard", 910 if big else 840)
    path = card("pathcard", 816 if big else 790)
    go = big_cta(width=1000, height=212, lip=16, size=94) if big else card(cta, 1160)
    put(c, plan, W / 2 - 40, y + plan.height / 2, angle=1.6, **sh)
    put(c, path, W / 2 + 56, y + plan.height - 26 + path.height / 2, angle=-2.0, **sh)
    yg = y + plan.height - 26 + path.height - (36 if big else 14) + go.height / 2
    sk.glow(c, W / 2, yg, 640, 160, t["glow"], alpha=80, blur=70)
    put(c, go, W / 2 + 6, yg, angle=0.8, **dict(sh, blur=30, dy=18, alpha=0.40))
    sparkles(c, [(1190, y + 30, 36), (90, y + plan.height + 70, 30), (1196, yg - 130, 30)], t)
    return c.convert("RGB")


def ready_b():
    """The countdown: the exam, ten minutes tonight, and where the readiness ends up."""
    c, y = start()
    prog = card("progcard", 1100)
    tonight = card("tonight", 740)
    done = card("examcard", 1050)
    put(c, prog, W / 2 - 20, y + prog.height / 2, angle=1.4, **SH)
    yb = y + prog.height + 84 + tonight.height / 2
    put(c, tonight, W / 2 + 150, yb, angle=-2.2, **SH)
    yc = yb + tonight.height / 2 + 84 + done.height / 2
    put(c, done, W / 2 + 4, yc, angle=-1.2, **SH)
    mk.d_arrow(c, (150, y + prog.height + 4), (322, yb - 6), -50, WHITE, 11, head=38)
    mk.d_arrow(c, (1150, yb + 56), (1112, yc - done.height / 2 - 14), 44, WHITE, 11, head=38)
    sparkles(c, [(1196, y + 14, 34), (96, yc + 80, 30)])
    return c.convert("RGB")


def ready_c():
    """Every kind of question: a pile of the app's own cards; each one shows its kind (the label line) above the next."""
    c, y = start()
    diagram = card("diagramcard", 760)
    cloze = card("clozecard", 830)
    mcq = card("mcqcard", 850)
    put(c, diagram, W / 2 - 24, y + diagram.height / 2, angle=-2.8, **SH)
    put(c, cloze, W / 2 + 10, y + 112 + cloze.height / 2, angle=2.2, **SH)
    put(c, mcq, W / 2 + 4, y + 226 + mcq.height / 2, angle=-0.8, **SH)
    sparkles(c, [(1190, y + 230, 34), (92, y + 90, 30)])
    return c.convert("RGB")


READY = {"a": ready_a, "b": ready_b, "c": ready_c}


# ======================================================================================================================== frame 2

def words(theme=None):
    """Answer in your own words: a full-marks answer, graded on the phone, cut above the verdict sheet so nothing covers the card."""
    t = theme or mimic_a.GZ_PURPLE
    c, wbot, cp = mimic_a.gizmo_top(1, t)
    k = 1060 / 1206
    pn = mk.panel("graded-full", 1060, height=round((SHEET_ROW - 152) * k))
    y0 = H - pn.height + 20
    put(c, pn, W / 2, y0 + pn.height / 2, blur=34, dy=20, alpha=0.30, colour=t["shadow"])
    return c.convert("RGB")


def frame(i, theme=None):
    """Frame i (0 to 7) of the finished set on the given ground (default: Gizmo's purple)."""
    if i == 0:
        return ready_a(theme=theme)
    if i == 1:
        return words(theme)
    return mimic_a.gizmo(i, theme)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pick", default="a", choices=sorted(READY))
    ap.add_argument("--out", default=os.path.join(sk.LISTING, "gizmo"))
    ap.add_argument("--only", default="", help="comma list of ready-a, ready-b, ready-c, 01 .. 08")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    only = {s for s in a.only.split(",") if s}
    jobs = {f"ready-{k}": fn for k, fn in READY.items()}
    jobs["01"] = READY[a.pick]
    jobs["02"] = words
    for i in range(2, 8):
        jobs[f"{i + 1:02d}"] = (lambda n: lambda: mimic_a.gizmo(n))(i)
    for name, fn in jobs.items():
        if only and name not in only:
            continue
        fn().save(os.path.join(a.out, f"{name}.png"))
        print(os.path.join(a.out, f"{name}.png"))


if __name__ == "__main__":
    main()
