#!/usr/bin/env python3
"""Composes Cap's character sheet (one tall PNG) from the panels in build/cap-anim2/sheet/.

    sheet_compose.py            writes build/cap-anim2/cap-character-sheet.png (3000 px wide)

The panels are the picks in build/cap-anim2/picks.json plus the ten faces and five close-ups. The palette is sampled from
the art itself (see PALETTE), so the hex values are what is in the pictures.
"""
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent.parent
B2 = ROOT / "build/cap-anim2"
SHEET = B2 / "sheet"
OUT = B2 / "cap-character-sheet.png"

PAPER = (251, 248, 243)
INK = (22, 33, 61)
INK2 = (86, 98, 122)
LINE = (227, 232, 240)

TURN = [("turn-front-2", "Front"), ("turn-threeq-1", "Three-quarter"), ("turn-side-1", "Side"), ("turn-back-1", "Back")]
FACES = [("expr-content", "Content (his default)"), ("expr-open", "Eyes open"), ("expr-wink", "Wink"), ("expr-laugh", "Laugh"),
         ("expr-yawn", "Yawn"), ("expr-surprised", "Surprised"), ("expr-thinking", "Thinking"), ("expr-notyet", "Kind: not yet"),
         ("expr-sleepy", "Sleepy"), ("expr-proud", "Proud")]
DETAILS = [("detail-teeth", "Teeth and tongue"), ("detail-eyes", "Eyes, open"), ("detail-eyes_closed", "Eyes, closed"),
           ("detail-paws", "Paws and feet"), ("detail-hat", "Mortarboard and headphones")]
PALETTE = [("Tangerine fur", "#E5803C"), ("Fur shade", "#C96730"), ("Muzzle", "#93553A"), ("Paw brown", "#6D3B2A"),
           ("Ink brown", "#472827"), ("Mortarboard navy", "#1F2F53"), ("Tassel gold", "#FEC24E"), ("Headphone cream", "#FEF4E8"),
           ("Headphone taupe", "#E5D0B6"), ("Tongue pink", "#FD766B")]
ALWAYS = ["Wears the navy mortarboard with its gold tassel and the cream headphones, in every picture.",
          "His default face has closed, content arc eyes and a small closed smile.",
          "Open eyes are large, round and dark brown with one small white highlight. Brows appear only on expressive faces.",
          "A laugh shows exactly two small cream upper front teeth and a pink tongue. A yawn shows the same.",
          "Flat vector shapes, soft simple shading, a few darker fur strokes. No outline around him.",
          "Calm, warm and kind, even when the answer is not yet."]
NEVER = ["Sad, angry, scared or guilt-tripping. \"Not yet\" is encouraging.",
         "Red or alarming colours around him.",
         "More teeth, fangs, or a hanging tongue outside a laugh or a yawn.",
         "A baked-in ground shadow, a background or a frame in his art.",
         "Text or logos drawn into the picture.",
         "A different hat, headphones or fur colour from one scene to the next."]


def font(size, bold=False):
    for path, index in (("/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf", 0), ("/System/Library/Fonts/Helvetica.ttc", 1 if bold else 0),
                        ("/System/Library/Fonts/HelveticaNeue.ttc", 1 if bold else 0)):
        try:
            return ImageFont.truetype(path, size, index=index)
        except Exception:
            continue
    return ImageFont.load_default()


def trimmed(name, pad=14):
    """The panel cropped to the figure on its white background, with a little room."""
    im = Image.open(SHEET / f"{name}.png").convert("RGB")
    a = np.asarray(im).astype(np.int16)
    mask = (np.abs(a - 255).sum(-1) > 24)
    ys, xs = np.where(mask)
    box = (max(xs.min() - pad, 0), max(ys.min() - pad, 0), min(xs.max() + pad, im.width), min(ys.max() + pad, im.height))
    out = np.asarray(im.crop(box)).copy()
    out[(out > 244).all(-1)] = 255
    return Image.fromarray(out)


def fit(im, w, h):
    s = min(w / im.width, h / im.height)
    return im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)


def card(d, x, y, w, h):
    d.rounded_rectangle([x, y, x + w, y + h], radius=34, fill=(255, 255, 255), outline=LINE, width=3)


