#!/usr/bin/env python3
"""Capling's App Store screenshots in several designed looks, so the owner can pick one. Every look is drawn from the app itself: real
screens, real cards cut out of them, Cap's own art and lines, the six skies' own colours (shotkit.py). Nothing is painted by a model.

    python3 -P scripts/store_art/shot_looks.py [--look sunny,alive,night,skies,scrap,cap] [--frames 8] [--out DIR] [--only 1,2,3]

Output: <out>/<look>/NN.png (1290 x 2796, the 6.9-inch iPhone), <out>/<look>/sheet.png (all frames side by side, as the store shows
them) and <out>/<look>/trio.png (the first three: what search shows). The story is the same in every look:
  1 Ready on exam day.  2 Answer in your own words.  3 See where you stand.  4 Turn pages into questions.
  5 Ask Cap to make cards.  6 Catch what's on the exam.  7 Your memory, lit up.  8 Keep your streak going.
"""
import argparse
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import shotkit as sk  # noqa: E402
from shotkit import (W, H, NIGHT, DEEP, SKY, TANGERINE, SUN, MINT, ROSE, WHITE, font, headline, put, cap, phone, gradient,
                     glow, confetti, paste)  # noqa: E402

# One story in every look: the words (two lines), the capture the phone shows, Cap's pose and one of his own lines (CapLines.swift).
FRAMES = [
    dict(key="ready", lines=("Ready on", "exam day."), shot="today-eve", cap="plan", say=("Future you", "says thanks.")),
    dict(key="words", lines=("Answer in your", "own words."), shot="graded", cap="listen", say=("Say it in", "your own words.")),
    dict(key="stand", lines=("See where", "you stand."), shot="exam", cap="point", say=("Look right", "there.")),
    dict(key="pages", lines=("Turn pages", "into questions."), shot="capture-checking", cap="scan", say=("Pages in,", "questions out.")),
    dict(key="ask", lines=("Ask Cap to", "make cards."), shot="ask-cards", cap="ask", say=("Let's find", "out together.")),
    dict(key="lecture", lines=("Catch what's", "on the exam."), shot="lecture-notes", cap="mic", say=("Lecture time.", "I'm all ears.")),
    dict(key="sky", lines=("Your memory,", "lit up."), shot="sky-fill", cap="stargaze", say=("Every star is", "something you know.")),
    dict(key="streak", lines=("Keep your", "streak going."), shot="streak", cap="nice", say=("You're on", "a roll.")),
]

MARGIN = 92
SHADOW = dict(blur=38, dy=28, alpha=0.30)


def head_size(width=W - 2 * MARGIN, cap_size=176, path=sk.DISPLAY):
    """One size for every frame of a look: the biggest at which the widest line of the whole story fits."""
    return min(sk.fit_size(f["lines"], width, path, cap_size) for f in FRAMES)


def P(name, width):
    """A piece of the app, or None when its capture isn't there (yet)."""
    try:
        return sk.piece(name, width=width)
    except (KeyError, FileNotFoundError):
        return None


def lay(c, items, **shadow):
    """Place (layer, cx, cy, angle) items in order; a None layer (a piece that isn't captured) is skipped."""
    for it in items:
        layer, cx, cy, ang = it[:4]
        if layer is not None:
            put(c, layer, cx, cy, angle=ang, **(shadow or SHADOW))


# ---- layers made in code ---------------------------------------------------------------------------------------------------------------

def ring_card(frac, label, sub, colour, d=620, bg=WHITE, ink=NIGHT, sub_ink=sk.INK2, pad=60):
    """The readiness ring the app draws on its exam screen, drawn big: a track, an arc with round ends, the number and 'ready'."""
    n = d + 2 * pad
    k = 3
    im = Image.new("RGBA", (n * k, n * k), (0, 0, 0, 0))
    ImageDraw.Draw(im).rounded_rectangle((0, 0, n * k - 1, n * k - 1), int(n * 0.16 * k), fill=bg)
    im = im.resize((n, n), Image.LANCZOS)
    im.alpha_composite(sk.ring(d, frac, colour, (233, 239, 247), stroke=d * 0.115), (pad, pad))
    dd = ImageDraw.Draw(im)
    fn, pct = font(sk.DISPLAY, d * 0.30), font(sk.DISPLAY, d * 0.15)
    w, wp = sk.text_width(label, fn), sk.text_width("%", pct)
    x = pad + d / 2 - (w + wp) / 2
    dd.text((x, pad + d * 0.29), label, font=fn, fill=ink)
    dd.text((x + w + 4, pad + d * 0.29 + d * 0.13), "%", font=pct, fill=ink)
    sf = font(sk.ROUNDED, d * 0.085)
    dd.text((pad + d / 2 - sk.text_width(sub, sf) / 2, pad + d * 0.58), sub, font=sf, fill=sub_ink)
    return im


