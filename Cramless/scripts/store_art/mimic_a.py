#!/usr/bin/env python3
"""Mimic styles 1 to 5 (shot_mimic.py): Quizlet, Gizmo, Kahoot!, Solvely, Photomath."""
from mimic_base import *  # noqa: F401,F403

# ======================================================================================================================== Quizlet

QZ_BG = [
    ((52, 84, 255), (96, 168, 255), (60, 206, 255)),
    ((150, 34, 212), (186, 84, 240), (232, 120, 255)),
    ((150, 34, 212), (186, 84, 240), (232, 120, 255)),
    ((112, 48, 196), (128, 70, 224), (30, 218, 176)),
    ((92, 30, 150), (190, 40, 156), (255, 100, 168)),
    ((70, 108, 255), (140, 176, 255), (20, 33, 61)),
]
QZ_COPY = [
    ["Be ready for", "exam day"], ["Answer in your", "own words"], ["See where", "you stand"], ["Turn pages into", "questions"],
    ["Ask Cap to make", "cards, quizzes", "and notes"], ["Catch what's", "on the exam"], ["Watch your", "memory light up"], ["Keep a calm,", "daily streak"],
]
YEL = (255, 226, 80)


@style("quizlet", "Quizlet", "quizlet",
       "A saturated colour per frame with a diagonal shard, a short white headline with a hand-drawn yellow doodle beside it, and the screen with no phone round it, running off the bottom.",
       "Brand blues, violets and mint instead of theirs; the panel is the app's own screen; the doodles are drawn here.")
def quizlet(i):
    top, bot, shard = QZ_BG[i % 6]
    c = mk.lin((W, H), [(0, top), (1, bot)], 80)
    if i % 2 == 0:
        mk.poly(c, [(W * 0.30, H), (W, H * 0.48), (W, H)], shard + (255,))
    else:
        mk.poly(c, [(0, H * 0.54), (W * 0.70, H), (0, H)], shard + (255,))
    lines = QZ_COPY[i]
    size = 112
    f = mk.sf(size, 700)
    yb = lines_block(c, lines, 210, size, WHITE, weight=700, pitch=1.16)
    lastw = mk.tw(lines[-1], f)
    rx, ry = W / 2 + lastw / 2 + 44, yb - size * 0.3
    k = i % 6
    if k == 0:
        mk.d_arrow(c, (rx + 6, ry - 52), (rx + 110, ry + 46), 44, YEL, 9, head=34, loop=True)
    elif k == 1:
        mk.d_sparkles(c, rx + 60, ry - 6, 84, YEL, 8)
    elif k == 2:
        mk.d_check(c, rx + 6, ry - 54, 100, YEL, 10)
    elif k == 3:
        mk.d_burst(c, rx + 64, ry + 12, 96, YEL, 9)
    elif k == 4:
        mk.d_squiggle(c, W / 2 - lastw / 2, yb + 46, lastw, YEL, 10, amp=11, waves=6)
    elif k == 5:
        mk.d_check(c, rx + 6, ry - 50, 96, YEL, 10, double=False)
    pw = 1040
    y0 = yb + size * 0.35 + 110
    pn = mk.panel(STORY[i]["shot"], pw, height=H - y0 + 20)
    put(c, pn, W / 2, y0 + pn.height / 2, blur=30, dy=18, alpha=0.18)
    return c.convert("RGB")


# ======================================================================================================================== Gizmo

GZ_COPY = [("Get ready for", "Exams"), ("Answer in your own", "Words"), ("Know your", "Readiness"), ("Snap pages into", "Questions"),
           ("Ask Cap for", "Cards"), ("Record", "Lectures"), ("Light up your", "Memory"), ("Keep your", "Streak")]


# One ground for the Gizmo frames: the gradient, the two pixel fields (colour, alpha range), the small line, the 3D word (face top, face
# bottom, edge), the shadow colour, the sparkles, the glow behind a button and a die-cut edge for Cap (0 for none). The purple is Gizmo's own;
# gizmo_colours.py has the others.
GZ_PURPLE = dict(bg=[(0, (26, 10, 96)), (0.55, (84, 24, 178)), (1, (140, 48, 214))],
                 pix=[((255, 255, 255), (5, 20)), ((20, 6, 70), (14, 40))], small=WHITE,
                 word=((255, 255, 255), (214, 196, 255), (56, 16, 150)), shadow=(30, 6, 90), spark=(255, 255, 255), glow=TANGERINE, cap_outline=0)


