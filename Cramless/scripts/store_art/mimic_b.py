#!/usr/bin/env python3
"""Mimic styles 6 to 15 (shot_mimic.py): Knowt, AnkiMobile, Brainscape, Gauth, StudyFetch, Turbo AI, Coconote, Knowunity, Duolingo, Brilliant."""
from mimic_base import *  # noqa: F401,F403

INK = (34, 38, 58)


def sfw(weight, width=100):
    return lambda s: mk.sf(s, weight, width)


def nyw(weight, italic=False):
    return lambda s: mk.ny(s, weight, italic)


# ======================================================================================================================== Knowt

KN = [  # background top, bottom, accent
    ((218, 246, 236), (250, 255, 253), MINT), ((224, 236, 255), (250, 252, 255), (70, 120, 240)), ((236, 226, 255), (252, 250, 255), (140, 96, 230)),
    ((255, 228, 238), (255, 251, 253), ROSE), ((255, 236, 216), (255, 252, 248), TANGERINE), ((214, 244, 250), (250, 255, 255), (30, 176, 200)),
    ((232, 232, 255), (252, 252, 255), (100, 100, 236)), ((255, 244, 208), (255, 253, 244), (236, 166, 16)),
]
KN_COPY = [
    ["The calm way to get", "ready for your exams,", "10 minutes a day"], ["Answer in your own", "words and see what", "you nailed and missed"],
    ["See how ready you are", "for every exam, in", "plain numbers"], ["Turn photos of notes", "into questions checked", "against your pages"],
    ["Ask Cap to draft cards,", "quizzes and notes, you", "decide what stays"], ["Record a lecture and", "catch every hint about", "what's on the exam"],
    ["Watch your memory", "light up, one star", "at a time"], ["Keep a daily streak", "with nothing to lose"],
]


@style("knowt", "Knowt", "knowt",
       "A pastel gradient per frame (mint, blue, lavender, pink), a medium-weight charcoal headline in plain words, one thin pen doodle in an accent colour, and a big whole phone running off the bottom.",
       "Capling's own tints for the pastels, the accent colours from the app, and sentences about what the screen shows.")
def knowt(i):
    top, bot, acc = KN[i]
    c = mk.lin((W, H), [(0, top), (0.6, bot)], 90)
    lines = KN_COPY[i]
    size = mk.fit(lines, W * 0.80, sfw(600), hi=92)
    f = mk.sf(size, 600)
    yb = lines_block(c, lines, 160, size, INK, weight=600, pitch=1.2, left=96)
    lastw = mk.tw(lines[-1], f)
    dx, dy = 96 + lastw + 54, yb - size * 0.3
    if i == 0:
        mk.d_arrow(c, (dx, dy - 30), (dx + 110, dy + 54), 46, acc, 7, head=30)
    elif i == 1:
        mk.d_loops(c, 96, yb + 40, 360, acc, 7, loops=3)
    elif i == 2:
        mk.d_sparkles(c, dx + 50, dy - 10, 84, acc, 7)
    elif i == 3:
        mk.d_squiggle(c, 96, yb + 44, min(lastw, 520), acc, 7)
    elif i == 4:
        mk.d_star(c, dx + 40, dy - 10, 46, acc, 7)
    elif i == 5:
        mk.d_spiral(c, dx + 46, dy, 50, acc, 7)
    elif i == 6:
        mk.d_star(c, dx + 40, dy - 6, 44, acc, 7)
    else:
        mk.d_check(c, dx, dy - 50, 96, acc, 8)
    ph = phone(STORY[i]["shot"], 1010, frame=(16, 16, 22), rim=(58, 60, 72), bezel=26)
    y0 = yb + size * 0.4 + 120
    put(c, ph, W / 2, y0 + ph.height / 2, blur=40, dy=26, alpha=0.20)
    return c.convert("RGB")


# ======================================================================================================================== AnkiMobile

AN_COPY = [
    "Every exam gets a readiness score, built from what you actually remember.",
    "Answers are graded in your own words. See what you nailed and what's missing.",
    "A projected grade for exam day, honestly labelled as a projection.",
    "Take a photo of your notes. Questions are written and checked against the page.",
    "Ask Cap for cards, quizzes or notes. Nothing is added until you say yes.",
    "Record lectures. Anything the lecturer says will be on the exam is starred.",
    "Your memory as a sky: every star is something you know, dimming as you forget.",
    "A daily streak with no lives, no timers and nothing to lose.",
]


