#!/usr/bin/env python3
"""Capling's function-first store art: what the app does, shown with its own real screens.

The universal asset (store_art.py) is the brand mood. This is the other job Apple gives the Search-results slot and the header: say
what the app is for ("state the obvious") and show the first-hand experience. Three real screens, each cropped to the part that
tells its step, over the same night scene:

    Snap your notes        the capture flow: a photo of a textbook page, the questions that come out of it, each tagged with its page
    Answer in your words   a question graded against the key points in what you wrote, the matching words highlighted
    Know you're ready      the end of a session: readiness 42% -> 78% and "on track for 80%"

The screens are captured from the Simulator with the app's own launch hooks (see CLAUDE.md "Seeing the app"), never drawn:

    scripts/shots.sh <udid> <dir> review         EXTRA="CRAMLESS_CAPTURE_PHASE=done"          -> w-done/review.png
    scripts/shots.sh <udid> <dir> session        EXTRA="CRAMLESS_SESSION_STATE=graded"        -> graded-w9/session.png (WAIT=9: the verdict panel)
    scripts/shots.sh <udid> <dir> session        EXTRA="CRAMLESS_SESSION_STATE=exameve-summary" -> exameve/session.png

(wait 13 s for the capture phases, 9 s for the verdict, 5 s for the others; `xcrun simctl status_bar <udid> override --time 9:41 ...` first.)

Sizes and boxes are Apple's templates, measured 2026-10-29: search 3840x2560 with the art safe area x 836-3002, y 766-1794; header
3840x1646 with x 1098-2742, y 494-1152. Everything that has to be read sits inside the box; Cap and the sky may be cropped.

    python3 -P store_lockup.py search --theme night --out build/store-art/capling-search-night.png
    python3 -P store_lockup.py search --scale 0.5 --safe --out /tmp/look.png       # a quick look with the box drawn
"""
import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import store_art as sa  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SHOTS = os.path.join(REPO, "build", "store-art", "shots")
FONTS = os.path.join(REPO, "Cramless", "Resources", "Fonts")
DISPLAY = os.path.join(FONTS, "BricolageGrotesque-Display.ttf")     # ExtraBold: the wordmark and hero titles
HEADING = os.path.join(FONTS, "BricolageGrotesque-Heading.ttf")     # SemiBold

SEARCH = dict(size=(3840, 2560), box=(836, 766, 3002, 1794), horizon=2060)
HEADER = dict(size=(3840, 1646), box=(1098, 494, 2742, 1152), horizon=1175)

# One window per step: which capture, which part of the 1206 x 2622 screen, and its words. The crops start and end between rows of
# ink (found by scanning the screenshots), so no label, chip or button is cut; all three are 1206 x 1720.
STEPS = [
    dict(src="w-done/review.png", crop=(0, 341, 1206, 2061), verb="Snap", rest="your notes"),
    dict(src="graded-w9/session.png", crop=(0, 405, 1206, 2125), verb="Answer", rest="in your own words"),
    dict(src="exameve/session.png", crop=(0, 230, 1206, 1950), verb="Know", rest="you're ready"),
]


def font(path, px):
    return ImageFont.truetype(path, int(round(px)))


def rounded_mask(size, radius, ss=3):
    w, h = size
    big = Image.new("L", (w * ss, h * ss), 0)
    ImageDraw.Draw(big).rounded_rectangle([0, 0, w * ss - 1, h * ss - 1], radius=radius * ss, fill=255)
    return big.resize((w, h), Image.LANCZOS)


def paste_tile(base, tile, xy, radius, k):
    """A real screen crop as a floating card: a soft shadow, the screen, a hairline edge."""
    x, y = int(round(xy[0] * k)), int(round(xy[1] * k))
    w, h = tile.size
    mask = rounded_mask((w, h), radius * k)
    pad = int(90 * k)
    sh = Image.new("L", (w + 2 * pad, h + 2 * pad), 0)
    sh.paste(mask.point(lambda v: int(v * 0.62)), (pad, pad + int(26 * k)))
    sh = sh.filter(ImageFilter.GaussianBlur(34 * k))
    base.paste(Image.new("RGB", sh.size, (2, 5, 14)), (x - pad, y - pad), sh)
    base.paste(tile, (x, y), mask)
    edge = Image.new("L", (w, h), 0)
    ImageDraw.Draw(edge).rounded_rectangle([0, 0, w - 1, h - 1], radius=radius * k, outline=255, width=max(2, int(3 * k)))
    base.paste(Image.new("RGB", (w, h), (255, 255, 255)), (x, y), edge.point(lambda v: int(v * 0.35)))


