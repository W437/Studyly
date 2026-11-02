#!/usr/bin/env python3
"""The drawing kit for Capling's App Store screenshots: everything a look (shot_looks.py) is made of.

The split is the one the listing-images skill asks for: what must be true is cut from the app itself (real screens, real cards, Cap's own
art, the six skies' own colours) and what is only style (grounds, words, shadows, stickers) is drawn here. Nothing is painted by a model.

  pieces    a card, a button or a chip cut out of a real screenshot (`piece`), rounded like the app rounds it, with a soft lift
  phone     a screenshot in a drawn front-view phone, with one standard Dynamic Island (`phone`)
  Cap       the app's own poses as stickers, with an optional die-cut edge (`cap`)
  sky       one of the app's six skies drawn from its palette: gradient, glow, stars, hills, water (`sky`)
  type      Bricolage headlines that fit a width, with a pill or a highlighter behind a line (`headline`)
  extras    sparkles, confetti, a ring, a speech bubble, tape, a highlighter stroke

Sources are read from build/listing/lib (scripts/store_art/capture_library.sh) and build/listing/src (capture_listing.sh).
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
LISTING = os.path.join(REPO, "build", "listing")
LIB = os.path.join(LISTING, "lib")
SRC = os.path.join(LISTING, "src")
FONTS = os.path.join(REPO, "Cramless", "Resources", "Fonts")
ASSETS = os.path.join(REPO, "Cramless", "Resources", "Assets.xcassets")
CANDS = os.path.abspath(os.path.join(REPO, "..", "docs", "rethink", "brand", "raw", "candidates"))
GAME = os.path.join(REPO, "docs", "shots", "game")

W, H = 1290, 2796     # the 6.9-inch iPhone screenshot
SCREEN_W = 1206       # what the Simulator's 3x screenshots are

# The app's own colours (Shared/BrandPalette.swift).
NIGHT = (20, 33, 61)
DEEP = (11, 18, 32)
SKY = (124, 200, 255)
TANGERINE = (255, 122, 26)
TANGERINE_EDGE = (212, 90, 4)
SUN = (255, 207, 63)
MINT = (34, 195, 142)
MINT_INK = (11, 127, 90)
ROSE = (255, 90, 120)
CAPY = (224, 136, 74)
PAGE = (241, 245, 250)
WHITE = (255, 255, 255)
INK2 = (86, 98, 122)

DISPLAY = os.path.join(FONTS, "BricolageGrotesque-Display.ttf")
HEADING = os.path.join(FONTS, "BricolageGrotesque-Heading.ttf")
ROUNDED = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"
HAND = "/System/Library/Fonts/Supplemental/Bradley Hand Bold.ttf"

_fonts = {}


def font(path, px):
    key = (path, int(px))
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(path, int(px))
    return _fonts[key]


# ---- pieces: cut from the app's own screens ---------------------------------------------------------------------------------------------

# name: (capture, box in the 1206-wide screenshot, corner radius, optional extra boxes for a piece made of several cards)
# Boxes come from scripts/store_art/cards.py (the flat regions of the capture) and are checked on the pieces sheet (shot_looks.py --pieces).
PIECES = {
    # Today
    "hero": ("today", (6, 170, 1200, 1298), 72),
    "study": ("today", (60, 1368, 1146, 1528), 80),
    "tonight": ("today-eve", (60, 1368, 1146, 1528), 80),
    "quests": ("today", (60, 1676, 1146, 2316), 84),
    "streakchip": ("today", (700, 220, 988, 328), 54),
    "eveexam": ("today-eve", (60, 1816, 1146, 2208), 84),
    # a session
    "question": ("graded", (60, 360, 1146, 1310), 84),
    "answer": ("graded", (84, 880, 1122, 1120), 54),
    "almost": ("graded", (0, 1356, 1206, 2338), 84),
    "keyideas": ("graded", (756, 780, 1086, 852), 36),
    "continue": ("graded", (60, 2176, 1146, 2338), 80),
    # an exam
    "grade": ("exam", (60, 1492, 1146, 2008), 84),
    "start": ("exam", (60, 1284, 1146, 1446), 80),
    "progcard": ("progress", (56, 736, 1148, 1392), 84),
    # pages into questions
    "scanpage": ("capture-checking", (324, 436, 888, 1276), 44),
    "steps": ("capture-checking", (40, 1520, 1166, 2262), 60),
    "transcript": ("record", (20, 1750, 1186, 2252), 60),
    "info": ("questions", (60, 592, 1146, 856), 60),
    "qrow": ("questions", (60, 1184, 1146, 1688), 84),
    "add": ("questions", (60, 2344, 1146, 2506), 80),
    # Ask Cap
    "proposal": ("ask-cards", (36, 575, 1168, 1500), 84),
    "bubble": ("ask-cards", (60, 1540, 1062, 1824), 60),
    "examdraft": ("ask-exam", (64, 728, 1136, 1580), 84),
    "askme": ("ask-exam", (284, 548, 1144, 676), 62),
    "draftbubble": ("ask-exam", (60, 1612, 1008, 1824), 60),
    # lectures
    "lectureinfo": ("lecture-notes", (60, 592, 1144, 852), 60),
    "examflag": ("lecture-notes", (68, 1164, 1136, 1688), 60),
    # the memory sky
    "skywin": ("sky-fill", (30, 500, 1176, 1860), 84),
    "chip103": ("sky-fill", (264, 372, 940, 500), 64),
    "legend": ("sky-fill", (256, 2380, 952, 2476), 48),
    "skysheet": ("sky-focus", (60, 1728, 1144, 2480), 84),
    # a finished session
    "statrow": ("saved", (60, 1032, 1146, 1268), 54, [(60, 1032, 400, 1268), (432, 1032, 772, 1268), (804, 1032, 1144, 1268)]),
    "relit": ("saved", (64, 1316, 1142, 1484), 60),
    "examcard": ("saved", (60, 1532, 1146, 1916), 84),
    # the streak
    "calendar": ("streak", (60, 668, 1146, 1820), 84),
    # a plan, and the kinds of question
    "plancard": ("plan", (60, 516, 1144, 1384), 84),
    "pathcard": ("plan", (60, 1432, 1144, 2180), 84),
    "startplan": ("plan", (60, 2356, 1144, 2504), 80),
    "mcqcard": ("mcq-answered", (60, 360, 1144, 1752), 84),
    "clozecard": ("cloze-answered", (60, 360, 1144, 1032), 84),
    "diagramcard": ("diagram", (60, 360, 1144, 1248), 84),
}


def _open(name):
    for root in (LIB, SRC):
        for fn in (f"{name}.png",):
            p = os.path.join(root, fn)
            if os.path.exists(p):
                return Image.open(p).convert("RGB")
    # the numbered captures of capture_listing.sh
    for fn in sorted(os.listdir(SRC)) if os.path.isdir(SRC) else []:
        if fn.endswith(".png") and fn[3:-4] == name:
            return Image.open(os.path.join(SRC, fn)).convert("RGB")
    raise FileNotFoundError(name)


def screen(name):
    """A full capture, with its status bar tidied (see island)."""
    return island(_open(name))


def rounded_mask(size, radius, ss=3):
    w, h = size
    big = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(big).rounded_rectangle((0, 0, w * ss - 1, h * ss - 1), int(radius * ss), fill=255)
    return big.resize((w, h), Image.LANCZOS)


def cut(src, box, radius, width=None, scale=None, inset=0):
    """A region of a capture as an RGBA card with rounded corners. width: its width in canvas px (or scale: canvas px per source px)."""
    im = src if isinstance(src, Image.Image) else _open(src)
    x0, y0, x1, y1 = box
    x0, y0, x1, y1 = x0 + inset, y0 + inset, x1 - inset, y1 - inset
    tile = im.crop((x0, y0, x1, y1)).convert("RGBA")
    k = (width / tile.width) if width else (scale or 1.0)
    if abs(k - 1) > 1e-3:
        tile = tile.resize((max(1, round(tile.width * k)), max(1, round(tile.height * k))), Image.LANCZOS)
    tile.putalpha(rounded_mask(tile.size, max(2, (radius - inset) * k)))
    return tile


def piece(name, width=None, scale=None, src=None):
    """A named piece of the app. A piece with parts (the three stat tiles) keeps the gaps between them transparent."""
    spec = PIECES[name]
    cap_name, box, radius = spec[:3]
    im = cut(src if src is not None else _open(cap_name), box, radius, width=width, scale=scale)
    if len(spec) > 3:
        k = im.width / (box[2] - box[0])
        m = Image.new("L", im.size, 0)
        md = ImageDraw.Draw(m)
        for x0, y0, x1, y1 in spec[3]:
            md.rounded_rectangle(((x0 - box[0]) * k, (y0 - box[1]) * k, (x1 - box[0]) * k - 1, (y1 - box[1]) * k - 1), radius * k, fill=255)
        im.putalpha(ImageChops.multiply(im.getchannel("A"), m.filter(ImageFilter.GaussianBlur(0.8))))
    return im


# ---- the status bar ---------------------------------------------------------------------------------------------------------------------

def island(s):
    """The Simulator's screenshots have no Dynamic Island (it is hardware), and the exam-week Live Activity can sit in its place. Copy the
    status bar's own pixels (the row above the island) down over that zone, then draw one standard island, so every frame has the same
    one. Chrome only: no app pixel is touched (the zone holds nothing but the page's background)."""
    s = s.copy()
    sc = s.width / 402.0
    x0, x1 = int(sc * 104), int(sc * 308)
    y0, y1 = int(sc * 9), int(sc * 56)
    strip = s.crop((x0, int(sc * 6), x1, int(sc * 6) + 1)).resize((x1 - x0, y1 - y0))
    s.paste(strip, (x0, y0))
    k = 4
    w, h = int(126 * sc), int(37 * sc)
    isl = Image.new("L", (w * k, h * k), 0)
    ImageDraw.Draw(isl).rounded_rectangle((0, 0, w * k - 1, h * k - 1), h * k // 2, fill=255)
    isl = isl.resize((w, h), Image.LANCZOS)
    s.paste((0, 0, 0), ((s.width - w) // 2, int(11 * sc)), isl)
    return s


# ---- the phone --------------------------------------------------------------------------------------------------------------------------

def phone(shot, width, frame=(18, 22, 34), rim=(70, 78, 98), bezel=26, crop_bottom=0):
    """A front-view phone: the capture under rounded corners, a dark bezel, a thin rim. crop_bottom: screen px (of 2622) to drop."""
    s = shot if isinstance(shot, Image.Image) else screen(shot)
    if crop_bottom:
        s = s.crop((0, 0, s.width, s.height - crop_bottom))
    sw = width - 2 * bezel
    sh = round(sw * s.height / s.width)
    s = s.resize((sw, sh), Image.LANCZOS)
    r_out = round(width * 0.13)
    r_in = r_out - bezel
    k = 3
    body = Image.new("RGBA", (width * k, (sh + 2 * bezel) * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    d.rounded_rectangle((0, 0, body.width - 1, body.height - 1), r_out * k, fill=rim)
    d.rounded_rectangle((4 * k, 4 * k, body.width - 4 * k - 1, body.height - 4 * k - 1), (r_out - 4) * k, fill=frame)
    body = body.resize((width, sh + 2 * bezel), Image.LANCZOS)
    mask = Image.new("L", (sw * k, sh * k), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw * k - 1, sh * k - 1), r_in * k, fill=255)
    body.paste(s, (bezel, bezel), mask.resize((sw, sh), Image.LANCZOS))
    return body


# ---- placing ----------------------------------------------------------------------------------------------------------------------------

def paste(canvas, layer, x, y):
    """alpha_composite that tolerates a layer hanging off the canvas."""
    x, y = int(round(x)), int(round(y))
    cx0, cy0 = max(0, x), max(0, y)
    cx1, cy1 = min(canvas.width, x + layer.width), min(canvas.height, y + layer.height)
    if cx1 <= cx0 or cy1 <= cy0:
        return
    canvas.alpha_composite(layer.crop((cx0 - x, cy0 - y, cx1 - x, cy1 - y)), (cx0, cy0))


def shadowed(layer, blur=34, dy=26, alpha=0.30, colour=(10, 18, 40), grow=0):
    """The layer on a transparent pad with its soft shadow under it. Returns (image, pad) so callers can place by the layer's own corner."""
    pad = int(blur * 3 + abs(dy) + grow)
    a = Image.new("L", (layer.width + 2 * pad, layer.height + 2 * pad), 0)
    mask = layer.getchannel("A")
    if grow:
        mask = mask.filter(ImageFilter.MaxFilter(grow * 2 + 1))
    a.paste(mask, (pad, pad + dy))
    a = a.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * alpha))
    out = Image.new("RGBA", a.size, colour + (0,))
    out.putalpha(a)
    out.alpha_composite(layer, (pad, pad))
    return out, pad


def put(canvas, layer, cx, cy, angle=0, shadow=True, blur=34, dy=26, alpha=0.30, colour=(10, 18, 40), flip=False):
    """Place a layer by its centre, turned `angle` degrees counter-clockwise, with a soft shadow."""
    if flip:
        layer = ImageOps.mirror(layer)
    if angle:
        layer = layer.convert("RGBa").rotate(angle, resample=Image.BICUBIC, expand=True).convert("RGBA")   # premultiplied: no dark fringe
    if shadow:
        layer, pad = shadowed(layer, blur=blur, dy=dy, alpha=alpha, colour=colour)
        paste(canvas, layer, cx - layer.width / 2, cy - layer.height / 2)
    else:
        paste(canvas, layer, cx - layer.width / 2, cy - layer.height / 2)


def put_at(canvas, layer, x, y, angle=0, shadow=True, **kw):
    """Place a layer by its top-left corner (before turning)."""
    put(canvas, layer, x + layer.width / 2, y + layer.height / 2, angle=angle, shadow=shadow, **kw)


# ---- Cap --------------------------------------------------------------------------------------------------------------------------------

_cap_cache = {}


def cap_art(name):
    """Cap's pose, cut to its pixels. The 1024 px studio art when there is some (almost, ask, listen, mic, nice, notYet, plan, point,
    proud, relax, scan, sleepy, stargaze, think, tuckIn), else the app's own 600 px (celebrate, wave, study, sleep)."""
    if name not in _cap_cache:
        p = os.path.join(CANDS, f"cap-{name}-1.png")
        if not os.path.exists(p):
            p = os.path.join(ASSETS, f"Cap-{name}.imageset", f"cap-{name}.png")
        im = Image.open(p).convert("RGBA")
        a = np.asarray(im)[:, :, 3]
        ys, xs = np.where(a > 100)
        _cap_cache[name] = im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    return _cap_cache[name]


def cap(name, height, flip=False, outline=0, outline_colour=WHITE):
    """Cap as a sticker. outline > 0: a die-cut edge that wide round him, with a soft shadow."""
    art = cap_art(name)
    sc = height / art.height
    art = art.resize((max(1, round(art.width * sc)), max(1, round(art.height * sc))), Image.LANCZOS)
    if flip:
        art = ImageOps.mirror(art)
    if outline:
        pad = int(outline * 2 + 8)
        m = Image.new("L", (art.width + 2 * pad, art.height + 2 * pad), 0)
        m.paste(art.getchannel("A"), (pad, pad))
        edge = m.filter(ImageFilter.MaxFilter(int(outline) * 2 + 1)).filter(ImageFilter.GaussianBlur(1.4))
        out = Image.new("RGBA", m.size, outline_colour + (0,))
        out.putalpha(edge)
        out.alpha_composite(art, (pad, pad))
        return out
    return art


# ---- type -------------------------------------------------------------------------------------------------------------------------------

def text_width(s, f):
    return ImageDraw.Draw(Image.new("L", (1, 1))).textlength(s, font=f)


def fit_size(lines, max_w, path=DISPLAY, cap_size=190):
    """The biggest size at which the widest line fits max_w."""
    widest = max(text_width(t, font(path, 100)) for t in lines)
    return min(cap_size, int(100 * max_w / widest))


def headline(canvas, lines, top, size, colours, left=None, centre=None, pill=None, pill_pad=0.22, path=DISPLAY, pitch=1.1, shadow=None,
             highlight=None):
    """Lines of display type. colours: one per line. left: x of the left edge; centre: x to centre on. pill: (line index, fill) draws a
    rounded pill behind that line; highlight: (line index, colour) a marker stroke behind it. Returns the bottom of the last line."""
    d = ImageDraw.Draw(canvas)
    f = font(path, size)
    y = top
    for i, line in enumerate(lines):
        w = text_width(line, f)
        x = left if left is not None else centre - w / 2
        if pill and pill[0] == i:
            pad = size * pill_pad
            d.rounded_rectangle((x - pad, y + size * 0.1, x + w + pad, y + size * 1.2), size * 0.32, fill=pill[1])
        if highlight and highlight[0] == i:
            marker(canvas, (x - size * 0.08, y + size * 0.42, x + w + size * 0.08, y + size * 1.02), highlight[1], seed=i + 3)
        if shadow:
            d.text((x + shadow[0], y + shadow[1]), line, font=f, fill=shadow[2])
        d.text((x, y), line, font=f, fill=colours[i])
        y += size * pitch
    return y


def marker(canvas, box, colour, seed=1, alpha=255):
    """A highlighter stroke: a wobbly rounded bar, like the one the app lays behind the words that matched."""
    x0, y0, x1, y1 = box
    rnd = random.Random(seed)
    layer = Image.new("RGBA", canvas.size, colour + (0,))
    d = ImageDraw.Draw(layer)
    h = y1 - y0
    pts_top = [(x0 + (x1 - x0) * t / 12.0, y0 + rnd.uniform(-0.05, 0.05) * h) for t in range(13)]
    pts_bot = [(x0 + (x1 - x0) * t / 12.0, y1 + rnd.uniform(-0.05, 0.05) * h) for t in range(12, -1, -1)]
    d.polygon(pts_top + pts_bot, fill=colour + (alpha,))
    d.ellipse((x0 - h * 0.35, y0, x0 + h * 0.35, y1), fill=colour + (alpha,))
    d.ellipse((x1 - h * 0.35, y0, x1 + h * 0.35, y1), fill=colour + (alpha,))
    canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(1.2)))


# ---- small things -----------------------------------------------------------------------------------------------------------------------

def sparkle(d, cx, cy, r, colour, alpha=255):
    """A four-point star."""
    k = 0.28
    pts = []
    for i in range(8):
        a = math.pi / 4 * i - math.pi / 2
        rr = r if i % 2 == 0 else r * k
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=colour + (alpha,))