@style("anki", "AnkiMobile", "anki",
       "Plain paper, one plain sentence in the system font on top, and the real screenshot, unframed with square corners, filling the page. No decoration at all.",
       "Capling's own sentences (what the screen does, in one line); the paper is drawn here. The least designed of the fifteen, kept for the contrast.")
def anki(i):
    rng = np.random.default_rng(300 + i)
    base = np.zeros((H, W, 4), "int16")
    base[..., :3] = np.array((238, 233, 222)) + rng.normal(0, 3.2, (H, W, 1)).astype("int16")
    base[..., 3] = 255
    c = Image.fromarray(np.clip(base, 0, 255).astype("uint8"), "RGBA")
    f = mk.sf(70, 400)
    lines = wrap(AN_COPY[i], f, W * 0.84)
    d = ImageDraw.Draw(c)
    y = 190
    for ln in lines:
        mk.draw(d, W / 2, y, ln, f, (20, 20, 20), "ms")
        y += 92
    s = sk.screen(STORY[i]["shot"]).convert("RGBA")
    k = 1110 / s.width
    s = s.resize((1110, round(s.height * k)), Image.LANCZOS)
    y0 = int(y + 60)
    ImageDraw.Draw(c).rectangle((90 - 3, y0 - 3, 90 + 1110 + 2, y0 + s.height + 2), fill=(170, 164, 150, 255))
    paste(c, s, 90, y0)
    return c.convert("RGB")


# ======================================================================================================================== Brainscape

BS_COPY = [("Be ready on", "exam day"), ("Answers graded in", "your own words"), ("See where", "you stand"), ("Pages in,", "questions out"),
           ("Let Cap draft", "your cards"), ("Catch what's", "on the exam"), ("Watch your", "memory light up"), ("A calm streak", "you can keep")]


@style("brainscape", "Brainscape", "brainscape",
       "Near-black navy, a heavy white two-line headline, a phone with a thick white bezel running off the bottom, and one floating object or card in front of it.",
       "The ground is the app's night blue; the floating pieces are real cards from the app. Their laurel of user counts is left out: no numbers the app can't back.")
def brainscape(i):
    c = mk.lin((W, H), [(0, (18, 26, 48)), (1, (10, 14, 28))], 90)
    sk.glow(c, W / 2, 1500, 760, 620, (40, 70, 150), alpha=70, blur=260)
    l1, l2 = BS_COPY[i]
    size = mk.fit([l1, l2], W * 0.84, sfw(800), hi=118)
    yb = lines_block(c, [l1, l2], 170, size, WHITE, weight=800, pitch=1.12)
    pw = 880
    ph = phone(STORY[i]["shot"], pw, frame=(255, 255, 255), rim=(255, 255, 255), bezel=30)
    y0 = int(yb + size * 0.4 + 140)
    ang = -5 if i % 2 else 0
    put(c, ph, W / 2, y0 + ph.height / 2, angle=ang, blur=44, dy=30, alpha=0.5, colour=(0, 0, 10))
    sh = dict(blur=34, dy=24, alpha=0.5, colour=(0, 0, 10))
    if i == 0:
        put(c, cap("plan", 620, outline=0), 210, H - 330, **sh)
    elif i == 1:
        put(c, P("answer", 720), 330, y0 + 760, angle=-4, **sh)
    elif i == 2:
        put(c, ring_card(0.42, "42", "ready", ROSE, d=250, pad=44), 1030, y0 + 430, angle=6, **sh)
    elif i == 3:
        for n, (g, col) in enumerate((("page", TANGERINE), ("mic", ROSE), ("cards", (122, 63, 208)), ("chat", SKY), ("star", MINT))):
            put(c, mk.icon_tile(190, col, g), 150 + n * 250, y0 - 60 + (40 if n % 2 else 0), angle=(-8, 6, -4, 8, -6)[n], **sh)
    elif i == 4:
        put(c, P("askme", 700), 900, y0 + 80, angle=4, **sh)
    elif i == 5:
        put(c, P("examflag", 700), 400, y0 + 820, angle=-3, **sh)
    elif i == 6:
        put(c, P("chip103", 660), W / 2, y0 + 60, angle=0, **sh)
    else:
        put(c, sk.medal(0, 380), 1040, y0 + 900, angle=8, **sh)
    return c.convert("RGB")


