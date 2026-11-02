#!/usr/bin/env python3
"""Three looks for Capling's first three App Store screenshots, drawn side by side so the owner can pick one.

    python3 -P scripts/store_art/shots_concepts.py [--out DIR]

The real screenshots (build/listing/..., from scripts/shots.sh) go inside a phone drawn here; the words are set in Bricolage; Cap is
the app's own art. Nothing is painted by a model, so a screen is exactly what the app draws. Output: <out>/<look>-trio.png (the three
frames next to each other, as the store's search results show them) and <out>/<look>-<n>.png (full size, 1290x2796).
"""
import argparse
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
FONTS = os.path.join(REPO, "Cramless", "Resources", "Fonts")
ASSETS = os.path.join(REPO, "Cramless", "Resources", "Assets.xcassets")
LISTING = os.path.join(REPO, "build", "listing")
DISPLAY = os.path.join(FONTS, "BricolageGrotesque-Display.ttf")

W, H = 1290, 2796
NAVY = (20, 33, 61)
DEEP = (11, 18, 32)
YELLOW = (255, 207, 63)
SUN = (255, 224, 138)
MINT = (62, 201, 146)

# What each of the first three frames says and shows: the welcome line, then the grading, then the projection.
SRC = os.path.join(LISTING, "src")   # scripts/store_art/capture_listing.sh
FRAMES = [
    ("Ready on", "exam day.", "src/01-today.png", "celebrate"),
    ("Answer in your", "own words.", "src/02-graded.png", "think"),
    ("See where you", "stand.", "src/03-exam.png", "point"),
    ("Turn your pages", "into questions.", "src/04-questions.png", "scan"),
    ("Ask Cap to", "make it for you.", "src/05-ask.png", "ask"),
    ("Watch your memory", "light up.", "src/06-sky.png", "stargaze"),
    ("Save what you", "were forgetting.", "src/07-saved.png", "proud"),
    ("Keep your", "streak going.", "src/08-streak.png", "relax"),
]


def font(px):
    return ImageFont.truetype(DISPLAY, int(px))


def cap(name, height):
    im = Image.open(os.path.join(ASSETS, f"Cap-{name}.imageset", f"cap-{name}.png")).convert("RGBA")
    box = im.getbbox()
    im = im.crop(box)
    return im.resize((round(im.width * height / im.height), int(height)), Image.LANCZOS)


def gradient(top, bottom):
    col = Image.linear_gradient("L").resize((W, H))
    return Image.composite(Image.new("RGB", (W, H), bottom), Image.new("RGB", (W, H), top), col)


def island(s):
    """The Simulator's screenshots have no Dynamic Island (it is hardware), and the exam-week Live Activity can sit in its place. Copy the
    status bar's own pixels (the row above the island) down over that zone, then draw one standard island, so every frame has the same
    one. Chrome only: no app pixel is touched (the zone holds nothing but the page's background)."""
    s = s.copy()
    sc = s.width / 402.0
    x0, x1 = int(sc * 104), int(sc * 308)   # between the clock and the wifi glyphs
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


