#!/usr/bin/env python3
"""More of the drawing kit, for the listing styles of the leaders (shot_mimic.py): variable system fonts, angled gradients, shards, hand-drawn
doodles, laurels, stickers, glass, neon outlines, 3D lettering, a sky of clouds, halftone and marker scribbles.

Everything is drawn in code on RGBA canvases of the 6.9-inch screenshot (1290 x 2796); shotkit.py has the rest (pieces, Cap, phones, skies).
"""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont, ImageOps

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import shotkit as sk  # noqa: E402
from shotkit import W, H, paste  # noqa: E402

SF = "/System/Library/Fonts/SFNS.ttf"
NY = "/System/Library/Fonts/NewYork.ttf"
NYI = "/System/Library/Fonts/NewYorkItalic.ttf"


# ---- fonts and text ---------------------------------------------------------------------------------------------------------------------

def sf(size, weight=700, width=100):
    """SF Pro (the system font) at a weight from 1 to 1000 and a width from 30 (condensed) to 150."""
    f = ImageFont.truetype(SF, int(size))
    f.set_variation_by_axes([width, 96 if size >= 110 else max(28, size * 0.8), 400, weight])
    return f


def ny(size, weight=500, italic=False):
    """New York (the system serif), regular or italic, at a weight from 400 to 1000."""
    f = ImageFont.truetype(NYI if italic else NY, int(size))
    f.set_variation_by_axes([min(256, max(12, size * 0.5)), weight, 0])
    return f


_probe = ImageDraw.Draw(Image.new("L", (1, 1)))


def tw(s, f, track=0.0):
    """Width of a string in a font; track is in em (-0.03 is tight)."""
    w = _probe.textlength(s, font=f)
    return w + track * f.size * (len(s) - 1) if track else w


def draw(d, x, y, s, f, fill, anchor="ls", track=0.0, stroke=0, stroke_fill=None):
    """Text at (x, y). anchor: l, m or r then s (baseline) or a (ascender top). Tracking draws letter by letter with kerning."""
    if not track:
        d.text((x, y), s, font=f, fill=fill, anchor=anchor, stroke_width=stroke, stroke_fill=stroke_fill)
        return
    w = tw(s, f, track)
    x0 = x if anchor[0] == "l" else x - w / 2 if anchor[0] == "m" else x - w
    cx = x0
    for i, ch in enumerate(s):
        d.text((cx, y), ch, font=f, fill=fill, anchor="l" + anchor[1], stroke_width=stroke, stroke_fill=stroke_fill)
        adv = (_probe.textlength(s[i:i + 2], font=f) - _probe.textlength(s[i + 1:i + 2], font=f)) if i + 1 < len(s) else _probe.textlength(ch, font=f)
        cx += adv + track * f.size


def parse_rich(s):
    """'Studying that *fits your exam*' -> [('Studying that ', False), ('fits your exam', True)]."""
    out, em = [], False
    for part in s.split("*"):
        if part:
            out.append((part, em))
        em = not em
    return out


def rich(canvas, s, y, f_reg, f_em, fill, fill_em=None, centre=None, left=None, track=0.0):
    """One line of text with *emphasis* segments in a second font, on baseline y. Returns the line's width."""
    segs = parse_rich(s)
    widths = [tw(t, f_em if e else f_reg, track) for t, e in segs]
    total = sum(widths)
    x = left if left is not None else centre - total / 2
    d = ImageDraw.Draw(canvas)
    for (t, e), w in zip(segs, widths):
        draw(d, x, y, t, f_em if e else f_reg, (fill_em or fill) if e else fill, "ls", track)
        x += w
    return total


def fit(lines, max_w, make, hi=400, lo=24, track=0.0):
    """The biggest size (make(size) -> font) at which the widest of the lines fits max_w."""
    plain = [("".join(t for t, _ in parse_rich(l))) for l in lines]
    size = hi
    while size > lo:
        f = make(size)
        if max(tw(p, f, track) for p in plain) <= max_w:
            return size
        size -= 2
    return lo


# ---- colour and shapes ------------------------------------------------------------------------------------------------------------------

def lin(size, stops, angle=90):
    """A multi-stop gradient. stops: [(position 0..1, (r, g, b)), ...]. angle: 90 runs top to bottom, 0 left to right, 45 top-left to bottom-right."""
    w, h = size
    th = math.radians(angle)
    ys, xs = np.mgrid[0:h, 0:w].astype("float32")
    dx, dy = math.cos(th), math.sin(th)
    t = ((xs - w / 2) * dx + (ys - h / 2) * dy) / (abs(w * dx) + abs(h * dy)) + 0.5
    t = np.clip(t, 0, 1)
    out = np.zeros((h, w, 4), "float32")
    pos = [s[0] for s in stops]
    for c in range(3):
        out[..., c] = np.interp(t, pos, [s[1][c] for s in stops])
    out[..., 3] = 255
    return Image.fromarray(out.astype("uint8"), "RGBA")


def tint(c, k):
    """Lighter (k > 0, towards white) or darker (k < 0, towards black) by a share."""
    if k >= 0:
        return tuple(int(v + (255 - v) * k) for v in c[:3])
    return tuple(int(v * (1 + k)) for v in c[:3])