# ======================================================================================================================== Gauth

GA_COPY = [("All-in-One", "Exam Coach"), ("Smart", "Own-Words Grading"), ("Honest", "Grade Projection"), ("Instant", "Page Scanner"),
           ("Ask Cap", "Anything"), ("Smart", "Lecture Recorder"), ("Visual", "Memory Sky"), ("Calm", "Daily Streak")]
GA_NOTE = ["Checked against your pages", "Graded on your own words", "A projection, not a promise", "Every question cites its page",
           "Cap drafts, you decide", "Hints from the lecturer, starred", "Every star is something you know", "Nothing to lose"]


@style("gauth", "Gauth", "gauth",
       "A soft pastel ground with blurred colour, a two-tone headline (black over a coral-to-violet gradient), a pale glass phone that fades out at the bottom, and floating frosted chips.",
       "The gradient is Capling's tangerine to rose to violet; the chips are real cards and honest claims; the student's photo is Cap, and the A is the projected grade.")
def gauth(i):
    if i == 0:
        c = mk.lin((W, H), [(0, (255, 150, 110)), (0.5, (240, 120, 170)), (1, (140, 120, 255))], 70)
    else:
        c = mk.lin((W, H), [(0, (252, 249, 255)), (1, (244, 240, 255))], 90)
        mk.blobs(c, 50 + i, 5, [(255, 190, 210), (200, 190, 255), (255, 220, 190), (190, 230, 255)], rx=(260, 480), ry=(200, 360), alpha=(60, 110))
    l1, l2 = GA_COPY[i]
    size = mk.fit([l1, l2], W * 0.86, sfw(800), hi=140)
    f = mk.sf(size, 800)
    d = ImageDraw.Draw(c)
    y1 = 170 + size * 0.76
    mk.draw(d, W / 2, y1, l1, f, WHITE if i == 0 else (20, 20, 28), "ms")
    if i:
        mk.gradient_text(c, l2, f, W / 2, y1 + size * 1.1, [(0, TANGERINE), (0.5, (255, 90, 120)), (1, (176, 90, 255))], "ms")
    else:
        mk.draw(d, W / 2, y1 + size * 1.1, l2, f, WHITE, "ms")
    yb = y1 + size * 1.1
    y0 = int(yb + size * 0.4 + 120)
    if i == 0:
        cp = cap("proud", 1350)
        put(c, cp, W / 2, H - cp.height / 2 + 120, blur=44, dy=30, alpha=0.30, colour=(90, 40, 140))
        put(c, mk.sticker_tag("A", 200, (240, 60, 72), WHITE, angle=-8, pad=0.8, weight=900), 1000, y0 + 200, blur=26, dy=18, alpha=0.30, colour=(90, 40, 140))
    else:
        ph = phone(STORY[i]["shot"], 900, frame=(246, 243, 252), rim=(255, 255, 255), bezel=24)
        ph = mk.fade_bottom(ph, 0.50, 1.0, 0.0)
        put(c, ph, W / 2, y0 + ph.height / 2, shadow=False)
        sh = dict(blur=34, dy=24, alpha=0.18, colour=(110, 80, 180))
        if i == 1:
            put(c, P("keyideas", 440), 1010, y0 + 360, angle=5, **sh)
        elif i == 2:
            put(c, mk.sticker_tag("A", 170, (240, 60, 72), WHITE, angle=8, pad=0.8, weight=900), 1040, y0 + 140, **sh)
        elif i == 3:
            put(c, P("scanpage", 380), 1030, y0 + 330, angle=6, **sh)
        elif i == 4:
            put(c, P("askme", 540), 960, y0 + 300, angle=4, **sh)
        elif i == 5:
            put(c, P("examflag", 760), 640, y0 + 760, angle=-2, **sh)
        elif i == 6:
            put(c, P("chip103", 560), 640, y0 + 140, **sh)
        else:
            put(c, sk.medal(0, 380), 1030, y0 + 420, angle=8, **sh)
    note = GA_NOTE[i]
    nf = mk.sf(52, 600)
    nw = int(mk.tw(note, nf) + 150)
    box = (W / 2 - nw / 2, 2480, W / 2 + nw / 2, 2480 + 128)
    mk.glass(c, box, 64, tint_rgb=(255, 255, 255), amount=0.55, blur=30, border=0.9, shadow=0.14, shadow_rgb=(110, 80, 180))
    c.alpha_composite(mk.icon_tile(76, TANGERINE, "check"), (int(box[0] + 28), int(box[1] + 26)))
    mk.draw(ImageDraw.Draw(c), box[0] + 124, box[1] + 64 + 2, note, nf, (26, 26, 40), "lm")
    return c.convert("RGB")