def scrim(img, box, k, strength=0.50, grow=150, feather=150):
    """Darken the sky behind the lockup, softly, so stars and constellation lines do not run through the words."""
    w, h = img.size
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([(box[0] - grow) * k, (box[1] - grow * 0.6) * k, (box[2] + grow) * k, (box[3] + grow * 0.6) * k],
                                       radius=170 * k, fill=int(255 * strength))
    m = m.filter(ImageFilter.GaussianBlur(feather * k))
    img.paste(Image.new("RGB", (w, h), (3, 7, 20)), (0, 0), m)


def soft_text(img, xy, text, fnt, fill, k, anchor="ls", shadow=0.55):
    """Text with a dark soft shadow under it."""
    w, h = img.size
    layer = Image.new("L", (w, h), 0)
    ImageDraw.Draw(layer).text(xy, text, font=fnt, fill=255, anchor=anchor)
    sh = layer.filter(ImageFilter.GaussianBlur(14 * k)).point(lambda v: int(v * shadow))
    img.paste(Image.new("RGB", (w, h), (2, 5, 14)), (0, 0), sh)
    ImageDraw.Draw(img, "RGBA").text(xy, text, font=fnt, fill=fill, anchor=anchor)


def chevron(base, cx, cy, size, k):
    """A small arrow between two steps."""
    d = ImageDraw.Draw(base, "RGBA")
    s = size * k
    w = max(3, int(13 * k))
    pts = [(cx - s * 0.30, cy - s * 0.5), (cx + s * 0.30, cy), (cx - s * 0.30, cy + s * 0.5)]
    d.line(pts, fill=(255, 255, 255, 190), width=w, joint="curve")
    for (px, py) in (pts[0], pts[2]):
        d.ellipse([px - w / 2, py - w / 2, px + w / 2, py + w / 2], fill=(255, 255, 255, 190))
    d.ellipse([pts[1][0] - w / 2, pts[1][1] - w / 2, pts[1][0] + w / 2, pts[1][1] + w / 2], fill=(255, 255, 255, 190))


def load_step(step, width, k):
    im = Image.open(os.path.join(SHOTS, step["src"])).convert("RGB").crop(step["crop"])
    h = round(im.height * width * k / im.width)
    return im.resize((int(round(width * k)), h), Image.LANCZOS)


# Rows: the part of each screen that proves its step, wide (full screen width), so it can be shown big.
ROWS = [
    dict(src="w-done/review.png", crop=(0, 740, 1206, 1290), verb="Snap", rest="your notes"),
    dict(src="graded-w9/session.png", crop=(0, 775, 1206, 1325), verb="Answer", rest="in your own words"),
    dict(src="exameve/session.png", crop=(0, 1548, 1206, 1905), verb="Know", rest="you're ready"),
]


def build_search_rows(theme="night", scale=1.0, safe=False, seed=7):
    """The Search card, made bigger: three rows, each the step in big words and the real screen that proves it, as large as the box allows."""
    W, H = SEARCH["size"]
    box = SEARCH["box"]
    yw = SEARCH["horizon"]
    k = scale
    plate = sa.render_scene(
        theme, k, (W, H), yw, seed,
        cap=dict(height=600, left=150, feet=yw - 34, knoll=(470, 520, 46)),
        hero=dict(u=72.0, gx0=3180, gy0=430),
        falling=((2330, 300), (1900, 520)), avoid=box)
    sa.set_canvas(5244, 2950, 1620)
    img = plate.convert("RGB")
    scrim(img, box, k)

    gap = 30
    shots = [Image.open(os.path.join(SHOTS, r["src"])).convert("RGB").crop(r["crop"]) for r in ROWS]
    avail = (box[3] - box[1]) - gap * (len(ROWS) - 1)
    sc = avail / sum(im.height for im in shots)               # one scale for all rows, so the three crops match
    card_w = round(shots[0].width * sc)
    x_card = box[2] - card_w
    f_verb, f_rest = font(DISPLAY, 196 * k), font(HEADING, 116 * k)
    dr = ImageDraw.Draw(img, "RGBA")
    y = box[1]
    for row, im in zip(ROWS, shots):
        h = round(im.height * sc)
        tile = im.resize((int(round(card_w * k)), int(round(h * k))), Image.LANCZOS)
        paste_tile(img, tile, (x_card, y), 40, k)
        cy = y + h / 2
        block = 262                                              # verb, a gap and the line under it
        top = max(box[1], min(cy - block / 2, box[3] - block))    # centred on the row, but never outside the box
        v_base, r_base = top + 142, top + 142 + 14 + 82
        soft_text(img, (box[0] * k, v_base * k), row["verb"], f_verb, (255, 255, 255, 255), k)
        soft_text(img, (box[0] * k, r_base * k), row["rest"], f_rest, (255, 255, 255, 215), k, shadow=0.5)
        # a dotted leader from the words to their screen, so each row reads as one line
        x0 = box[0] + dr.textlength(row["rest"], font=f_rest) / k + 44
        x1 = x_card - 40
        yy = (r_base - 0.34 * 116) * k
        n = int((x1 - x0) / 24)
        for i in range(max(n, 0) + 1):
            xx = (x0 + i * 24) * k
            r = 4.5 * k
            dr.ellipse([xx - r, yy - r, xx + r, yy + r], fill=(255, 255, 255, 95))
        y += h + gap
    if safe:
        ImageDraw.Draw(img).rectangle([box[0] * k, box[1] * k, box[2] * k, box[3] * k], outline=(255, 90, 120), width=max(2, int(4 * k)))
    return img