def gizmo_top(i, theme=None):
    """The ground, the small line, the giant word, Cap and the sparkles of a Gizmo frame: (canvas, bottom of the word, Cap's layer)."""
    t = theme or GZ_PURPLE
    c = mk.lin((W, H), t["bg"], 90)
    for seed, density, (col, alpha) in zip((7, 17), (0.5, 0.4), t["pix"]):
        mk.pixels(c, seed + i, (0, 0, W, 1500), col, size=72, density=density, alpha=alpha)
    small, word = GZ_COPY[i]
    d = ImageDraw.Draw(c)
    mk.draw(d, W / 2, 224, small, mk.sf(96, 800), t["small"], "ms")
    gw = mk.giant_word(word, 320, seed=3 + i, top=t["word"][0], bottom=t["word"][1], edge=t["word"][2])
    target = min(0.95, 0.52 + 0.06 * len(word)) * W
    k = target / gw.width
    if gw.height * k > 700:
        k = 700 / gw.height
    gw = gw.resize((int(gw.width * k), int(gw.height * k)), Image.LANCZOS)
    wtop = 270
    wbot = wtop + gw.height
    cp = cap(STORY[i]["cap"], 900)
    cy = wbot + 10 + cp.height / 2
    art = cap(STORY[i]["cap"], 900, outline=t["cap_outline"]) if t["cap_outline"] else cp
    put(c, art, W / 2, cy, blur=40, dy=30, alpha=0.30, colour=t["shadow"])
    put(c, gw, W / 2, wtop + gw.height / 2, shadow=False)
    # solid sparkles scattered round the title, never on its letters: each frame has its own scatter (its own seed) of sizes, turns and places
    line = Image.new("RGBA", (W, 330), (0, 0, 0, 0))
    mk.draw(ImageDraw.Draw(line), W / 2, 224, small, mk.sf(96, 800), (255, 255, 255, 255), "ms")
    title = [(line, 0, 0), (gw, W / 2 - gw.width / 2, wtop)]
    near = mk.coarse_mask((W, H), title, margin=30)
    ring = mk.coarse_mask((W, H), title, margin=290) & ~near
    occ = near | mk.coarse_mask((W, H), [(cp, W / 2 - cp.width / 2, cy - cp.height / 2)], margin=14, below=wbot + 10 + cp.height - 110)
    mk.random_sparkles(c, ring, occ, t["spark"], seed=1000 + 97 * i)
    return c, wbot, cp


@style("gizmo", "Gizmo", "gizmo",
       "One giant word of chunky 3D lettering under a small line, a bold object in front of it (here Cap), sparkles, and the screen with no phone, running off the bottom, on a purple pixel ground.",
       "Cap is the object instead of a rocket or a heart; the lettering is built here in Capling's own face; the ground is the app's dusk violet.")
def gizmo(i, theme=None):
    t = theme or GZ_PURPLE
    c, wbot, cp = gizmo_top(i, t)
    y0 = int(wbot + 10 + cp.height - 150)
    pn = mk.panel(STORY[i]["shot"], 1060, height=H - y0 + 20)
    put(c, pn, W / 2, y0 + pn.height / 2, blur=34, dy=20, alpha=0.30, colour=t["shadow"])
    return c.convert("RGB")


# ======================================================================================================================== Kahoot!

KH = [  # base, light shard, dark shard, ink
    ((91, 43, 208), (126, 78, 238), (62, 28, 156), WHITE),
    ((255, 176, 0), (255, 208, 70), (240, 140, 0), NIGHT),
    ((232, 38, 78), (255, 88, 120), (168, 20, 60), WHITE),
    ((59, 42, 158), (96, 70, 208), (40, 24, 118), WHITE),
    ((34, 195, 142), (88, 224, 176), (18, 140, 100), NIGHT),
    ((255, 122, 26), (255, 164, 76), (212, 90, 4), NIGHT),
]
KH_COPY = [
    ["Get ready for", "your exams in", "10 minutes a day"], ["Answer in your", "own words and", "get graded"], ["Check your", "readiness for", "every exam"],
    ["Turn your pages", "into questions", "checked by Cap"], ["Ask Cap to make", "cards, quizzes", "and notes"], ["Record lectures", "and catch what's", "on the exam"],
    ["Watch your", "memory sky", "light up"], ["Keep a daily", "streak without", "the guilt"],
]


