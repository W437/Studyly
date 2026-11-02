#!/usr/bin/env python3
"""The review page for gizmo_colours.py: the finished Gizmo set on ten grounds, the first three frames of each side by side, then all eight.

    python3 -P scripts/store_art/build_gizmo_colours_page.py [colours-dir] [out-dir]     (default build/listing/gizmo-colours -> build/listing/gizmo-colours-page)
Then `running publish <out-dir>` and `tshare add <out-dir>/index.html ...`. The page holds only Capling's own art.
"""
import html
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gizmo_colours as gc  # noqa: E402

REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "build", "listing", "gizmo-colours")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, "build", "listing", "gizmo-colours-page")
PICK = {
    "sunrise": "My pick: the sunny look you liked, and saturated, so it still reads when the store shows it small.",
    "rose": "My pick: none of the 15 study apps uses it, and it stays loud at thumbnail size.",
    "night": "My pick: the app's own night, the quietest and the most grown-up of the ten.",
}


def small(src, name, width=360):
    im = Image.open(src).convert("RGB")
    im = im.resize((width, round(width * im.height / im.width)), Image.LANCZOS)
    im.save(os.path.join(OUT, name), quality=82)
    return name


def main():
    os.makedirs(OUT, exist_ok=True)
    overview, sections = [], []
    for n, key in enumerate(gc.ORDER, 1):
        files = [small(os.path.join(SRC, key, f"{j:02d}.png"), f"{key}-{j}.jpg") for j in range(1, 9)]
        name = html.escape(gc.NAMES[key])
        tri = "".join(f'<img src="{f}" alt="{name}, frame {j}" loading="lazy">' for j, f in enumerate(files[:3], 1))
        overview.append(f'<a class="opt" href="#{key}"><b>{n}. {name}</b><span class="tri">{tri}</span></a>')
        pick = f'<p class="pick">{html.escape(PICK[key])}</p>' if key in PICK else ""
        row = "".join(f'<img src="{f}" alt="{name}, frame {j}" loading="lazy">' for j, f in enumerate(files, 1))
        sections.append(f'<section id="{key}"><h2>{n}. {name}</h2><p class="mut">{html.escape(gc.NOTES[key])}</p>{pick}<div class="row">{row}</div></section>')
    page = f"""<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Capling screenshots: Gizmo colours</title>
<style>
:root{{--bg:#f4f4f6;--fg:#14213d;--mut:#56627a;--acc:#d96208;--card:#fff}}
@media (prefers-color-scheme:dark){{:root{{--bg:#0b1220;--fg:#eef3fa;--mut:#a9b4c8;--acc:#ff9a4d;--card:#151e30}}}}
body{{font:16px/1.45 -apple-system,system-ui,sans-serif;margin:0;padding:16px;background:var(--bg);color:var(--fg)}}
h1{{font-size:22px;margin:4px 0 6px}}h2{{font-size:19px;margin:30px 0 2px}}p{{margin:4px 0}}.mut{{color:var(--mut)}}
.pick{{font-weight:700;color:var(--acc)}}
.ov{{display:grid;grid-template-columns:repeat(auto-fill,minmax(310px,1fr));gap:12px;margin:14px 0}}
.opt{{display:block;background:var(--card);border-radius:12px;padding:10px;text-decoration:none;color:inherit;box-shadow:0 1px 6px rgba(0,0,0,.12)}}
.tri{{display:flex;gap:6px;margin-top:6px}}.tri img{{width:calc((100% - 12px)/3);height:auto;border-radius:6px;display:block}}
.row{{display:flex;gap:10px;overflow-x:auto;padding:6px 0 12px;scroll-snap-type:x proximity}}
.row img{{height:min(58vh,580px);width:auto;border-radius:12px;flex:none;scroll-snap-align:start;box-shadow:0 2px 10px rgba(0,0,0,.18)}}
</style>
<h1>Capling screenshots: the Gizmo set on ten grounds</h1>
<p class="mut">Purple is Gizmo's own, so here are ten others: Capling's own colours and a few of the app's skies. The cards, Cap and the words are the same on every ground; only the ground, the lettering colours and the shadows change. English only, 1290 by 2796, nothing uploaded anywhere. The first three frames are what the store shows in search: the boxes below are that, at about that size. Tap one for all eight.</p>
<div class="ov">{''.join(overview)}</div>
{''.join(sections)}
"""
    open(os.path.join(OUT, "index.html"), "w").write(page)
    print(os.path.join(OUT, "index.html"))


if __name__ == "__main__":
    main()
