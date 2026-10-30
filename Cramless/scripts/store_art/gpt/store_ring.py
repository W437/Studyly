#!/usr/bin/env python3
"""Look 4, "Readiness ring", rebuilt for Apple's two slots: the model paints only the scenery (run_plates.py), code owns everything exact.

    python3 -P scripts/store_art/gpt/store_ring.py [--fmt card|header] [--plates DIR] [--out DIR] [--debug]

Layers, back to front: the plate (sky, mountains, lake), a soft scrim behind the words, a grassy bank, Cap (the app's own art, his
telescope pointed at the ring), the readiness ring (the app's ReadinessRing: a round-capped arc over a track, the readiness colour at
78%, rounded numerals), two glass cards with the real strings of the result screen, and the headline in Bricolage Grotesque.
What must survive any crop goes inside Apple's art safe area (the headline and the ring); Cap and the cards are atmosphere around it.
Writes <out>/ring-<fmt>.png (3840 x 2560 or 3840 x 1646, no alpha), a copy with the safe area outlined, the box cut out, and layout.json.
"""
import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import looks  # noqa: E402
import store_art as sa  # noqa: E402
import store_lockup as sl  # noqa: E402

PLATES = os.path.join(looks.OUT_DIR, "plates")
OUT = os.path.join(looks.OUT_DIR, "final")
SIZE = looks.FULL
SFR = "/System/Library/Fonts/SFNSRounded.ttf"      # the app's numerals: SF Rounded, heavy
SF = "/System/Library/Fonts/SFNS.ttf"
DISPLAY = sl.DISPLAY                                # Bricolage Grotesque ExtraBold

SUN = (255, 195, 75)         # the ring's readiness colour, sampled from the real result screen (exameve/session.png)
ACCENT = (255, 207, 63)      # brand sun yellow #FFCF3F
MINT = (52, 214, 158)
INK2 = (205, 217, 240)
NAVY = (8, 14, 32)

WORDS = ["Know where", "you stand."]

# Everything in full-size pixels. `ring`: outer diameter and centre; `head`: left edge and the space it may use; `cap`: height, left
# edge, feet; `bank`: where the grassy bank's plateau, slope and toe are; `cards`: centre, size, tilt.
LAYOUT = {
    "card": dict(
        ring=dict(d=840, cx=2516, cy=1280),
        head=dict(left=872, gap=70),
        cap=dict(height=750, left=3040, feet=2160),
        bank=dict(plateau=1950, toe_y=2640, x0=2000, x1=2960),
        cards=dict(a=dict(cx=3060, cy=420, w=1080, h=330, tilt=-4), b=dict(cx=1010, cy=2090, w=880, h=210, tilt=3)),
    ),
    "header": dict(
        ring=dict(d=560, cx=2434, cy=823),
        head=dict(left=1126, gap=60),
        cap=dict(height=640, left=2880, feet=1450),
        bank=dict(plateau=1292, toe_y=1720, x0=2200, x1=2900),
        cards=dict(a=dict(cx=560, cy=420, w=900, h=280, tilt=-4), b=dict(cx=540, cy=1130, w=760, h=190, tilt=3)),
    ),
}


def vfont(path, px, name):
    f = ImageFont.truetype(path, int(round(px)))
    f.set_variation_by_name(name)
    return f


def box_px(fmt):
    w, h = SIZE[fmt]
    x0, y0, x1, y1 = looks.SAFE[fmt]
    return (round(x0 * w), round(y0 * h), round(x1 * w), round(y1 * h))


def over(base, color, alpha):
    return base * (1 - alpha[:, :, None]) + np.asarray(color, np.float32)[None, None, :] / 255 * alpha[:, :, None]


def screen(base, color, alpha):
    return 1 - (1 - base) * (1 - np.asarray(color, np.float32)[None, None, :] / 255 * alpha[:, :, None])


def arr(im):
    return np.asarray(im.convert("RGB"), np.float32) / 255


