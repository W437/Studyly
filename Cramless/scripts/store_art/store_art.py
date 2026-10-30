#!/usr/bin/env python3
"""Capling's App Store header and search-results art, drawn from the app's own pieces (no AI spend).

iOS 27's product page header and Search-results slot take one 16:9 "universal asset" (5244x2950 png, no alpha). Apple's template keeps
the art inside a box 1401x961 at (1922, 660); everything outside it may be cropped (21:9 header, 3:2 search card), so it is only sky.

What is drawn comes from the app:
  - the six skies and their colours: Shared/SkyTheme.swift (night is the default, the other five are the seasonal swaps)
  - the constellation Cap's mortarboard makes, in seven stars: Cramless/Features/Onboarding/WelcomeSky.swift (same points, same lines)
  - the star look (a core, a ring, a halo, a glow; dim stars are hollow rings on dashed lines): Features/Sky/SkyRenderer.swift
  - Cap looking through his telescope: docs/rethink/brand/raw/candidates/cap-stargaze-N.png (1024 px, transparent)

    python3 -P store_art.py universal --theme night --out build/store-art/universal-night.png
    python3 -P store_art.py universal --theme dusk --scale 0.25 --out /tmp/look.png     # a quick look
    python3 -P store_art.py crops build/store-art/universal-night.png --out build/store-art/preview   # header 21:9 + search 3:2

Needs only Pillow and NumPy. Run heavy renders through `simq run media -- python3 -P ...`.
"""
import argparse
import math
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", ".."))

W, H = 5244, 2950                      # the universal asset
SAFE = (1922, 660, 1922 + 1401, 660 + 961)   # Apple's art safe area for it (measured from their PSD template, 2026-10-28)
YW = 1620                              # the waterline, the bottom of the safe area
BASE_W, BASE_YW = 5244, 1620           # positions below are written for the universal canvas and scaled to any other


def set_canvas(w, h, yw):
    """The scene is drawn for any canvas size: the header and search cards have their own."""
    global W, H, YW
    W, H, YW = w, h, yw


def fx(x):
    return x * W / BASE_W


def fy(y):
    return y * YW / BASE_YW

# ---------------------------------------------------------------------------------------------------------------- colours


def rgb(h):
    return np.array([(h >> 16) & 255, (h >> 8) & 255, h & 255], np.float32) / 255


WHITE = np.array([1, 1, 1], np.float32)

# Shared/SkyTheme.swift, copied (sky top/bottom, horizon glow high/mid/low, haze cool/warm, dust cool/warm, far hills, mid hills, water,
# ground, crest warm/cool). If the app's skies change, change these.
THEMES = {
    "night": dict(sky=(0x070D1B, 0x14213D), glow=(0x6C46A8, 0xE4708C, 0xFFB070), haze=(0xA9B8FF, 0xFFD9B0), dust=(0xC7DEFF, 0xFFE6C2),
                  far=(0x333E78, 0x1A2350), mid=(0x212D5E, 0x121C3E), water=(0x24396E, 0x0C1432), ground=(0x131F3E, 0x080E22),
                  crest=(0xFFE2C4, 0xB9C6FF)),
    "dusk": dict(sky=(0x0F0A28, 0x2A1A5A), glow=(0x7A3FD0, 0xE0507E, 0xFFB070), haze=(0xC9B0FF, 0xFFC9A8), dust=(0xE4D4FF, 0xFFD9C2),
                 far=(0x43307A, 0x261A52), mid=(0x30225A, 0x1B1240), water=(0x362A78, 0x140C36), ground=(0x1A1034, 0x0C0722),
                 crest=(0xFFC9B0, 0xCDBDFF)),
    "aurora": dict(sky=(0x04141A, 0x0B2E33), glow=(0x2BD9A0, 0x39B6C8, 0x7A5BE0), haze=(0x9BFFE0, 0xC9FFE8), dust=(0xC9FFEE, 0xE8FFD8),
                   far=(0x1F5560, 0x10343C), mid=(0x153F48, 0x0B2830), water=(0x1B4F5C, 0x07222B), ground=(0x0C2A30, 0x041418),
                   crest=(0xA5F5DC, 0x9FE3E8)),
    "ember": dict(sky=(0x1A0A0A, 0x3A1A14), glow=(0x9E2A2B, 0xFF6A2A, 0xFFC24A), haze=(0xFFB89A, 0xFFD9A0), dust=(0xFFD2B8, 0xFFE2A8),
                  far=(0x5A2A2A, 0x341616), mid=(0x421E1E, 0x240F0F), water=(0x4A2424, 0x1C0B0B), ground=(0x2A1212, 0x120606),
                  crest=(0xFFC9A0, 0xFFB08A)),
    "bloom": dict(sky=(0x1D1432, 0x4E3060), glow=(0xFF8FB8, 0xFFC4A0, 0xFFEBC8), haze=(0xFFD0E8, 0xFFE8D0), dust=(0xFFE0F2, 0xFFEAD8),
                  far=(0x7A4E7A, 0x452C57), mid=(0x5C3A66, 0x34204A), water=(0x6B4A82, 0x2A1A48), ground=(0x35204F, 0x19102B),
                  crest=(0xFFE6D4, 0xFFD0EC)),
    "glacier": dict(sky=(0x06121F, 0x163552), glow=(0x5AB8E8, 0x9CE6FF, 0xE8F8FF), haze=(0xD0ECFF, 0xFFFFFF), dust=(0xE6F6FF, 0xFFFFFF),
                    far=(0x3D6A8F, 0x1F3F5F), mid=(0x2A506F, 0x142D45), water=(0x2F6A94, 0x0C2238), ground=(0x153048, 0x08141F),
                    crest=(0xE4F6FF, 0xBFE4FF)),
}