def confetti(canvas, seed, n, box, colours=(SUN, ROSE, SKY, MINT, TANGERINE), size=(8, 18), avoid=None):
    rnd = random.Random(seed)
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x0, y0, x1, y1 = box
    for _ in range(n):
        x, y = rnd.uniform(x0, x1), rnd.uniform(y0, y1)
        if avoid and any(a[0] <= x <= a[2] and a[1] <= y <= a[3] for a in avoid):
            continue
        c = rnd.choice(colours)
        s = rnd.uniform(*size)
        kind = rnd.random()
        if kind < 0.4:
            sparkle(d, x, y, s * 0.9, c, 230)
        elif kind < 0.7:
            d.ellipse((x - s / 2, y - s / 2, x + s / 2, y + s / 2), fill=c + (230,))
        else:
            piece_ = Image.new("RGBA", (int(s * 1.6), int(s * 0.7)), c + (235,))
            piece_ = piece_.rotate(rnd.uniform(0, 180), expand=True, resample=Image.BICUBIC)
            layer.alpha_composite(piece_, (int(x), int(y)))
    canvas.alpha_composite(layer)


def gradient(size, top, bottom, horizontal=False):
    w, h = size
    g = Image.linear_gradient("L")
    g = g.rotate(90, expand=True).transpose(Image.FLIP_LEFT_RIGHT) if horizontal else g
    g = g.resize((w, h), Image.BILINEAR)
    return Image.composite(Image.new("RGB", size, bottom), Image.new("RGB", size, top), g).convert("RGBA")