@style("kahoot", "Kahoot!", "kahoot",
       "A flat saturated colour per frame with a lighter and a darker diagonal shard, a three-line bold white headline, and one whole phone, centred, the same size in every frame.",
       "Capling's brand colours (violet, sun, rose, mint, tangerine); the headline says what the screen shows; the phone is the app's own screen.")
def kahoot(i):
    base, light, dark, ink = KH[i % 6]
    c = Image.new("RGBA", (W, H), base + (255,))
    mk.poly(c, [(W * 0.42, 0), (W, 0), (W, H * 0.36)], light + (255,))
    mk.poly(c, [(0, H * 0.60), (W * 0.62, H), (0, H)], dark + (255,))
    mk.poly(c, [(W * 0.70, H), (W, H * 0.76), (W, H)], light + (255,))
    lines = KH_COPY[i]
    size = mk.fit(lines, W * 0.88, lambda s: mk.sf(s, 800), hi=124)
    yb = lines_block(c, lines, 150, size, ink, weight=800, pitch=1.18)
    ph = phone(STORY[i]["shot"], 860, frame=(10, 10, 14), rim=(60, 62, 70), bezel=30)
    top = max(int(yb + size * 0.5 + 100), 900)
    put(c, ph, W / 2, top + ph.height / 2, blur=40, dy=26, alpha=0.34, colour=(20, 10, 60))
    return c.convert("RGB")


# ======================================================================================================================== Solvely

SV_COPY = [["Know Your", "Exam Readiness"], ["Graded in Your", "Own Words"], ["See Your", "Projected Grade"], ["Scan Any Page,", "Get Questions"],
           ["Ask Cap to", "Draft Cards"], ["Smart Lecture", "Recorder"], ["Your Memory", "Sky"], ["Keep Your", "Daily Streak"]]
RED = (240, 60, 72)


@style("solvely", "Solvely", "solvely",
       "Royal blue, a big bold Title Case headline (left-aligned at first), a tilted phone running off the bottom, and stickers: a round badge, a grade, subject chips, a hand tag.",
       "The badge says something the app can back (checked against your page) instead of a user count; the grade is the projected one the app really shows.")
def solvely(i):
    c = mk.lin((W, H), [(0, (8, 60, 240)), (1, (32, 112, 255))], 90)
    sk.glow(c, W * 0.7, H * 0.6, 700, 900, (96, 164, 255), alpha=90, blur=300)
    lines = SV_COPY[i]
    left = i < 2
    size = mk.fit(lines, W * 0.84, lambda s: mk.sf(s, 800), hi=132)
    yb = lines_block(c, lines, 180, size, WHITE, weight=800, pitch=1.12, left=84 if left else None)
    ang = (-8, 7)[i] if i < 2 else 0
    pw = 1000 if i == 0 else 900
    ph = phone(STORY[i]["shot"], pw, frame=(14, 18, 34), rim=(100, 112, 150), bezel=24)
    y0 = int(yb + size * 0.4 + 120)
    px = W / 2 - 30 if i == 0 else 500 if i == 1 else W / 2
    put(c, ph, px, y0 + ph.height / 2, angle=ang, blur=44, dy=30, alpha=0.40, colour=(0, 10, 90))
    sh = dict(blur=22, dy=14, alpha=0.30, colour=(0, 10, 90))
    if i == 0:
        st = mk.sticker_round(450, (255, 207, 63), [("Checked", 0.12, 800), ("against your", 0.105, 700), ("own pages", 0.105, 700)], NIGHT, burst=16)
        put(c, st, 250, 2250, angle=-10, **sh)
    elif i == 1:
        for n, (t, col) in enumerate((("Bio 101", MINT), ("Chem 110", TANGERINE), ("AP Psychology", ROSE), ("Spanish II", SKY))):
            ch = chip(t, h=104, size=46, dot=col)
            put(c, ch, 1030 - n * 30, y0 + 300 + n * 170, angle=(-3, 2, -2, 3)[n], **sh)
    elif i == 2:
        st = mk.sticker_tag("A", 160, RED, WHITE, angle=10, pad=0.8, weight=900)
        put(c, st, 1020, y0 + 40, **sh)
        mk.d_sparkles(c, 1130, y0 - 50, 80, WHITE, 8)
    elif i == 3:
        put(c, mk.sticker_tag("Pages in, questions out", 60, (120, 224, 140), (14, 60, 36), angle=-5), 740, 2400, **sh)
    elif i == 4:
        put(c, mk.sticker_tag("Cap drafts, you decide", 60, SUN, NIGHT, angle=-4), 740, 2420, **sh)
    elif i == 5:
        put(c, mk.icon_tile(190, RED, "mic"), 1030, y0 + 60, **sh)
    elif i == 6:
        put(c, P("chip103", 560), 300, y0 + 330, angle=-4, **sh)
    elif i == 7:
        put(c, sk.medal(0, 400), 1050, y0 + 60, angle=8, **sh)
    return c.convert("RGB")