# What a sky needs beyond its palette so Cap and the gold cap in the sky stay the brightest things in it.
TWEAKS = {"ember": dict(glow=0.62, haze=0.55, rim=0xBFD4FF, rim_amt=0.34)}
DEFAULT_TWEAK = dict(glow=1.0, haze=1.0, rim=None, rim_amt=0.30)

# The course colours (Shared/BrandPalette.swift): the stars keep them in every sky.
COURSE = dict(sky=0x7CC8FF, tangerine=0xFF7A1A, mint=0x22C38E, sun=0xFFCF3F, rose=0xFF5A78)

# ---------------------------------------------------------------------------------------------------------------- numpy helpers


def _boxes(sigma, n=3):
    ideal = math.sqrt(12 * sigma * sigma / n + 1)
    wl = int(math.floor(ideal))
    if wl % 2 == 0:
        wl -= 1
    wu = wl + 2
    m = round((12 * sigma * sigma - n * wl * wl - 4 * n * wl - 3 * n) / (-4 * wl - 4))
    return [(wl if i < m else wu) for i in range(n)]


def _box(a, r, axis):
    if r <= 0:
        return a
    n = a.shape[axis]
    pad = [(0, 0)] * a.ndim
    pad[axis] = (r + 1, r)
    c = np.cumsum(np.pad(a, pad, mode="edge"), axis=axis, dtype=np.float64)
    hi = [slice(None)] * a.ndim
    lo = [slice(None)] * a.ndim
    hi[axis] = slice(2 * r + 1, 2 * r + 1 + n)
    lo[axis] = slice(0, n)
    return ((c[tuple(hi)] - c[tuple(lo)]) / (2 * r + 1)).astype(np.float32)