def glow(canvas, cx, cy, rx, ry, colour, alpha=120, blur=None):
    """A soft ellipse of colour. Drawn on a layer only as big as the glow, so it is cheap on a very wide canvas."""
    blur = blur or min(rx, ry) * 0.6
    pad = int(blur * 3)
    lw, lh = int(2 * rx + 2 * pad), int(2 * ry + 2 * pad)
    layer = Image.new("RGBA", (lw, lh), colour + (0,))          # the colour everywhere, so the blur doesn't darken the edge
    ImageDraw.Draw(layer).ellipse((pad, pad, pad + 2 * rx, pad + 2 * ry), fill=colour + (alpha,))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    paste(canvas, layer, cx - rx - pad, cy - ry - pad)


def ring(d_px, frac, colour, track, stroke=None, start=-90, cap_round=True):
    """A progress ring on a transparent square, drawn at 3x. frac 0 to 1."""
    k = 3
    n = d_px * k
    stroke = (stroke or d_px * 0.12) * k
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    box = (stroke / 2, stroke / 2, n - stroke / 2, n - stroke / 2)
    d.arc(box, 0, 360, fill=track, width=int(stroke))
    if frac > 0:
        d.arc(box, start, start + 360 * frac, fill=colour, width=int(stroke))
        if cap_round:
            r = stroke / 2
            cx = cy = n / 2
            rad = n / 2 - stroke / 2
            for ang in (start, start + 360 * frac):
                a = math.radians(ang)
                px, py = cx + rad * math.cos(a), cy + rad * math.sin(a)
                d.ellipse((px - r, py - r, px + r, py + r), fill=colour)
    return im.resize((d_px, d_px), Image.LANCZOS)