def phone(shot, width, frame=(18, 22, 34), rim=(70, 78, 98), bezel=26):
    """A front-view phone: the screenshot under rounded corners, a dark bezel, a thin rim and the island."""
    s = Image.open(os.path.join(LISTING, shot)).convert("RGB")
    s = island(s)
    sw = width - 2 * bezel
    sh = round(sw * s.height / s.width)
    s = s.resize((sw, sh), Image.LANCZOS)
    r_out, r_in = round(width * 0.13), round(width * 0.13) - bezel
    k = 3
    body = Image.new("RGBA", ((width) * k, (sh + 2 * bezel) * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    d.rounded_rectangle((0, 0, body.width - 1, body.height - 1), r_out * k, fill=rim)
    d.rounded_rectangle((4 * k, 4 * k, body.width - 4 * k - 1, body.height - 4 * k - 1), (r_out - 4) * k, fill=frame)
    body = body.resize((width, sh + 2 * bezel), Image.LANCZOS)
    mask = Image.new("L", (sw * k, sh * k), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, sw * k - 1, sh * k - 1), r_in * k, fill=255)
    mask = mask.resize((sw, sh), Image.LANCZOS)
    body.paste(s, (bezel, bezel), mask)
    # The island, only when the screenshot is a full screen with one (the sim draws it in the shot itself).
    return body


def shadow(layer, blur=40, dy=30, alpha=90):
    """A soft shadow on a canvas padded by the blur, so its edge is never cut off into a visible box."""
    pad = blur * 3
    a = Image.new("L", (layer.width + 2 * pad, layer.height + 2 * pad), 0)
    a.paste(layer.getchannel("A"), (pad, pad))
    a = a.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: v * alpha // 255)
    sh = Image.new("RGBA", a.size, (0, 0, 0, 0))
    sh.putalpha(a)
    return sh, dy, pad


def paste_phone(canvas, ph, cx, top, angle=0):
    if angle:
        ph = ph.rotate(angle, resample=Image.BICUBIC, expand=True)
    sh, dy, pad = shadow(ph)
    canvas.alpha_composite(sh, (cx - ph.width // 2 - pad, top + dy - pad))
    canvas.alpha_composite(ph, (cx - ph.width // 2, top))


def fit(size, margin=110, pill=False):
    """The biggest size at which the widest line of every frame still clears the margins."""
    d = ImageDraw.Draw(Image.new("RGB", (1, 1)))
    widest = max(d.textlength(t, font=font(100)) + (40 if pill and k else 0) for fr in FRAMES for k, t in enumerate(fr[:2]))
    return min(size, int(100 * (W - 2 * margin) / widest))


def headline(canvas, l1, l2, top, fill, fill2=None, pill=None, size=190, left=None):
    d = ImageDraw.Draw(canvas)
    f = font(size)
    y = top
    for i, line in enumerate((l1, l2)):
        w = d.textlength(line, font=f)
        x = left if left is not None else (W - w) / 2
        col = fill if i == 0 else (fill2 or fill)
        if i == 1 and pill:
            pad = size * 0.2
            d.rounded_rectangle((x - pad, y + size * 0.02, x + w + pad, y + size * 1.2), size * 0.3, fill=pill)
        d.text((x, y), line, font=f, fill=col)
        y += size * 1.12


def stars(canvas, seed, n=70, colors=((255, 255, 255), YELLOW), box=None):
    rnd = random.Random(seed)
    d = ImageDraw.Draw(canvas)
    x0, y0, x1, y1 = box or (0, 0, W, H)
    for _ in range(n):
        x, y = rnd.randint(x0, x1), rnd.randint(y0, y1)
        r = rnd.choice((3, 4, 6, 9))
        c = rnd.choice(colors)
        a = rnd.choice((120, 180, 255))
        d.ellipse((x - r, y - r, x + r, y + r), fill=c + (a,))


def hills(canvas, y, color, amp=60, phase=0.0):
    import math
    d = ImageDraw.Draw(canvas)
    pts = [(x, y + amp * math.sin(x / W * 2 * math.pi + phase)) for x in range(0, W + 1, 10)]
    d.polygon(pts + [(W, H), (0, H)], fill=color)


def peek(canvas, pose, i, phone_w, phone_top, height=430):
    """Cap looks over the phone's top edge, drawn before the phone so the phone's bezel hides his feet."""
    cp = cap(pose, height)
    x = (W + phone_w) // 2 - cp.width - 70 if i % 2 == 0 else (W - phone_w) // 2 + 70
    canvas.alpha_composite(cp, (x, phone_top - cp.height + 70))


def sunny(i):
    c = gradient((255, 235, 160), (255, 207, 63)).convert("RGBA")
    l1, l2, shot, pose = FRAMES[i]
    stars(c, 10 + i, 40, ((255, 255, 255), (255, 140, 60), (80, 180, 255)), (0, 0, W, 700))
    hills(c, 2150, MINT + (255,), 70, i)
    hills(c, 2330, (40, 170, 120, 255), 50, i + 2)
    headline(c, l1, l2, 170, NAVY, YELLOW, pill=NAVY, size=fit(190, 150, True))
    peek(c, pose, i, 960, 940)
    paste_phone(c, phone(shot, 960), W // 2, 940)
    return c.convert("RGB")


def night(i):
    c = gradient(DEEP, (26, 44, 92)).convert("RGBA")
    l1, l2, shot, pose = FRAMES[i]
    stars(c, 99, 220)  # the same seed on all three: one sky behind the whole row
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((W // 2 - 620, 1100, W // 2 + 620, 2500), fill=(255, 207, 63, 70))
    c.alpha_composite(glow.filter(ImageFilter.GaussianBlur(160)))
    headline(c, l1, l2, 170, (255, 255, 255), YELLOW, size=fit(190, 110))
    peek(c, pose, i, 960, 940)
    paste_phone(c, phone(shot, 960, frame=(8, 10, 18), rim=(120, 130, 160)), W // 2, 940)
    return c.convert("RGB")


def bold(i):
    bg = [(255, 207, 63), (62, 201, 146), (255, 125, 90)][i % 3]
    ink = NAVY
    c = Image.new("RGBA", (W, H), bg + (255,))
    l1, l2, shot, pose = FRAMES[i]
    d = ImageDraw.Draw(c)
    d.ellipse((-300, 1500, W + 300, 3600), fill=tuple(int(v * 0.88) for v in bg) + (255,))
    headline(c, l1, l2, 170, ink, (255, 255, 255), pill=None, size=fit(190, 90), left=90)
    paste_phone(c, phone(shot, 940, frame=(20, 24, 38), rim=(90, 98, 120)), W // 2 + (50 if i % 2 == 0 else -50), 960, angle=(-4 if i % 2 == 0 else 4))
    return c.convert("RGB")


LOOKS = {"sunny": sunny, "night": night, "bold": bold}


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
    ap.add_argument("--out", default=os.path.join(LISTING, "concepts"))
    ap.add_argument("--only", default="")
    ap.add_argument("--frames", type=int, default=3, help="how many frames to draw (3 for the search trio, 8 for the set)")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    for name, fn in LOOKS.items():
        if a.only and name not in a.only.split(","):
            continue
        ims = [fn(i) for i in range(a.frames)]
        for i, im in enumerate(ims, 1):
            im.save(os.path.join(a.out, f"{name}-{i}.png"))
        trio(ims, os.path.join(a.out, f"{name}-trio.png"))
        print(os.path.join(a.out, f"{name}-trio.png"))


if __name__ == "__main__":
    main()
