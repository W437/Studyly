#!/usr/bin/env python3
"""Review page for the store-art directions (directions.py): ~/Sites/capling-store-directions/ (static, phone-width friendly).

    python3 -P build_directions_page.py [--src DIR] [--site DIR] [--lead poster2]

Leads with the direction the owner picked (the sunny poster with bigger badges, 2026-10-30), then folds the first version of it, the
other words and the three other looks underneath. Reads <src>/<direction>/<copy>-<card|header>.png and layout.json (directions.py), runs
the OCR check on every picture (the words the brief asked for, spelled exactly) and writes index.html and img/*.jpg.
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
import directions as dr  # noqa: E402
import looks  # noqa: E402

LABEL = {"card": "Search card, 3:2, 3840 x 2560", "header": "Header, 21:9, 3840 x 1646"}
WAS = {"card": 207, "header": 174}          # the headline sizes of the first rebuild of look 4

OTHERS = [
    ("night", "Night lake", "Painted night scenery, the readiness ring, Cap at his telescope."),
    ("screens", "The app itself", "The app's own night sky with crops of the real screens."),
    ("notebook", "Notebook", "Ruled paper, a highlighter, Cap as a sticker taking notes."),
]


def jpg(src, dst, width=1700):
    im = Image.open(src).convert("RGB")
    if im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    im.save(dst, quality=87, optimize=True, progressive=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=dr.OUT)
    ap.add_argument("--site", default=os.path.expanduser("~/Sites/capling-store-directions"))
    ap.add_argument("--lead", default="poster2")
    a = ap.parse_args()
    img_dir = os.path.join(a.site, "img")
    os.makedirs(img_dir, exist_ok=True)
    layout = json.load(open(os.path.join(a.src, "layout.json")))
    check.build_tool()
    seen = {}

    def fig(did, cid, fmt, lazy=False):
        png = os.path.join(a.src, did, f"{cid}-{fmt}.png")
        lay = layout[f"{did}/{cid}/{fmt}"]
        res = check.judge(png, fmt, dr.COPY[cid]["lines"])
        name = f"{did}-{cid}-{fmt}.jpg"
        jpg(png, os.path.join(img_dir, name))
        seen[(did, cid, fmt)] = (res["text_ok"], lay["headline_inside"])
        tags = [
            '<span class="tag ok">words exact (read back by OCR)</span>' if res["text_ok"] else
            f'<span class="tag bad">words off: {html.escape(", ".join(res["missing"]))}</span>',
            '<span class="tag ok">words inside Apple\'s safe area</span>' if lay["headline_inside"] else
            '<span class="tag bad">words outside the safe area</span>',
            f'<span class="tag">words {lay["headline_px"]} px, was {WAS[fmt]}</span>',
            f'<span class="tag">{os.path.getsize(png) / 1e6:.1f} MB png, no alpha</span>',
        ]
        return (f'<figure class="{"crd" if fmt == "card" else "hdr"}"><div class="frame"><img src="img/{name}" alt="{html.escape(LABEL[fmt])}"'
                f'{" loading=lazy" if lazy else ""}>{bp.safe_box(fmt)}</div><figcaption>{LABEL[fmt]}. {"".join(tags)}</figcaption></figure>')

    def pair(did, cid, lazy=False):
        return f'<div class="pair">{fig(did, cid, "card", lazy)}{fig(did, cid, "header", lazy)}</div>'

    lead = a.lead
    preview_src = os.path.join(os.path.dirname(a.src), "..", "final", "apple-preview.jpg")
    preview_src = os.path.abspath(os.path.join(looks.OUT_DIR, "..", "final", "apple-preview.jpg"))
    has_preview = os.path.exists(preview_src)
    if has_preview:
        Image.open(preview_src).convert("RGB").save(os.path.join(img_dir, "apple-preview.jpg"), quality=88)
    other_words = "".join(
        f'<h3>{html.escape(dr.COPY[cid]["name"])}</h3><p class="muted">{note}</p>{pair(lead, cid, True)}'
        for cid, note in (("notes", "Says what you do with it."), ("know", "Says what it measures.")))
    others = "".join(f'<h3>{title}</h3><p class="muted">{html.escape(idea)}</p>{pair(did, "day", True)}' for did, title, idea in OTHERS)

    extra = """