def bubble(text_lines, size, fill=WHITE, ink=NIGHT, tail="left", pad=0.5, path=HEADING, radius=0.55, outline=None):
    """A speech bubble with a tail at the bottom (left or right)."""
    f = font(path, size)
    wmax = max(text_width(t, f) for t in text_lines)
    lh = size * 1.18
    w = int(wmax + size * pad * 2)
    h = int(lh * len(text_lines) + size * pad * 1.6)
    k = 3
    tailh = int(size * 0.6)
    im = Image.new("RGBA", (w * k, (h + tailh) * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, w * k - 1, h * k - 1), int(size * radius * k), fill=fill, outline=outline, width=int(4 * k) if outline else 0)
    tx = int(w * (0.2 if tail == "left" else 0.8)) * k
    d.polygon([(tx - size * 0.35 * k, (h - 2) * k), (tx + size * 0.35 * k, (h - 2) * k),
               (tx + (-0.25 if tail == "left" else 0.25) * size * k, (h + tailh) * k)], fill=fill)
    im = im.resize((w, h + tailh), Image.LANCZOS)
    d = ImageDraw.Draw(im)
    y = size * pad * 0.8
    for t in text_lines:
        d.text((size * pad, y), t, font=f, fill=ink)
        y += lh
    return im


def tape(w=190, h=64, colour=(255, 236, 160), alpha=215, angle=0):
    """A strip of washi tape with torn ends, on a transparent pad."""
    k = 3
    n = 7
    im = Image.new("RGBA", (w * k, h * k), colour + (0,))
    d = ImageDraw.Draw(im)
    pts = [(0, 0)]
    for j in range(n + 1):
        pts.append((((j % 2) * 7) * k, j * h * k / n))
    pts += [(w * k, h * k)]
    right = [(w * k - ((j % 2) * 7) * k, j * h * k / n) for j in range(n, -1, -1)]
    d.polygon([(x, y) for x, y in pts[1:-1]] + right, fill=colour + (alpha,))
    im = im.resize((w, h), Image.LANCZOS)
    return im.rotate(angle, expand=True, resample=Image.BICUBIC) if angle else im