# ======================================================================================================================== StudyFetch

SF_COPY = [["Studying that", "*fits your exam*"], ["Every answer graded", "in *your own words*"], ["See *exactly where*", "you stand"],
           ["Turn your pages into", "*checked questions*"], ["Ask Cap for cards,", "*you decide* what stays"], ["Record lectures, catch", "*what's on the exam*"],
           ["Watch your memory", "*light up*"], ["Keep a streak with", "*nothing to lose*"]]


@style("studyfetch", "StudyFetch", "studyfetch",
       "A photographed sky or a pastel solid, a serif headline with italic emphasis, and one phone, centred and smaller, with the person standing in front of the sky.",
       "The sky is drawn here, not photographed; Cap stands where their person does; the serif is New York, the system serif.")
def studyfetch(i):
    pink = (i % 3 == 2)
    if pink:
        c = mk.lin((W, H), [(0, (248, 214, 248)), (1, (236, 196, 250))], 90)
        ink = em = (30, 24, 70)
    else:
        c = mk.cloud_sky((W, H), seed=3 + i, top=(26, 100, 204), bottom=(150, 206, 248), coverage=0.42, clear_top=0.85)
        ink = em = WHITE
    size = 112
    yb = lines_rich(c, SF_COPY[i], 190, size, nyw(500), nyw(500, True), ink, em, pitch=1.16)
    y0 = int(yb + size * 0.4 + 150)
    if i == 0:
        cp = cap("scan", 1300)
        put(c, cp, W / 2, H - cp.height / 2 + 150, blur=44, dy=30, alpha=0.30, colour=(10, 30, 80))
    else:
        ph = phone(STORY[i]["shot"], 880, frame=(14, 14, 18), rim=(70, 70, 80), bezel=24)
        put(c, ph, W / 2, y0 + ph.height / 2, blur=44, dy=30, alpha=0.30, colour=(10, 30, 80))
        left = i % 2 == 0
        cp = cap(STORY[i]["cap"], 640, outline=0, flip=not left)
        put(c, cp, 190 if left else W - 190, H - cp.height / 2 + 80, blur=34, dy=24, alpha=0.30, colour=(10, 30, 80))
    return c.convert("RGB")


# ======================================================================================================================== Turbo AI

TB_COPY = ["Ready on exam day", "Graded in your own words", "See where you stand", "Pages in. Questions out.", "Ask Cap to draft cards",
           "Catch what's on the exam", "Watch your memory light up", "Keep your streak going"]
VIO = (136, 84, 255)


@style("turbo", "Turbo AI", "turbo-ai",
       "Near-black violet, bold white captions (at the top, or at the bottom under a cropped phone), and everything outlined in a glowing purple neon line.",
       "The neon is violet and sky blue, the colours of the app's night; the cards are real pieces of its screens.")
def turbo(i):
    c = mk.lin((W, H), [(0, (14, 8, 30)), (1, (8, 5, 18))], 90)
    sk.glow(c, W / 2, 1750, 760, 900, (88, 40, 220), alpha=70, blur=280)
    size = 104
    f = mk.sf(size, 700)
    lines = wrap(TB_COPY[i], f, W * 0.84)
    at_bottom = i in (2, 5)
    top_y = H - 170 - size * 1.14 * len(lines) if at_bottom else 170
    yb = lines_block(c, lines, top_y, size, WHITE, weight=700, pitch=1.14)
    if i == 3:
        a, b = P("scanpage", 640), P("qrow", 960)
        ax, ay = W / 2, int(yb + 150)
        mk.neon(c, (ax - a.width / 2 - 6, ay - 6, ax + a.width / 2 + 6, ay + a.height + 6), 50, SKY, width=7)
        put(c, a, ax, ay + a.height / 2, shadow=False)
        by = ay + a.height + 120
        mk.neon(c, (W / 2 - b.width / 2 - 6, by - 6, W / 2 + b.width / 2 + 6, by + b.height + 6), 90, VIO, width=7)
        put(c, b, W / 2, by + b.height / 2, shadow=False)
        return c.convert("RGB")
    pw = 880 if at_bottom else 1000
    ph = phone(STORY[i]["shot"], pw, frame=(6, 6, 10), rim=(30, 30, 40), bezel=22)
    y0 = 190 if at_bottom else max(int(yb + size * 0.4 + 190), 540)
    x0 = (W - pw) // 2
    mk.neon(c, (x0 - 6, y0 - 6, x0 + pw + 6, y0 + ph.height + 6), int(pw * 0.13) + 6, VIO if i % 2 == 0 else SKY, width=7)
    put(c, ph, W / 2, y0 + ph.height / 2, shadow=False)
    return c.convert("RGB")