def put(canvas, im, x, y, w, h, pad=26, bottom=False):
    """Fit `im` inside the card at (x, y, w, h), centred (or standing on the card's floor when bottom is set)."""
    im = fit(im, w - 2 * pad, h - 2 * pad)
    canvas.paste(im, (x + (w - im.width) // 2, y + (h - pad - im.height if bottom else (h - im.height) // 2)))


def heading(d, x, y, text, sub=None):
    d.text((x, y), text, fill=INK, font=font(64, True))
    if sub:
        d.text((x, y + 82), sub, fill=INK2, font=font(34))
    d.line([(x, y + 140), (x + 2840, y + 140)], fill=LINE, width=3)
    return y + 180


def main():
    W, M = 3000, 80
    canvas = Image.new("RGB", (W, 7000), PAPER)
    d = ImageDraw.Draw(canvas)
    y = M
    d.text((M, y), "CAP", fill=INK, font=font(190, True))
    d.text((M + 520, y + 60), "Character sheet", fill=INK, font=font(84, True))
    d.text((M + 520, y + 165), "The capybara mascot of Cramless. Every animation is made from this. Version 1, October 24, 2026.", fill=INK2, font=font(36))
    y += 290

    y = heading(d, M, y, "Turnaround", "The same proportions in every view: a big round head, a chunky body and short legs.")
    cell = (W - 2 * M) // 4
    height = 760
    for i, (name, label) in enumerate(TURN):
        x = M + i * cell + 10
        card(d, x, y, cell - 20, height)
        put(canvas, trimmed(name), x, y, cell - 20, height, bottom=True)
        d.text((x + 24, y + height + 18), label, fill=INK2, font=font(34))
    y += height + 110

    y = heading(d, M, y, "Faces", "His default is the first one. Every face keeps the same eyes, muzzle, ears, mortarboard and headphones.")
    cell = (W - 2 * M) // 5
    for i, (name, label) in enumerate(FACES):
        col, row = i % 5, i // 5
        x, top = M + col * cell + 10, y + row * 590
        card(d, x, top, cell - 20, 500)
        put(canvas, trimmed(name), x, top, cell - 20, 500, pad=20)
        d.text((x + 24, top + 512), label, fill=INK2, font=font(32))
    y += 2 * 590 + 40

    y = heading(d, M, y, "Details", "The parts that animation tends to get wrong.")
    cell = (W - 2 * M) // 5
    for i, (name, label) in enumerate(DETAILS):
        x = M + i * cell + 10
        card(d, x, y, cell - 20, 500)
        put(canvas, trimmed(name, pad=0), x, y, cell - 20, 500, pad=20)
        d.text((x + 24, y + 512), label, fill=INK2, font=font(32))
    y += 620

    y = heading(d, M, y, "Palette", "Sampled from the art itself.")
    cell = (W - 2 * M) // 5
    for i, (label, hex_) in enumerate(PALETTE):
        col, row = i % 5, i // 5
        x, top = M + col * cell + 20, y + row * 340
        rgb = tuple(int(hex_[k:k + 2], 16) for k in (1, 3, 5))
        d.rounded_rectangle([x, top, x + 200, top + 200], radius=36, fill=rgb, outline=LINE, width=3)
        d.text((x + 230, top + 40), label, fill=INK, font=font(34, True))
        d.text((x + 230, top + 90), hex_, fill=INK2, font=font(34))
    y += 2 * 340 + 40

    y = heading(d, M, y, "Rules", "Proposed from his voice in docs/design.md and from what the sheet shows. Change any that you disagree with.")
    colw = (W - 2 * M) // 2
    ends = []
    for col, (title, rules) in enumerate((("Always", ALWAYS), ("Never", NEVER))):
        x, top = M + col * colw + 20, y
        d.text((x, top), title, fill=INK, font=font(48, True))
        top += 80
        for rule in rules:
            words, line, lines = rule.split(), "", []
            for w_ in words:
                trial = (line + " " + w_).strip()
                if d.textlength(trial, font=font(34)) > colw - 120:
                    lines.append(line); line = w_
                else:
                    line = trial
            lines.append(line)
            d.ellipse([x, top + 14, x + 14, top + 28], fill=(255, 122, 26))
            for k, ln in enumerate(lines):
                d.text((x + 36, top + k * 46), ln, fill=INK2, font=font(34))
            top += 46 * len(lines) + 24
        ends.append(top)
    canvas = canvas.crop((0, 0, W, max(ends) + 80))
    canvas.save(OUT, optimize=True)
    print(OUT, canvas.size, OUT.stat().st_size // 1024, "KB")


if __name__ == "__main__":
    main()
