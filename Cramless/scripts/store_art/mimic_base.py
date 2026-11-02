#!/usr/bin/env python3
"""Shared parts of the mimic styles (shot_mimic.py): the story, the style registry and the text helpers."""
import math
import os
import random
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mimickit as mk  # noqa: E402
import shotkit as sk  # noqa: E402
from shotkit import W, H, NIGHT, SUN, MINT, ROSE, SKY, TANGERINE, WHITE, paste, put, cap, phone  # noqa: E402
from shot_looks import P, ring_card, chip  # noqa: E402

# The same eight screens in every style (the story: ready, words, stand, pages, ask, lecture, sky, streak).
STORY = [
    dict(key="ready", shot="today-eve", cap="plan"),
    dict(key="words", shot="graded", cap="listen"),
    dict(key="stand", shot="exam", cap="point"),
    dict(key="pages", shot="capture-checking", cap="scan"),
    dict(key="ask", shot="ask-cards", cap="ask"),
    dict(key="lecture", shot="lecture-notes", cap="mic"),
    dict(key="sky", shot="sky-fill", cap="stargaze"),
    dict(key="streak", shot="streak", cap="nice"),
]

STYLES = {}


def style(key, name, ref, took, changed):
    """Register a style: key, its name, the competitor folder in the research, what was taken, what was changed."""
    def deco(fn):
        STYLES[key] = dict(fn=fn, name=name, ref=ref, took=took, changed=changed)
        return fn
    return deco


def canvas(top=None, bottom=None, angle=90):
    if top is None:
        return Image.new("RGBA", (W, H), (255, 255, 255, 255))
    return mk.lin((W, H), [(0, top), (1, bottom or top)], angle)


def lines_block(c, lines, top, size, fill, make=None, centre=W / 2, left=None, pitch=1.16, track=0.0, fills=None, weight=700):
    """Stacked headline lines; top is the cap-line of the first. Returns the baseline of the last."""
    make = make or (lambda s: mk.sf(s, weight))
    f = make(size)
    d = ImageDraw.Draw(c)
    y = top + size * 0.76
    for n, ln in enumerate(lines):
        col = fills[n] if fills else fill
        mk.draw(d, left if left is not None else centre, y, ln, f, col, "ls" if left is not None else "ms", track)
        y += size * pitch
    return y - size * pitch




def wrap(text, f, maxw):
    """Break a sentence into lines no wider than maxw."""
    lines, cur = [], ""
    for w in text.split():
        t = (cur + " " + w).strip()
        if mk.tw(t, f) <= maxw:
            cur = t
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def lines_rich(c, lines, top, size, reg, em, fill, fill_em=None, centre=W / 2, left=None, pitch=1.16, track=0.0):
    """Stacked lines with *emphasis* segments in a second font (reg(size) and em(size) make the fonts). Returns the last baseline."""
    f_reg, f_em = reg(size), em(size)
    y = top + size * 0.76
    for ln in lines:
        mk.rich(c, ln, y, f_reg, f_em, fill, fill_em, centre=None if left is not None else centre, left=left, track=track)
        y += size * pitch
    return y - size * pitch
