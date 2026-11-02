#!/usr/bin/env python3
"""The review page for gizmo_final.py: the two frames that changed, and the whole set.

    python3 -P scripts/store_art/build_gizmo_page.py [gizmo-dir] [out-dir]     (default build/listing/gizmo -> build/listing/gizmo-page)
Then `running publish <out-dir>` and `tshare add <out-dir>/index.html ...`. The page holds only Capling's own art.
"""
import html
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, "build", "listing", "gizmo")
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, "build", "listing", "gizmo-page")
OLD = os.path.join(REPO, "build", "listing", "mimic", "gizmo")

def small(src, name, width):
    im = Image.open(src).convert("RGB")
    im = im.resize((width, round(width * im.height / im.width)), Image.LANCZOS)
    im.save(os.path.join(OUT, name), quality=84)
    return name


def fig(name, label, note=""):
    n = f"<p>{html.escape(note)}</p>" if note else ""
    return f'<figure><img src="{name}" alt="{html.escape(label)}" loading="lazy"><figcaption><b>{html.escape(label)}</b>{n}</figcaption></figure>'


def main():
    os.makedirs(OUT, exist_ok=True)
    first = fig(small(os.path.join(SRC, "01.png"), "first.jpg", 520), "Frame 1", "Your plan and the path to the exam, with a big study button (the app's own button, drawn larger).")
    second = fig(small(os.path.join(SRC, "02.png"), "second.jpg", 520), "Frame 2", "A full-marks answer, cut above the verdict sheet.")
    whole = "".join(f'<img src="{small(os.path.join(SRC, f"{j:02d}.png"), f"set-{j}.jpg", 420)}" alt="Frame {j}" loading="lazy">' for j in range(1, 9))
    page = f"""<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Capling screenshots: Gizmo set</title>
<style>
:root{{--bg:#f4f4f6;--fg:#14213d;--mut:#56627a;--acc:#d96208}}
@media (prefers-color-scheme:dark){{:root{{--bg:#0b1220;--fg:#eef3fa;--mut:#a9b4c8;--acc:#ff9a4d}}}}
body{{font:16px/1.45 -apple-system,system-ui,sans-serif;margin:0;padding:16px;background:var(--bg);color:var(--fg)}}
h1{{font-size:22px;margin:4px 0 6px}}h2{{font-size:19px;margin:30px 0 4px}}p{{margin:4px 0}}.mut{{color:var(--mut)}}
.row{{display:flex;gap:12px;overflow-x:auto;padding:6px 0 12px;scroll-snap-type:x proximity}}
figure{{margin:0;flex:none;scroll-snap-align:start;max-width:min(62vw,330px)}}
figure img{{display:block;height:min(58vh,560px);width:auto;border-radius:12px;box-shadow:0 2px 10px rgba(0,0,0,.18)}}
figcaption{{font-size:14px;margin-top:6px}}figcaption p{{color:var(--mut);margin:2px 0 0}}
.set{{display:flex;gap:10px;overflow-x:auto;padding:4px 0 10px;scroll-snap-type:x proximity}}
.set img{{height:min(60vh,620px);width:auto;border-radius:12px;flex:none;scroll-snap-align:start;box-shadow:0 2px 10px rgba(0,0,0,.18)}}
</style>
<h1>Capling screenshots: the Gizmo set</h1>
<p class="mut">The cards are cut from the app's own screens; Cap, the lettering, the ground and the button's size are drawn in code. English only, 1290 by 2796, nothing uploaded anywhere.</p>
<h2>The two frames that changed</h2>
<div class="row">{first}{second}</div>
<h2>The whole set</h2>
<div class="set">{whole}</div>
"""
    open(os.path.join(OUT, "index.html"), "w").write(page)
    print(os.path.join(OUT, "index.html"))


if __name__ == "__main__":
    main()
