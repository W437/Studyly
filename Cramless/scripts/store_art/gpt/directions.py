#!/usr/bin/env python3
"""Four directions for Capling's App Store header and Search card, the words set BIG inside Apple's art safe area.

    python3 -P scripts/store_art/gpt/directions.py [--only night,poster,screens,notebook] [--fmt card|header] [--out DIR] [--debug]

The owner asked (2026-10-30) for bigger text, copy that says what the app is for, and more than one style to pick from. So: one line for
every direction (the app's own welcome line, "Ready on exam day.", so the directions compare on look alone), the line as big as the box
allows (two short lines, left-aligned, tight leading), and everything else around the box as atmosphere that a crop may drop. The night
direction is also set with two other lines. Everything exact is set by code (words, ring, real UI crops); the only model-painted pixels
are the night scenery plates (run_plates.py).

Directions: night (painterly lake, the ring, Cap at his telescope), poster (flat bright, Cap with the exam-day calendar), screens (the
app's own sky with real UI crops, Cap scanning), notebook (paper, a marker, Cap taking notes).
Output: <out>/<direction>/<copy>-<fmt>.png, -box.png (cut to Apple's box), -safe.png (box outlined) and layout.json.
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
import looks  # noqa: E402
import store_ring as sr  # noqa: E402  (also puts scripts/store_art on the path)
import store_lockup as sl  # noqa: E402
import store_art as sa  # noqa: E402
import locales as lc  # noqa: E402

SIZE = looks.FULL
OUT = os.path.join(looks.OUT_DIR, "directions")
SHOTS = sl.SHOTS
CANDS = os.path.abspath(os.path.join(looks.REPO, "..", "docs", "rethink", "brand", "raw", "candidates"))

NAVY = (20, 33, 61)          # #14213D
DEEP = (11, 18, 32)          # #0B1220
YELLOW = sr.ACCENT           # #FFCF3F
SUN = sr.SUN                 # the ring's readiness colour
WHITE = (255, 255, 255)
MINT_INK = (16, 160, 116)
GREY_INK = (96, 110, 140)

# The words. Two short lines each, so they can be set very big. "day" is the app's own welcome line (Cramless/Features/Onboarding/
# WelcomeView.swift: "A little every day. Ready on exam day.").
COPY = {
    "day": dict(name="Ready on exam day.", lines=["Ready on", "exam day."]),
    "notes": dict(name="Notes in. Exam ready.", lines=["Notes in.", "Exam ready."]),
    "know": dict(name="Know you're exam ready.", lines=["Know you're", "exam ready."]),
}


# ---- the words -----------------------------------------------------------------------------------------------------------------

def layout_headline(lines, box, *, left=None, right=None, cy=None, fit_h=0.90, pitch=0.95, margin=44, path=None, sp=None, kw=None, align="left"):
    """The lines as big as the box allows (width and height), left-aligned (right-aligned for a right-to-left language), the ink block
    centred on cy. sp: a font spec from locales.py (default: the brand's Bricolage); kw: what Raqm needs to shape the line. Nothing is drawn."""
    sp = sp or lc.spec(path or sr.DISPLAY)
    kw = kw or {}
    x0, y0, x1, y1 = box
    left = x0 + margin if left is None else left
    right = x1 - margin if right is None else right
    cy = (y0 + y1) / 2 if cy is None else cy
    width, maxh = right - left, (y1 - y0) * fit_h

    def metrics(px):
        f = lc.load(sp, px)
        sw = round(px * sp["stroke"])
        bb = [f.getbbox(t, anchor="ls", stroke_width=sw, **kw) for t in lines]
        return f, bb, sw, max(b[2] - b[0] for b in bb), (len(lines) - 1) * pitch * px + bb[-1][3] - bb[0][1]

    lo, hi = 60, 900
    while hi - lo > 1:
        mid = (lo + hi) // 2
        _, _, _, w, h = metrics(mid)
        if w <= width and h <= maxh:
            lo = mid
        else:
            hi = mid
    px = lo
    f, bb, sw, w, h = metrics(px)
    b0 = cy - h / 2 - bb[0][1]
    items = []
    for i, t in enumerate(lines):
        yb = b0 + i * pitch * px
        x = left - bb[i][0] if align == "left" else right - bb[i][2]
        items.append(dict(text=t, x=x, y=yb, ink=(x + bb[i][0], yb + bb[i][1], x + bb[i][2], yb + bb[i][3])))
    return dict(px=px, font=f, stroke=sw, kw=kw, items=items)


def render_headline(img, hl, colors, shadow=None):
    px, f, sw, kw = hl["px"], hl["font"], hl["stroke"], hl["kw"]
    for it, col in zip(hl["items"], colors):
        if shadow:
            w, h = img.size
            layer = Image.new("L", (w, h), 0)
            ImageDraw.Draw(layer).text((it["x"], it["y"] + px * 0.02), it["text"], font=f, fill=255, anchor="ls", stroke_width=sw, **kw)
            sh = layer.filter(ImageFilter.GaussianBlur(px * 0.05)).point(lambda v: int(v * shadow))
            img.paste(Image.new("RGB", (w, h), (2, 5, 14)), (0, 0), sh)
        ImageDraw.Draw(img).text((it["x"], it["y"]), it["text"], font=f, fill=tuple(col), anchor="ls", stroke_width=sw, stroke_fill=tuple(col), **kw)


def ink_boxes(hl):
    return [it["ink"] for it in hl["items"]]


# ---- Cap ---------------------------------------------------------------------------------------------------------------------------

def pose_art(name):
    if name == "stargaze":
        return sr.cap_art()
    im = Image.open(os.path.join(CANDS, f"cap-{name}-1.png")).convert("RGBA")
    a = np.asarray(im)[:, :, 3]
    ys, xs = np.where(a > 150)
    return im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def place_pose(img, name, left, feet, height, *, flip=False, outline=0, shadow_rgb=(3, 6, 16), ground=0.5):
    """One of Cap's poses (the app's own art): a contact shadow under his feet, or a white die-cut edge round him when outline > 0."""
    art = pose_art(name)
    sc = height / art.height
    art = art.resize((round(art.width * sc), round(art.height * sc)), Image.LANCZOS)
    if flip:
        art = ImageOps.mirror(art)
    x0, y0 = int(left), int(feet - art.height)
    a = art.split()[3]
    if outline:
        pad = outline * 2 + 50
        m = Image.new("L", (art.width + 2 * pad, art.height + 2 * pad), 0)
        m.paste(a, (pad, pad))
        edge = m.filter(ImageFilter.GaussianBlur(outline / 1.48)).point(lambda v: 255 if v > 18 else 0).filter(ImageFilter.GaussianBlur(1.6))
        sh = edge.filter(ImageFilter.GaussianBlur(24)).point(lambda v: int(v * 0.34))
        img.paste(Image.new("RGB", sh.size, shadow_rgb), (x0 - pad, y0 - pad + 20), sh)
        img.paste(Image.new("RGB", edge.size, WHITE), (x0 - pad, y0 - pad), edge)
    else:
        w, h = img.size
        sh = Image.new("L", (w, h), 0)
        cx = x0 + art.width * 0.5
        ImageDraw.Draw(sh).ellipse([cx - art.width * 0.36, feet - 26, cx + art.width * 0.36, feet + 22], fill=255)
        sh = sh.filter(ImageFilter.GaussianBlur(18)).point(lambda v: int(v * ground))
        img.paste(Image.new("RGB", (w, h), shadow_rgb), (0, 0), sh)
    img.paste(art.convert("RGB"), (x0, y0), a)
    return (x0, y0, x0 + art.width, y0 + art.height)


# ---- cards ---------------------------------------------------------------------------------------------------------------------

def light_card(img, cx, cy, w, h, tilt, content, radius=58, fill=(255, 255, 255), shadow=0.30, shadow_rgb=(10, 20, 50), edge=None):
    """A solid card (white paper, or a real screen crop) with a soft shadow, tilted a few degrees. No glass: for the light and real-UI looks."""
    k = 2
    s = int(math.hypot(w, h)) + 300
    s += s % 2
    layer = Image.new("RGBA", (s * k, s * k), (0, 0, 0, 0))
    rect = [(s - w) / 2 * k, (s - h) / 2 * k, (s + w) / 2 * k, (s + h) / 2 * k]
    sh = Image.new("L", layer.size, 0)
    ImageDraw.Draw(sh).rounded_rectangle([rect[0], rect[1] + 24 * k, rect[2], rect[3] + 24 * k], radius=radius * k, fill=int(255 * shadow))
    sh = sh.filter(ImageFilter.GaussianBlur(36 * k))
    layer.paste(Image.new("RGBA", layer.size, shadow_rgb + (255,)), (0, 0), sh)
    if fill is not None:
        ImageDraw.Draw(layer).rounded_rectangle(rect, radius=radius * k, fill=tuple(fill) + (255,))
    content(layer, rect[0], rect[1], k, w, h)
    if edge:
        ImageDraw.Draw(layer).rounded_rectangle(rect, radius=radius * k, outline=edge, width=3 * k)
    layer = layer.rotate(tilt, resample=Image.BICUBIC, center=(s * k / 2, s * k / 2)).resize((s, s), Image.LANCZOS)
    x0, y0 = int(round(cx - s / 2)), int(round(cy - s / 2))
    cl, ct, cr, cb = max(0, x0), max(0, y0), min(img.width, x0 + s), min(img.height, y0 + s)
    base = img.crop((cl, ct, cr, cb)).convert("RGBA")
    base.alpha_composite(layer.crop((cl - x0, ct - y0, cr - x0, cb - y0)))
    img.paste(base.convert("RGB"), (cl, ct))
    return (cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)


def card_a_light(layer, ox, oy, k, w, h):
    d = ImageDraw.Draw(layer)
    rd = 196 * k
    sr.mini_ring(layer, ox + 48 * k + rd / 2, oy + h * k / 2, rd, 0.78, k, track=((184, 196, 220), 0.60))
    f1, f2 = sr.vfont(sr.SFR, 64 * k, "Heavy"), sr.vfont(sr.SFR, 31 * k, "Bold")
    wd = f1.getlength("78") + 2 * k + f2.getlength("%")
    x = ox + 48 * k + rd / 2 - wd / 2
    yb = oy + h * k / 2 + 22 * k
    d.text((x, yb), "78", font=f1, fill=NAVY + (255,), anchor="ls")
    d.text((x + f1.getlength("78") + 2 * k, yb), "%", font=f2, fill=NAVY + (255,), anchor="ls")
    tx = ox + 296 * k
    d.text((tx, oy + 140 * k), "Chem 110 Quiz", font=sr.vfont(sr.SF, 76 * k, "Semibold"), fill=NAVY + (255,), anchor="ls")
    d.text((tx, oy + 216 * k), "42% → 78% ready · 2 days left", font=sr.vfont(sr.SF, 46 * k, "Regular"), fill=GREY_INK + (255,), anchor="ls")


def card_b_light(layer, ox, oy, k, w, h):
    s = 92 * k
    sr.trend_icon(layer, ox + 58 * k, oy + h * k / 2 - s / 2 + 4 * k, s, MINT_INK, k)
    ImageDraw.Draw(layer).text((ox + 208 * k, oy + h * k / 2 + 24 * k), "On track for 80%", font=sr.vfont(sr.SF, 68 * k, "Semibold"),
                               fill=MINT_INK + (255,), anchor="ls")


CARD_A, CARD_B = (1080, 330), (880, 210)      # the sizes card_a_light and card_b_light are drawn for


def scaled(fn, z):
    """A card's content function, drawn z times as big (the content is laid out in units of k, so k * z does it)."""
    return lambda layer, ox, oy, k, w, h: fn(layer, ox, oy, k * z, w / z, h / z)


LABEL_SCALE = {"ja": 1.15, "zh-Hans": 1.15, "zh-Hant": 1.15, "ko": 1.05, "th": 1.1, "hi": 1.05, "ar": 1.1, "he": 1.1}


def mixed_width(text, sp, role, px, kw=None):
    rs = lc.runs(text, sp)
    if len(rs) == 1 and rs[0][1]:
        return lc.load(sp, px).getlength(text, **(kw or {}))
    fp, ff = lc.load(sp, px), lc.load(lc.FALLBACK[role], px)
    return sum((fp if ok else ff).getlength(seg) for seg, ok in rs)


def draw_mixed(d, xy, text, sp, role, px, fill, kw=None, anchor="ls"):
    """Text in the language's own face, with the characters it lacks (an arrow, a dot) drawn in the system face on the same baseline.
    A line that one face covers is drawn whole, so right-to-left shaping stays intact."""
    rs = lc.runs(text, sp)
    if len(rs) == 1 and rs[0][1]:
        d.text(xy, text, font=lc.load(sp, px), fill=fill, anchor=anchor, **(kw or {}))
        return
    fp, ff = lc.load(sp, px), lc.load(lc.FALLBACK[role], px)
    x, y = xy
    if anchor.startswith("r"):
        x -= sum((fp if ok else ff).getlength(seg) for seg, ok in rs)
    for seg, ok in rs:
        f = fp if ok else ff
        d.text((x, y), seg, font=f, fill=fill, anchor="ls")
        x += f.getlength(seg)


def fit_px(text, sp, role, px, max_w, kw=None, floor=0.55):
    """px, or smaller so that the line fits max_w."""
    w = mixed_width(text, sp, role, px, kw)
    return px if w <= max_w else max(px * floor, px * max_w / w)


def card_a_loc(layer, ox, oy, k, w, h, row):
    """card_a_light with the words of one language (right to left: the ring on the right, the text right-aligned)."""
    d = ImageDraw.Draw(layer)
    F, kw, rtl = lc.FONTS[row["script"]], lc.text_kw(row["code"]), row["rtl"]
    W_ = w * k
    rd = 196 * k
    ring_cx = (W_ - 48 * k - rd / 2) if rtl else (48 * k + rd / 2)
    sr.mini_ring(layer, ox + ring_cx, oy + h * k / 2, rd, 0.78, k, track=((184, 196, 220), 0.60))
    f1, f2 = sr.vfont(sr.SFR, 64 * k, "Heavy"), sr.vfont(sr.SFR, 31 * k, "Bold")
    w1, w2, g = f1.getlength("78"), f2.getlength("%"), 2 * k
    x = ox + ring_cx - (w1 + g + w2) / 2
    yb = oy + h * k / 2 + 22 * k
    xn, xp = (x + w2 + g, x) if row["pct_prefix"] else (x, x + w1 + g)
    d.text((xn, yb), "78", font=f1, fill=NAVY + (255,), anchor="ls")
    d.text((xp, yb), "%", font=f2, fill=NAVY + (255,), anchor="ls")
    avail = (w - 296 - 48) * k
    tpx, spx = fit_px(row["title"], F["semi"], "semi", 76 * k, avail, kw), fit_px(row["sub"], F["reg"], "reg", 46 * k, avail, kw)
    tx, anc = (ox + W_ - 296 * k, "rs") if rtl else (ox + 296 * k, "ls")
    draw_mixed(d, (tx, oy + 140 * k), row["title"], F["semi"], "semi", tpx, NAVY + (255,), kw, anc)
    draw_mixed(d, (tx, oy + 216 * k), row["sub"], F["reg"], "reg", spx, GREY_INK + (255,), kw, anc)


def card_b_loc(layer, ox, oy, k, w, h, row):
    F, kw, rtl = lc.FONTS[row["script"]], lc.text_kw(row["code"]), row["rtl"]
    W_ = w * k
    s = 92 * k
    sr.trend_icon(layer, (ox + W_ - 58 * k - s) if rtl else (ox + 58 * k), oy + h * k / 2 - s / 2 + 4 * k, s, MINT_INK, k)
    px = fit_px(row["track"], F["semi"], "semi", 68 * k, (w - 208 - 48) * k, kw)
    tx, anc = (ox + W_ - 208 * k, "rs") if rtl else (ox + 208 * k, "ls")
    draw_mixed(ImageDraw.Draw(layer), (tx, oy + h * k / 2 + 24 * k), row["track"], F["semi"], "semi", px, MINT_INK + (255,), kw, anc)


def real_card(img, src, crop, cx, cy, w, tilt, radius=52):
    """A crop of a real Simulator screen as a floating card: the app's own pixels, nothing redrawn."""
    tile = Image.open(os.path.join(SHOTS, src)).convert("RGB").crop(crop)
    h = round(tile.height * w / tile.width)

    def content(layer, ox, oy, k, w_, h_):
        t = tile.resize((w * k, h * k), Image.LANCZOS)
        m = sl.rounded_mask((w * k, h * k), radius * k)
        layer.paste(t.convert("RGBA"), (int(ox), int(oy)), m)

    return light_card(img, cx, cy, w, h, tilt, content, radius=radius, fill=None, shadow=0.60, shadow_rgb=(2, 5, 14), edge=(255, 255, 255, 70))


# ---- the ring on a solid disc (light grounds) ------------------------------------------------------------------------------

def badge_ring(img, cx, cy, d, value=0.78, shadow=0.30, row=None):
    """The readiness ring on a solid navy disc, flat: the app's round-capped arc over a track, SF Rounded numerals, a soft shadow."""
    s = int(d * 1.5) // 2 * 2
    x0, y0 = int(round(cx - s / 2)), int(round(cy - s / 2))
    k = 3
    disc = Image.new("L", (s * k, s * k), 0)
    ImageDraw.Draw(disc).ellipse([s * k / 2 - d * k / 2, s * k / 2 - d * k / 2, s * k / 2 + d * k / 2, s * k / 2 + d * k / 2], fill=255)
    disc = np.asarray(disc.resize((s, s), Image.LANCZOS), np.float32) / 255
    reg = sr.arr(img.crop((x0, y0, x0 + s, y0 + s)))
    sh = sr.blur_l(np.roll(disc, int(d * 0.045), axis=0), d * 0.05)
    reg = sr.over(reg, (10, 20, 50), sh * shadow)
    yy = (np.arange(s, dtype=np.float32)[:, None] - s / 2) / (d / 2)
    top = np.clip(0.5 - yy * 0.5, 0, 1)                         # a touch lighter at the top, like the app's night card
    col = np.array(NAVY, np.float32)[None, None, :] / 255 * (1 + 0.10 * top[:, :, None])
    reg = reg * (1 - disc[:, :, None]) + np.clip(col, 0, 1) * disc[:, :, None]
    dr = d * 0.80
    track, arc = sr.ring_masks(s, dr, dr * 0.135, value)
    reg = sr.over(reg, (196, 216, 255), track * 0.20)
    reg = sr.over(reg, SUN, arc)
    img.paste(sr.to_img(reg), (x0, y0))
    if row:
        F = lc.FONTS[row["script"]]
        sr.ring_numerals(img, cx, cy, dr, label=row["label"], label_font=lc.load(F["semi"], dr * 0.095 * LABEL_SCALE.get(row["script"], 1.0)),
                         pct_prefix=row["pct_prefix"], label_kw=lc.text_kw(row["code"]))
    else:
        sr.ring_numerals(img, cx, cy, dr)
    return (cx - d / 2, cy - d / 2, cx + d / 2, cy + d / 2)


# ---- backgrounds -----------------------------------------------------------------------------------------------------------------

def grain(img, amount=0.8, seed=3):
    a = sr.arr(img)
    a += np.random.default_rng(seed).normal(0, amount / 255, a.shape).astype(np.float32)
    return sr.to_img(np.clip(a, 0, 1))


def vignette(a, strength):
    h, w = a.shape[:2]
    yy = (np.arange(h, dtype=np.float32)[:, None] / h - 0.5) * 1.15
    xx = (np.arange(w, dtype=np.float32)[None, :] / w - 0.5)
    t = np.clip((np.sqrt(xx ** 2 + yy ** 2) - 0.36) / 0.5, 0, 1)
    return a * (1 - strength * t * t * (3 - 2 * t))[:, :, None]


def keep_clear(rects, x, y, r):
    return all(not (rc[0] - r < x < rc[2] + r and rc[1] - r < y < rc[3] + r) for rc in rects)


def confetti(img, rects, n, seed, colors, scale=1.0):
    """Little flat shapes (dots, four-point sparkles, plus signs) on the bright ground, kept clear of the given rectangles."""
    rng = np.random.default_rng(seed)
    W, H = img.size
    k = 2
    layer = Image.new("RGBA", (W * k, H * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    placed = 0
    tries = 0
    while placed < n and tries < n * 60:
        tries += 1
        x, y = rng.uniform(40, W - 40), rng.uniform(40, H - 40)
        r = rng.uniform(16, 34) * scale
        if not keep_clear(rects, x, y, r * 2.4):
            continue
        col = colors[int(rng.integers(0, len(colors)))] + (255,)
        kind = int(rng.integers(0, 3))
        if kind == 0:
            d.ellipse([(x - r * 0.6) * k, (y - r * 0.6) * k, (x + r * 0.6) * k, (y + r * 0.6) * k], fill=col)
        elif kind == 1:
            pts = []
            for i in range(8):
                rad = r * 1.5 if i % 2 == 0 else r * 0.34
                ang = math.pi / 4 * i - math.pi / 2
                pts.append(((x + rad * math.cos(ang)) * k, (y + rad * math.sin(ang)) * k))
            d.polygon(pts, fill=col)
        else:
            t = r * 0.34
            d.rounded_rectangle([(x - r) * k, (y - t) * k, (x + r) * k, (y + t) * k], radius=t * k, fill=col)
            d.rounded_rectangle([(x - t) * k, (y - r) * k, (x + t) * k, (y + r) * k], radius=t * k, fill=col)
        placed += 1
    layer = layer.resize((W, H), Image.LANCZOS)
    base = img.convert("RGBA")
    base.alpha_composite(layer)
    img.paste(base.convert("RGB"))


def sunny_bg(W, H):
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    t = np.clip(xx / W * 0.45 + yy / H * 0.55, 0, 1)[:, :, None]
    c0, c1 = np.array([255, 226, 112], np.float32) / 255, np.array([255, 189, 52], np.float32) / 255
    a = c0 * (1 - t) + c1 * t
    glow = np.exp(-(((xx - W * 0.30) / (W * 0.55)) ** 2 + ((yy - H * 0.38) / (H * 0.60)) ** 2))[:, :, None]
    a = sr.screen(a, (255, 244, 190), glow[:, :, 0] * 0.42)
    return sr.to_img(a)


def crest(xs, base, amp, lam, phase):
    return base + amp * np.sin(xs / lam + phase) + amp * 0.38 * np.sin(xs / (lam * 0.41) + phase * 1.9)


def hill(img, ys_fn, color_top, color_bot, rim=None, ss=2):
    """A flat hill: the area under a crest function, lit a little along its edge."""
    W, H = img.size
    xs = np.arange(0, W + 8, 8, dtype=np.float32)
    ys = ys_fn(xs)
    y0 = int(ys.min()) - 20
    big = Image.new("L", (W * ss, (H - y0) * ss), 0)
    pts = [(float(x) * ss, float(y - y0) * ss) for x, y in zip(xs, ys)] + [(W * ss, (H - y0) * ss), (0, (H - y0) * ss)]
    ImageDraw.Draw(big).polygon(pts, fill=255)
    m = np.asarray(big.resize((W, H - y0), Image.LANCZOS), np.float32) / 255
    reg = sr.arr(img.crop((0, y0, W, H)))
    rows = np.linspace(0, 1, H - y0, dtype=np.float32)[:, None, None]
    col = np.array(color_top, np.float32)[None, None, :] / 255 * (1 - rows) + np.array(color_bot, np.float32)[None, None, :] / 255 * rows
    reg = reg * (1 - m[:, :, None]) + col * m[:, :, None]
    if rim is not None:
        edge = np.clip(m - np.roll(m, 14, axis=0), 0, 1)
        reg = sr.screen(reg, rim, sr.blur_l(edge, 3) * 0.55)
    img.paste(sr.to_img(reg), (0, y0))


def paper_bg(W, H, seed=11):
    rng = np.random.default_rng(seed)
    a = np.zeros((H, W, 3), np.float32) + np.array([248, 243, 229], np.float32) / 255
    lp = H / 17.0
    ruled = np.zeros((H, W), np.float32)
    for i in range(1, 17):
        y = int(round(H * 0.07 + i * lp))
        if y < H - 4:
            ruled[y - 3:y + 3, :] = 1.0
    a = sr.over(a, (150, 190, 236), ruled * 0.50)
    mx = int(W * 0.165)
    margin = np.zeros((H, W), np.float32)
    margin[:, mx - 3:mx + 3] = 1.0
    a = sr.over(a, (240, 120, 140), margin * 0.46)
    low = sr.blur_l(rng.random((H, W)).astype(np.float32), 60) - 0.5
    a = a * (1 + low[:, :, None] * 0.05)
    a = vignette(a, 0.10)
    return sr.to_img(np.clip(a, 0, 1))


def marker(img, box, color=(255, 223, 84), seed=4, tilt=-0.7):
    """A yellow highlighter swipe behind the words (multiplied, so the ink stays dark), a little rough at the ends."""
    rng = np.random.default_rng(seed)
    x0, y0, x1, y1 = box
    ss = 2
    W, H = img.size
    m = Image.new("L", (W * ss, H * ss), 0)
    d = ImageDraw.Draw(m)
    xs = np.linspace(x0, x1, 40)
    top = [(x, y0 + (x - x0) * math.tan(math.radians(tilt)) + rng.uniform(-6, 6)) for x in xs]
    bot = [(x, y1 + (x - x0) * math.tan(math.radians(tilt)) + rng.uniform(-6, 6)) for x in xs[::-1]]
    pts = [(p[0] - 14, p[1]) for p in top[:1]] + top + [(top[-1][0] + 22, (top[-1][1] + bot[0][1]) / 2)] + bot + [(bot[-1][0] - 20, (top[0][1] + bot[-1][1]) / 2)]
    d.polygon([(px * ss, py * ss) for px, py in pts], fill=255)
    mm = np.asarray(m.resize((W, H), Image.LANCZOS).filter(ImageFilter.GaussianBlur(1.5)), np.float32) / 255
    a = sr.arr(img)
    tint = np.asarray(color, np.float32)[None, None, :] / 255
    a = a * (1 - mm[:, :, None] * 0.95) + a * tint * mm[:, :, None] * 0.95
    img.paste(sr.to_img(a))


# ---- the four directions -------------------------------------------------------------------------------------------------------

def inside(box, b):
    return b[0] >= box[0] and b[1] >= box[1] and b[2] <= box[2] and b[3] <= box[3]


NIGHT = {
    "card": dict(ring=(3430, 860, 640), cap=dict(height=700, left=3070, feet=2160), bank=dict(plateau=1950, toe_y=2640, x0=2000, x1=2960),
                 cards=dict(a=(1500, 420, 1080, 330, -4), b=(1100, 2150, 880, 210, 3))),
    "header": dict(ring=(3290, 470, 520), cap=dict(height=600, left=3010, feet=1450), bank=dict(plateau=1292, toe_y=1720, x0=2200, x1=2900),
                   cards=dict(a=(560, 420, 900, 280, -4), b=(540, 1130, 760, 190, 3))),
}


def d_night(fmt, copy, plates):
    L = NIGHT[fmt]
    box = sr.box_px(fmt)
    img = sr.load_plate(fmt, plates)
    sl.scrim(img, box, 1, strength=0.46, grow=190, feather=190)
    sr.draw_bank(img, L["bank"])
    cap = sr.place_cap(img, L["cap"]["left"], L["cap"]["feet"], L["cap"]["height"], flip=True)
    extras = {"cap": cap}
    for key, fn in (("a", sr.card_a), ("b", sr.card_b)):
        cx, cy, w, h, tilt = L["cards"][key]
        extras["card_" + key] = sr.glass_card(img, cx, cy, w, h, tilt, fn)
    cx, cy, d = L["ring"]
    extras["ring"] = sr.draw_ring(img, cx, cy, d)
    sr.ring_numerals(img, cx, cy, d)
    hl = layout_headline(COPY[copy]["lines"], box)
    render_headline(img, hl, [WHITE, YELLOW], shadow=0.6)
    return sr.finish(img), hl, extras


POSTER = {
    "card": dict(ring=(3430, 860, 640), cap=dict(pose="plan", height=840, left=3090), cards=dict(a=(1500, 420, 1080, 330, -4), b=(1100, 2190, 880, 210, 3)),
                 hills=dict(back=(2140, 70, 700, 0.6), front=(2330, 80, 900, 2.4))),
    "header": dict(ring=(3290, 520, 520), cap=dict(pose="plan", height=650, left=3040), cards=dict(a=(560, 420, 900, 280, -4), b=(540, 1130, 760, 190, 3)),
                   hills=dict(back=(1330, 50, 600, 0.6), front=(1470, 55, 760, 2.4))),
}


def ring_clearance(cx, cy, d, rects):
    """How far the ring's edge is from the nearest of the rectangles (negative: they overlap). Conservative: the pill's corners are round."""
    return min(math.hypot(cx - min(max(cx, r[0]), r[2]), cy - min(max(cy, r[1]), r[3])) - d / 2 for r in rects)


def fit_ring(cx, cy, d, rects, W, gap=60, direction=1):
    """Keep a big ring clear of the words: slide it towards the frame's edge while there is room (right for a left-to-right layout,
    left for a mirrored one), then shrink it with its outer edge fixed."""
    d0 = d
    while ring_clearance(cx, cy, d, rects) < gap:
        if direction > 0 and cx + d / 2 + 20 <= W - 24:
            cx += 20
        elif direction < 0 and cx - d / 2 - 20 >= 24:
            cx -= 20
        elif d > d0 * 0.7:
            d -= 20
            cx += 10 * direction
        else:
            break
    return cx, cy, d


def mirror_layout(L, W, capw):
    """The same picture right to left: ring, Cap and cards swap sides (their tilt flips)."""
    import copy
    M = copy.deepcopy(L)
    cx, cy, d = M["ring"]
    M["ring"] = (W - cx, cy, d)
    M["cap"]["left"] = W - L["cap"]["left"] - capw
    for k_, (cx, cy, w, h, tilt) in L["cards"].items():
        M["cards"][k_] = (W - cx, cy, w, h, -tilt)
    return M


def d_poster(fmt, copy, plates, layouts=None, row=None):
    """The sunny poster. row: one language from locales.py (its words, its fonts, right to left); None: the English poster as approved."""
    L = (layouts or POSTER)[fmt]
    W, H = SIZE[fmt]
    box = sr.box_px(fmt)
    rtl = bool(row and row["rtl"])
    lines = row["lines"] if row else COPY[copy]["lines"]
    F = lc.FONTS[row["script"]] if row else None
    kw = lc.text_kw(row["code"]) if row else {}
    cap_h = L["cap"]["height"]
    pa = pose_art("plan")
    capw = round(pa.width * cap_h / pa.height)
    cx_cap = L["cap"]["left"] + cap_h * 0.36
    if rtl:
        L = mirror_layout(L, W, capw)
        cx_cap = W - cx_cap
    img = sunny_bg(W, H)
    b, f_ = L["hills"]["back"], L["hills"]["front"]
    hill(img, lambda xs: crest(xs, b[0], b[1], b[2], b[3]), (110, 214, 170), (34, 183, 138), rim=(255, 255, 255))
    hill(img, lambda xs: crest(xs, f_[0], f_[1], f_[2], f_[3]), (34, 195, 142), (18, 150, 110), rim=(200, 255, 230))
    # the words first (nothing else moves them): line 1 in navy on the sun, line 2 in sun on a navy pill
    pad = 0.15
    head = dict(sp=F["head"] if F else None, kw=kw, align="right" if rtl else "left")
    hl0 = layout_headline(lines, box, fit_h=0.80, margin=44, pitch=1.03, **head)
    hl = layout_headline(lines, box, fit_h=0.80, margin=44, pitch=1.03, left=box[0] + 44 + hl0["px"] * pad, right=box[2] - 44 - hl0["px"] * pad, **head)
    px = hl["px"]
    ink = hl["items"][1]["ink"]
    pill = (ink[0] - px * pad, ink[1] - px * 0.05, ink[2] + px * pad, ink[3] + px * 0.06)
    hl["pill"] = pill
    words = ink_boxes(hl) + [pill]
    feet = float(crest(np.array([cx_cap], np.float32), f_[0], f_[1], f_[2], f_[3])[0]) + 18
    extras = {}
    confetti(img, [box, (L["cap"]["left"] - 60, feet - cap_h - 40, L["cap"]["left"] + capw + 60, feet + 40)], 26 if fmt == "card" else 18, 5,
             [WHITE, (124, 200, 255), (34, 195, 142), (255, 90, 120), (255, 122, 26)], scale=1.0 if fmt == "card" else 0.8)
    for key, base in (("a", CARD_A), ("b", CARD_B)):
        cx, cy, w, h, tilt = L["cards"][key]
        z = w / base[0]
        if row:
            loc_fn = card_a_loc if key == "a" else card_b_loc
            content = scaled(lambda layer, ox, oy, k, w_, h_, fn=loc_fn: fn(layer, ox, oy, k, w_, h_, row), z)
        else:
            content = scaled(card_a_light if key == "a" else card_b_light, z)
        extras["card_" + key] = light_card(img, cx, cy, w, h, tilt, content, radius=round(58 * z))
    cx, cy, d = fit_ring(*L["ring"], words, W, direction=-1 if rtl else 1)
    extras["ring"] = badge_ring(img, cx, cy, d, row=row)
    hl["ring_gap"] = round(ring_clearance(cx, cy, d, words))
    extras["cap"] = place_pose(img, "plan", L["cap"]["left"], feet, cap_h, flip=rtl, ground=0.35, shadow_rgb=(6, 70, 52))
    ss = 2
    pm = Image.new("L", (W * ss, H * ss), 0)
    ImageDraw.Draw(pm).rounded_rectangle([v * ss for v in pill], radius=(pill[3] - pill[1]) * ss * 0.5, fill=255)
    pm = pm.resize((W, H), Image.LANCZOS)
    img.paste(Image.new("RGB", (W, H), (10, 20, 50)), (0, 0), pm.filter(ImageFilter.GaussianBlur(26)).point(lambda v: int(v * 0.22)))
    img.paste(Image.new("RGB", (W, H), NAVY), (0, 0), pm)
    render_headline(img, hl, [NAVY, YELLOW])
    return grain(img, 0.7), hl, extras


POSTER2 = {
    "card": dict(ring=(3330, 810, 900), cap=dict(pose="plan", height=900, left=3070), cards=dict(a=(1500, 430, 1512, 462, -4), b=(1060, 2190, 1232, 294, 3)),
                 hills=dict(back=(2140, 70, 700, 0.6), front=(2330, 80, 900, 2.4))),
    "header": dict(ring=(3000, 500, 780), cap=dict(pose="plan", height=740, left=3290), cards=dict(a=(640, 300, 1250, 382, -4), b=(560, 1180, 1056, 252, 3)),
                   hills=dict(back=(1330, 50, 600, 0.6), front=(1470, 55, 760, 2.4))),
}


def d_poster2(fmt, copy, plates):
    return d_poster(fmt, copy, plates, POSTER2)


def d_poster2_row(fmt, row):
    """The approved poster in one language (locales.py), for build_locales.py."""
    return d_poster(fmt, "day", None, POSTER2, row)


SCREENS = {
    "card": dict(cap=dict(pose="scan", height=640, left=130, feet=2360), bank=dict(plateau=2250, toe_y=2800, x0=2000, x1=2900), mirror=True,
                 real=[("w-done/review.png", (0, 740, 1206, 1290), 1120, 1040, 410, -3),
                       ("graded-w9/session.png", (0, 775, 1206, 1325), 1120, 2380, 400, 2),
                       ("exameve/session.png", (0, 1548, 1206, 1905), 1240, 2640, 2130, -2)],
                 yw=1900),
    "header": dict(cap=dict(pose="scan", height=560, left=3060, feet=1540), bank=dict(plateau=1440, toe_y=1760, x0=2400, x1=3000), mirror=False,
                   real=[("w-done/review.png", (0, 740, 1206, 1290), 860, 560, 330, -3),
                         ("graded-w9/session.png", (0, 775, 1206, 1325), 860, 540, 960, 2),
                         ("exameve/session.png", (0, 1548, 1206, 1905), 900, 3300, 330, -2)],
                   yw=1300),
}


def d_screens(fmt, copy, plates):
    L = SCREENS[fmt]
    W, H = SIZE[fmt]
    box = sr.box_px(fmt)
    img = sa.render_scene("night", 1.0, canvas=(W, H), yw=L["yw"], supporting=0.55, avoid=(box[0] - 40, box[1] - 40, box[2] + 40, box[3] + 40)).convert("RGB")
    sl.scrim(img, box, 1, strength=0.58, grow=210, feather=200)
    if L["mirror"]:
        img = ImageOps.mirror(img)
        sr.draw_bank(img, L["bank"])
        img = ImageOps.mirror(img)
    else:
        sr.draw_bank(img, L["bank"])
    extras = {"cap": place_pose(img, L["cap"]["pose"], L["cap"]["left"], L["cap"]["feet"], L["cap"]["height"], ground=0.55, shadow_rgb=(2, 4, 12))}
    for i, (src, crop, w, cx, cy, tilt) in enumerate(L["real"]):
        extras[f"real_{i}"] = real_card(img, src, crop, cx, cy, w, tilt)
    hl = layout_headline(COPY[copy]["lines"], box)
    render_headline(img, hl, [WHITE, YELLOW], shadow=0.6)
    return sr.finish(img), hl, extras


NOTEBOOK = {
    "card": dict(ring=(3430, 860, 640), cap=dict(pose="listen", height=820, left=3050, feet=2330), cards=dict(a=(1500, 420, 1080, 330, -4), b=(1100, 2190, 880, 210, 3))),
    "header": dict(ring=(3290, 520, 520), cap=dict(pose="listen", height=640, left=3050, feet=1520), cards=dict(a=(560, 420, 900, 280, -4), b=(540, 1130, 760, 190, 3))),
}


def d_notebook(fmt, copy, plates):
    L = NOTEBOOK[fmt]
    W, H = SIZE[fmt]
    box = sr.box_px(fmt)
    img = paper_bg(W, H)
    hl = layout_headline(COPY[copy]["lines"], box)
    ink = hl["items"][1]["ink"]
    px = hl["px"]
    marker(img, (ink[0] - px * 0.06, ink[1] + px * 0.14, ink[2] + px * 0.05, ink[3] - px * 0.02))
    extras = {}
    for key, fn in (("a", card_a_light), ("b", card_b_light)):
        cx, cy, w, h, tilt = L["cards"][key]
        extras["card_" + key] = light_card(img, cx, cy, w, h, tilt, fn, shadow=0.26)
    cx, cy, d = L["ring"]
    extras["ring"] = badge_ring(img, cx, cy, d)
    extras["cap"] = place_pose(img, L["cap"]["pose"], L["cap"]["left"], L["cap"]["feet"], L["cap"]["height"], outline=30)
    render_headline(img, hl, [NAVY, NAVY])
    return grain(img, 0.8), hl, extras


DIRECTIONS = {
    "night": dict(name="Night lake", fn=d_night, idea="Painted night scenery, the readiness ring, Cap at his telescope: calm and premium."),
    "poster": dict(name="Sunny poster", fn=d_poster, idea="Flat, bright and bold: Cap with the exam-day calendar. The loudest thumbnail."),
    "poster2": dict(name="Sunny poster, bigger badges", fn=d_poster2, idea="The poster with the ring and both cards much bigger."),
    "screens": dict(name="The app itself", fn=d_screens, idea="The app's own night sky with crops of the real screens around the words."),
    "notebook": dict(name="Notebook", fn=d_notebook, idea="Notes made literal: ruled paper, a highlighter, Cap taking notes."),
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="comma-separated directions")
    ap.add_argument("--fmt", choices=("card", "header"))
    ap.add_argument("--copy", default="", help="comma-separated copy ids (default: day, and for night also notes and know)")
    ap.add_argument("--plates", default=sr.PLATES)
    ap.add_argument("--out", default=OUT)
    a = ap.parse_args()
    only = [s for s in a.only.split(",") if s] or list(DIRECTIONS)
    layouts = {}
    for did in only:
        D = DIRECTIONS[did]
        copies = [s for s in a.copy.split(",") if s] or (["day", "notes", "know"] if did in ("night", "poster2") else ["day"])
        os.makedirs(os.path.join(a.out, did), exist_ok=True)
        for cid in copies:
            for fmt in ([a.fmt] if a.fmt else ["card", "header"]):
                img, hl, extras = D["fn"](fmt, cid, a.plates)
                box = sr.box_px(fmt)
                name = os.path.join(a.out, did, f"{cid}-{fmt}")
                img.save(name + ".png")
                img.crop(box).save(name + "-box.png")
                dbg = img.copy()
                ImageDraw.Draw(dbg).rectangle(box, outline=(255, 90, 120), width=6)
                dbg.save(name + "-safe.png")
                heads = [[round(v) for v in b] for b in ink_boxes(hl)]
                ok = all(inside(box, b) for b in ink_boxes(hl)) and (inside(box, hl["pill"]) if "pill" in hl else True)
                layouts[f"{did}/{cid}/{fmt}"] = dict(size=list(SIZE[fmt]), box=list(box), headline_px=hl["px"], headline=heads, headline_inside=ok,
                                                      lines=COPY[cid]["lines"], extras={k: [round(v) for v in b] for k, b in extras.items()})
                print(f"{did:9s} {cid:6s} {fmt:6s} headline {hl['px']:4d} px  inside box: {ok}" + (f"  ring clear of the words by {hl['ring_gap']} px" if "ring_gap" in hl else ""), flush=True)
    path = os.path.join(a.out, "layout.json")
    old = json.load(open(path)) if os.path.exists(path) else {}
    old.update(layouts)
    with open(path, "w") as f:
        json.dump(old, f, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