# ======================================================================================================================== Coconote

PURPLE = (124, 58, 237)
PINK = (236, 72, 153)
CC = [
    (["Never miss", "what's on", "the *exam*"], PURPLE), (["Graded in", "*your own words*"], PINK), (["See *exactly*", "where you stand"], PURPLE),
    (["Capture from"], PURPLE), (["Ask Cap, then", "*you decide*"], PINK), (["Hear every hint", "about *the exam*"], PURPLE),
    (["Watch your memory", "*light up*"], PINK), (["A streak with", "*nothing to lose*"], PURPLE),
]
CC_LIST = ["Photos", "PDFs", "Lectures", "Pasted text", "Anki decks", "Quizlet sets"]


@style("coconote", "Coconote", "coconote",
       "A warm cream ground, very large dark headlines with the key words in purple or pink, a checklist with round check marks, and a phone held low and cropped.",
       "The check list names only inputs the app takes (photos, PDFs, lectures, pasted text, Anki, Quizlet); no review quotes or ratings.")
def coconote(i):
    c = mk.lin((W, H), [(0, (247, 244, 238)), (1, (240, 236, 229))], 90)
    lines, acc = CC[i]
    ink = (22, 20, 30)
    big = i in (0, 3)
    size = mk.fit(["".join(t for t, _ in mk.parse_rich(l)) for l in lines], W * (0.84 if big else 0.86), sfw(800), hi=200 if big else 150)
    reg, emf = sfw(800), sfw(800)
    left = 84 if (big or i == 1) else None
    yb = lines_rich(c, lines, 150, size, reg, emf, ink, acc, left=left, pitch=1.06)
    y0 = int(yb + size * 0.4 + 110)
    if i == 3:
        d = ImageDraw.Draw(c)
        iy = yb + 150
        for n, t in enumerate(CC_LIST):
            cy = iy + n * 150
            d.ellipse((90, cy - 38, 166, cy + 38), outline=acc + (255,), width=7)
            mk.d_check(c, 104, cy - 26, 48, acc, 8, double=False)
            mk.draw(d, 196, cy + 24, t, mk.sf(68, 700), ink, "ls")
        ph = phone(STORY[i]["shot"], 740, frame=(16, 16, 22), rim=(58, 60, 72), bezel=24)
        put(c, ph, 1090, 560 + ph.height / 2, blur=40, dy=26, alpha=0.20)
        put(c, cap("scan", 760, outline=0), 330, H - 380, blur=30, dy=20, alpha=0.24)
        return c.convert("RGB")
    pw = 860 if big else 900
    ph = phone(STORY[i]["shot"], pw, frame=(16, 16, 22), rim=(58, 60, 72), bezel=24)
    px = W / 2 + (180 if big else 0)
    put(c, ph, px, y0 + ph.height / 2, blur=40, dy=26, alpha=0.20)
    if i == 2:
        put(c, mk.sticker_tag("A", 170, (240, 60, 72), WHITE, angle=8, pad=0.8, weight=900), 1050, y0 + 130, blur=24, dy=16, alpha=0.24)
    elif i == 4:
        put(c, cap("ask", 520, outline=0), 215, H - 290, blur=30, dy=20, alpha=0.24)
    elif i == 7:
        put(c, sk.medal(0, 380), 1090, H - 330, angle=8, blur=26, dy=18, alpha=0.26)
    return c.convert("RGB")