def blur(a, sx, sy=None):
    """Gaussian blur (three box passes) of a float array (h, w) or (h, w, c); sx along x, sy along y."""
    sy = sx if sy is None else sy
    out = a
    if sx > 0.4:
        for w in _boxes(sx):
            out = _box(out, (w - 1) // 2, 1)
    if sy > 0.4:
        for w in _boxes(sy):
            out = _box(out, (w - 1) // 2, 0)
    return out


def resize2(a, w, h, method=Image.BICUBIC):
    """Resize a float32 (h, w) field."""
    return np.asarray(Image.fromarray(np.ascontiguousarray(a, np.float32), mode="F").resize((w, h), method), np.float32)


def fbm(rng, h, w, base, octaves=5, stretch=1.0):
    """Smooth noise in 0...1; `base` is the size of the biggest feature in px, `stretch` > 1 makes it wider than tall."""
    out = np.zeros((h, w), np.float32)
    amp, total = 1.0, 0.0
    size = float(base)
    for _ in range(octaves):
        gw = max(2, int(w / size) + 2)
        gh = max(2, int(h / (size / stretch)) + 2)
        out += amp * resize2(rng.random((gh, gw)).astype(np.float32), w, h)
        total += amp
        amp *= 0.5
        size /= 2
    return out / total


def smooth(x):
    x = np.clip(x, 0, 1)
    return x * x * (3 - 2 * x)


class Canvas:
    """A float RGB picture at `k` times the real size. All sizes given to it are in real (5244 px wide) pixels."""

    def __init__(self, k):
        self.k = k
        self.w = int(round(W * k))
        self.h = int(round(H * k))
        self.px = np.zeros((self.h, self.w, 3), np.float32)

    def _box(self, cx, cy, r):
        x0, x1 = max(0, int(cx - r)), min(self.w, int(cx + r) + 2)
        y0, y1 = max(0, int(cy - r)), min(self.h, int(cy + r) + 2)
        return x0, x1, y0, y1

    def _grid(self, x0, x1, y0, y1, cx, cy):
        ys = (np.arange(y0, y1, dtype=np.float32) + 0.5 - cy)[:, None]
        xs = (np.arange(x0, x1, dtype=np.float32) + 0.5 - cx)[None, :]
        return xs, ys

    def glow(self, x, y, sigma, color, amount):
        """A soft round glow, screen-blended."""
        k = self.k
        cx, cy, s = x * k, y * k, sigma * k
        x0, x1, y0, y1 = self._box(cx, cy, 3.4 * s)
        if x0 >= x1 or y0 >= y1:
            return
        xs, ys = self._grid(x0, x1, y0, y1, cx, cy)
        g = np.exp(-(xs * xs + ys * ys) / (2 * s * s)) * amount
        sub = self.px[y0:y1, x0:x1]
        self.px[y0:y1, x0:x1] = 1 - (1 - sub) * (1 - g[:, :, None] * color[None, None, :])

    def disc(self, x, y, r, color, alpha=1.0):
        k = self.k
        cx, cy, rr = x * k, y * k, r * k
        x0, x1, y0, y1 = self._box(cx, cy, rr + 2)
        if x0 >= x1 or y0 >= y1:
            return
        xs, ys = self._grid(x0, x1, y0, y1, cx, cy)
        a = np.clip(rr + 0.5 - np.sqrt(xs * xs + ys * ys), 0, 1)[:, :, None] * alpha
        sub = self.px[y0:y1, x0:x1]
        self.px[y0:y1, x0:x1] = sub * (1 - a) + color[None, None, :] * a

    def ring(self, x, y, r, width, color, alpha=1.0, dashes=0):
        k = self.k
        cx, cy, rr, ww = x * k, y * k, r * k, max(width * k, 1.0)
        x0, x1, y0, y1 = self._box(cx, cy, rr + ww + 2)
        if x0 >= x1 or y0 >= y1:
            return
        xs, ys = self._grid(x0, x1, y0, y1, cx, cy)
        d = np.sqrt(xs * xs + ys * ys)
        a = np.clip(ww / 2 + 0.5 - np.abs(d - rr), 0, 1)
        if dashes:
            ang = (np.arctan2(ys, xs) / (2 * math.pi)) * dashes
            a = a * (np.mod(ang, 1.0) < 0.5)
        a = a[:, :, None] * alpha
        sub = self.px[y0:y1, x0:x1]
        self.px[y0:y1, x0:x1] = sub * (1 - a) + color[None, None, :] * a

    def line(self, x_a, y_a, x_b, y_b, width, color, alpha=1.0, dash=None):
        k = self.k
        ax, ay, bx, by = x_a * k, y_a * k, x_b * k, y_b * k
        ww = max(width * k, 1.0)
        x0, x1 = max(0, int(min(ax, bx) - ww - 2)), min(self.w, int(max(ax, bx) + ww + 3))
        y0, y1 = max(0, int(min(ay, by) - ww - 2)), min(self.h, int(max(ay, by) + ww + 3))
        if x0 >= x1 or y0 >= y1:
            return
        xs = (np.arange(x0, x1, dtype=np.float32) + 0.5)[None, :]
        ys = (np.arange(y0, y1, dtype=np.float32) + 0.5)[:, None]
        dx, dy = bx - ax, by - ay
        ln2 = dx * dx + dy * dy
        t = np.clip(((xs - ax) * dx + (ys - ay) * dy) / max(ln2, 1e-6), 0, 1)
        d = np.sqrt((xs - (ax + t * dx)) ** 2 + (ys - (ay + t * dy)) ** 2)
        a = np.clip(ww / 2 + 0.5 - d, 0, 1)
        if dash:
            seg = math.sqrt(ln2)
            a = a * (np.mod(t * seg / (dash * k), 1.0) < 0.5)
        a = a[:, :, None] * alpha
        sub = self.px[y0:y1, x0:x1]
        self.px[y0:y1, x0:x1] = sub * (1 - a) + color[None, None, :] * a

    def spark(self, x, y, length, thick, color, alpha=1.0):
        """A four-point sparkle: two thin tapering cross-bars."""
        k = self.k
        cx, cy, ln, th = x * k, y * k, length * k, max(thick * k, 0.9)
        x0, x1, y0, y1 = self._box(cx, cy, ln)
        if x0 >= x1 or y0 >= y1:
            return
        xs, ys = self._grid(x0, x1, y0, y1, cx, cy)
        horiz = np.exp(-(ys * ys) / (2 * th * th)) * np.clip(1 - np.abs(xs) / ln, 0, 1) ** 2
        vert = np.exp(-(xs * xs) / (2 * th * th)) * np.clip(1 - np.abs(ys) / ln, 0, 1) ** 2
        g = np.clip(horiz + vert, 0, 1) * alpha
        sub = self.px[y0:y1, x0:x1]
        self.px[y0:y1, x0:x1] = 1 - (1 - sub) * (1 - g[:, :, None] * color[None, None, :])


# ---------------------------------------------------------------------------------------------------------------- the scene


def ridge(w, base, amps, waves, seed, k):
    """A hill line: y for every column of a canvas `w` px wide, in canvas px."""
    rng = np.random.default_rng(seed)
    x = np.arange(w, dtype=np.float32) / k
    y = np.full(w, float(base), np.float32)
    for amp, wave in zip(amps, waves):
        y += amp * np.sin(2 * math.pi * x / wave + rng.random() * 2 * math.pi)
    return y * k


def paint_sky(cv, p, rng, tw=DEFAULT_TWEAK):
    k, w, h = cv.k, cv.w, cv.h
    yw = YW * k
    top, bottom = rgb(p["sky"][0]), rgb(p["sky"][1])
    t = np.clip((np.arange(h, dtype=np.float32) + 0.5) / yw, 0, 1)[:, None, None]
    t = t ** 1.15
    cv.px[:] = top[None, None, :] * (1 - t) + bottom[None, None, :] * t

    # the dusk at the horizon: purple high up, rose, then amber where the hills begin (screen-blended, at 1/8 size)
    s = 8
    gh, gw = h // s + 1, w // s + 1
    ys = (np.arange(gh, dtype=np.float32) * s + 0.5) / k
    xs = (np.arange(gw, dtype=np.float32) * s + 0.5) / k
    X, Y = np.meshgrid(xs, ys)
    xmod = 0.55 + 0.45 * np.exp(-((X - fx(2700)) / fx(2300.0)) ** 2)
    glow = np.zeros((gh, gw, 3), np.float32)
    for col, mid, sig, amt in ((p["glow"][0], fy(900), fy(330), 0.30), (p["glow"][1], fy(1230), fy(190), 0.30), (p["glow"][2], fy(1440), fy(105), 0.42)):
        prof = np.exp(-((Y - mid) / sig) ** 2) * amt * xmod * tw["glow"]
        glow += prof[:, :, None] * rgb(col)[None, None, :]
    glow = np.stack([resize2(glow[:, :, c], w, h) for c in range(3)], axis=2)
    cv.px[:] = 1 - (1 - cv.px) * (1 - np.clip(glow, 0, 1))

    # the pale band of countless stars, rising to the right behind Cap and the cap in the sky
    ang = math.radians(-23)
    cx, cy = fx(2650.0), fy(1040.0)
    d = (-math.sin(ang) * (X - cx) + math.cos(ang) * (Y - cy))
    band = np.exp(-(d / 430.0) ** 2)
    noise = fbm(rng, gh, gw, 80, octaves=5)
    n2 = fbm(rng, gh, gw, 34, octaves=4)
    dens = band * (0.30 + 1.35 * noise) * (0.7 + 0.6 * n2)
    tint = np.clip(noise * 1.4 - 0.1, 0, 1)[:, :, None]
    hz = rgb(p["haze"][0])[None, None, :] * (1 - tint * 0.55) + rgb(p["haze"][1])[None, None, :] * tint * 0.55
    haze = np.stack([resize2(dens * hz[:, :, c], w, h) for c in range(3)], axis=2) * 0.28 * tw["haze"]
    cv.px[:] = 1 - (1 - cv.px) * (1 - np.clip(haze, 0, 1))
    return band, (X, Y)


def paint_dust(cv, p, rng, band_fn):
    k = cv.k
    cool, warm = rgb(p["dust"][0]), rgb(p["dust"][1])
    placed = 0
    stars = []
    while placed < 950:
        x = rng.random() * W
        y = (rng.random() ** 1.5) * (YW - 150)
        keep = 0.55 + 0.9 * band_fn(x, y)
        if rng.random() > keep:
            continue
        stars.append((x, y))
        placed += 1
    for i, (x, y) in enumerate(stars):
        u = rng.random()
        tier = 0 if u < 0.62 else 1 if u < 0.90 else 2
        r = (2.0 + 1.5 * rng.random()) if tier == 0 else (3.4 + 2.0 * rng.random()) if tier == 1 else (5.6 + 3.2 * rng.random())
        col = cool if rng.random() < 0.7 else warm
        alpha = (0.40, 0.66, 0.90)[tier] * (0.75 + 0.25 * rng.random())
        cv.glow(x, y, r * 2.6, col, (0.10, 0.17, 0.26)[tier])
        cv.disc(x, y, r, col, alpha)
        if tier == 2 and rng.random() < 0.22:
            cv.spark(x, y, r * 6.0, max(1.2, r * 0.2), col, 0.6)


def paint_hills(cv, p):
    k, w, h = cv.k, cv.w, cv.h
    yw = YW * k
    rows = np.arange(h, dtype=np.float32)[:, None] + 0.5

    def hill(line, pair, y_to):
        top, bottom = rgb(pair[0]), rgb(pair[1])
        y0 = int(max(0, line.min() - 4))
        y1 = int(min(h, y_to)) + 1
        r = rows[y0:y1]
        a = np.clip(r - line[None, :] + 0.5, 0, 1)
        tt = np.clip((r - line[None, :]) / np.maximum(1.0, y_to - line[None, :]), 0, 1)[:, :, None]
        col = top[None, None, :] * (1 - tt) + bottom[None, None, :] * tt
        sub = cv.px[y0:y1]
        cv.px[y0:y1] = sub * (1 - a[:, :, None]) + col * a[:, :, None]
        return y0, y1

    far = ridge(w, YW - 235, (62, 34, 18), (3100, 1250, 520), 11, k)
    mid = ridge(w, YW - 125, (44, 26, 12), (2500, 960, 410), 23, k)

    # mist on the far ridge, then the hill, then its lit crest
    hill(far, p["far"], yw)
    y0, y1 = int(max(0, far.min() - 190 * k)), int(far.max() + 40 * k)
    r = rows[y0:y1]
    above = np.exp(-((far[None, :] - r) / (95 * k)) ** 2) * (r < far[None, :] + 6 * k)
    cool = rgb(p["crest"][1])
    sub = cv.px[y0:y1]
    cv.px[y0:y1] = 1 - (1 - sub) * (1 - above[:, :, None] * cool[None, None, :] * 0.16)
    rim = np.exp(-((r - far[None, :] - 1.5 * k) / (5.5 * k)) ** 2) * (r > far[None, :] - 3 * k)
    warm = rgb(p["crest"][0])
    sub = cv.px[y0:y1]
    cv.px[y0:y1] = 1 - (1 - sub) * (1 - rim[:, :, None] * warm[None, None, :] * 0.38)
    # the second ridge, with a little mist between the two
    y0, y1 = int(mid.min() - 120 * k), int(mid.max() + 20 * k)
    r = rows[y0:y1]
    mist = np.exp(-((mid[None, :] - r) / (70 * k)) ** 2) * (r < mid[None, :] + 4 * k)
    sub = cv.px[y0:y1]
    cv.px[y0:y1] = 1 - (1 - sub) * (1 - mist[:, :, None] * cool[None, None, :] * 0.10)
    hill(mid, p["mid"], yw)
    return far, mid


def lit_star(cv, x, y, r, color, ring=True, spark=0.0, glow=1.0):
    core = color * 0.35 + WHITE * 0.65
    cv.glow(x, y, r * 7.5, color, 0.16 * glow)
    cv.glow(x, y, r * 3.0, color, 0.60 * glow)
    cv.disc(x, y, r * 3.4, color, 0.07)
    if ring:
        cv.ring(x, y, r * 1.62, max(2.0, r * 0.13), color, 0.62)
    cv.disc(x, y, r, core, 1.0)
    if spark:
        cv.spark(x, y, r * spark, max(1.4, r * 0.11), WHITE * 0.4 + color * 0.6, 0.9)


def dim_star(cv, x, y, r, color):
    ghost = color * 0.45 + WHITE * 0.55
    cv.glow(x, y, r * 4.0, color, 0.10)
    cv.ring(x, y, r * 1.05, max(2.0, r * 0.16), ghost, 0.62)
    cv.disc(x, y, r * 0.28, ghost, 0.55)


def constellation(cv, pts, lines, color, lit, r, rng=None, nebula=True, region=None, strength=1.0, hero=False):
    """pts in real px; lit=True draws bright stars on solid lines, lit=False hollow rings on dashed lines (a fading memory)."""
    if region and nebula:
        (rx, ry, rr) = region
        k = cv.k
        cx, cy, R = rx * k, ry * k, rr * k
        x0, x1, y0, y1 = cv._box(cx, cy, R)
        xs, ys = cv._grid(x0, x1, y0, y1, cx, cy)
        g = np.clip(1 - np.sqrt(xs * xs + ys * ys) / R, 0, 1) ** 1.6 * (0.10 if lit else 0.05) * strength
        sub = cv.px[y0:y1, x0:x1]
        cv.px[y0:y1, x0:x1] = 1 - (1 - sub) * (1 - g[:, :, None] * color[None, None, :])
        cv.ring(rx, ry, rr, 2.2, color, 0.30 if lit else 0.20, dashes=int(rr / 14))
    for a, b in lines:
        (xa, ya), (xb, yb) = pts[a], pts[b]
        if lit:
            cv.line(xa, ya, xb, yb, max(2.6, r * (0.24 if hero else 0.2)), color * 0.45 + WHITE * 0.55, (0.85 if hero else 0.5) * strength)
        else:
            cv.line(xa, ya, xb, yb, max(2.2, r * 0.16), color * 0.5 + WHITE * 0.5, 0.35, dash=26)
    for i, (x, y) in enumerate(pts):
        if lit:
            lit_star(cv, x, y, r * (1.0 + 0.22 * ((i * 7) % 3) / 2), color, ring=hero or (i % 2 == 0),
                     spark=(5.0 if hero and i in (1, 4) else 0.0), glow=strength)
        else:
            dim_star(cv, x, y, r * 0.9, color)


# the cap in the sky (WelcomeSky.points / .lines), in star spacings
CAP_POINTS = [(0.0, 1.9), (2.7, 0.0), (2.7, 1.65), (2.7, 3.3), (5.4, 1.6), (5.55, 2.75), (5.4, 3.85)]
CAP_LINES = [(0, 1), (1, 4), (4, 3), (3, 0), (1, 2), (2, 3), (4, 5), (5, 6)]


def cluster(cx, cy, spread, n, seed, link=2):
    """A small made-up constellation: n stars around (cx, cy), each joined to its nearest earlier ones."""
    rng = np.random.default_rng(seed)
    pts = []
    for _ in range(n):
        a = rng.random() * 2 * math.pi
        d = spread * (0.25 + 0.75 * math.sqrt(rng.random()))
        pts.append((cx + math.cos(a) * d * 1.15, cy + math.sin(a) * d * 0.82))
    lines = []
    for i in range(1, n):
        order = sorted(range(i), key=lambda j: (pts[i][0] - pts[j][0]) ** 2 + (pts[i][1] - pts[j][1]) ** 2)
        for j in order[: (1 if i < 3 else link)]:
            lines.append((i, j))
    return pts, lines


def falling_star(cv, p, head, tail_to):
    """One falling star (the refresh's arc of light, as a still): a bright head and a tail that fades along its path."""
    hx, hy = head
    tx, ty = tail_to
    col = rgb(p["dust"][0])
    steps = 70
    for i in range(steps):
        t = i / steps
        x, y = hx + (tx - hx) * t, hy + (ty - hy) * t
        a = (1 - t) ** 1.8
        cv.disc(x, y, 3.4 * (1 - 0.6 * t), col, 0.9 * a)
        cv.glow(x, y, 16 * (1 - 0.5 * t), col, 0.28 * a)
    cv.glow(hx, hy, 46, col, 0.5)
    cv.disc(hx, hy, 6.5, WHITE, 1.0)
    cv.spark(hx, hy, 52, 2.0, WHITE, 0.9)


def load_cap(which):
    path = os.path.join(REPO, "docs", "rethink", "brand", "raw", "candidates", f"cap-stargaze-{which}.png")
    im = Image.open(path).convert("RGBA")
    # the three small gold stars by the lens are drawn into the render: the sky has its own, so take them off
    erase = {1: [(925, 128, 46), (868, 175, 30), (972, 205, 30)], 2: [(918, 112, 46), (847, 150, 30), (972, 188, 30)]}[which]
    arr = np.array(im)
    yy, xx = np.mgrid[0:arr.shape[0], 0:arr.shape[1]]
    for (ex, ey, er) in erase:
        arr[((xx - ex) ** 2 + (yy - ey) ** 2) < er * er, 3] = 0
    im = Image.fromarray(arr, "RGBA")
    a = np.asarray(im)[:, :, 3]
    ys, xs = np.where(a > 20)
    box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
    return im, box


def paint_cap(cv, p, which, height, left, feet, tw=DEFAULT_TWEAK):
    """Cap, `height` px tall (the whole drawing: hat to feet), left edge at `left`, feet at `feet`. Returns his lens position."""
    k = cv.k
    im, box = load_cap(which)
    bw, bh = box[2] - box[0], box[3] - box[1]
    sc = height / bh
    art = im.crop(box).resize((max(1, int(round(bw * sc * k))), max(1, int(round(bh * sc * k)))), Image.LANCZOS)
    arr = np.asarray(art, np.float32) / 255
    a = arr[:, :, 3:4]
    ah, aw = a.shape[:2]
    x0 = int(round(left * k))
    y0 = int(round(feet * k)) - ah
    # a soft contact shadow on the ground, then a faint backlight so the navy hat reads against the night
    cv.glow(left + bw * sc * 0.42, feet - 6, 330, np.array([0, 0, 0], np.float32), 0.0)
    ys0, ys1, xs0, xs1 = max(0, y0), min(cv.h, y0 + ah), max(0, x0), min(cv.w, x0 + aw)
    alpha = np.zeros((cv.h, cv.w), np.float32)
    alpha[ys0:ys1, xs0:xs1] = a[ys0 - y0:ys1 - y0, xs0 - x0:xs1 - x0, 0]
    rim_box = (max(0, ys0 - int(260 * k)), min(cv.h, ys1 + int(260 * k)), max(0, xs0 - int(260 * k)), min(cv.w, xs1 + int(260 * k)))
    ry0, ry1, rx0, rx1 = rim_box
    halo = blur(alpha[ry0:ry1, rx0:rx1], 70 * k)
    hz = rgb(tw["rim"]) if tw["rim"] else rgb(p["haze"][0]) * 0.55 + rgb(p["glow"][1]) * 0.45
    sub = cv.px[ry0:ry1, rx0:rx1]
    cv.px[ry0:ry1, rx0:rx1] = 1 - (1 - sub) * (1 - np.clip(halo * 1.5, 0, 1)[:, :, None] * hz[None, None, :] * tw["rim_amt"])
    sub = cv.px[ys0:ys1, xs0:xs1]
    fg = arr[ys0 - y0:ys1 - y0, xs0 - x0:xs1 - x0, :3]
    aa = a[ys0 - y0:ys1 - y0, xs0 - x0:xs1 - x0]
    cv.px[ys0:ys1, xs0:xs1] = sub * (1 - aa) + fg * aa
    # where his lens is, in real px (the 1024 art has it near x 0.9, y 0.26 for take 1 and x 0.88, y 0.23 for take 2)
    lens = {1: (0.905, 0.262), 2: (0.880, 0.232)}[which]
    lx = left + (lens[0] * 1024 - box[0]) * sc
    ly = feet - height + (lens[1] * 1024 - box[1]) * sc
    return lx, ly, (left, feet - height, left + bw * sc, feet)


def paint_knoll(cv, p, cx, half_w, height):
    """A low dark knoll at the waterline for Cap to stand on, lit along its top edge. It sits above the water; the lake reflects it."""
    k = cv.k
    top_c, bottom_c = rgb(p["mid"][1]), rgb(p["ground"][1])
    x0, x1 = max(0, int((cx - half_w - 30) * k)), min(cv.w, int((cx + half_w + 30) * k))
    y0, y1 = max(0, int((YW - height - 24) * k)), min(cv.h, int(YW * k))
    xs = (np.arange(x0, x1, dtype=np.float32) + 0.5) / k - cx
    t = np.clip(np.abs(xs) / half_w, 0, 1)
    line = (YW - height * (1 - t ** 2.0) ** 0.7) * k                      # the knoll's top edge, per column
    rows = np.arange(y0, y1, dtype=np.float32)[:, None] + 0.5
    a = np.clip(rows - line[None, :] + 0.5, 0, 1)
    tt = np.clip((rows - line[None, :]) / (height * k + 1), 0, 1)[:, :, None]
    col = top_c[None, None, :] * (1 - tt) + bottom_c[None, None, :] * tt
    sub = cv.px[y0:y1, x0:x1]
    cv.px[y0:y1, x0:x1] = sub * (1 - a[:, :, None]) + col * a[:, :, None]
    rim = np.exp(-((rows - line[None, :] - 1.2 * k) / (4.0 * k)) ** 2) * (rows > line[None, :] - 2 * k) * 0.24
    cool = rgb(p["crest"][1])
    sub = cv.px[y0:y1, x0:x1]
    cv.px[y0:y1, x0:x1] = 1 - (1 - sub) * (1 - rim[:, :, None] * cool[None, None, :])


def make_water(cv, scene, p, rng):
    """The lake: the sky and everything standing at the waterline, flipped, rippled, softened and sunk into the water colour."""
    k, w, h = cv.k, cv.w, cv.h
    yw = int(round(YW * k))
    n = h - yw
    src = scene[yw - n:yw][::-1].copy()                      # mirror about the waterline
    d = (np.arange(n, dtype=np.float32) + 0.5)[:, None] / k   # depth in real px

    # ripples: the picture slides sideways by an amount that grows with depth
    field = fbm(rng, n, w, 120 * k, octaves=4, stretch=7.0) - 0.5
    amp = (7 + 0.055 * d) * k
    dx = field * 2 * amp
    cols = np.clip((np.arange(w, dtype=np.float32)[None, :] + dx + 0.5).astype(np.int32), 0, w - 1)
    rows = np.arange(n)[:, None]
    refl = src[rows, cols]
    near = blur(refl, 2.2 * k, 0.9 * k)
    far_ = blur(refl, 46 * k, 11 * k)                          # stretched glints: wide and flat
    t = smooth(d / 520.0)[:, :, None]
    refl = near * (1 - t * 0.7) + far_ * (t * 0.7)
    sheen = np.maximum(near - 0.45, 0) * 0.0

    wt, wb = rgb(p["water"][0]), rgb(p["water"][1])
    tt = np.clip(d / (H - YW), 0, 1)[:, :, None] ** 0.8
    base = wt[None, None, :] * (1 - tt) + wb[None, None, :] * tt
    a = (0.62 * np.exp(-d / 1250.0) + 0.14)[:, :, None]
    water = base * (1 - a) + refl * a * 0.92 + base * 0.0 + sheen
    # a light mist hugging the shore line
    mist = np.exp(-d / (40.0))[:, :, None] * rgb(p["crest"][1])[None, None, :] * 0.10
    water = 1 - (1 - np.clip(water, 0, 1)) * (1 - mist)
    return water


def finish(px, k, rng):
    h, w = px.shape[:2]
    # a soft vignette, then a whisper of grain so the gradients do not band
    yy = (np.arange(h, dtype=np.float32)[:, None] / h - 0.46)
    xx = (np.arange(w, dtype=np.float32)[None, :] / w - 0.5)
    r = np.sqrt((xx * 1.0) ** 2 + (yy * 1.25) ** 2)
    px *= (1 - 0.30 * smooth((r - 0.34) / 0.45))[:, :, None]
    px += rng.normal(0, 0.9 / 255, px.shape).astype(np.float32)
    return np.clip(px, 0, 1)


def render_scene(theme="night", scale=1.0, canvas=(5244, 2950), yw=1620, seed=7, cap=None, hero=None, falling=None,
                 supporting=1.0, safe=None, cap_take=1, avoid=None):
    """One night scene. cap = dict(height, left, feet, knoll=(cx, half_width, height)); hero = dict(u, gx0, gy0) is the cap in the sky;
    falling = (head, tail); supporting = the strength of the other constellations (0 for none); avoid = a box (x0, y0, x1, y1) that no
    other constellation may touch, so lines and stars never run behind words; safe = a box to outline (debug)."""
    set_canvas(canvas[0], canvas[1], yw)
    p = THEMES[theme]
    tw = {**DEFAULT_TWEAK, **TWEAKS.get(theme, {})}
    rng = np.random.default_rng(seed)
    cv = Canvas(scale)
    k = scale

    band, (X, Y) = paint_sky(cv, p, rng, tw)
    ang = math.radians(-23)

    def band_fn(x, y):
        d = (-math.sin(ang) * (x - fx(2650.0)) + math.cos(ang) * (y - fy(1040.0)))
        return math.exp(-(d / 430.0) ** 2)

    paint_dust(cv, p, rng, band_fn)

    # the other constellations: remembered (lit, in their course colours) and fading (hollow rings): a whole sky around the subject
    stars_r = 15
    sets = [
        (COURSE["sky"], True, 870, 760, 300, 7, 101),
        (COURSE["mint"], True, 4420, 1120, 250, 6, 102),
        (COURSE["tangerine"], False, 4380, 560, 270, 5, 103),
        (COURSE["sun"], False, 1180, 1190, 210, 5, 104),
        (COURSE["sky"], True, 300, 1230, 170, 4, 105),
        (COURSE["rose"], False, 4980, 880, 160, 4, 106),
        (COURSE["sky"], True, 1560, 420, 190, 5, 107),
        (COURSE["sun"], False, 3820, 380, 180, 4, 108),
    ]
    if supporting > 0:
        for col, lit, cx, cy, spread, n, sd in sets:
            cx, cy = fx(cx), fy(cy)
            spread = spread * min(W / BASE_W * 1.35, 1.0)
            pts, lines = cluster(cx, cy, spread, n, sd)
            if avoid and any(avoid[0] - 70 <= x <= avoid[2] + 70 and avoid[1] - 70 <= y <= avoid[3] + 70 for x, y in pts):
                continue
            constellation(cv, pts, lines, rgb(col), lit, stars_r if lit else stars_r * 0.9, region=(cx, cy, spread * 1.5),
                          strength=0.42 * supporting)

    if falling:
        falling_star(cv, p, falling[0], falling[1])
    far, mid = paint_hills(cv, p)

    lx = ly = 0.0
    cbox = (0, 0, 0, 0)
    if cap:
        kx, kh, kt = cap["knoll"]
        paint_knoll(cv, p, kx, kh, kt)
        lx, ly, cbox = paint_cap(cv, p, cap_take, cap["height"], cap["left"], cap["feet"], tw)
    if hero:
        u, gx0, gy0 = hero["u"], hero["gx0"], hero["gy0"]
        pts = [(gx0 + x * u, gy0 + y * u) for x, y in CAP_POINTS]
        cv.glow(gx0 + 2.8 * u, gy0 + 1.95 * u, 230 * u / 74.0, rgb(COURSE["sun"]), 0.10)
        constellation(cv, pts, CAP_LINES, rgb(COURSE["sun"]), True, 17 * u / 74.0, region=None, hero=True)

    scene = cv.px
    water = make_water(cv, scene, p, rng)
    yw_px = int(round(YW * k))
    out = scene.copy()
    out[yw_px:] = water
    cv.px = out
    px = finish(cv.px, k, rng)
    img = Image.fromarray((px * 255 + 0.5).astype(np.uint8), "RGB")
    if safe:
        from PIL import ImageDraw
        d = ImageDraw.Draw(img)
        d.rectangle([safe[0] * k, safe[1] * k, safe[2] * k, safe[3] * k], outline=(255, 90, 120), width=max(2, int(4 * k)))
        if cap:
            d.ellipse([lx * k - 6, ly * k - 6, lx * k + 6, ly * k + 6], outline=(0, 255, 0), width=2)
            d.rectangle([cbox[0] * k, cbox[1] * k, cbox[2] * k, cbox[3] * k], outline=(60, 200, 255), width=2)
    return img


def render_universal(theme="night", scale=1.0, cap_take=1, seed=7, safe_debug=False):
    """The 16:9 universal asset (5244 x 2950): Cap with his telescope, the cap in the sky, a mirror lake."""
    cap_left = SAFE[0] + 6
    img = render_scene(
        theme, scale, (5244, 2950), 1620, seed,
        cap=dict(height=860, left=cap_left, feet=1620 - 44, knoll=(cap_left + 450, 800, 62)),
        hero=dict(u=74.0, gx0=3284 - 5.55 * 74.0, gy0=694),        # the tassel's star sits 40 px inside the box's right edge
        falling=((2640, 250), (2160, 470)),
        safe=SAFE if safe_debug else None, cap_take=cap_take)
    set_canvas(5244, 2950, 1620)
    return img


def crops(path, out_dir):
    """How the 16:9 asset is cut for the two slots (a centred cover crop, an estimate: Apple's own Preview tool is the truth)."""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    os.makedirs(out_dir, exist_ok=True)
    name = os.path.splitext(os.path.basename(path))[0]
    for label, ratio, size in (("header-21x9", 3840 / 1646, (3840, 1646)), ("search-3x2", 3 / 2, (3840, 2560))):
        if ratio > w / h:
            ch = int(round(w / ratio))
            top = int(round((h - ch) * 0.30))            # the template's box sits high, so lean the cut to the top
            box = (0, top, w, top + ch)
        else:
            cw = int(round(h * ratio))
            left = (w - cw) // 2
            box = (left, 0, left + cw, h)
        c = im.crop(box).resize(size, Image.LANCZOS)
        c.save(os.path.join(out_dir, f"{name}-{label}.png"))
        print(os.path.join(out_dir, f"{name}-{label}.png"), c.size, "cut from", box)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    u = sub.add_parser("universal")
    u.add_argument("--theme", default="night", choices=sorted(THEMES))
    u.add_argument("--scale", type=float, default=1.0)
    u.add_argument("--cap", type=int, default=1, choices=(1, 2))
    u.add_argument("--seed", type=int, default=7)
    u.add_argument("--safe", action="store_true", help="draw Apple's safe box and Cap's lens (for looking, not for upload)")
    u.add_argument("--out", required=True)
    c = sub.add_parser("crops")
    c.add_argument("path")
    c.add_argument("--out", required=True)
    a = ap.parse_args()
    if a.cmd == "universal":
        img = render_universal(a.theme, a.scale, a.cap, a.seed, a.safe)
        os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
        img.save(a.out, optimize=True)
        print(a.out, img.size)
    else:
        crops(a.path, a.out)


if __name__ == "__main__":
    sys.exit(main())
