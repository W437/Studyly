#!/usr/bin/env python3
"""Review page for the rebuilt look 4 (store_ring.py): ~/Sites/capling-store-ring/ (static, phone-width friendly).

    python3 -P build_ring_page.py [--final DIR] [--site DIR]

Reads <final>/ring-<card|header>.png, the -box cut-outs and layout.json (store_ring.py), runs the OCR check on the two pictures (the
words the brief asked for, spelled exactly, and where they sit) and shows the concept each came from next to them. Writes index.html
and img/*.jpg.
"""
import argparse
import html
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_page as bp  # noqa: E402
import check  # noqa: E402
import looks  # noqa: E402

LOOK = next(l for l in looks.LOOKS if l["id"] == "ring")
LABEL = {"card": "Search card, 3:2, 3840 x 2560", "header": "Header, 21:9, 3840 x 1646"}


def jpg(src, dst, width=None):
    im = Image.open(src).convert("RGB")
    if width and im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    im.save(dst, quality=88, optimize=True, progressive=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--final", default=os.path.join(looks.OUT_DIR, "final"))
    ap.add_argument("--site", default=os.path.expanduser("~/Sites/capling-store-ring"))
    ap.add_argument("--note", default="", help="a line shown at the top of the page (for a draft)")
    a = ap.parse_args()
    img_dir = os.path.join(a.site, "img")
    os.makedirs(img_dir, exist_ok=True)
    layout = json.load(open(os.path.join(a.final, "layout.json")))
    check.build_tool()
    ledger = os.path.join(looks.OUT_DIR, "ledger.jsonl")
    plate_cost, plate_n = 0.0, 0
    if os.path.exists(ledger):
        for line in open(ledger):
            r = json.loads(line)
            if r.get("ok") and str(r.get("id", "")).startswith("plate-"):
                plate_cost += r.get("est_usd", 0)
                plate_n += 1

    figs, cuts = [], []
    for fmt in ("card", "header"):
        png = os.path.join(a.final, f"ring-{fmt}.png")
        lay = layout[fmt]
        res = check.judge(png, fmt, LOOK["lines"])
        jpg(png, os.path.join(img_dir, f"ring-{fmt}.jpg"))
        jpg(os.path.join(a.final, f"ring-{fmt}-box.png"), os.path.join(img_dir, f"ring-{fmt}-box.jpg"))
        jpg(os.path.join(looks.OUT_DIR, "out", f"ring-{fmt}.png"), os.path.join(img_dir, f"concept-{fmt}.jpg"))
        flags = [
            '<span class="tag ok">words exact (read back by OCR)</span>' if res["text_ok"] else
            f'<span class="tag bad">words off: {html.escape(", ".join(res["missing"]))}</span>',
            '<span class="tag ok">headline and ring inside Apple\'s safe area</span>' if lay["headline_inside"] and lay["ring_inside"] else
            '<span class="tag bad">headline or ring outside the safe area</span>',
            '<span class="tag warn">Cap and the two cards are outside it: atmosphere, may be cropped</span>',
            f'<span class="tag">{os.path.getsize(png) / 1e6:.1f} MB png, no alpha (Apple takes up to 500 MB)</span>',
        ]
        figs.append(
            f'<figure class="{"crd" if fmt == "card" else "hdr"}"><div class="frame"><img src="img/ring-{fmt}.jpg" alt="{LABEL[fmt]}">'
            f'{bp.safe_box(fmt)}</div><figcaption>{LABEL[fmt]}. {"".join(flags)}</figcaption></figure>')
        cuts.append(
            f'<figure><div class="frame"><img src="img/ring-{fmt}-box.jpg" alt="the safe area of the {fmt}"></div>'
            f'<figcaption>{fmt.capitalize()} cut to Apple\'s safe area: what every device shows</figcaption></figure>')

    concepts = "".join(
        f'<figure><div class="frame"><img src="img/concept-{fmt}.jpg" alt="concept {fmt}"></div><figcaption>The concept ({fmt}), 1920 px, all drawn by the model</figcaption></figure>'
        for fmt in ("card", "header"))

    extra = """
.cuts { display:grid; grid-template-columns:1fr; gap:14px; margin-top:10px; }
@media (min-width:760px) { .cuts { grid-template-columns:1fr 1fr; align-items:start; } }
"""
    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Capling store art, look 4 rebuilt</title><style>{bp.CSS}{extra}</style></head>
<body><main>
<h1>Look 4, "Readiness ring", rebuilt at full size</h1>
<p class="lede">{"The model painted only the night scenery. " if plate_n else ""}The ring, the words, the glass cards and Cap are set by code, so every word is exact and the headline and the ring sit inside Apple's safe area (the dashed box).</p>
{f'<div class="take">{html.escape(a.note)}</div>' if a.note else ""}
<p>{f'<span class="tag">scenery: fal · GPT Image 2.5 · {plate_n} plates · about ${plate_cost:.2f} (my estimate)</span>' if plate_n else '<span class="tag warn">scenery: a stand-in sky from the code engine, the GPT scenery is not rendered yet</span>'}<span class="tag">ring, words, cards, Cap: code</span><span class="tag">not uploaded anywhere</span></p>
<div class="bar"><label><input type="checkbox" id="t-safe"> Show Apple's art safe area</label><label><input type="checkbox" id="t-size"> Show at phone size</label></div>
<section><h2>Search card</h2><div class="pair">{figs[0]}</div></section>
<section><h2>Header</h2><div class="pair">{figs[1]}</div></section>
<section><h2>What survives the tightest crop</h2><p class="muted">Apple only promises the box. Here it is on its own: the headline and the ring still tell the story.</p><div class="cuts">{"".join(cuts)}</div></section>
<section><h2>What is real in it</h2><ul>
<li>The ring is the app's own readiness ring: an arc from 12 o'clock with round ends over a track, the readiness colour at 78%, rounded numerals.</li>
<li>The glass cards use the result screen's own words: "Chem 110 Quiz", "42% to 78% ready, 2 days left", "On track for 80%".</li>
<li>Cap is the app's own "stargaze" art, facing the ring. Nothing here is a feature the app does not ship.</li>
</ul></section>
<section><h2>The concept it came from</h2><div class="cuts">{concepts}</div></section>
<section><h2>Your call</h2><ul>
<li>The words "Know where you stand." are the concept's. Say if you want "Know you're ready." or "See how ready you are." instead; they are one line in the script.</li>
<li>Cap sits outside Apple's box, so a tight crop would drop him. Say if you want him inside, smaller.</li>
<li>Next, only when you ask: check the pictures in Apple's Preview tool (needs a team: Loopware or Bellavita), then upload. Each language needs its own set.</li>
</ul>
<p class="muted">Masters: <code>Cramless/build/store-art/gpt/final/</code> (png). Code: <code>Cramless/scripts/store_art/gpt/store_ring.py</code> and <code>run_plates.py</code>. Nothing is committed or uploaded. Earlier: <a href="../capling-store-gpt/">the eight concepts</a>.</p></section>
</main><script>{bp.JS}</script></body></html>"""
    with open(os.path.join(a.site, "index.html"), "w") as f:
        f.write(page)
    print(a.site, "ok")


if __name__ == "__main__":
    sys.exit(main())