def poly(canvas, pts, fill, ss=2):
    """An anti-aliased polygon (supersampled inside its own box)."""
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    x0, y0 = max(0, int(min(xs)) - 2), max(0, int(min(ys)) - 2)
    x1, y1 = min(canvas.width, int(max(xs)) + 3), min(canvas.height, int(max(ys)) + 3)
    if x1 <= x0 or y1 <= y0:
        return
    m = Image.new("L", ((x1 - x0) * ss, (y1 - y0) * ss), 0)
    ImageDraw.Draw(m).polygon([((x - x0) * ss, (y - y0) * ss) for x, y in pts], fill=255)
    m = m.resize((x1 - x0, y1 - y0), Image.LANCZOS)
    a = fill[3] if len(fill) == 4 else 255
    if a < 255:
        m = m.point(lambda v: v * a // 255)
    layer = Image.new("RGBA", m.size, tuple(fill[:3]) + (0,))
    layer.putalpha(m)
    canvas.alpha_composite(layer, (x0, y0))


def rrect(canvas, box, radius, fill, ss=3, outline=None, width=0):
    """An anti-aliased rounded rectangle on the canvas."""
    x0, y0, x1, y1 = [int(round(v)) for v in box]
    w, h = x1 - x0, y1 - y0
    if w <= 0 or h <= 0:
        return
    m = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w * ss - 1, h * ss - 1), radius * ss, fill=255)
    m = m.resize((w, h), Image.LANCZOS)
    a = fill[3] if fill and len(fill) == 4 else 255
    if fill is not None:
        mm = m.point(lambda v: v * a // 255) if a < 255 else m
        layer = Image.new("RGBA", (w, h), tuple(fill[:3]) + (0,))
        layer.putalpha(mm)
        paste(canvas, layer, x0, y0)
    if outline is not None and width:
        o = Image.new("L", (w * ss, h * ss), 0)
        od = ImageDraw.Draw(o)
        od.rounded_rectangle((0, 0, w * ss - 1, h * ss - 1), radius * ss, fill=255)
        od.rounded_rectangle((width * ss, width * ss, w * ss - 1 - width * ss, h * ss - 1 - width * ss), max(0, (radius - width)) * ss, fill=0)
        o = o.resize((w, h), Image.LANCZOS)
        oa = outline[3] if len(outline) == 4 else 255
        if oa < 255:
            o = o.point(lambda v: v * oa // 255)
        layer = Image.new("RGBA", (w, h), tuple(outline[:3]) + (0,))
        layer.putalpha(o)
        paste(canvas, layer, x0, y0)


def stroke(canvas, pts, color, width, alpha=255, ss=3, round_caps=True):
    """An anti-aliased polyline with round joins and caps, like a pen line."""
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    pad = int(width * 2 + 4)
    x0, y0, x1, y1 = int(min(xs)) - pad, int(min(ys)) - pad, int(max(xs)) + pad, int(max(ys)) + pad
    w, h = x1 - x0, y1 - y0
    m = Image.new("L", (w * ss, h * ss), 0)
    d = ImageDraw.Draw(m)
    P = [((x - x0) * ss, (y - y0) * ss) for x, y in pts]
    d.line(P, fill=255, width=max(1, int(width * ss)), joint="curve")
    if round_caps:
        r = width * ss / 2
        for px, py in (P[0], P[-1]):
            d.ellipse((px - r, py - r, px + r, py + r), fill=255)
    m = m.resize((w, h), Image.LANCZOS)
    if alpha < 255:
        m = m.point(lambda v: v * alpha // 255)
    layer = Image.new("RGBA", (w, h), tuple(color[:3]) + (0,))
    layer.putalpha(m)
    paste(canvas, layer, x0, y0)


# ---- backgrounds ------------------------------------------------------------------------------------------------------------------------

def blobs(canvas, seed, n, colours, rx=(260, 520), ry=(160, 360), alpha=(50, 110), box=None):
    """Soft blurred patches of colour, for a painterly ground."""
    rnd = random.Random(seed)
    x0, y0, x1, y1 = box or (0, 0, canvas.width, canvas.height)
    for _ in range(n):
        sk.glow(canvas, rnd.uniform(x0, x1), rnd.uniform(y0, y1), rnd.uniform(*rx), rnd.uniform(*ry), rnd.choice(colours),
                alpha=rnd.randint(*alpha), blur=rnd.uniform(*rx) * 0.45)


def halftone(canvas, box, colour, step=34, rmax=13, to="right", alpha=255):
    """A halftone dot field whose dots grow towards one side: the printed-paper look of a collage."""
    x0, y0, x1, y1 = box
    layer = Image.new("RGBA", canvas.size, tuple(colour[:3]) + (0,))
    d = ImageDraw.Draw(layer)
    ny_ = int((y1 - y0) / step) + 1
    nx_ = int((x1 - x0) / step) + 1
    for j in range(ny_):
        for i in range(nx_):
            cx = x0 + i * step + (step / 2 if j % 2 else 0)
            cy = y0 + j * step * 0.86
            t = {"right": i / max(1, nx_ - 1), "left": 1 - i / max(1, nx_ - 1), "down": j / max(1, ny_ - 1), "up": 1 - j / max(1, ny_ - 1)}[to]
            r = rmax * t
            if r > 0.8:
                d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=tuple(colour[:3]) + (alpha,))
    canvas.alpha_composite(layer)


def pixels(canvas, seed, box, colour, size=64, density=0.35, alpha=(10, 34)):
    """A field of square pixels at low opacity (the retro-game ground)."""
    rnd = random.Random(seed)
    x0, y0, x1, y1 = box
    layer = Image.new("RGBA", canvas.size, tuple(colour[:3]) + (0,))
    d = ImageDraw.Draw(layer)
    for y in range(int(y0), int(y1), size):
        for x in range(int(x0), int(x1), size):
            if rnd.random() < density:
                d.rectangle((x, y, x + size - 1, y + size - 1), fill=tuple(colour[:3]) + (rnd.randint(*alpha),))
    canvas.alpha_composite(layer)


def cloud_sky(size, seed=1, top=(40, 112, 206), bottom=(176, 218, 250), coverage=0.5, lit=(255, 255, 255), clear_top=0.0):
    """A daytime sky with soft clouds (smooth fractal noise on coarse grids), the stand-in for a photograph of the sky.
    clear_top: how much to keep the clouds off the top of the sky (0 to 1), so words set there stay readable."""
    w, h = size
    sw, sh = w // 4, h // 4
    rng = np.random.default_rng(seed)
    n = np.zeros((sh, sw), "float32")
    tot = 0.0
    for o, amp in enumerate((1.0, 0.5, 0.25, 0.10)):
        gw, gh = 2 * 2 ** o + 2, 3 * 2 ** o + 2
        base = rng.random((gh, gw)).astype("float32")
        im = Image.fromarray((base * 255).astype("uint8")).resize((sw, sh), Image.BICUBIC)
        n += np.asarray(im, "float32") / 255 * amp
        tot += amp
    n /= tot
    n = (n - n.min()) / max(1e-6, n.max() - n.min())
    yy = np.linspace(0, 1, sh, dtype="float32")[:, None]
    c = np.clip((n - (1 - coverage) + 0.10 * (1 - yy)) * 2.6, 0, 1)
    c = c * c * (3 - 2 * c)
    if clear_top:
        c = c * np.clip(yy / 0.55, 1 - clear_top, 1)
    a = Image.fromarray((c * 255).astype("uint8")).resize((w, h), Image.BICUBIC).filter(ImageFilter.GaussianBlur(14))
    base = lin(size, [(0, top), (1, bottom)], 90)
    shade = Image.new("RGBA", size, (96, 130, 190, 0))
    shade.putalpha(a.point(lambda v: int(v * 0.30)))
    base.alpha_composite(shade)
    cl = Image.new("RGBA", size, tuple(lit) + (0,))
    cl.putalpha(a.point(lambda v: int(v * 0.92)))
    base.alpha_composite(cl)
    return base


# ---- hand-drawn doodles -----------------------------------------------------------------------------------------------------------------

def d_arrow(canvas, p0, p3, bend, colour, w=8, head=40, loop=False):
    """A pen arrow from p0 to p3, bowed by `bend` px (sign picks the side); loop adds a curl at the start."""
    mx, my = (p0[0] + p3[0]) / 2, (p0[1] + p3[1]) / 2
    dx, dy = p3[0] - p0[0], p3[1] - p0[1]
    L = math.hypot(dx, dy) or 1
    c = (mx - dy / L * bend, my + dx / L * bend)
    pts = sk.curve(p0, ((p0[0] + c[0]) / 2 + (c[0] - p0[0]) * 0.2, (p0[1] + c[1]) / 2), ((p3[0] + c[0]) / 2, (p3[1] + c[1]) / 2 + (c[1] - p3[1]) * 0.2), p3)
    if loop:
        r = L * 0.12
        cx0, cy0 = p0[0] - r * 0.2, p0[1] - r * 1.1
        circ = [(cx0 + r * math.cos(t), cy0 + r * math.sin(t)) for t in np.linspace(math.pi * 0.35, math.pi * 2.3, 26)]
        pts = circ + pts
    stroke(canvas, pts, colour, w)
    a = math.atan2(p3[1] - pts[-6][1], p3[0] - pts[-6][0])
    for da in (2.6, -2.6):
        stroke(canvas, [p3, (p3[0] + head * math.cos(a + da), p3[1] + head * math.sin(a + da))], colour, w)


def d_sparkles(canvas, x, y, s, colour, w=7):
    """Three little four-point stars drawn as crossing strokes, the big one first."""
    for dx, dy, k in ((0, 0, 1.0), (0.9, -0.55, 0.55), (-0.5, 0.75, 0.42)):
        cx, cy, r = x + dx * s, y + dy * s, s * k * 0.5
        stroke(canvas, [(cx, cy - r), (cx, cy + r)], colour, w * (0.6 + 0.4 * k))
        stroke(canvas, [(cx - r, cy), (cx + r, cy)], colour, w * (0.6 + 0.4 * k))


def d_star4(canvas, x, y, r, colour, glow=0.5, squash=0.80, pinch=0.0, rot=0.0):
    """A solid four-point sparkle centred on (x, y): tips r away up and down, r*squash left and right, the sides curving in towards the
    middle (pinch 0 is the sharpest; a bigger one is a fatter star). glow: opacity of the soft halo round it, 0 for none."""
    ss = 4
    pad = int(r * 0.9)
    n = int(2 * r + 2 * pad)
    N = n * ss
    cx = cy = N / 2
    rx, ry = r * squash * ss, r * ss
    tips = [(cx, cy - ry), (cx + rx, cy), (cx, cy + ry), (cx - rx, cy)]
    pts = []
    for a, b in zip(tips, tips[1:] + tips[:1]):
        mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        c = (cx + (mx - cx) * pinch, cy + (my - cy) * pinch)
        for t in np.linspace(0, 1, 32, endpoint=False):
            pts.append(((1 - t) ** 2 * a[0] + 2 * (1 - t) * t * c[0] + t ** 2 * b[0], (1 - t) ** 2 * a[1] + 2 * (1 - t) * t * c[1] + t ** 2 * b[1]))
    m = Image.new("L", (N, N), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    if rot:
        m = m.rotate(rot, resample=Image.BICUBIC)
    m = m.resize((n, n), Image.LANCZOS)
    tile = Image.new("RGBA", (n, n), tuple(colour[:3]) + (0,))
    if glow:
        halo = m.filter(ImageFilter.GaussianBlur(r * 0.32)).point(lambda v: int(min(255, v * 1.5) * glow * 0.55))
        tile.putalpha(halo)
    tile.alpha_composite(Image.composite(Image.new("RGBA", (n, n), tuple(colour[:3]) + (255,)), Image.new("RGBA", (n, n), (0, 0, 0, 0)), m))
    sk.paste(canvas, tile, x - n / 2, y - n / 2)


def d_sparkles_solid(canvas, x, y, r, colour, glow=0.5):
    """Three solid sparkles in a loose cluster, the big one centred on (x, y) with tips r away."""
    for dx, dy, k in ((0, 0, 1.0), (1.55, -0.95, 0.56), (-0.95, 1.25, 0.40)):
        d_star4(canvas, x + dx * r, y + dy * r, r * k, colour, glow)


def sparkle_discs(x, y, r):
    """The discs (centre, tip reach) of the three stars of a solid cluster, the big one on (x, y)."""
    return [(x, y, r), (x + 1.55 * r, y - 0.95 * r, r * 0.56), (x - 0.95 * r, y + 1.25 * r, r * 0.40)]


def coarse_mask(size, layers, scale=4, margin=0, below=None):
    """A coarse bool grid (the canvas at 1/scale) of where the layers [(RGBA layer, x, y)] have pixels, grown by `margin` canvas px; every
    row from `below` down is marked too."""
    w, h = size[0] // scale, size[1] // scale
    m = Image.new("L", (w, h), 0)
    for layer, x, y in layers:
        a = layer.getchannel("A").point(lambda v: 255 if v > 24 else 0)
        a = a.resize((max(1, a.width // scale), max(1, a.height // scale)), Image.BOX).point(lambda v: 255 if v > 0 else 0)
        bx, by = int(x // scale), int(y // scale)
        m.paste(255, (bx, by, bx + a.width, by + a.height), a)
    if margin:
        m = m.filter(ImageFilter.MaxFilter(int(margin / scale) * 2 + 1))
    occ = np.asarray(m) > 0
    if below is not None:
        occ[int(below // scale):, :] = True
    return occ


def place_sparkles(canvas, occ, anchors, colour, scale=4, step=10, reach=170, edge=24, gap=18):
    """Draw a solid cluster for each preferred spot (x, y, r) at the nearest place where none of its stars touches the occupied grid `occ`
    (the title, Cap, the screen below), shrinking it a little if nothing near is free; each one is then marked occupied for the next."""
    h, w = occ.shape
    cw, ch = w * scale, h * scale

    def free(discs):
        for cx, cy, rr in discs:
            R = rr * 1.2
            if cx - R < edge or cx + R > cw - edge or cy - R < edge or cy + R > ch - edge:
                return False
            if occ[int((cy - R) // scale):int((cy + R) // scale) + 1, int((cx - R) // scale):int((cx + R) // scale) + 1].any():
                return False
        return True

    spots = sorted(((dx, dy) for dx in range(-reach, reach + 1, step) for dy in range(-reach, reach + 1, step)), key=lambda d: d[0] ** 2 + d[1] ** 2)
    placed = []
    for ax, ay, r in anchors:
        found = None
        for shrink in (1.0, 0.85, 0.7):
            for dx, dy in spots:
                if free(sparkle_discs(ax + dx, ay + dy, r * shrink)):
                    found = (ax + dx, ay + dy, r * shrink)
                    break
            if found:
                break
        if not found:
            continue
        x, y, rr = found
        d_sparkles_solid(canvas, x, y, rr, colour)
        for cx, cy, r2 in sparkle_discs(x, y, rr):
            R = r2 * 1.2 + gap
            occ[max(0, int((cy - R) // scale)):int((cy + R) // scale) + 1, max(0, int((cx - R) // scale)):int((cx + R) // scale) + 1] = True
        placed.append(found)
    return placed


def cluster_pattern(rng):
    """A random cluster of one to three stars as (dx, dy, k, rot, squash): offsets in units of the big star's reach r, k its share of r, rot
    its turn in degrees. The big star sits at the origin; the others are turned round it by a random angle."""
    kind = rng.choices(("single", "pair", "trio"), weights=(25, 35, 40))[0]
    turn = rng.uniform(0, 2 * math.pi)
    stars = [(0.0, 0.0, 1.0)]
    if kind in ("pair", "trio"):
        stars.append((rng.uniform(1.3, 1.7), -rng.uniform(0.7, 1.1), rng.uniform(0.46, 0.62)))
    if kind == "trio":
        stars.append((-rng.uniform(0.7, 1.1), rng.uniform(0.9, 1.4), rng.uniform(0.34, 0.46)))
    out = []
    for dx, dy, k in stars:
        out.append((dx * math.cos(turn) - dy * math.sin(turn), dx * math.sin(turn) + dy * math.cos(turn), k, rng.uniform(-28, 28), rng.uniform(0.72, 0.88)))
    return out


def draw_cluster(canvas, x, y, r, pattern, colour, glow=0.5):
    for dx, dy, k, rot, squash in pattern:
        d_star4(canvas, x + dx * r, y + dy * r, r * k, colour, glow, squash=squash, rot=rot)


def random_sparkles(canvas, ring, occ, colour, seed, count=(6, 9), r_range=(26, 54), scale=4, edge=24, gap=18, tries=500):
    """Scatter random solid sparkles (their number, place, size, turn and make-up all drawn from `seed`) over the free cells of `ring`: the
    band round the title. `occ` is what they must not touch (the title, Cap, the screen below). Each new cluster goes where it is far from
    the others, so they spread round the title instead of bunching, and every frame (every seed) gets its own scatter."""
    rng = random.Random(seed)
    h, w = occ.shape
    cw, ch = w * scale, h * scale

    def free(discs):
        for cx, cy, rr in discs:
            R = rr * 1.2
            if cx - R < edge or cx + R > cw - edge or cy - R < edge or cy + R > ch - edge:
                return False
            if occ[int((cy - R) // scale):int((cy + R) // scale) + 1, int((cx - R) // scale):int((cx + R) // scale) + 1].any():
                return False
        return True

    pool = np.argwhere(ring & ~occ)
    if len(pool) == 0:
        return []
    placed = []
    for _ in range(rng.randint(*count)):
        best, best_score = None, -1.0
        for _t in range(tries):
            cy, cx = pool[rng.randrange(len(pool))]
            x, y = cx * scale + scale / 2, cy * scale + scale / 2
            r = rng.uniform(*r_range)
            pattern = cluster_pattern(rng)
            discs = [(x + dx * r, y + dy * r, r * k) for dx, dy, k, _, _ in pattern]
            if not free(discs):
                continue
            near = min([math.hypot(x - px, y - py) for px, py, _ in placed] or [420.0])
            score = min(near, 420.0) + rng.uniform(0, 70)
            if score > best_score:
                best, best_score = (x, y, r, pattern, discs), score
        if best is None:
            continue
        x, y, r, pattern, discs = best
        draw_cluster(canvas, x, y, r, pattern, colour, rng.uniform(0.35, 0.65))
        for cx, cy, rr in discs:
            R = rr * 1.2 + gap
            occ[max(0, int((cy - R) // scale)):int((cy + R) // scale) + 1, max(0, int((cx - R) // scale)):int((cx + R) // scale) + 1] = True
        placed.append((x, y, r))
    return placed


def d_check(canvas, x, y, s, colour, w=9, double=True):
    """A check mark drawn with two quick strokes."""
    for k in ((0, 0), (s * 0.35, s * 0.2)) if double else ((0, 0),):
        ox, oy = k
        stroke(canvas, [(x + ox, y + oy + s * 0.5), (x + ox + s * 0.28, y + oy + s * 0.8), (x + ox + s * 0.95, y + oy)], colour, w)


def d_burst(canvas, x, y, s, colour, w=8, n=4, spread=1.4):
    """Short rays fanning out from a point, like a sparkle of motion."""
    for i in range(n):
        a = -math.pi / 2 - spread / 2 + spread * i / max(1, n - 1)
        stroke(canvas, [(x + math.cos(a) * s * 0.45, y + math.sin(a) * s * 0.45), (x + math.cos(a) * s, y + math.sin(a) * s)], colour, w)


def d_squiggle(canvas, x, y, width, colour, w=8, amp=12, waves=5):
    """A wavy underline."""
    pts = [(x + width * t / 60, y + math.sin(t / 60 * waves * 2 * math.pi) * amp) for t in range(61)]
    stroke(canvas, pts, colour, w)


def d_star(canvas, cx, cy, r, colour, w=7, angle=-90, fill=None):
    """A five-point star, outlined (or filled) by hand."""
    pts = []
    for i in range(10):
        rr = r if i % 2 == 0 else r * 0.42
        a = math.radians(angle + i * 36)
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    if fill:
        poly(canvas, pts, fill)
    stroke(canvas, pts + [pts[0], pts[1]], colour, w)


def d_loops(canvas, x, y, width, colour, w=7, loops=3, r=34):
    """A ribbon of loops, the way a bored pen draws on a margin."""
    a = width / (loops * 2 * math.pi)
    b = max(r, a * 2.4)
    pts = [(x + a * t - b * math.sin(t), y - b * math.cos(t) + b) for t in np.linspace(0, loops * 2 * math.pi, 40 * loops)]
    stroke(canvas, pts, colour, w)


def d_spiral(canvas, cx, cy, r, colour, w=7, turns=2.4):
    pts = []
    for t in np.linspace(0, turns * 2 * math.pi, 140):
        k = t / (turns * 2 * math.pi)
        pts.append((cx + math.cos(t) * r * k, cy + math.sin(t) * r * k))
    stroke(canvas, pts, colour, w)


def d_zig(canvas, x, y, length, colour, w=7, amp=22, n=7, angle=0):
    pts = []
    for i in range(n + 1):
        a = (-amp if i % 2 else amp)
        px, py = length * i / n, a
        pts.append((x + px * math.cos(angle) - py * math.sin(angle), y + px * math.sin(angle) + py * math.cos(angle)))
    stroke(canvas, pts, colour, w)


def scribbles(canvas, seed, box, n, colour, w=7, keep_out=None):
    """Marker doodles scattered in a box: plus signs, rings, zigzags, little arrows and dots."""
    rnd = random.Random(seed)
    x0, y0, x1, y1 = box
    for _ in range(n):
        x, y = rnd.uniform(x0, x1), rnd.uniform(y0, y1)
        if keep_out and any(k[0] <= x <= k[2] and k[1] <= y <= k[3] for k in keep_out):
            continue
        s = rnd.uniform(26, 58)
        kind = rnd.choice(["plus", "ring", "zig", "dot", "x", "tri"])
        if kind == "plus":
            stroke(canvas, [(x - s / 2, y), (x + s / 2, y)], colour, w)
            stroke(canvas, [(x, y - s / 2), (x, y + s / 2)], colour, w)
        elif kind == "ring":
            stroke(canvas, [(x + s / 2 * math.cos(t), y + s / 2 * math.sin(t)) for t in np.linspace(0, 6.5, 24)], colour, w)
        elif kind == "zig":
            d_zig(canvas, x, y, s * 1.6, colour, w, amp=s * 0.3, n=4, angle=rnd.uniform(-0.6, 0.6))
        elif kind == "dot":
            ImageDraw.Draw(canvas).ellipse((x - w, y - w, x + w, y + w), fill=tuple(colour[:3]) + (255,))
        elif kind == "x":
            stroke(canvas, [(x - s / 3, y - s / 3), (x + s / 3, y + s / 3)], colour, w)
            stroke(canvas, [(x - s / 3, y + s / 3), (x + s / 3, y - s / 3)], colour, w)
        else:
            stroke(canvas, [(x - s / 2, y + s / 3), (x, y - s / 2), (x + s / 2, y + s / 3), (x - s / 2, y + s / 3)], colour, w)


# ---- badges and stickers ----------------------------------------------------------------------------------------------------------------

def laurel(h, colour, leaves=10):
    """A laurel wreath (two branches facing each other) on a transparent square of the given height, with room inside for words."""
    k = 3
    n = h * k
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    cx = cy = n / 2
    r = n * 0.33
    sd = ImageDraw.Draw(im)
    for side in (-1, 1):
        stem = [(cx + side * r * math.sin(math.radians(14 + 150 * u / 40)), cy + r * math.cos(math.radians(14 + 150 * u / 40))) for u in range(41)]
        sd.line(stem, fill=tuple(colour[:3]) + (255,), width=int(n * 0.012), joint="curve")
        for i in range(leaves):
            t = i / (leaves - 1)
            th = math.radians(18 + 140 * t)                                  # from the bottom, round the side, to the top
            px, py = cx + side * r * math.sin(th), cy + r * math.cos(th)
            tang = math.atan2(-math.sin(th), side * math.cos(th))            # the way the branch runs there
            for off in (-1, 1):
                a = tang + off * math.radians(38)
                ll = n * 0.17 * (1 - 0.22 * t)
                lw = ll * 0.44
                c0 = ll * 1.2
                leaf = Image.new("L", (int(ll * 2.4), int(ll * 2.4)), 0)
                ImageDraw.Draw(leaf).ellipse((c0 - ll / 2, c0 - lw / 2, c0 + ll / 2, c0 + lw / 2), fill=255)
                leaf = leaf.rotate(-math.degrees(a), resample=Image.BICUBIC)
                layer = Image.new("RGBA", leaf.size, tuple(colour[:3]) + (0,))
                layer.putalpha(leaf)
                im.alpha_composite(layer, (int(px + math.cos(a) * ll * 0.5 - c0), int(py + math.sin(a) * ll * 0.5 - c0)))
    return im.resize((h, h), Image.LANCZOS)


def sticker_round(diam, fill, lines, ink, edge=None, burst=0, ring=None):
    """A round sticker (optionally a scalloped starburst) with centred lines of text: [(text, size share of diam, weight)]."""
    k = 3
    n = diam * k
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if burst:
        pts = []
        for i in range(burst * 2):
            rr = n / 2 * (1.0 if i % 2 == 0 else 0.90)
            a = math.pi * i / burst
            pts.append((n / 2 + math.cos(a) * rr, n / 2 + math.sin(a) * rr))
        d.polygon(pts, fill=fill)
    else:
        d.ellipse((0, 0, n - 1, n - 1), fill=fill)
    if edge:
        d.ellipse((n * 0.06, n * 0.06, n * 0.94, n * 0.94), outline=edge, width=int(n * 0.018))
    if ring:
        d.ellipse((n * 0.10, n * 0.10, n * 0.90, n * 0.90), outline=ring, width=int(n * 0.012))
    total = sum(s * 1.12 for _, s, _ in lines)
    y = n / 2 - total * n / 2
    for text, s, wt in lines:
        f = sf(s * n, wt)
        d.text((n / 2, y + s * n * 0.56), text, font=f, fill=ink, anchor="mm")
        y += s * n * 1.12
    return im.resize((diam, diam), Image.LANCZOS)


def sticker_tag(text, size, fill, ink, angle=0, edge=None, pad=0.5, weight=800, path=None):
    """A hand-cut tag of words, a little skewed, with a thin darker edge."""
    f = sf(size, weight) if path is None else ImageFont.truetype(path, int(size))
    w = int(tw(text, f) + size * pad * 2)
    h = int(size * 1.7)
    k = 3
    im = Image.new("RGBA", (w * k, h * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, w * k - 1, h * k - 1), int(size * 0.5 * k), fill=fill, outline=edge, width=int(size * 0.07 * k) if edge else 0)
    im = im.resize((w, h), Image.LANCZOS)
    ImageDraw.Draw(im).text((w / 2, h / 2 + size * 0.04), text, font=f, fill=ink, anchor="mm")
    return im.rotate(angle, expand=True, resample=Image.BICUBIC) if angle else im


def icon_tile(d_px, fill, glyph, ink=(255, 255, 255), radius=0.26):
    """A rounded-square app-icon tile with one drawn glyph: 'page', 'check', 'star', 'mic', 'cards', 'chat', 'cap', 'bolt', 'sky'."""
    k = 3
    n = d_px * k
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, n - 1, n - 1), int(n * radius), fill=fill)
    c = n / 2
    s = n * 0.26
    lw = int(n * 0.075)
    if glyph == "page":
        d.rounded_rectangle((c - s * 0.8, c - s, c + s * 0.8, c + s), int(s * 0.18), outline=ink, width=lw)
        for yy in (-0.35, 0.05, 0.45):
            d.line((c - s * 0.45, c + yy * s, c + s * 0.45, c + yy * s), fill=ink, width=lw)
    elif glyph == "check":
        d.line((c - s * 0.8, c + s * 0.05, c - s * 0.2, c + s * 0.65, c + s * 0.9, c - s * 0.6), fill=ink, width=int(lw * 1.4), joint="curve")
    elif glyph == "star":
        pts = []
        for i in range(10):
            rr = s * (1.05 if i % 2 == 0 else 0.45)
            a = math.radians(-90 + i * 36)
            pts.append((c + math.cos(a) * rr, c + math.sin(a) * rr))
        d.polygon(pts, fill=ink)
    elif glyph == "mic":
        d.rounded_rectangle((c - s * 0.35, c - s * 0.95, c + s * 0.35, c + s * 0.25), int(s * 0.35), fill=ink)
        d.arc((c - s * 0.7, c - s * 0.55, c + s * 0.7, c + s * 0.7), 0, 180, fill=ink, width=lw)
        d.line((c, c + s * 0.7, c, c + s * 0.98), fill=ink, width=lw)
    elif glyph == "cards":
        d.rounded_rectangle((c - s * 0.85, c - s * 0.55, c + s * 0.45, c + s * 0.85), int(s * 0.2), outline=ink, width=lw)
        d.rounded_rectangle((c - s * 0.45, c - s * 0.85, c + s * 0.85, c + s * 0.55), int(s * 0.2), fill=fill, outline=ink, width=lw)
    elif glyph == "chat":
        d.rounded_rectangle((c - s * 0.95, c - s * 0.75, c + s * 0.95, c + s * 0.45), int(s * 0.4), outline=ink, width=lw)
        d.polygon([(c - s * 0.4, c + s * 0.4), (c - s * 0.7, c + s * 0.95), (c + s * 0.05, c + s * 0.4)], fill=ink)
    elif glyph == "bolt":
        d.polygon([(c + s * 0.2, c - s), (c - s * 0.6, c + s * 0.15), (c - s * 0.05, c + s * 0.15), (c - s * 0.25, c + s), (c + s * 0.6, c - s * 0.2), (c + s * 0.05, c - s * 0.2)], fill=ink)
    elif glyph == "sky":
        for (dx, dy, rr) in ((-0.5, -0.3, 0.2), (0.4, -0.5, 0.15), (0.05, 0.35, 0.25), (0.6, 0.45, 0.12)):
            d.ellipse((c + dx * s - rr * s, c + dy * s - rr * s, c + dx * s + rr * s, c + dy * s + rr * s), fill=ink)
        d.line((c - 0.5 * s, c - 0.3 * s, c + 0.05 * s, c + 0.35 * s, c + 0.4 * s, c - 0.5 * s), fill=ink, width=int(lw * 0.6))
    elif glyph == "cap":
        d.polygon([(c, c - s * 0.7), (c + s * 1.05, c - s * 0.2), (c, c + s * 0.3), (c - s * 1.05, c - s * 0.2)], fill=ink)
        d.rectangle((c - s * 0.55, c + s * 0.15, c + s * 0.55, c + s * 0.65), fill=ink)
    return im.resize((d_px, d_px), Image.LANCZOS)


# ---- glass, neon and lettering ----------------------------------------------------------------------------------------------------------

def glass(canvas, box, radius, tint_rgb=(255, 255, 255), amount=0.40, blur=34, border=0.8, shadow=0.16, shadow_rgb=(60, 40, 120)):
    """A frosted-glass panel on the canvas: what is under it, blurred, washed with a tint, with a bright edge and a soft shadow."""
    x0, y0, x1, y1 = [int(round(v)) for v in box]
    w, h = x1 - x0, y1 - y0
    if shadow:
        pad = 70
        m = Image.new("L", (w + 2 * pad, h + 2 * pad), 0)
        m.paste(sk.rounded_mask((w, h), radius), (pad, pad + 26))
        m = m.filter(ImageFilter.GaussianBlur(34)).point(lambda v: int(v * shadow))
        sh = Image.new("RGBA", m.size, tuple(shadow_rgb) + (0,))
        sh.putalpha(m)
        paste(canvas, sh, x0 - pad, y0 - pad)
    region = canvas.crop((x0, y0, x1, y1)).filter(ImageFilter.GaussianBlur(blur))
    region.alpha_composite(Image.new("RGBA", region.size, tuple(tint_rgb) + (int(255 * amount),)))
    canvas.paste(region, (x0, y0), sk.rounded_mask((w, h), radius))
    if border:
        rrect(canvas, (x0, y0, x1, y1), radius, None, outline=(255, 255, 255, int(255 * border)), width=3)


def neon(canvas, box, radius, colour, width=7, glow_px=(70, 26), glow_alpha=0.85, core=(255, 255, 255)):
    """A glowing outline round a rounded rectangle: a wide blur, a tight blur, the line, and a white-hot core."""
    x0, y0, x1, y1 = [int(round(v)) for v in box]
    pad = int(glow_px[0] * 3)
    w, h = x1 - x0 + 2 * pad, y1 - y0 + 2 * pad
    line = Image.new("L", (w, h), 0)
    ImageDraw.Draw(line).rounded_rectangle((pad, pad, w - pad - 1, h - pad - 1), radius, outline=255, width=width)
    for blur, a in ((glow_px[0], glow_alpha * 0.7), (glow_px[1], glow_alpha)):
        g = line.filter(ImageFilter.GaussianBlur(blur)).point(lambda v, a=a: min(255, int(v * 2.2 * a)))
        layer = Image.new("RGBA", (w, h), tuple(colour[:3]) + (0,))
        layer.putalpha(g)
        paste(canvas, layer, x0 - pad, y0 - pad)
    layer = Image.new("RGBA", (w, h), tuple(colour[:3]) + (0,))
    layer.putalpha(line)
    paste(canvas, layer, x0 - pad, y0 - pad)
    cl = Image.new("L", (w, h), 0)
    ImageDraw.Draw(cl).rounded_rectangle((pad + width // 3, pad + width // 3, w - pad - 1 - width // 3, h - pad - 1 - width // 3), max(2, radius - width // 3),
                                         outline=255, width=max(1, width // 3))
    layer = Image.new("RGBA", (w, h), tuple(core[:3]) + (0,))
    layer.putalpha(cl.point(lambda v: int(v * 0.8)))
    paste(canvas, layer, x0 - pad, y0 - pad)


def gradient_text(canvas, s, f, x, y, stops, anchor="ms", angle=0):
    """Text filled with a gradient (stops as in lin()), baseline at y."""
    w = int(tw(s, f)) + 40
    top, bot = int(f.size * 1.05), int(f.size * 0.35)
    m = Image.new("L", (w, top + bot), 0)
    ImageDraw.Draw(m).text((20, top), s, font=f, fill=255, anchor="ls")
    fillimg = lin((w, top + bot), stops, angle)
    x0 = x - w / 2 if anchor[0] == "m" else x if anchor[0] == "l" else x - w
    layer = fillimg
    layer.putalpha(m)
    paste(canvas, layer, x0 - 20 + 20, y - top)


def giant_word(word, size, top=(255, 255, 255), bottom=(214, 196, 255), edge=(56, 16, 150), depth=None, jitter=3.2, seed=1, weight=900, width=100):
    """The word as big, chunky 3D lettering: each letter a little off its line and angle, with a thick extruded side, like a toy sign."""
    f = sf(size, weight, width)
    rnd = random.Random(seed)
    depth = int(depth or size * 0.07)
    x, items = 0.0, []
    for i, ch in enumerate(word):
        adv = (_probe.textlength(word[i:i + 2], font=f) - _probe.textlength(word[i + 1:i + 2], font=f)) if i + 1 < len(word) else _probe.textlength(ch, font=f)
        items.append((ch, x, adv))
        x += adv * 0.97
    total = x
    pad = int(size * 0.35)
    out = Image.new("RGBA", (int(total + 2 * pad), int(size * 1.5 + 2 * pad)), (0, 0, 0, 0))
    for ch, lx, adv in items:
        n = int(size * 2.0)
        g = Image.new("L", (n, n), 0)
        ImageDraw.Draw(g).text((n / 2, n / 2 + size * 0.35), ch, font=f, fill=255, anchor="ms")
        ang = rnd.uniform(-jitter, jitter)
        g = g.rotate(ang, resample=Image.BICUBIC)
        dy = rnd.uniform(-size * 0.035, size * 0.035)
        ext = Image.new("RGBA", g.size, (0, 0, 0, 0))
        for k in range(depth, 0, -1):
            c = tuple(int(edge[j] + (min(255, edge[j] * 1.5 + 30) - edge[j]) * (1 - k / depth) * 0.4) for j in range(3))
            sh = Image.new("RGBA", g.size, c + (0,))
            sh.putalpha(ImageChops.offset(g, int(k * 0.62), int(k * 0.78)))
            ext.alpha_composite(sh)
        face = lin(g.size, [(0.28, top), (0.78, bottom)], 90)
        face.putalpha(g)
        ext.alpha_composite(face)
        out.alpha_composite(ext, (int(pad + lx - n / 2 + adv / 2), int(pad + dy - n / 2 + size * 0.65)))
    return out.crop(out.getbbox())


# ---- misc layers ------------------------------------------------------------------------------------------------------------------------

def tinted(layer, rgb, amount):
    """A layer washed with a colour (amount 0 to 1), keeping its alpha."""
    a = layer.getchannel("A")
    over = Image.new("RGBA", layer.size, tuple(rgb[:3]) + (int(255 * amount),))
    out = layer.copy()
    out.alpha_composite(over)
    out.putalpha(a)
    return out


def fade_bottom(layer, start, end=1.0, to=0.0):
    """Fade a layer's alpha towards the bottom: from `start` (a share of its height) to `end`, down to `to` opacity."""
    a = np.asarray(layer.getchannel("A")).astype("float32")
    h = a.shape[0]
    t = np.clip((np.arange(h, dtype="float32") / h - start) / max(1e-4, end - start), 0, 1)[:, None]
    a *= (1 - t * (1 - to))
    out = layer.copy()
    out.putalpha(Image.fromarray(a.astype("uint8")))
    return out


def panel(shot, width, top=152, height=None, radius=46, round_bottom=False):
    """A screen with no phone round it: the capture's top rounded, its bottom left square to run off the canvas (or rounded too). top: source
    rows of the status bar to drop. height: how tall to cut it, in canvas px (default the rest of the screen)."""
    s = sk.screen(shot)
    k = width / s.width
    src_h = int(height / k) if height else s.height - top
    src_h = min(src_h, s.height - top)
    tile = s.crop((0, top, s.width, top + src_h)).resize((width, round(src_h * k)), Image.LANCZOS).convert("RGBA")
    if round_bottom:
        m = sk.rounded_mask(tile.size, radius)
    else:
        m = Image.new("L", (tile.width * 3, (tile.height + radius * 2) * 3), 0)
        ImageDraw.Draw(m).rounded_rectangle((0, 0, tile.width * 3 - 1, (tile.height + radius * 2) * 3 - 1), radius * 3, fill=255)
        m = m.resize((tile.width, tile.height + radius * 2), Image.LANCZOS).crop((0, 0, tile.width, tile.height))
    tile.putalpha(m)
    return tile
