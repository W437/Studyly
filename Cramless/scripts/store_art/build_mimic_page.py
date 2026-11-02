#!/usr/bin/env python3
"""The review page for shot_mimic.py: each of the 15 study apps' listing styles, filled with Capling, next to their first three frames.

    python3 -P scripts/store_art/build_mimic_page.py [mimic-dir] [out-dir]     (default build/listing/mimic -> build/listing/mimic-page)
Then `running publish <out-dir>` and `tshare add <out-dir>/index.html ...`. The page holds other companies' store images: keep it private.
"""
import html
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mimic_base  # noqa: E402
import mimic_a  # noqa: E402,F401
import mimic_b  # noqa: E402,F401

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "build", "listing", "mimic")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, "build", "listing", "mimic-page")
RESEARCH = os.path.expanduser("~/Sites/capling-store-research/img")
ORDER = ["duolingo", "kahoot", "gizmo", "quizlet", "knowt", "gauth", "photomath", "brilliant", "brainscape", "solvely", "studyfetch", "turbo",
         "coconote", "knowunity", "anki"]
NOTE = {
    "duolingo": "My pick: Capling's own buttons already have that raised lip, so the listing feels like the app before it is opened.",
    "kahoot": "My pick: the clearest at thumbnail size, and the same phone in the same place on every frame.",
    "gizmo": "My pick: Cap is the star, with one giant word per frame.",
}


def main():
    os.makedirs(OUT, exist_ok=True)
    rows = []
    for n, key in enumerate(ORDER, 1):
        st = mimic_base.STYLES[key]
        theirs = []
        fs = sorted(f for f in os.listdir(os.path.join(RESEARCH, st["ref"])) if f[:2].isdigit())[:3]
        for j, f in enumerate(fs):
            im = Image.open(os.path.join(RESEARCH, st["ref"], f)).convert("RGB")
            im = im.resize((220, round(220 * im.height / im.width)), Image.LANCZOS)
            fn = f"{key}-t{j + 1}.jpg"
            im.save(os.path.join(OUT, fn), quality=80)
            theirs.append(f'<img class="t" src="{fn}" alt="{html.escape(st["name"])} frame {j + 1}" loading="lazy">')
        ours = []
        for j in range(1, 9):
            p = os.path.join(SRC, key, f"{j:02d}.png")
            im = Image.open(p).convert("RGB")
            im = im.resize((400, round(400 * im.height / im.width)), Image.LANCZOS)
            fn = f"{key}-{j}.jpg"
            im.save(os.path.join(OUT, fn), quality=82)
            ours.append(f'<img src="{fn}" alt="Capling in the {html.escape(st["name"])} style, frame {j}" loading="lazy">')
        note = f'<p class="pick">{html.escape(NOTE[key])}</p>' if key in NOTE else ""
        rows.append(f'<section id="{key}"><h2>{n}. {html.escape(st["name"])}</h2>{note}'
                    f'<p><b>Taken:</b> {html.escape(st["took"])}</p><p><b>Changed:</b> {html.escape(st["changed"])}</p>'
                    f'<div class="lab">Theirs, first three frames</div><div class="th">{"".join(theirs)}</div>'
                    f'<div class="lab">Capling, all eight</div><div class="row">{"".join(ours)}</div></section>')
    toc = " · ".join(f'<a href="#{k}">{html.escape(mimic_base.STYLES[k]["name"])}</a>' for k in ORDER)
    page = f"""<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Capling screenshots: 15 listing styles</title>
<style>
:root{{--bg:#f4f4f6;--fg:#14213d;--mut:#56627a;--card:#fff;--acc:#d96208}}
@media (prefers-color-scheme:dark){{:root{{--bg:#0b1220;--fg:#eef3fa;--mut:#a9b4c8;--card:#151e30;--acc:#ff9a4d}}}}
body{{font:16px/1.45 -apple-system,system-ui,sans-serif;margin:0;padding:16px;background:var(--bg);color:var(--fg)}}
h1{{font-size:22px;margin:4px 0 6px}}h2{{font-size:20px;margin:34px 0 4px}}p{{margin:4px 0}}.mut{{color:var(--mut)}}
.pick{{font-weight:700;color:var(--acc)}}a{{color:var(--acc)}}.toc{{line-height:2}}
.lab{{font-size:12px;text-transform:uppercase;letter-spacing:.06em;color:var(--mut);margin:12px 0 4px}}
.th{{display:flex;gap:8px;overflow-x:auto}}.th img{{height:200px;width:auto;border-radius:8px;flex:none;opacity:.92}}
.row{{display:flex;gap:10px;overflow-x:auto;padding:4px 0 10px;scroll-snap-type:x proximity}}
.row img{{height:min(60vh,620px);width:auto;border-radius:12px;flex:none;scroll-snap-align:start;box-shadow:0 2px 10px rgba(0,0,0,.18)}}
</style>
<h1>Capling App Store screenshots, in the style of 15 study apps</h1>
<p class="mut">Each row takes one app's listing style (layout, colour, type, decoration) and fills it with Capling's own things: its real screens, cards cut out of them, Cap, the app's colours and its own words. 1290 by 2796, English, drawn in code from the app: nothing is painted by a model and nothing of theirs is used. Their numbers, awards, laurels and reviews are left out: every claim here is one the app can back. Swipe each row sideways; the first three frames are what search shows.</p>
<p class="mut">Private: the small "theirs" pictures are other companies' store images, for comparing. Do not share this page outside.</p>
<p class="toc">{toc}</p>
{''.join(rows)}
"""
    open(os.path.join(OUT, "index.html"), "w").write(page)
    print(os.path.join(OUT, "index.html"))


if __name__ == "__main__":
    main()