def curve(p0, p1, p2, p3, n=60):
    out = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        out.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                    u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return out


def arrow(canvas, p0, p1, p2, p3, colour=(40, 66, 150), width=7, head=34):
    """A hand-drawn curved arrow (a cubic through four points) with an open head."""
    pts = curve(p0, p1, p2, p3)
    layer = Image.new("RGBA", canvas.size, colour + (0,))
    d = ImageDraw.Draw(layer)
    d.line(pts, fill=colour + (255,), width=width, joint="curve")
    for x, y in (pts[0], pts[-1]):
        d.ellipse((x - width / 2, y - width / 2, x + width / 2, y + width / 2), fill=colour + (255,))
    (x1, y1), (x2, y2) = pts[-6], pts[-1]
    a = math.atan2(y2 - y1, x2 - x1)
    for da in (2.5, -2.5):
        d.line((x2, y2, x2 + head * math.cos(a + da), y2 + head * math.sin(a + da)), fill=colour + (255,), width=width)
    canvas.alpha_composite(layer)


def scribble(canvas, text, xy, size, angle=0, colour=(40, 66, 150), path=None, anchor="la"):
    """Handwriting (Bradley Hand), turned a little, as if written on the page."""
    f = font(path or HAND, size)
    w = int(text_width(text, f)) + 40
    layer = Image.new("RGBA", (w, int(size * 1.6)), colour + (0,))
    ImageDraw.Draw(layer).text((20, 8), text, font=f, fill=colour + (255,))
    layer = layer.rotate(angle, expand=True, resample=Image.BICUBIC)
    x, y = xy
    if anchor == "ca":
        x -= layer.width / 2
    canvas.alpha_composite(layer, (int(x), int(y))) if x >= 0 and y >= 0 else paste(canvas, layer, x, y)