def to_img(a):
    return Image.fromarray(np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8), "RGB")


def blur_l(mask, sigma):
    """A float mask, blurred."""
    im = Image.fromarray(np.clip(mask * 255 + 0.5, 0, 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(sigma))
    return np.asarray(im, np.float32) / 255


def load_plate(fmt, plates):
    w, h = SIZE[fmt]
    im = Image.open(os.path.join(plates, f"ring-{fmt}.png")).convert("RGB")
    s = max(w / im.width, h / im.height)
    if abs(s - 1) > 1e-6:
        im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    left, top = (im.width - w) // 2, (im.height - h) // 2
    return im.crop((left, top, left + w, top + h))


# ---- the ring ------------------------------------------------------------------------------------------------------------------

def ring_masks(s, d, w, value, k=3):
    """Float masks (track, arc) of a ring of outer diameter d and stroke w, centred in an s x s square: an arc from 12 o'clock, clockwise,
    with round ends, like the app's trimmed Circle stroke."""
    c = s * k / 2
    big, small = d * k / 2, (d / 2 - w) * k
    track = Image.new("L", (s * k, s * k), 0)
    td = ImageDraw.Draw(track)
    td.ellipse([c - big, c - big, c + big, c + big], fill=255)
    td.ellipse([c - small, c - small, c + small, c + small], fill=0)
    a0, a1 = -math.pi / 2, -math.pi / 2 + value * 2 * math.pi
    arc = Image.new("L", (s * k, s * k), 0)
    ad = ImageDraw.Draw(arc)
    th = np.linspace(a0, a1, 1200)
    pts = [(c + big * math.cos(t), c + big * math.sin(t)) for t in th] + [(c + small * math.cos(t), c + small * math.sin(t)) for t in th[::-1]]
    ad.polygon(pts, fill=255)
    mid, cr = (big + small) / 2, (big - small) / 2
    for a in (a0, a1):
        x, y = c + mid * math.cos(a), c + mid * math.sin(a)
        ad.ellipse([x - cr, y - cr, x + cr, y + cr], fill=255)
    return [np.asarray(m.resize((s, s), Image.LANCZOS), np.float32) / 255 for m in (track, arc)]


def draw_ring(img, cx, cy, d, value=0.78):
    """The readiness ring at hero size, glowing on the night: a wide warm halo, the arc's own glow, a dark disc for the numerals."""
    w = d * 0.135
    s = int(d * 2.3) // 2 * 2
    x0, y0 = int(round(cx - s / 2)), int(round(cy - s / 2))
    track, arc = ring_masks(s, d, w, value)
    reg = arr(img.crop((x0, y0, x0 + s, y0 + s)))
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)
    r = np.hypot(xx - s / 2 + 0.5, yy - s / 2 + 0.5)
    halo = blur_l((r < d * 0.60).astype(np.float32), d * 0.22)
    reg = screen(reg, (255, 170, 60), halo * 0.22)
    reg = screen(reg, SUN, np.clip(blur_l(arc, d * 0.075) * 0.95 + blur_l(arc, d * 0.022) * 0.45, 0, 1))
    inner = blur_l((r < d / 2 - w - 1).astype(np.float32), 3)
    reg = over(reg, (6, 11, 26), inner * 0.58)
    reg = over(reg, (196, 216, 255), track * 0.17)
    reg = over(reg, SUN, arc)
    img.paste(to_img(reg), (x0, y0))
    return (cx - d / 2, cy - d / 2, cx + d / 2, cy + d / 2)


