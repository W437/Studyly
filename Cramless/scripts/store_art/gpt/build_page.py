#!/usr/bin/env python3
"""Builds the review page for the GPT Image 2.5 concept set: ~/Sites/capling-store-gpt/ (static, phone-width friendly).

    python3 -P build_page.py [--src DIR] [--site DIR]

Reads  build/store-art/gpt/out/<look>-<card|header>.png, checks.json (check.py), prompts.json (run_fal.py), ledger.jsonl and an optional
notes.json ({look id: my one-line take}). Writes index.html and img/*.jpg (the pictures at full pixel size as q86 JPEGs).
"""
import argparse
import html
import json
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks  # noqa: E402

CSS = """
:root { --bg:#0b1220; --card:#151e30; --line:rgba(255,255,255,.09); --ink:#eef3fa; --ink2:#a9b4c8; --rose:#ff5a78; --mint:#22c38e; --sun:#ffcf3f; }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--ink); font:16px/1.5 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif; }
main { max-width:1040px; margin:0 auto; padding:20px 16px 72px; }
h1 { font-size:28px; line-height:1.15; margin:8px 0 6px; letter-spacing:-.01em; }
h2 { font-size:21px; margin:0; }
p { margin:8px 0; }
.lede { color:var(--ink2); font-size:17px; max-width:66ch; }
.muted, figcaption { color:var(--ink2); font-size:14px; }
.tag { display:inline-block; font-size:12px; padding:1px 8px; border-radius:99px; border:1px solid var(--line); color:var(--ink2); margin:0 6px 6px 0; }
.ok { color:var(--mint); border-color:rgba(34,195,142,.4); } .bad { color:var(--rose); border-color:rgba(255,90,120,.45); } .warn { color:var(--sun); border-color:rgba(255,207,63,.4); }
.bar { position:sticky; top:0; z-index:5; background:rgba(11,18,32,.92); backdrop-filter:blur(8px); padding:8px 0; display:flex; gap:18px; flex-wrap:wrap; border-bottom:1px solid var(--line); margin:12px 0 0; }
.bar label { display:inline-flex; gap:8px; align-items:center; color:var(--ink2); font-size:14px; cursor:pointer; }
.grid { display:grid; grid-template-columns:1fr 1fr; gap:10px; margin:16px 0; }
@media (min-width:760px) { .grid { grid-template-columns:repeat(4,1fr); } }
.grid a { display:block; border-radius:12px; overflow:hidden; border:1px solid var(--line); background:var(--card); color:var(--ink); text-decoration:none; }
.grid img { display:block; width:100%; height:auto; }
.grid span { display:block; padding:6px 10px 8px; font-size:13px; color:var(--ink2); } .grid b { color:var(--sun); margin-right:6px; }
section { margin:44px 0 0; padding-top:8px; border-top:1px solid var(--line); }
.num { display:inline-block; min-width:30px; text-align:center; background:var(--sun); color:#14213d; font-weight:800; border-radius:99px; padding:0 8px; margin-right:8px; }
.copy { font-weight:600; }
.pair { display:grid; grid-template-columns:1fr; gap:14px; margin-top:10px; }
@media (min-width:900px) { .pair.wide { grid-template-columns:1.25fr 1fr; align-items:start; } }
figure { margin:0; }
.frame { position:relative; border-radius:14px; overflow:hidden; background:#000; border:1px solid var(--line); }
.frame img { display:block; width:100%; height:auto; }
.safe { position:absolute; border:2px dashed var(--rose); border-radius:4px; display:none; pointer-events:none; }
.show-safe .safe { display:block; }
.phone-size .frame { max-width:360px; } .phone-size .hdr .frame { max-width:390px; }
details { background:var(--card); border:1px solid var(--line); border-radius:14px; padding:10px 14px; margin:12px 0; }
summary { cursor:pointer; font-weight:600; }
pre { white-space:pre-wrap; font:12.5px/1.45 ui-monospace,Menlo,monospace; color:var(--ink2); margin:10px 0 0; }
code { background:var(--card); padding:1px 6px; border-radius:6px; font-size:14px; }
.take { border-left:3px solid var(--sun); padding:2px 0 2px 12px; margin:10px 0; }
ul { padding-left:20px; margin:8px 0; } li { margin:6px 0; }
a { color:#7cc8ff; }
"""

JS = """
const b = document.body;
document.getElementById('t-safe').addEventListener('change', e => b.classList.toggle('show-safe', e.target.checked));
document.getElementById('t-size').addEventListener('change', e => b.classList.toggle('phone-size', e.target.checked));
"""


def safe_box(fmt):
    x0, y0, x1, y1 = looks.SAFE[fmt]
    return f'<div class="safe" style="left:{x0 * 100:.2f}%;top:{y0 * 100:.2f}%;width:{(x1 - x0) * 100:.2f}%;height:{(y1 - y0) * 100:.2f}%"></div>'