# ---- the six skies ----------------------------------------------------------------------------------------------------------------------

def _hex(v):
    return ((v >> 16) & 255, (v >> 8) & 255, v & 255)


# Shared/SkyTheme.swift, as hex numbers: sky (top, bottom), glow (high, mid, low), dust (cool, warm), far hills, mid hills, water, ground, crest (warm, cool).
SKIES = {
    "night": dict(sky=(0x070D1B, 0x14213D), glow=(0x6C46A8, 0xE4708C, 0xFFB070), dust=(0xC7DEFF, 0xFFE6C2), far=(0x333E78, 0x1A2350),
                  mid=(0x212D5E, 0x121C3E), water=(0x24396E, 0x0C1432), ground=(0x131F3E, 0x080E22), crest=(0xFFE2C4, 0xB9C6FF)),
    "dusk": dict(sky=(0x0F0A28, 0x2A1A5A), glow=(0x7A3FD0, 0xE0507E, 0xFFB070), dust=(0xE4D4FF, 0xFFD9C2), far=(0x43307A, 0x261A52),
                 mid=(0x30225A, 0x1B1240), water=(0x362A78, 0x140C36), ground=(0x1A1034, 0x0C0722), crest=(0xFFC9B0, 0xCDBDFF)),
    "aurora": dict(sky=(0x04141A, 0x0B2E33), glow=(0x2BD9A0, 0x39B6C8, 0x7A5BE0), dust=(0xC9FFEE, 0xE8FFD8), far=(0x1F5560, 0x10343C),
                   mid=(0x153F48, 0x0B2830), water=(0x1B4F5C, 0x07222B), ground=(0x0C2A30, 0x041418), crest=(0xA5F5DC, 0x9FE3E8)),
    "ember": dict(sky=(0x1A0A0A, 0x3A1A14), glow=(0x9E2A2B, 0xFF6A2A, 0xFFC24A), dust=(0xFFD2B8, 0xFFE2A8), far=(0x5A2A2A, 0x341616),
                  mid=(0x421E1E, 0x240F0F), water=(0x4A2424, 0x1C0B0B), ground=(0x2A1212, 0x120606), crest=(0xFFC9A0, 0xFFB08A)),
    "bloom": dict(sky=(0x1D1432, 0x4E3060), glow=(0xFF8FB8, 0xFFC4A0, 0xFFEBC8), dust=(0xFFE0F2, 0xFFEAD8), far=(0x7A4E7A, 0x452C57),
                  mid=(0x5C3A66, 0x34204A), water=(0x6B4A82, 0x2A1A48), ground=(0x35204F, 0x19102B), crest=(0xFFE6D4, 0xFFD0EC)),
    "glacier": dict(sky=(0x06121F, 0x163552), glow=(0x5AB8E8, 0x9CE6FF, 0xE8F8FF), dust=(0xE6F6FF, 0xFFFFFF), far=(0x3D6A8F, 0x1F3F5F),
                    mid=(0x2A506F, 0x142D45), water=(0x2F6A94, 0x0C2238), ground=(0x153048, 0x08141F), crest=(0xE4F6FF, 0xBFE4FF)),
}