def ring_numerals(img, cx, cy, d, pct=78, label="ready", label_font=None, pct_prefix=False, label_kw=None):
    """78 % over a label ('ready'), set like the app's ring (heavy rounded numerals, a small bold percent sign) at hero size. The label,
    its font (another script) and the percent sign's side (Turkish writes %78) can be set; label_kw is what Raqm needs for a right-to-left word."""
    d_ = ImageDraw.Draw(img)
    f1, f2 = vfont(SFR, d * 0.335, "Heavy"), vfont(SFR, d * 0.16, "Bold")
    f3 = label_font or vfont(SF, d * 0.095, "Semibold")
    kw = label_kw or {}
    s1, s2 = str(pct), "%"
    w1, w2, gap = f1.getlength(s1), f2.getlength(s2), d * 0.012
    top = f1.getbbox(s1, anchor="ls")[1]                       # negative: the digits' height above the baseline
    h1 = -top
    h3 = -f3.getbbox(label, anchor="ls", **kw)[1]
    gap2 = d * 0.055
    block = h1 + gap2 + h3
    b1 = cy - block / 2 + h1 + d * 0.01
    x = cx - (w1 + gap + w2) / 2
    xn, xp = (x + w2 + gap, x) if pct_prefix else (x, x + w1 + gap)
    sh = Image.new("L", img.size, 0)
    sd = ImageDraw.Draw(sh)
    sd.text((xn, b1), s1, font=f1, fill=255, anchor="ls")
    sd.text((xp, b1), s2, font=f2, fill=255, anchor="ls")
    sh = sh.filter(ImageFilter.GaussianBlur(10)).point(lambda v: int(v * 0.5))
    img.paste(Image.new("RGB", img.size, NAVY), (0, 0), sh)
    d_.text((xn, b1), s1, font=f1, fill=(255, 255, 255), anchor="ls")
    d_.text((xp, b1), s2, font=f2, fill=(255, 255, 255), anchor="ls")
    d_.text((cx, b1 + gap2 + h3), label, font=f3, fill=INK2 + (240,), anchor="ms", **kw)


# ---- Cap, the bank, the scrim --------------------------------------------------------------------------------------------------

def cap_art():
    im, _ = sa.load_cap(1)
    a = np.asarray(im)[:, :, 3]
    ys, xs = np.where(a > 150)
    return im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def bank_edge(xs, b, h):
    """The bank's top edge per column: the lake's shore, a gentle slope, then a plateau with a little undulation, down a touch to the right."""
    t = np.clip((xs - b["x0"]) / (b["x1"] - b["x0"]), 0, 1)
    ease = t * t * (3 - 2 * t)
    y = b["toe_y"] + (b["plateau"] - b["toe_y"]) * ease
    y = y + 9 * np.sin(xs / 210.0) * ease + 6 * np.sin(xs / 83.0 + 1.3) * ease
    y = np.where(xs > b["x1"] + 500, y + (xs - b["x1"] - 500) * 0.045, y)
    return y