# ======================================================================================================================== Photomath

PM_COPY = [["Learn what's on", "your exam, a little", "every day"], ["Find the way to", "study that makes", "sense to you"], ["Take your time", "on every answer"], ["Feel confident", "on exam day!"],
           ["Turn photos of notes", "into questions"], ["Record, then catch", "what's on the exam"], ["Watch your memory", "light up"], ["Keep going, one", "short session at a time"]]
PM_BG = [((10, 77, 255), (255, 210, 31), (255, 143, 184)), ((255, 143, 184), (10, 77, 255), (255, 210, 31)), ((255, 143, 184), (10, 77, 255), (255, 210, 31)),
         ((10, 77, 255), (255, 210, 31), (255, 143, 184)), ((10, 77, 255), (255, 143, 184), (255, 210, 31)), ((255, 143, 184), (255, 210, 31), (10, 77, 255)),
         ((10, 77, 255), (255, 210, 31), (255, 143, 184)), ((255, 143, 184), (10, 77, 255), (255, 210, 31))]


@style("photomath", "Photomath", "photomath",
       "Blue and pink grounds cut with yellow and blue shards, halftone dots, black marker doodles, a white three-line headline, a tilted phone off the bottom and a cut-out figure with a white edge in front.",
       "The cut-out figure is Cap, in colour, with the die-cut edge the app's stickers have; the doodles are stars, rings and plus signs, drawn here.")
def photomath(i):
    base, s1, s2 = PM_BG[i]
    c = Image.new("RGBA", (W, H), base + (255,))
    mk.poly(c, [(W * 0.30, H), (W, H * 0.46), (W, H)], s1 + (255,))
    mk.poly(c, [(0, H * 0.40), (W * 0.52, H * 0.18), (W * 0.40, H * 0.34), (0, H * 0.58)], s2 + (255,))
    mk.halftone(c, (W * 0.62, H * 0.20, W, H * 0.62), (20, 20, 40), step=36, rmax=15, to="right", alpha=255)
    lines = PM_COPY[i]
    size = mk.fit(lines, W * 0.86, lambda s: mk.sf(s, 700), hi=116)
    yb = lines_block(c, lines, 170, size, WHITE, weight=700, pitch=1.16)
    mk.scribbles(c, 40 + i, (40, 900, 1250, 2600), 16, (20, 20, 40), 8, keep_out=[(150, 1000, 1140, 2700)])
    ang = (-9, 7, -6, 8, -7, 6, -8, 7)[i]
    ph = phone(STORY[i]["shot"], 860, frame=(20, 20, 30), rim=(90, 90, 110), bezel=24)
    top = max(int(yb + size * 0.5 + 100), 880)
    put(c, ph, W / 2 + (60 if ang < 0 else -60), top + 800, angle=ang, blur=40, dy=26, alpha=0.36, colour=(10, 10, 60))
    cp = cap(STORY[i]["cap"], 680, outline=20, flip=ang > 0)
    put(c, cp, 215 if ang < 0 else W - 215, H - cp.height / 2 + 70, blur=26, dy=18, alpha=0.30, colour=(10, 10, 60))
    return c.convert("RGB")