def build_search(theme="night", scale=1.0, safe=False, seed=7):
    W, H = SEARCH["size"]
    box = SEARCH["box"]
    yw = SEARCH["horizon"]
    k = scale
    # Cap stands on his knoll in the left margin (outside the box, so a crop may take him), the cap in the sky is the brand's mark
    plate = sa.render_scene(
        theme, k, (W, H), yw, seed,
        cap=dict(height=600, left=150, feet=yw - 34, knoll=(470, 520, 46)),
        hero=dict(u=72.0, gx0=3180, gy0=430),
        falling=((2330, 300), (1900, 520)), avoid=box)
    sa.set_canvas(5244, 2950, 1620)
    img = plate.convert("RGB")

    tile_w = 572
    gap = (box[2] - box[0] - 3 * tile_w) / 2
    xs = [box[0] + i * (tile_w + gap) for i in range(3)]
    tiles = [load_step(s, tile_w, k) for s in STEPS]
    tile_h = tiles[0].height / k
    cap_block = 180
    total = cap_block + 30 + tile_h
    top = box[1] + (box[3] - box[1] - total) / 2
    ty = top + cap_block + 30

    scrim(img, box, k)
    f_verb, f_rest = font(DISPLAY, 140 * k), font(HEADING, 70 * k)
    for i, (step, tile) in enumerate(zip(STEPS, tiles)):
        x = xs[i]
        soft_text(img, (x * k, (top + 104) * k), step["verb"], f_verb, (255, 255, 255, 255), k)
        soft_text(img, (x * k, (top + 172) * k), step["rest"], f_rest, (255, 255, 255, 205), k, shadow=0.5)
        paste_tile(img, tile, (x, ty), 46, k)
        if i < 2:
            chevron(img, (x + tile_w + gap / 2) * k, (ty + tile_h / 2) * k, 62, k)
    if safe:
        ImageDraw.Draw(img).rectangle([box[0] * k, box[1] * k, box[2] * k, box[3] * k], outline=(255, 90, 120), width=max(2, int(4 * k)))
    return img


def build_header(theme="night", scale=1.0, safe=False, seed=7):
    """The product page header: the brand (Cap, the night sky, the cap in the stars) and the promise in two lines."""
    W, H = HEADER["size"]
    box = HEADER["box"]
    yw = HEADER["horizon"]
    k = scale
    plate = sa.render_scene(
        theme, k, (W, H), yw, seed,
        cap=dict(height=620, left=box[0] - 48, feet=yw - 26, knoll=(box[0] + 290, 520, 44)),
        hero=dict(u=60.0, gx0=2960, gy0=190),
        falling=((2560, 250), (2190, 440)), avoid=box)
    sa.set_canvas(5244, 2950, 1620)
    img = plate.convert("RGB")
    scrim(img, (1700, 600, box[2], 1010), k, strength=0.45, grow=110, feather=110)

    f = font(DISPLAY, 112 * k)
    x = 1790
    soft_text(img, (x * k, 772 * k), "Snap your notes.", f, (255, 255, 255, 255), k)
    # "ready" is the lit word
    line2 = "Know you're "
    soft_text(img, (x * k, 904 * k), line2, f, (255, 255, 255, 255), k)
    wlen = ImageDraw.Draw(img).textlength(line2, font=f)
    soft_text(img, (x * k + wlen, 904 * k), "ready.", f, (255, 207, 63, 255), k)
    if safe:
        ImageDraw.Draw(img).rectangle([box[0] * k, box[1] * k, box[2] * k, box[3] * k], outline=(255, 90, 120), width=max(2, int(4 * k)))
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=("search", "search-strip", "header"))
    ap.add_argument("--theme", default="night", choices=sorted(sa.THEMES))
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--safe", action="store_true", help="outline Apple's art safe area (for looking, not for upload)")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    build = dict(search=build_search_rows, header=build_header)
    build["search-strip"] = build_search
    img = build[a.kind](a.theme, a.scale, a.safe)
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    img.save(a.out, optimize=True)
    print(a.out, img.size)


if __name__ == "__main__":
    sys.exit(main())
