#!/usr/bin/env python3
"""The review page for shot_looks.py: every look as a row of its eight frames, to pick from on a phone.

    python3 -P scripts/store_art/build_looks_page.py [looks-dir] [out-dir]     (default build/listing/looks -> build/listing/looks-page)
Then `running publish <out-dir>` and `tshare add <out-dir>/index.html ...`.
"""
import html
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "build", "listing", "looks")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, "build", "listing", "looks-page")

LOOKS = [
    ("lift", "Lift", "The leaders' formula, as Scanbase does it: one big verb, a whole phone, and the card you'd tap lifted off the screen, bigger.",
     "Clean and instantly readable. The safest."),
    ("sunny", "Sunny", "The approved yellow poster look: words in a navy pill, the phone on green hills, Cap looking over its shoulder, cards pulled out of the screen.",
     "Matches the header and search art you already approved."),
    ("alive", "Alive", "No phone. The app's own cards, cut out of its screens and set big on a blue sky, the way the Keepable set shows its swipe badges.",
     "Shows the most of the app in a glance."),
    ("night", "Night", "One sky across all eight frames: the memory sky's stars and constellations run from frame to frame, so the first three read as one picture in search.",
     "The most atmospheric. Reads as one story."),
    ("skies", "Six skies", "Each frame stands in one of the app's six skies (night, dusk, glacier, aurora, bloom, ember). Cap on the hill with one of his own lines.",
     "Shows off the sky themes and Cap's voice."),
    ("scrap", "Study desk", "Graph paper, the screen printed and taped down, the app's cards stuck on like notes, a highlighter stroke, handwriting and an arrow.",
     "The warmest and most human."),
    ("cap", "Cap-led", "No phone. Cap, big, with one of his own lines in a bubble, one card of the app, and a flat brand colour per frame.",
     "The loudest thumbnail. Least about the app."),
]


def main():
    os.makedirs(OUT, exist_ok=True)
    rows = []
    for key, name, desc, verdict in LOOKS:
        d = os.path.join(SRC, key)
        if not os.path.isdir(d):
            continue
        imgs = []
        for n in range(1, 9):
            p = os.path.join(d, f"{n:02d}.png")
            if not os.path.exists(p):
                continue
            im = Image.open(p).convert("RGB")
            im = im.resize((520, round(520 * im.height / im.width)), Image.LANCZOS)
            fn = f"{key}-{n}.jpg"
            im.save(os.path.join(OUT, fn), quality=86)
            imgs.append(f'<img src="{fn}" alt="{html.escape(name)} {n}" loading="lazy">')
        rows.append(f'<section><h2>{html.escape(name)}</h2><p class="d">{html.escape(desc)}</p><p class="v">{html.escape(verdict)}</p>'
                    f'<div class="row">{"".join(imgs)}</div></section>')
    page = f"""<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Capling screenshots: seven looks</title>
<style>
:root{{--bg:#f4f4f6;--fg:#14213d;--mut:#56627a;--card:#fff}}
@media (prefers-color-scheme:dark){{:root{{--bg:#0b1220;--fg:#eef3fa;--mut:#a9b4c8;--card:#151e30}}}}
body{{font:16px/1.45 -apple-system,system-ui,sans-serif;margin:0;padding:16px;background:var(--bg);color:var(--fg)}}
h1{{font-size:22px;margin:4px 0 6px}}h2{{font-size:19px;margin:30px 0 2px}}p{{margin:3px 0}}.d{{color:var(--mut)}}.v{{font-weight:600}}
.row{{display:flex;gap:10px;overflow-x:auto;padding:10px 0 8px;scroll-snap-type:x proximity}}
img{{height:min(62vh,640px);width:auto;border-radius:12px;flex:none;scroll-snap-align:start;box-shadow:0 2px 10px rgba(0,0,0,.18)}}
</style>
<h1>Capling App Store screenshots: seven looks</h1>
<p class="d">The same eight frames in every look, drawn from the app itself: its real screens, cards cut out of them, Cap's own art and lines, the sky colours. 1290 by 2796, English. Swipe each row sideways; the first three are what search shows. Tell me a look (or a mix) and I'll finish it.</p>
{''.join(rows)}
"""
    open(os.path.join(OUT, "index.html"), "w").write(page)
    print(os.path.join(OUT, "index.html"))


if __name__ == "__main__":
    main()