# ======================================================================================================================== Knowunity

KU_COPY = [("Be ready", "on exam day"), ("Graded in your", "own words"), ("Understand", "where you stand"), ("Turn pages into", "checked questions"),
           ("Ask Cap", "for anything"), ("Never miss", "what's on the exam"), ("Watch your", "memory light up"), ("A calm streak", "you can keep")]
KU_ROWS = {
    2: [("Readiness for every exam", "bolt", TANGERINE), ("A projected grade", "star", SUN), ("A plan that bends", "check", MINT), ("Weak spots first", "sky", SKY)],
    4: [("Flashcards", "cards", TANGERINE), ("Quizzes", "check", MINT), ("Notes", "page", SKY), ("Exam plans", "star", ROSE)],
    5: [("A live transcript", "mic", ROSE), ("The lecturer's hints, starred", "star", SUN), ("Notes from the recording", "page", SKY), ("Recording survives a crash", "bolt", MINT)],
}


@style("knowunity", "Knowunity", "knowunity",
       "A deep violet gradient with soft light, a bold white two-line headline, frosted-glass rows with glossy icon tiles (or a tilted phone with glass chips), and Cap beside them.",
       "The glass rows list real features of the app; their laurels (awards, number one) are left out: nothing the app can't back.")
def knowunity(i):
    c = mk.lin((W, H), [(0, (36, 14, 104)), (0.55, (70, 30, 170)), (1, (110, 56, 214))], 70)
    mk.blobs(c, 90 + i, 6, [(150, 90, 255), (90, 60, 230), (200, 120, 255)], rx=(300, 520), ry=(220, 380), alpha=(60, 110))
    l1, l2 = KU_COPY[i]
    size = mk.fit([l1, l2], W * 0.84, sfw(800), hi=124)
    yb = lines_block(c, [l1, l2], 170, size, WHITE, weight=800, pitch=1.12)
    y0 = int(yb + size * 0.4 + 120)
    if i in KU_ROWS:
        f = mk.sf(58, 700)
        for n, (label, g, col) in enumerate(KU_ROWS[i]):
            by = y0 + 40 + n * 262
            mk.glass(c, (90, by, W - 90, by + 204), 70, tint_rgb=(255, 255, 255), amount=0.20, blur=30, border=0.5, shadow=0.22, shadow_rgb=(20, 0, 80))
            c.alpha_composite(mk.icon_tile(140, col, g), (126, by + 32))
            mk.draw(ImageDraw.Draw(c), 306, by + 102 + 2, label, mk.sf(64, 700), WHITE, "lm")
        cp = cap(STORY[i]["cap"], 900)
        put(c, cp, W - 270, H - cp.height / 2 + 90, blur=34, dy=24, alpha=0.4, colour=(10, 0, 50))
        return c.convert("RGB")
    ang = -7 if i % 2 == 0 else 7
    ph = phone(STORY[i]["shot"], 900, frame=(10, 8, 24), rim=(120, 110, 180), bezel=24)
    put(c, ph, W / 2, y0 + ph.height / 2, angle=ang, blur=44, dy=30, alpha=0.5, colour=(10, 0, 50))
    note = ("Checked against your pages", "Graded on your own words", None, "Every question cites its page", None, None, "Every star is something you know", "Nothing to lose")[i]
    if note:
        nf = mk.sf(54, 700)
        nw = int(mk.tw(note, nf) + 150)
        box = (W / 2 - nw / 2, y0 + 760, W / 2 + nw / 2, y0 + 760 + 128)
        mk.glass(c, box, 64, tint_rgb=(255, 255, 255), amount=0.24, blur=30, border=0.6, shadow=0.24, shadow_rgb=(20, 0, 80))
        c.alpha_composite(mk.icon_tile(76, MINT, "check"), (int(box[0] + 28), int(box[1] + 26)))
        mk.draw(ImageDraw.Draw(c), box[0] + 124, box[1] + 66, note, nf, WHITE, "lm")
    return c.convert("RGB")


# ======================================================================================================================== Duolingo

DL_BTN = [(TANGERINE, (212, 90, 4)), (MINT, (18, 150, 106)), (SKY, (70, 150, 220)), (SUN, (214, 165, 17)),
          (ROSE, (217, 54, 89)), (TANGERINE, (212, 90, 4)), (MINT, (18, 150, 106)), (SKY, (70, 150, 220))]