h3 { margin:18px 0 2px; font-size:1.05rem; }
details { margin:18px 0; }
summary { cursor:pointer; font-weight:600; padding:8px 0; }
"""
    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Capling store art, sunny poster</title><style>{bp.CSS}{extra}</style></head>
<body><main>
<h1>Capling store art: the sunny poster, bigger badges</h1>
<p class="lede">You picked the sunny poster. The ring badge is now 900 px on the card (was 640) and 780 px on the header (was 520), and both white cards are 40% bigger, with their words. The headline and the pill are as before, and Cap is a little bigger so he keeps up.</p>
<p><span class="tag">flat, drawn in code: no model pixels, no spend</span><span class="tag">the ring, the cards and Cap are the app's own</span><span class="tag ok">uploaded to Capling 1.0 in App Store Connect (Loopware), not submitted</span></p>
<div class="bar"><label><input type="checkbox" id="t-safe"> Show Apple's art safe area</label><label><input type="checkbox" id="t-size"> Show at phone size</label></div>
<section><h2>Sunny poster, bigger badges</h2>{pair(lead, "day")}
<p class="muted">The ring is allowed to reach into the empty top corner of Apple's box (it never touches the words); Cap and the cards sit outside it. Only the words are guaranteed on every device.</p></section>
{('<section><h2>In App Store Connect now</h2><p>Uploaded on 2026-10-30 to Capling 1.0 (Loopware, English U.S.) and placed as its header and search-results card; Apple reads them back as active at 3840 x 1646 and 3840 x 2560. Not submitted for review. Below, Apple&#39;s own Preview tool: iPhone and iPad, light and dark, the product page and the search results. The words are never cropped; the ring and Cap are trimmed at the header&#39;s edges, and the Search card shows whole.</p><figure><div class="frame"><img src="img/apple-preview.jpg" alt="Apple&#39;s Preview tool, five views"></div><figcaption>Apple&#39;s Device Preview: iPhone product page (light, dark), iPad product page (dark), iPhone search, iPad search (dark)</figcaption></figure></section>') if has_preview else ''}
<details><summary>Before: the first version</summary>{pair("poster", "day", True)}</details>
<details><summary>Other words on this look</summary><p class="muted">Same picture, different line. "Ready on exam day." is the app's own welcome line.</p>{other_words}</details>
<details><summary>The other three looks</summary>{others}</details>
<section><h2>Your call</h2><ul>
<li>Happy with it as it is? It is placed, so a change means a re-upload (one command).</li>
<li>Other languages need their own header and card (the words translated, then a native read). Say which languages, and I build them the same way.</li>
<li>Still empty on the Capling record: the listing text, screenshots (iPhone Duo from April 2027), privacy answers, a build and the review details.</li>
</ul>
<p class="muted">Masters: <code>Cramless/build/store-art/gpt/directions/poster2/</code> (png). Code: <code>Cramless/scripts/store_art/gpt/directions.py</code>. Upload: <code>Cramless/scripts/asc/capling_asc.mjs</code>. Nothing is committed or submitted for review.</p></section>
</main><script>{bp.JS}</script></body></html>"""
    with open(os.path.join(a.site, "index.html"), "w") as f:
        f.write(page)
    bad = [(k, v) for k, v in seen.items() if not all(v)]
    print(a.site, "ok;", len(seen), "pictures checked;", "problems:" if bad else "all words exact and inside the box", bad or "")
    return 0


if __name__ == "__main__":
    sys.exit(main())