def chip(text, h=92, fill=WHITE, ink=NIGHT, size=None, pad=0.5, path=sk.ROUNDED, dot=None):
    """A small capsule of words, like the app's chips (dot: a coloured dot before the words)."""
    size = size or h * 0.42
    f = font(path, size)
    extra = h * 0.5 if dot else 0
    w = int(sk.text_width(text, f) + h * pad * 2 + extra)
    k = 3
    im = Image.new("RGBA", (w * k, h * k), (0, 0, 0, 0))
    ImageDraw.Draw(im).rounded_rectangle((0, 0, w * k - 1, h * k - 1), h * k // 2, fill=fill)
    im = im.resize((w, h), Image.LANCZOS)
    d = ImageDraw.Draw(im)
    x = h * pad
    if dot:
        d.ellipse((x, h / 2 - h * 0.13, x + h * 0.26, h / 2 + h * 0.13), fill=dot)
        x += h * 0.5
    d.text((x, h / 2), text, font=f, fill=ink, anchor="lm")
    return im


def speech(lines, size, **kw):
    return sk.bubble(lines, size, **kw)


def finish(c):
    return c.convert("RGB")


def hills(c, y, col_a, col_b, amp=70, seed=1, wl=1.2):
    sk._fill_ridge(c, sk._ridge(W, y, amp, seed, wl), col_a, col_b, H)


# ============================================================================================================================ A. Sunny

# Sunny: the cards that hang off the bottom of the phone and the one small piece off its corner.  (piece, cx, cy, width, angle)
SUNNY_CARDS = {
    "ready": [("examcard", 645, 2470, 960, -2)],
    "words": [("answer", 645, 2440, 940, 2), ("keyideas", 1110, 1265, 380, 6)],
    "stand": [("grade", 645, 2440, 960, -2), ("ring42", 190, 1340, 330, -6)],
    "pages": [("qrow", 645, 2430, 940, 2), ("scanpage", 150, 1420, 300, -7)],
    "ask": [("bubble", 645, 2440, 920, -2), ("askme", 960, 1280, 500, 4)],
    "lecture": [("examflag", 645, 2430, 960, -2)],
    "sky": [("relit", 645, 2400, 980, -1.5), ("chip103", 645, 2590, 700, 1)],
    "streak": [("medal2", 1110, 1340, 330, 8), ("medal0", 200, 2420, 400, -8), ("streakchip", 940, 2470, 330, 5)],
}


def sunny(i):
    """A. Sunny: the approved 'Ready on exam day.' poster's yellow, the words in navy with a pill, a real phone, and the app's own cards
    pulled out of the screen and set big where the phone runs off the page. Cap looks over the phone's shoulder."""
    f = FRAMES[i]
    c = gradient((W, H), (255, 240, 176), (255, 204, 58))
    glow(c, 1050, 330, 520, 420, (255, 255, 255), 120)
    hills(c, 2330, (88, 214, 160), (36, 168, 122), 60, i * 3 + 1)
    hills(c, 2520, (46, 178, 130), (24, 140, 100), 50, i * 3 + 2, 1.6)
    headline(c, f["lines"], 160, head_size(W - 2 * 130), (NIGHT, SUN), centre=W / 2, pill=(1, NIGHT), pitch=1.12)
    pw, cx, top = 860, W // 2, 1010
    ph = phone(f["shot"], pw)
    left = i % 2 == 1
    cp = cap(f["cap"], 440, flip=left)
    paste(c, cp, cx - pw / 2 + 50 if left else cx + pw / 2 - cp.width - 50, top - cp.height + 80)
    put(c, ph, cx, top + ph.height / 2, shadow=True, blur=46, dy=36, alpha=0.34)
    items = []
    for name, x, y, w, ang in SUNNY_CARDS[f["key"]]:
        if name == "ring42":
            layer = ring_card(0.42, "42", "ready", ROSE, d=int(w * 0.76), pad=int(w * 0.12))
        elif name == "ring78":
            layer = ring_card(0.78, "78", "ready", SUN, d=int(w * 0.76), pad=int(w * 0.12))
        elif name.startswith("medal"):
            layer = sk.medal(int(name[-1]), w)
        else:
            layer = P(name, w)
        items.append((layer, x, y, ang))
    lay(c, items)
    confetti(c, 40 + i, 30, (0, 0, W, 900), avoid=[(90, 150, 1200, 640)])
    return finish(c)


# ============================================================================================================================ B. Alive

def alive_ground(i):
    c = gradient((W, H), (84, 170, 244), (196, 232, 255))
    rnd = random.Random(30 + i)
    for _ in range(7):
        x, y = rnd.uniform(-100, W + 100), rnd.uniform(500, H - 100)
        glow(c, x, y, rnd.uniform(220, 420), rnd.uniform(70, 130), (255, 255, 255), alpha=rnd.randint(60, 120), blur=60)
    return c


def alive(i):
    """B. Alive: no phone. The app's own pieces, cut out of its screens and set big on a sky, each frame showing its feature happening
    (the way the Keepable set draws its swipe badges and album bubbles)."""
    f = FRAMES[i]
    c = alive_ground(i)
    headline(c, f["lines"], 150, head_size(), (NIGHT, NIGHT), left=MARGIN, highlight=(1, SUN), pitch=1.1)
    k = f["key"]
    sticker = lambda name, h, flip=False: cap(name, h, outline=14, flip=flip)
    if k == "ready":
        lay(c, [(P("hero", 1040), 640, 1210, -2), (P("eveexam", 1040), 690, 1925, 2.5), (P("tonight", 940), 590, 2230, -2),
                (sticker("plan", 520), 1040, 2500, 0)])
    elif k == "words":
        lay(c, [(P("question", 1040), 640, 1140, -2), (P("almost", 1130), 700, 2070, 2), (P("keyideas", 440), 1000, 700, 8)])
    elif k == "stand":
        lay(c, [(ring_card(0.42, "42", "ready", ROSE, d=560, pad=70), 440, 1130, -4), (sticker("point", 520, True), 1040, 1090, 0),
                (P("grade", 960), 680, 1800, 2.5), (P("progcard", 980), 600, 2330, -2)])
    elif k == "pages":
        lay(c, [(P("scanpage", 560), 350, 1190, -5), (P("qrow", 820), 810, 1340, 3), (P("info", 960), 640, 1850, -1.5),
                (P("steps", 900), 600, 2300, 1.5), (sticker("scan", 460), 1060, 2490, 0)])
    elif k == "ask":
        lay(c, [(P("proposal", 1030), 650, 1150, -2), (P("bubble", 900), 560, 1790, 2), (P("askme", 760), 820, 1990, -2),
                (P("examdraft", 860), 620, 2390, 2)])
    elif k == "lecture":
        lay(c, [(P("examflag", 1040), 650, 1010, -2), (P("transcript", 1000), 640, 1570, 2), (P("lectureinfo", 920), 600, 1990, -1.5),
                (sticker("mic", 560), 940, 2430, 0)])
    elif k == "sky":
        lay(c, [(P("chip103", 700), 560, 700, 2), (P("skywin", 880), 500, 1330, -2), (P("skysheet", 720), 870, 2040, 3),
                (P("relit", 980), 600, 2430, -1), (P("statrow", 900), 650, 2640, 1.5)])
    elif k == "streak":
        lay(c, [(P("calendar", 960), 600, 1230, -2), (sk.medal(2, 420), 250, 2080, -8), (sk.medal(0, 520), 650, 2060, 0),
                (sk.medal(1, 420), 1040, 2090, 8), (P("streakchip", 380), 900, 2520, 4), (sticker("nice", 400), 250, 2590, 0)])
    confetti(c, 70 + i, 26, (0, 480, W, H), avoid=[(60, 600, 1230, 2740)], size=(10, 22))
    return finish(c)


# ============================================================================================================================ C. Night panorama

_night = {}


def night_features():
    """The one sky behind all eight frames, as features at world coordinates (frame i starts at x = i * W): nebulae, star dust and
    constellations, some of them running across the edge between two frames."""
    if _night:
        return _night
    rnd = random.Random(11)
    world = W * 8
    _night["band"] = [(world * t / 14.0, 2300 - 1700 * t / 14.0 + rnd.uniform(-90, 90), rnd.uniform(520, 760), rnd.uniform(170, 260)) for t in range(15)]
    _night["neb"] = [(rnd.uniform(0, world), rnd.uniform(250, 2500), rnd.uniform(380, 760), rnd.uniform(260, 520),
                      rnd.choice([(108, 70, 168), (50, 100, 190), (170, 70, 140), (40, 150, 170)]), rnd.randint(34, 62)) for _ in range(26)]
    _night["dust"] = [(rnd.uniform(0, world), rnd.uniform(0, H), rnd.choice((1.5, 2, 2, 3, 3, 4.5)), rnd.randint(110, 255),
                       rnd.choice(((199, 222, 255), (255, 230, 194), (255, 255, 255)))) for _ in range(2600)]
    cons = []
    cols = [(110, 170, 255), SUN, ROSE, (120, 230, 190), (190, 160, 255)]
    for j in range(15):
        x, y = world * (j + 0.5) / 15 + rnd.uniform(-160, 160), rnd.uniform(700, 2560)
        nodes = [(x, y)]
        for _ in range(rnd.randint(4, 8)):
            ang = rnd.uniform(-1.2, 1.2) + (0 if rnd.random() < 0.7 else math.pi)
            x += math.cos(ang) * rnd.uniform(110, 240)
            y = min(2640, max(640, y + math.sin(ang) * rnd.uniform(90, 230)))
            nodes.append((x, y))
        cons.append((nodes, rnd.choice(cols)))
    _night["cons"] = cons
    return _night


def night_bg(i):
    n = night_features()
    c = gradient((W, H), (6, 11, 27), (26, 38, 96))
    x0 = i * W
    for x, y, rx, ry, col, a in n["neb"]:
        if x + rx > x0 - 200 and x - rx < x0 + W + 200:
            glow(c, x - x0, y, rx, ry, col, alpha=a, blur=min(rx, ry) * 0.7)
    for x, y, rx, ry in n["band"]:
        if x + rx > x0 - 200 and x - rx < x0 + W + 200:
            glow(c, x - x0, y, rx, ry, (150, 175, 255), alpha=34, blur=ry * 0.8)
    d = ImageDraw.Draw(c)
    for x, y, r, a, col in n["dust"]:
        if x0 - 10 <= x <= x0 + W + 10:
            d.ellipse((x - x0 - r, y - r, x - x0 + r, y + r), fill=col + (a,))
    for nodes, col in n["cons"]:
        if max(p[0] for p in nodes) < x0 - 40 or min(p[0] for p in nodes) > x0 + W + 40:
            continue
        pts = [(px - x0, py) for px, py in nodes]
        d.line(pts, fill=(255, 255, 255, 120), width=4)
        for px, py in pts:
            if -40 < px < W + 40:
                glow(c, px, py, 34, 34, col, alpha=150, blur=18)
                d.ellipse((px - 12, py - 12, px + 12, py + 12), fill=col + (255,))
                d.ellipse((px - 4.5, py - 4.5, px + 4.5, py + 4.5), fill=(255, 255, 255, 255))
    return c


NIGHT_CARD = {"ready": ("eveexam", 820), "words": ("answer", 820), "stand": ("grade", 820), "pages": ("info", 820), "ask": ("bubble", 800),
              "lecture": ("examflag", 800), "sky": ("chip103", 720), "streak": ("medal0", 340)}


def night(i):
    """C. Night: one sky across all eight frames (the first three read as one picture in search): the memory sky's stars and constellations
    run from frame to frame, the phones lean in turns over a warm glow, and one card of the app floats at each phone's foot."""
    f = FRAMES[i]
    c = night_bg(i)
    headline(c, f["lines"], 160, head_size(W - 2 * 100), (WHITE, SUN), centre=W / 2, pitch=1.1)
    ang = 5 if i % 2 == 0 else -5
    glow(c, W / 2, 1750, 560, 700, (255, 190, 90), alpha=70, blur=200)
    ph = phone(f["shot"], 860, frame=(8, 10, 18), rim=(125, 135, 168))
    put(c, ph, W / 2 + (30 if i % 2 == 0 else -30), 1010 + ph.height / 2 - 90, angle=ang, shadow=True, blur=50, dy=30, alpha=0.55)
    name, w = NIGHT_CARD[f["key"]]
    card = sk.medal(0, w) if name.startswith("medal") else P(name, w)
    if card is not None:
        put(c, card, W / 2 + (-90 if i % 2 == 0 else 90), 2470, angle=-ang * 0.6, blur=40, dy=26, alpha=0.5)
    return finish(c)


# ============================================================================================================================ D. Six skies

SKY_OF = ["night", "dusk", "glacier", "aurora", "bloom", "ember", "dusk", "night"]
ACCENT = {"night": (255, 207, 63), "dusk": (255, 170, 120), "glacier": (160, 230, 255), "aurora": (130, 255, 205), "bloom": (255, 190, 215),
          "ember": (255, 190, 90)}


def skies(i):
    """D. Six skies: each frame stands in one of the app's own skies (the ones a week of quests lights), the phone rising out of the
    hills, Cap on the near ridge with one of his own lines."""
    f = FRAMES[i]
    t = SKY_OF[i]
    c = sk.sky(t, horizon=0.70, seed=21 + i, part="back")
    headline(c, f["lines"], 160, head_size(W - 2 * 100), (WHITE, ACCENT[t]), centre=W / 2, pitch=1.1)
    ph = phone(f["shot"], 900, frame=(8, 10, 18), rim=(125, 135, 168))
    put(c, ph, W / 2, 800 + ph.height / 2, shadow=True, blur=40, dy=20, alpha=0.5)
    c.alpha_composite(sk.sky(t, horizon=0.70, seed=21 + i, part="front"))
    left = i % 2 == 0
    cp = cap(f["cap"], 540, flip=not left)
    cx = 215 if left else W - 215
    paste(c, cp, cx - cp.width / 2, 2500 - cp.height)
    b = speech(list(f["say"]), 48, tail="left" if left else "right")
    paste(c, b, 400 if left else W - 400 - b.width, 2420)
    return finish(c)


# ============================================================================================================================ E. Scrapbook

def paper(i):
    c = Image.new("RGBA", (W, H), (252, 247, 235, 255))
    d = ImageDraw.Draw(c)
    for x in range(30, W, 64):
        d.line((x, 0, x, H), fill=(184, 210, 236, 120), width=2)
    for y in range(30, H, 64):
        d.line((0, y, W, y), fill=(184, 210, 236, 120), width=2)
    rnd = np.random.default_rng(5 + i)
    g = (rnd.normal(0, 5, (H, W))).astype("int16")
    a = np.asarray(c).astype("int16")
    a[:, :, :3] = np.clip(a[:, :, :3] + g[:, :, None], 0, 255)
    return Image.fromarray(a.astype("uint8"), "RGBA")


def print_of(shot, width, crop=(0, 110, 1206, 2300), border=26, radius=22):
    """A screenshot printed out: white border, the crop of the screen."""
    s = sk.screen(shot).crop(crop)
    k = (width - 2 * border) / s.width
    s = s.resize((width - 2 * border, round(s.height * k)), Image.LANCZOS)
    out = Image.new("RGBA", (width, s.height + 2 * border), (0, 0, 0, 0))
    ImageDraw.Draw(out).rounded_rectangle((0, 0, out.width - 1, out.height - 1), radius, fill=(255, 255, 255, 255))
    out.paste(s, (border, border))
    return out


# per frame: the cards stuck beside the print (top to bottom), and the handwritten note
SCRAP = {
    "ready": ([("eveexam", 600), ("tonight", 560), ("quests", 580)], "42% to 78% in two days"),
    "words": ([("answer", 600), ("keyideas", 360), ("continue", 560)], "graded on your own words"),
    "stand": ([("grade", 620), ("progcard", 590), ("start", 560)], "an honest projection"),
    "pages": ([("scanpage", 380), ("qrow", 620), ("info", 590)], "every question cites p. 87"),
    "ask": ([("bubble", 590), ("examdraft", 590)], "you say yes, then it's added"),
    "lecture": ([("examflag", 620), ("lectureinfo", 590), ("transcript", 590)], "the lecturer's hints, starred"),
    "sky": ([("chip103", 560), ("relit", 620), ("skysheet", 580)], "every star is something you know"),
    "streak": ([("medal0", 360), ("streakchip", 320), ("quests", 590)], "twelve days and counting"),
}


def scrap(i):
    """E. Scrapbook: a study desk. Graph paper, the screen printed and taped down, the app's cards stuck on like notes, a highlighter
    stroke behind the key words, handwriting and an arrow in the margin, Cap as a sticker."""
    f = FRAMES[i]
    c = paper(i)
    headline(c, f["lines"], 150, head_size(W - 2 * MARGIN), (NIGHT, NIGHT), left=MARGIN, highlight=(1, (255, 224, 90)), pitch=1.1)
    side = 1 if i % 2 == 0 else -1
    pw = 640
    pr = print_of(f["shot"], pw)
    px = 60 + pw / 2 if side > 0 else W - 60 - pw / 2
    py = 700 + pr.height / 2
    ang = -3 * side
    put(c, pr, px, py, angle=ang, blur=26, dy=18, alpha=0.30, colour=(70, 50, 20))
    for dx in (-0.34, 0.34):
        t = sk.tape(220, 66, angle=(-28 if dx < 0 else 28) + ang)
        cx_, cy_ = dx * pw, -pr.height / 2 + 6
        a_ = math.radians(ang)
        rx = px + cx_ * math.cos(a_) + cy_ * math.sin(a_)
        ry = py - cx_ * math.sin(a_) + cy_ * math.cos(a_)
        paste(c, t, rx - t.width / 2, ry - t.height / 2)
    cards, note = SCRAP[f["key"]]
    y = 760
    for n, (name, w) in enumerate(cards):
        layer = sk.medal(0, w) if name.startswith("medal") else P(name, w)
        if layer is None or y > 2250:
            continue
        x = (W - 60 - w / 2) if side > 0 else (60 + w / 2)
        put(c, layer, x, y + layer.height / 2, angle=(3 if n % 2 == 0 else -3) * side, blur=24, dy=16, alpha=0.28, colour=(70, 50, 20))
        y += layer.height + 70
    cp = cap(f["cap"], 420, outline=14, flip=side < 0)
    paste(c, cp, 70 if side > 0 else W - 70 - cp.width, 2796 - cp.height - 40)
    nsz = 56
    while sk.text_width(note, font(sk.HAND, nsz)) > (W - 600 if side > 0 else W - 190) and nsz > 34:
        nsz -= 2
    nx = 560 if side > 0 else 110
    sk.scribble(c, note, (nx, 2600), nsz, angle=-3)
    if side > 0:
        sk.arrow(c, (nx + 120, 2580), (nx + 60, 2460), (nx + 200, 2380), (nx + 300, 2330))
    else:
        sk.arrow(c, (nx + 160, 2580), (nx + 200, 2470), (nx + 120, 2400), (nx + 60, 2340))
    return finish(c)


# ============================================================================================================================ F. Cap-led

CAP_GROUND = [SUN, MINT, SKY, (255, 128, 150), (176, 156, 255), TANGERINE, NIGHT, (255, 226, 120)]
CAP_CARD = {"ready": ("eveexam", 880), "words": ("answer", 900), "stand": ("grade", 900), "pages": ("info", 900), "ask": ("bubble", 860),
            "lecture": ("examflag", 900), "sky": ("chip103", 760), "streak": ("medal0", 460)}


def capled(i):
    """F. Cap-led: no phone. Cap, big, with one of his own lines in a bubble, one card of the app, and a flat colour of the brand's for
    each frame. The loudest thumbnail."""
    f = FRAMES[i]
    bg = CAP_GROUND[i]
    c = Image.new("RGBA", (W, H), bg + (255,))
    dark = sum(bg) < 330
    glow(c, W * 0.65, 2150, 760, 760, (255, 255, 255), alpha=70 if not dark else 18, blur=240)
    on_white = bg in (MINT, TANGERINE, (255, 128, 150), (176, 156, 255))
    head = (WHITE, SUN) if dark else (NIGHT, WHITE if on_white else NIGHT)
    headline(c, f["lines"], 150, head_size(), head, left=MARGIN, pitch=1.1, shadow=(0, 6, (20, 33, 61, 70)) if head[1] == WHITE else None)
    name, w = CAP_CARD[f["key"]]
    card = sk.medal(0, w) if name.startswith("medal") else P(name, w)
    if card is not None:
        put(c, card, MARGIN + w / 2 + 10, 740 + card.height / 2, angle=-3, blur=36, dy=26, alpha=0.30)
    cp = cap(f["cap"], 1260, outline=22)
    cx = W * 0.60
    cy = 2796 + 150 - cp.height / 2
    put(c, cp, cx, cy, shadow=True, blur=40, dy=30, alpha=0.30)
    b = speech(list(f["say"]), 64, tail="right")
    paste(c, b, cx - b.width + 170, cy - cp.height / 2 - b.height + 40)
    return finish(c)


# ============================================================================================================================ G. Lift

VERBS = [("Prepare", "for exam day"), ("Answer", "in your own words"), ("Check", "where you stand"), ("Capture", "pages into questions"),
         ("Ask", "Cap to make cards"), ("Record", "what's on the exam"), ("Light up", "your memory"), ("Keep", "your streak going")]
# the pieces lifted off the phone's own screen (their capture is the phone's), each with how much bigger than life
LIFTS = {
    "ready": [("eveexam", 1.14), ("tonight", 1.12)], "words": [("answer", 1.16), ("keyideas", 1.4)], "stand": [("grade", 1.14), ("start", 1.1)],
    "pages": [("scanpage", 1.1), ("steps", 1.12)], "ask": [("bubble", 1.14), ("proposal", 1.06)],
    "lecture": [("examflag", 1.16), ("lectureinfo", 1.12)], "sky": [("chip103", 1.35), ("legend", 1.35)], "streak": [("calendar", 1.1)],
}


def lift(i):
    """G. Lift: the leaders' formula (the way Scanbase's listing does it). One big verb and a line under it on a clean ground, a whole
    phone, and the card you'd tap lifted off the screen, bigger, in the exact place it sits."""
    f = FRAMES[i]
    verb, sub = VERBS[i]
    c = gradient((W, H), (255, 255, 255), (234, 243, 252))
    glow(c, 1000, 200, 560, 380, (255, 214, 140), alpha=70, blur=200)
    d = ImageDraw.Draw(c)
    vs = min(250, sk.fit_size([v for v, _ in VERBS], W - 2 * MARGIN, sk.DISPLAY, 250))
    d.text((MARGIN, 120), verb, font=font(sk.DISPLAY, vs), fill=NIGHT)
    d.text((MARGIN + 6, 120 + vs * 1.08), sub, font=font(sk.HEADING, vs * 0.4), fill=(217, 98, 8))
    pw, bezel = 940, 26
    left, top = (W - pw) // 2, 620
    ph = phone(f["shot"], pw)
    put(c, ph, W // 2, top + ph.height / 2, shadow=True, blur=46, dy=34, alpha=0.28)
    s_ = (pw - 2 * bezel) / sk.SCREEN_W
    for name, k in LIFTS[f["key"]]:
        cap_name, (x0, y0, x1, y1) = sk.PIECES[name][0], sk.PIECES[name][1]
        layer = P(name, int((x1 - x0) * s_ * k))
        if layer is None:
            continue
        put(c, layer, left + bezel + (x0 + x1) / 2 * s_, top + bezel + (y0 + y1) / 2 * s_, blur=34, dy=26, alpha=0.30)
    return finish(c)


# ============================================================================================================================ the page

LOOKS = {"sunny": sunny, "alive": alive, "lift": lift, "night": night, "skies": skies, "scrap": scrap, "cap": capled}


def trio(images, path, gap=60):
    w = sum(im.width for im in images) + gap * (len(images) - 1)
    sheet = Image.new("RGB", (w, images[0].height), (235, 235, 238))
    x = 0
    for im in images:
        sheet.paste(im, (x, 0))
        x += im.width + gap
    sheet.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--look", default="")
    ap.add_argument("--out", default=os.path.join(sk.LISTING, "looks"))
    ap.add_argument("--frames", type=int, default=8)
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    names = [n for n in LOOKS if not a.look or n in a.look.split(",")]
    only = [int(v) - 1 for v in a.only.split(",") if v] or list(range(a.frames))
    for name in names:
        d = os.path.join(a.out, name)
        os.makedirs(d, exist_ok=True)
        ims = []
        for i in only:
            im = LOOKS[name](i)
            im.save(os.path.join(d, f"{i + 1:02d}.png"))
            ims.append(im)
        if len(only) >= 3:
            trio(ims[:3], os.path.join(d, "trio.png"))
        trio(ims, os.path.join(d, "sheet.png"), gap=40)
        print(os.path.join(d, "sheet.png"))


if __name__ == "__main__":
    main()