def flags(chk, look):
    if not chk:
        return ""
    out = []
    expect = list(look.get("lines", [])) + list(look.get("captions", []))
    if expect:
        out.append('<span class="tag ok">words exact</span>' if chk["text_ok"]
                   else f'<span class="tag bad">words off: {html.escape(", ".join(chk["missing"]))}</span>')
        if look.get("bleed"):
            out.append('<span class="tag warn">goes past the safe area on purpose</span>')
        elif chk["in_box"]:
            out.append('<span class="tag ok">words inside the safe area</span>')
        else:
            out.append(f'<span class="tag warn">outside the safe area: {html.escape(", ".join(chk["outside"]))}</span>')
    return "".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=os.path.join(looks.OUT_DIR, "out"))
    ap.add_argument("--site", default=os.path.expanduser("~/Sites/capling-store-gpt"))
    a = ap.parse_args()
    img_dir = os.path.join(a.site, "img")
    os.makedirs(img_dir, exist_ok=True)

    def load(name, default):
        p = os.path.join(looks.OUT_DIR, name)
        return json.load(open(p)) if os.path.exists(p) else default

    checks, prompts, notes = load("checks.json", {}), load("prompts.json", {}), load("notes.json", {})
    spent, n_ok = 0.0, 0
    ledger = os.path.join(looks.OUT_DIR, "ledger.jsonl")
    if os.path.exists(ledger):
        done = {}
        for line in open(ledger):
            r = json.loads(line)
            if r.get("ok"):
                done[r["id"]] = r.get("est_usd", 0)
        spent, n_ok = sum(done.values()), len(done)

    have = {}
    for look in looks.LOOKS:
        for fmt in ("card", "header"):
            jid = f"{look['id']}-{fmt}"
            src = os.path.join(a.src, f"{jid}.png")
            if os.path.exists(src):
                Image.open(src).convert("RGB").save(os.path.join(img_dir, f"{jid}.jpg"), quality=86, optimize=True, progressive=True)
                have[jid] = True

    grid = "".join(
        f'<a href="#look-{i}"><img src="img/{l["id"]}-card.jpg" alt=""><span><b>{i}</b>{html.escape(l["name"])}</span></a>'
        for i, l in enumerate(looks.LOOKS, 1) if f'{l["id"]}-card' in have)

    sections = []
    for i, look in enumerate(looks.LOOKS, 1):
        words = " / ".join(look.get("lines", [])) or " | ".join(look.get("captions", []))
        figs = []
        for fmt, label, cls in (("card", "Search card, 3:2", "crd"), ("header", "Header, 21:9", "hdr")):
            jid = f"{look['id']}-{fmt}"
            if jid not in have:
                figs.append(f'<figure class="{cls}"><div class="muted">{label}: not rendered yet</div></figure>')
                continue
            figs.append(
                f'<figure class="{cls}"><div class="frame"><img src="img/{jid}.jpg" alt="{html.escape(look["name"])}, {label}">{safe_box(fmt)}</div>'
                f'<figcaption>{label}. {flags(checks.get(jid), look)}</figcaption></figure>')
        briefs = "".join(
            f'<details><summary>The brief for the {fmt}</summary><pre>{html.escape(prompts.get(f"{look["id"]}-{fmt}", ""))}</pre></details>'
            for fmt in ("card", "header"))
        take = f'<div class="take">{html.escape(notes[look["id"]])}</div>' if look["id"] in notes else ""
        sections.append(
            f'<section id="look-{i}"><h2><span class="num">{i}</span>{html.escape(look["name"])}</h2>'
            f'<p>{html.escape(look["idea"])}</p><p class="copy">Words: {html.escape(words)}</p>{take}'
            f'<div class="pair wide">{figs[0]}{figs[1]}</div>{briefs}</section>')

    summary = f'<div class="take">{html.escape(notes["_summary"])}</div>' if "_summary" in notes else ""
    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Capling store art, GPT variants</title><style>{CSS}</style></head>
<body><main>
<h1>Capling store art: GPT Image 2.5 variants</h1>
<p class="lede">Eight looks, each as a Search card (3:2) and a header (21:9). The model drew everything, the app's screens included, from the real screens and Cap's character sheet it was shown. These are concepts: the one you pick gets rebuilt with the real screenshots at 3840 wide.</p>
<p><span class="tag">fal · GPT Image 2.5 (sunburst) · high quality</span><span class="tag">{n_ok} images · about ${spent:.2f} (my estimate; fal doesn't publish the price)</span><span class="tag">not uploaded anywhere</span></p>
<div class="bar"><label><input type="checkbox" id="t-safe"> Show Apple's art safe area</label><label><input type="checkbox" id="t-size"> Show at phone size</label></div>
<div class="grid">{grid}</div>
{summary}
{"".join(sections)}
<section><h2>Your call</h2><ul>
<li>Tell me the numbers you like. I rebuild those at 3840 px wide with the real screenshots (the model's screens are approximations), and make the header and card of a look match.</li>
<li>Words in these pictures are English, so each language needs its own set. Copy to settle: "Know you're ready" vs "See how ready you are" (the app calls readiness a projection).</li>
<li>Apple's safe area is small: on a phone about 204 x 97 pt of a 360 pt card. Bigger than that may be cropped on some devices; check Apple's Preview tool before anything goes live.</li>
</ul>
<p class="muted">Pictures: <code>Cramless/build/store-art/gpt/out/</code> (1920 px masters). Briefs, checker and page builder: <code>Cramless/scripts/store_art/gpt/</code>. Nothing is committed or uploaded. Earlier, code-drawn version: <a href="../capling-store-assets/">capling-store-assets</a>.</p></section>
</main><script>{JS}</script></body></html>"""
    with open(os.path.join(a.site, "index.html"), "w") as f:
        f.write(page)
    print(a.site, f"{len(have)} pictures")


if __name__ == "__main__":
    sys.exit(main())