def _ridge(w, base, amp, seed, wl):
    rnd = random.Random(seed)
    ph = [rnd.uniform(0, 6.28) for _ in range(3)]
    return [base + amp * (0.6 * math.sin(x / w * 2 * math.pi * wl + ph[0]) + 0.3 * math.sin(x / w * 2 * math.pi * wl * 2.3 + ph[1])
                          + 0.1 * math.sin(x / w * 2 * math.pi * wl * 5.1 + ph[2])) for x in range(w + 1)]


def _fill_ridge(canvas, ys, top_c, bottom_c, y_bottom, crest=None):
    w = canvas.width
    mask = Image.new("L", canvas.size, 0)
    md = ImageDraw.Draw(mask)
    md.polygon([(x, y) for x, y in enumerate(ys)] + [(w, y_bottom), (0, y_bottom)], fill=255)
    top = int(min(ys))
    fill = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    fill.paste(gradient((w, max(2, y_bottom - top)), top_c, bottom_c), (0, top))
    canvas.paste(fill, (0, 0), mask)
    if crest:
        ld = ImageDraw.Draw(canvas)
        ld.line([(x, y) for x, y in enumerate(ys)], fill=crest + (150,), width=3)


def sky(theme, size=(W, H), horizon=0.70, seed=7, stars=260, part="all", seed_shift=0):
    """One of the app's skies (Shared/SkyTheme.swift) as a picture: the gradient, the dusk glow at the horizon, the dust of faint stars,
    two ridges of hills, the lake and the ground. horizon: where the far hills meet the sky, as a share of the height.
    part: "all", "back" (everything but the near hills, to put a phone in front of) or "front" (only the near hills, on transparent)."""
    p = SKIES[theme]
    w, h = size
    hy = int(h * horizon)
    if part == "front":
        c = Image.new("RGBA", size, (0, 0, 0, 0))
        near = _ridge(w, hy + h * 0.11, h * 0.012, seed + 3, 1.1)
        _fill_ridge(c, near, _hex(p["ground"][0]), _hex(p["ground"][1]), h, crest=_hex(p["crest"][1]))
        return c
    c = gradient(size, _hex(p["sky"][0]), _hex(p["sky"][1]))
    # the glow: three soft ellipses, high to low, centred on the horizon
    for col, ry, a in ((p["glow"][0], 0.30, 70), (p["glow"][1], 0.17, 110), (p["glow"][2], 0.08, 150)):
        glow(c, w / 2, hy, w * 0.85, h * ry, _hex(col), alpha=a, blur=h * ry * 0.5)
    rnd = random.Random(seed + seed_shift)
    d = ImageDraw.Draw(c)
    for _ in range(stars):
        x, y = rnd.uniform(0, w), rnd.uniform(0, hy * 0.95)
        fade = 1 - (y / hy) ** 2 * 0.75
        r = rnd.choice((1.5, 2, 2, 3, 3, 4.5))
        col = _hex(p["dust"][rnd.randint(0, 1)])
        d.ellipse((x - r, y - r, x + r, y + r), fill=col + (int(rnd.uniform(110, 255) * fade),))
    far = _ridge(w, hy, h * 0.022, seed + 1, 1.3)
    _fill_ridge(c, far, _hex(p["far"][0]), _hex(p["far"][1]), int(hy + h * 0.2), crest=_hex(p["crest"][0]))
    mid = _ridge(w, hy + h * 0.05, h * 0.02, seed + 2, 1.9)
    _fill_ridge(c, mid, _hex(p["mid"][0]), _hex(p["mid"][1]), int(hy + h * 0.25))
    if part == "all":
        near = _ridge(w, hy + h * 0.11, h * 0.012, seed + 3, 1.1)
        _fill_ridge(c, near, _hex(p["ground"][0]), _hex(p["ground"][1]), h, crest=_hex(p["crest"][1]))
    else:   # back: the ground fills what the phone will stand on
        c.paste(Image.new("RGBA", (w, h - int(hy + h * 0.1)), _hex(p["ground"][0]) + (255,)), (0, int(hy + h * 0.1)))
    return c