def draw_bank(img, b, seed=5):
    """A dark grassy bank in the lower right (the plateau Cap and his tripod stand on), lit along its top edge from the sky."""
    w, h = img.size
    rng = np.random.default_rng(seed)
    x0 = b["x0"] - 120
    xs = np.arange(x0, w, dtype=np.float32)
    top = bank_edge(xs, b, h)
    y0 = int(top.min()) - 60
    rows = np.arange(y0, h, dtype=np.float32)[:, None]
    depth = np.clip((rows - top[None, :]) / 520.0, 0, 1)[:, :, None]
    c_top, c_bot = np.array([34, 52, 96], np.float32) / 255, np.array([7, 12, 30], np.float32) / 255
    col = c_top[None, None, :] * (1 - depth) + c_bot[None, None, :] * depth
    noise = blur_l(rng.random((h - y0, w - x0)).astype(np.float32), 9) - 0.5
    noise2 = blur_l(rng.random((h - y0, w - x0)).astype(np.float32), 38) - 0.5
    col = col * (1 + (noise * 1.6 + noise2 * 2.2)[:, :, None] * 0.55)
    a = np.clip(rows - top[None, :] + 0.5, 0, 1)
    # the sky's cool light along the top edge
    rim = np.exp(-((rows - top[None, :] - 3.0) / 5.0) ** 2) * (rows > top[None, :] - 2)
    sky = np.array([128, 178, 255], np.float32) / 255
    reg = arr(img.crop((x0, y0, w, h)))
    reg = reg * (1 - a[:, :, None]) + col * a[:, :, None]
    reg = 1 - (1 - reg) * (1 - rim[:, :, None] * sky[None, None, :] * 0.30)
    img.paste(to_img(reg), (x0, y0))
    # tufts of grass on the plateau's top edge
    big = Image.new("RGBA", (img.width * 2, (h - y0) * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    for i in range(38):
        x = rng.uniform(b["x1"] - 160, w - 40)
        yb = float(bank_edge(np.array([x]), b, h)[0]) + 8
        n = int(rng.integers(3, 6))
        for j in range(n):
            bx = x + rng.uniform(-24, 24)
            bh = rng.uniform(30, 82)
            tilt = rng.uniform(-0.30, 0.30) * bh
            bw = rng.uniform(5, 8)
            shade = int(rng.integers(0, 3))
            fill = [(18, 30, 62, 255), (26, 42, 82, 255), (44, 70, 124, 255)][shade]
            pts = [(bx - bw, yb), (bx + tilt, yb - bh), (bx + bw, yb)]
            d.polygon([((px) * 2, (py - y0) * 2) for px, py in pts], fill=fill)
    big = big.resize((img.width, h - y0), Image.LANCZOS)
    base = img.crop((0, y0, img.width, h)).convert("RGBA")
    base.alpha_composite(big)
    img.paste(base.convert("RGB"), (0, y0))


def place_cap(img, left, feet, height, flip=True):
    """Cap with his telescope (the app's own art), a soft contact shadow, and a faint cool backlight so the navy hat reads on the night."""
    art = cap_art()
    sc = height / art.height
    art = art.resize((round(art.width * sc), round(art.height * sc)), Image.LANCZOS)
    if flip:
        art = ImageOps.mirror(art)
    x0, y0 = int(left), int(feet - art.height)
    pad = 240
    rx0, ry0, rx1, ry1 = max(0, x0 - pad), max(0, y0 - pad), min(img.width, x0 + art.width + pad), min(img.height, y0 + art.height + pad)
    a_full = Image.new("L", (rx1 - rx0, ry1 - ry0), 0)
    a_full.paste(art.split()[3], (x0 - rx0, y0 - ry0))
    reg = arr(img.crop((rx0, ry0, rx1, ry1)))
    halo = blur_l(np.asarray(a_full, np.float32) / 255, 54)
    reg = screen(reg, (110, 160, 255), np.clip(halo * 1.4, 0, 1) * 0.30)
    # shadows: under Cap and under the tripod (it stands a little further back on the plateau)
    sh = Image.new("L", a_full.size, 0)
    sd = ImageDraw.Draw(sh)
    cxb = (x0 - rx0) + art.width * (0.40 if flip else 0.36)
    sd.ellipse([cxb - art.width * 0.34, feet - ry0 - 22, cxb + art.width * 0.34, feet - ry0 + 18], fill=255)
    tx = (x0 - rx0) + art.width * (0.22 if flip else 0.76)
    ty = (y0 - ry0) + art.height * 0.76
    sd.ellipse([tx - art.width * 0.14, ty - 8, tx + art.width * 0.14, ty + 12], fill=190)
    reg = over(reg, (3, 6, 16), blur_l(np.asarray(sh, np.float32) / 255, 16) * 0.62)
    img.paste(to_img(reg), (rx0, ry0))
    img.paste(art.convert("RGB"), (x0, y0), art.split()[3])
    return (x0, y0, x0 + art.width, y0 + art.height)


# ---- glass cards ---------------------------------------------------------------------------------------------------------------

def mini_ring(layer, cx, cy, d, value, k, track=((200, 220, 255), 0.30)):
    w = d * 0.12
    s = int(d * 1.2) // 2 * 2
    track_m, arc = ring_masks(s, d, w, value, k=4)
    rgba = np.zeros((s, s, 4), np.float32)
    for m, col, al in ((track_m, track[0], track[1]), (arc, SUN, 1.0)):
        a = m * al
        rgba[:, :, :3] = rgba[:, :, :3] * (1 - a[:, :, None]) + np.asarray(col, np.float32)[None, None, :] / 255 * a[:, :, None]
        rgba[:, :, 3] = rgba[:, :, 3] + a * (1 - rgba[:, :, 3])
    tile = Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
    layer.alpha_composite(tile, (int(cx - s / 2), int(cy - s / 2)))


def card_a(layer, ox, oy, k, w, h):
    d = ImageDraw.Draw(layer)
    rd = 196 * k
    mini_ring(layer, ox + 48 * k + rd / 2, oy + h * k / 2, rd, 0.78, k)
    f1, f2 = vfont(SFR, 64 * k, "Heavy"), vfont(SFR, 31 * k, "Bold")
    wd = f1.getlength("78") + 2 * k + f2.getlength("%")
    x = ox + 48 * k + rd / 2 - wd / 2
    yb = oy + h * k / 2 + 22 * k
    d.text((x, yb), "78", font=f1, fill=(255, 255, 255, 255), anchor="ls")
    d.text((x + f1.getlength("78") + 2 * k, yb), "%", font=f2, fill=(255, 255, 255, 255), anchor="ls")
    tx = ox + 296 * k
    d.text((tx, oy + 140 * k), "Chem 110 Quiz", font=vfont(SF, 76 * k, "Semibold"), fill=(255, 255, 255, 255), anchor="ls")
    d.text((tx, oy + 216 * k), "42% → 78% ready · 2 days left", font=vfont(SF, 46 * k, "Regular"), fill=INK2 + (240,), anchor="ls")


def trend_icon(layer, x, y, s, color, k):
    """The 'on track' chart: two axes and a rising line with an arrow head."""
    d = ImageDraw.Draw(layer)
    lw = max(3, int(s * 0.085))
    col = color + (255,)
    ax = [(x, y), (x, y + s), (x + s, y + s)]
    d.line(ax, fill=col, width=lw, joint="curve")
    pts = [(x + s * 0.12, y + s * 0.80), (x + s * 0.42, y + s * 0.46), (x + s * 0.60, y + s * 0.62), (x + s * 0.98, y + s * 0.14)]
    d.line(pts, fill=col, width=lw, joint="curve")
    for p in pts + ax:
        d.ellipse([p[0] - lw / 2, p[1] - lw / 2, p[0] + lw / 2, p[1] + lw / 2], fill=col)
    ex, ey = pts[-1]
    d.line([(ex - s * 0.30, ey), (ex, ey), (ex, ey + s * 0.30)], fill=col, width=lw, joint="curve")
    for p in ((ex - s * 0.30, ey), (ex, ey + s * 0.30)):
        d.ellipse([p[0] - lw / 2, p[1] - lw / 2, p[0] + lw / 2, p[1] + lw / 2], fill=col)


def card_b(layer, ox, oy, k, w, h):
    s = 92 * k
    trend_icon(layer, ox + 58 * k, oy + h * k / 2 - s / 2 + 4 * k, s, MINT, k)
    ImageDraw.Draw(layer).text((ox + 208 * k, oy + h * k / 2 + 24 * k), "On track for 80%", font=vfont(SF, 68 * k, "Semibold"),
                               fill=MINT + (255,), anchor="ls")


def glass_card(img, cx, cy, w, h, tilt, content, radius=58):
    """A frosted-glass card: the sky behind it blurred and tinted navy, a soft shadow, a hairline edge, the content, tilted a few degrees."""
    s = int(math.hypot(w, h)) + 300
    s += s % 2
    x0, y0 = int(round(cx - s / 2)), int(round(cy - s / 2))
    cl, ct = max(0, x0), max(0, y0)                       # the working square may run past the picture: keep the part that is in it
    cr, cb = min(img.width, x0 + s), min(img.height, y0 + s)
    crop = (cl - x0, ct - y0, cr - x0, cb - y0)
    k = 3
    big = Image.new("L", (s * k, s * k), 0)
    ImageDraw.Draw(big).rounded_rectangle([(s - w) / 2 * k, (s - h) / 2 * k, (s + w) / 2 * k, (s + h) / 2 * k], radius=radius * k, fill=255)
    edge_big = Image.new("L", (s * k, s * k), 0)
    ImageDraw.Draw(edge_big).rounded_rectangle([(s - w) / 2 * k, (s - h) / 2 * k, (s + w) / 2 * k, (s + h) / 2 * k], radius=radius * k,
                                               outline=255, width=4 * k)

    def rot(m):
        return m.rotate(tilt, resample=Image.BICUBIC, center=(s * k / 2, s * k / 2)).resize((s, s), Image.LANCZOS)

    full = rot(big)
    mask, edge = full.crop(crop), rot(edge_big).crop(crop)
    shadow = full.filter(ImageFilter.GaussianBlur(40)).point(lambda v: int(v * 0.60))
    shadow = shadow.crop((crop[0], crop[1] - 26, crop[2], crop[3] - 26))            # the same shape, 26 px lower
    region = img.crop((cl, ct, cr, cb))
    rs = region.size
    glass = region.filter(ImageFilter.GaussianBlur(34))
    glass = Image.blend(glass, Image.new("RGB", rs, (28, 48, 104)), 0.38)
    t = np.clip((np.arange(rs[1], dtype=np.float32) + ct - y0 - (s - h) / 2) / h, 0, 1)
    sheen = (0.17 - 0.14 * t)[:, None].repeat(rs[0], 1)
    glass = to_img(over(arr(glass), (225, 238, 255), sheen))
    region.paste(Image.new("RGB", rs, (2, 5, 14)), (0, 0), shadow)
    region.paste(glass, (0, 0), mask)
    # the hairline edge is brighter along the top, like light catching the glass
    edge_a = np.asarray(edge, np.float32) / 255 * (0.62 - 0.36 * t)[:, None]
    region = to_img(over(arr(region), (255, 255, 255), edge_a))
    kk = 2
    layer = Image.new("RGBA", (s * kk, s * kk), (0, 0, 0, 0))
    content(layer, (s - w) / 2 * kk, (s - h) / 2 * kk, kk, w, h)
    layer = layer.rotate(tilt, resample=Image.BICUBIC, center=(s * kk / 2, s * kk / 2)).resize((s, s), Image.LANCZOS).crop(crop)
    region = region.convert("RGBA")
    region.alpha_composite(layer)
    img.paste(region.convert("RGB"), (cl, ct))
    return (cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)


# ---- the headline --------------------------------------------------------------------------------------------------------------

def headline(img, left, width, cy):
    lo, hi = 60, 700
    while hi - lo > 1:
        mid = (lo + hi) // 2
        f = ImageFont.truetype(DISPLAY, mid)
        if max(f.getbbox(t, anchor="ls")[2] - f.getbbox(t, anchor="ls")[0] for t in WORDS) <= width:
            lo = mid
        else:
            hi = mid
    px = lo
    f = ImageFont.truetype(DISPLAY, px)
    pitch = 0.97 * px
    cap_top = -f.getbbox("K", anchor="ls")[1]
    b1 = cy - (pitch - cap_top) / 2 - 0.02 * px + cap_top * 0.0
    b1 = cy + cap_top / 2 - pitch / 2 + 0.06 * px
    boxes = []
    for i, line in enumerate(WORDS):
        yb = b1 + i * pitch
        l0 = f.getbbox(line, anchor="ls")
        x = left - l0[0]
        if i == 1:
            lead = "you "
            sl.soft_text(img, (x, yb), lead, f, (255, 255, 255, 255), 1, anchor="ls", shadow=0.6)
            xa = x + f.getlength(lead)
            sl.soft_text(img, (xa, yb), "stand.", f, ACCENT + (255,), 1, anchor="ls", shadow=0.6)
        else:
            sl.soft_text(img, (x, yb), line, f, (255, 255, 255, 255), 1, anchor="ls", shadow=0.6)
        boxes.append((x + l0[0], yb + l0[1], x + l0[2], yb + l0[3]))
    return px, boxes


# ---- the whole picture ---------------------------------------------------------------------------------------------------------

def finish(img, seed=3):
    a = arr(img)
    h, w = a.shape[:2]
    yy = (np.arange(h, dtype=np.float32)[:, None] / h - 0.5) * 1.15
    xx = (np.arange(w, dtype=np.float32)[None, :] / w - 0.5)
    r = np.sqrt(xx ** 2 + yy ** 2)
    t = np.clip((r - 0.36) / 0.5, 0, 1)
    a *= (1 - 0.24 * t * t * (3 - 2 * t))[:, :, None]
    a += np.random.default_rng(seed).normal(0, 0.8 / 255, a.shape).astype(np.float32)
    return to_img(np.clip(a, 0, 1))


def build(fmt, plates):
    L = LAYOUT[fmt]
    W, H = SIZE[fmt]
    box = box_px(fmt)
    img = load_plate(fmt, plates)
    sl.scrim(img, box, 1, strength=0.40, grow=190, feather=190)
    draw_bank(img, L["bank"])
    cap_box = place_cap(img, L["cap"]["left"], L["cap"]["feet"], L["cap"]["height"], flip=True)
    cards = {}
    for key, fn in (("a", card_a), ("b", card_b)):
        c = L["cards"][key]
        cards[key] = glass_card(img, c["cx"], c["cy"], c["w"], c["h"], c["tilt"], fn)
    r = L["ring"]
    ring_box = draw_ring(img, r["cx"], r["cy"], r["d"])
    ring_numerals(img, r["cx"], r["cy"], r["d"])
    ring_left = r["cx"] - r["d"] / 2
    px, lines = headline(img, L["head"]["left"], ring_left - L["head"]["gap"] - L["head"]["left"], r["cy"])
    img = finish(img)
    inside = lambda b: b[0] >= box[0] and b[1] >= box[1] and b[2] <= box[2] and b[3] <= box[3]
    layout = dict(size=[W, H], box=list(box), headline_px=px,
                  headline=[[round(v) for v in b] for b in lines], ring=[round(v) for v in ring_box], cap=list(cap_box),
                  cards={k: [round(v) for v in b] for k, b in cards.items()},
                  headline_inside=all(inside(b) for b in lines), ring_inside=inside(ring_box),
                  cap_inside=inside(cap_box), cards_inside={k: inside(b) for k, b in cards.items()})
    return img, layout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--fmt", choices=("card", "header"))
    ap.add_argument("--plates", default=PLATES)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--debug", action="store_true", help="also write the picture with Apple's safe area outlined")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    layouts = {}
    for fmt in ([a.fmt] if a.fmt else ["card", "header"]):
        img, layout = build(fmt, a.plates)
        img.save(os.path.join(a.out, f"ring-{fmt}.png"))
        box = layout["box"]
        img.crop(tuple(box)).save(os.path.join(a.out, f"ring-{fmt}-box.png"))
        dbg = img.copy()
        d = ImageDraw.Draw(dbg)
        d.rectangle(box, outline=(255, 90, 120), width=6)
        dbg.save(os.path.join(a.out, f"ring-{fmt}-safe.png"))
        layouts[fmt] = layout
        print(fmt, img.size, "headline", layout["headline_px"], "px; inside box: headline", layout["headline_inside"], "ring", layout["ring_inside"])
    with open(os.path.join(a.out, "layout.json"), "w") as f:
        json.dump(layouts, f, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