DL_COPY = ["ready on exam day", "answer your way", "know where you stand", "snap your pages", "ask Cap", "catch the hints", "light up your sky", "keep your streak"]


@style("duolingo", "Duolingo", "duolingo",
       "The app's own screen, full-bleed with no phone, and one chunky lowercase caption set as a button in the app's own button style, a different colour each frame, at the bottom.",
       "Capling's buttons already have that raised lip (tangerine, mint, sky, sun, rose), so the captions are drawn with its real button recipe: Night ink on a brand fill.")
def duolingo(i):
    ph = 2400
    pn = mk.panel(STORY[i]["shot"], W, top=152, height=ph, radius=0)
    bc = tuple(int(v) for v in pn.crop((0, pn.height - 6, W, pn.height)).convert("RGB").resize((1, 1), Image.BOX).getpixel((0, 0)))
    c = Image.new("RGBA", (W, H), bc + (255,))
    paste(c, pn, 0, 0)
    fade = Image.new("RGBA", (W, 260), bc + (0,))
    a = np.linspace(0, 255, 260, dtype="float32")[:, None].repeat(W, 1)
    fade.putalpha(Image.fromarray(a.astype("uint8")))
    paste(c, fade, 0, ph - 260)
    fill, edge = DL_BTN[i]
    y = 2520
    mk.rrect(c, (84, y + 16, W - 84, y + 16 + 170), 62, edge + (255,))
    mk.rrect(c, (84, y, W - 84, y + 170), 62, fill + (255,))
    mk.draw(ImageDraw.Draw(c), W / 2, y + 85 + 4, DL_COPY[i], mk.sf(82, 800), NIGHT, "mm")
    return c.convert("RGB")


# ======================================================================================================================== Brilliant

BR_COPY = [["Your personal *exam coach*", "in your pocket"], ["Grades your answer", "in *your own words*"], ["Shows you *where*", "you stand"],
           ["Turns your pages into", "*checked* questions"], ["Drafts cards and notes", "*with you*, not for you"], ["Catches what the", "*lecturer* flagged"],
           ["Lights up what", "*you remember*"], ["A calm streak,", "*nothing to lose*"]]
BR_SAY = [("Future you", "says thanks."), ("Say it in", "your own words."), ("Look right", "there."), ("Pages in,", "questions out."),
          ("Let's find", "out together."), ("Lecture time.", "I'm all ears."), ("Every star is", "something you know."), ("You're on", "a roll.")]


@style("brilliant", "Brilliant", "brilliant",
       "Warm off-white, a serif headline with italic emphasis, the app's screen in a big rounded white card with a hairline edge, and the tutor's chat bubble overlapping the bottom.",
       "The serif is New York; the tutor is Cap, with one of his own lines; no credentials or institution names.")
def brilliant(i):
    c = Image.new("RGBA", (W, H), (246, 243, 238, 255))
    size = mk.fit(["".join(t for t, _ in mk.parse_rich(l)) for l in BR_COPY[i]], W * 0.84, nyw(500), hi=108)
    yb = lines_rich(c, BR_COPY[i], 190, size, nyw(500), nyw(500, True), (30, 30, 36), (30, 30, 36), pitch=1.16)
    y0 = int(yb + size * 0.4 + 110)
    strip = 340
    ch = H - strip - y0
    pw = 1010
    inner = mk.panel(STORY[i]["shot"], pw - 36, top=152, height=ch - 36, radius=44, round_bottom=True)
    card = Image.new("RGBA", (pw, ch), (0, 0, 0, 0))
    mk.rrect(card, (0, 0, pw, ch), 72, (255, 255, 255, 255), outline=(222, 218, 208, 255), width=3)
    card.alpha_composite(inner, (18, 18))
    put(c, card, W / 2, y0 + ch / 2, blur=34, dy=20, alpha=0.12, colour=(60, 50, 30))
    cp = cap(STORY[i]["cap"], 260, outline=0)
    paste(c, cp, 140, H - strip + 40)
    b = sk.bubble(list(BR_SAY[i]), 52, tail="left")
    put(c, b, 140 + cp.width + 30 + b.width / 2, H - strip + 60 + b.height / 2, blur=26, dy=18, alpha=0.18, colour=(60, 50, 30))
    return c.convert("RGB")