# ---- the six sky swatches the app draws for its picker, and the medals and flames it renders ----------------------------------------------

def _keyed(path, box, bg=PAGE, tol=14, feather=2.0):
    """A render from docs/shots/game cut off the page colour it was drawn on: the pixels that differ from it become opaque."""
    im = Image.open(path).convert("RGB").crop(box)
    a = np.asarray(im).astype(int)
    diff = np.abs(a - np.array(bg)).max(axis=2)
    m = Image.fromarray(np.clip((diff - tol) * 14, 0, 255).astype("uint8"))
    m = m.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(feather / 2))
    out = im.convert("RGBA")
    out.putalpha(m)
    return out


def medal(index, height):
    """One of the app's streak medals (docs/shots/game/medals-large-light.png): 0 the flame, 1 the star, 2 the gold flame."""
    path = os.path.join(GAME, "medals-large-light.png")
    boxes = [(40, 56, 456, 472), (488, 56, 904, 472), (916, 56, 1332, 472)]
    im = Image.open(path).convert("RGB")
    x0, y0, x1, y1 = boxes[index]
    tile = im.crop((x0, y0, x1, y1)).convert("RGBA")
    d = (x1 - x0)
    m = Image.new("L", (d * 3, d * 3), 0)
    ImageDraw.Draw(m).ellipse((d * 3 * 0.045, d * 3 * 0.045, d * 3 * 0.955, d * 3 * 0.955), fill=255)
    tile.putalpha(m.resize((d, d), Image.LANCZOS))
    return tile.resize((height, height), Image.LANCZOS)
