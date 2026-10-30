#!/usr/bin/env python3
"""Review page for Capling's header and Search card in every App Store language: ~/Sites/capling-store-languages/.

    python3 -P build_locales_page.py [--src DIR] [--site DIR] [--uploaded]

Reads <src>/<code>/{header,search}-<code>.png and report.json (build_locales.py), reads every picture back with Apple's Vision where it
knows the language (the headline must come back exactly), and shows each language's pictures, its strings and a note for the native
reviewer. Writes index.html and img/*.jpg. --uploaded says the pictures are placed in App Store Connect.
"""
import argparse
import html
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_page as bp  # noqa: E402
import build_locales as bl  # noqa: E402
import check  # noqa: E402
import locales as lc  # noqa: E402

# The biggest App Store markets first, then the rest.
TOP = ["en-US", "zh-Hans", "ja", "ko", "de-DE", "fr-FR", "zh-Hant", "pt-BR", "es-ES", "it", "ru", "es-MX", "tr", "ar-SA", "nl-NL"]
MORE = ["id", "th", "vi", "pl", "hi", "sv", "da", "no", "fi", "cs", "sk", "hu", "ro", "hr", "el", "he", "uk", "ms", "ca", "pt-PT", "fr-CA"]
COUNTRIES = {
    "en-US": "US, UK, Canada, Australia, India and more (en-GB, en-AU, en-CA reuse it)", "zh-Hans": "China", "ja": "Japan", "ko": "South Korea",
    "de-DE": "Germany, Austria, Switzerland", "fr-FR": "France, Belgium, Switzerland", "fr-CA": "Canada (Quebec)", "zh-Hant": "Taiwan, Hong Kong",
    "pt-BR": "Brazil", "es-ES": "Spain", "it": "Italy", "ru": "Russia, Kazakhstan", "es-MX": "Mexico and Latin America", "tr": "Turkey",
    "ar-SA": "Saudi Arabia, UAE, Egypt", "nl-NL": "Netherlands, Belgium", "id": "Indonesia", "th": "Thailand", "vi": "Vietnam", "pl": "Poland",
    "hi": "India", "sv": "Sweden", "da": "Denmark", "no": "Norway", "fi": "Finland", "cs": "Czechia", "sk": "Slovakia", "hu": "Hungary",
    "ro": "Romania", "hr": "Croatia", "el": "Greece", "he": "Israel", "uk": "Ukraine", "ms": "Malaysia", "ca": "Catalonia, Andorra", "pt-PT": "Portugal",
}
LABEL = {"card": "Search card 3840 x 2560", "header": "Header 3840 x 1646"}


def jpg(src, dst, width=900):
    im = Image.open(src).convert("RGB")
    if im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    im.save(dst, quality=84, optimize=True, progressive=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default=bl.OUT)
    ap.add_argument("--site", default=os.path.expanduser("~/Sites/capling-store-languages"))
    ap.add_argument("--uploaded", action="store_true")
    a = ap.parse_args()
    img_dir = os.path.join(a.site, "img")
    os.makedirs(img_dir, exist_ok=True)
    report = json.load(open(os.path.join(a.src, "report.json")))
    check.build_tool()

    def path(code, fmt):
        return os.path.join(a.src, code, f"{bl.NAMES[fmt]}-{code}.png")

    def judge(job):
        code, fmt = job
        row = lc.LOCALES[code]
        if not row["ocr"]:
            return job, None
        try:
            return job, check.judge(path(code, fmt), fmt, row["lines"], row["ocr"])
        except Exception as e:  # noqa: BLE001
            return job, dict(error=str(e))

    jobs = [(c, f) for c in TOP + MORE for f in ("card", "header")]
    with ThreadPoolExecutor(max_workers=3) as ex:
        ocr = dict(ex.map(judge, jobs))
    for c, f in jobs:
        jpg(path(c, f), os.path.join(img_dir, f"{c}-{f}.jpg"))

    def tags(code, fmt):
        rep, res, row = report[f"{code}/{fmt}"], ocr[(code, fmt)], lc.LOCALES[code]
        out = []
        if res is None:
            out.append('<span class="tag warn">not read back (Vision cannot read this language): check by eye</span>')
        elif res.get("error"):
            out.append('<span class="tag warn">read-back failed</span>')
        elif res["text_ok"]:
            out.append('<span class="tag ok">words read back exact (OCR)</span>')
        else:
            out.append('<span class="tag warn">OCR read it differently: check by eye</span>')
        out.append('<span class="tag ok">words inside the safe area</span>' if rep["inside_box"] else '<span class="tag bad">words outside the safe area</span>')
        out.append(f'<span class="tag">words {rep["headline_px"]} px</span>')
        if rep["missing_glyphs"]:
            out.append(f'<span class="tag bad">no glyph for {html.escape("".join(rep["missing_glyphs"]))}</span>')
        return "".join(out)

    def fig(code, fmt):
        return (f'<figure class="{"crd" if fmt == "card" else "hdr"}"><div class="frame"><img loading="lazy" src="img/{code}-{fmt}.jpg" alt="{code} {fmt}">'
                f'{bp.safe_box(fmt)}</div><figcaption>{LABEL[fmt]}. {tags(code, fmt)}</figcaption></figure>')

    def section(code):
        row = lc.LOCALES[code]
        strings = (f'<p class="muted"><b>{html.escape(" / ".join(row["lines"]))}</b> · ring: {html.escape(row["label"])} · '
                   f'{html.escape(row["title"])} · {html.escape(row["sub"])} · {html.escape(row["track"])}'
                   f'{" · " + html.escape(row["note"]) if row["note"] else ""}</p>')
        dirn = ' dir="auto"'
        return (f'<section id="{code}"><h3>{html.escape(row["name"])} <span class="muted">{html.escape(row["native"])} · {code} · '
                f'{html.escape(COUNTRIES.get(code, ""))}</span></h3><div{dirn}>{strings}</div><div class="pair">{fig(code, "card")}{fig(code, "header")}</div></section>')

    n_ok = sum(1 for k, v in ocr.items() if v and v.get("text_ok"))
    n_read = sum(1 for k, v in ocr.items() if v is not None)
    soft = [f"{c} {f}" for (c, f), v in ocr.items() if v is not None and not v.get("text_ok")]
    top = "".join(section(c) for c in TOP)
    more = "".join(section(c) for c in MORE)
    status = ('<span class="tag ok">placed in App Store Connect (Loopware, Capling 1.0)</span>' if a.uploaded
              else '<span class="tag">not uploaded yet</span>')
    extra = """
h3 { margin:22px 0 2px; font-size:1.1rem; } h3 .muted { font-weight:400; font-size:.85rem; }
details { margin:18px 0; } summary { cursor:pointer; font-weight:600; padding:8px 0; }
"""
    page = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Capling store art, all languages</title><style>{bp.CSS}{extra}</style></head>
<body><main>
<h1>Capling store art in every App Store language</h1>
<p class="lede">The approved sunny poster, header and Search card, in all 39 languages the App Store takes. 36 sets of pictures: the English variants (UK, Australia, Canada) reuse the U.S. one. The 15 biggest markets come first.</p>
<p>{status}<span class="tag warn">words are drafts by Claude, not native-reviewed</span><span class="tag">{n_ok} of {n_read} read back exact by OCR</span><span class="tag">layout mirrors for Arabic and Hebrew</span></p>
<div class="bar"><label><input type="checkbox" id="t-safe"> Show Apple's art safe area</label><label><input type="checkbox" id="t-size"> Show at phone size</label></div>
<section><h2>The 15 biggest markets</h2>{top}</section>
<details><summary>{len(MORE)} more languages</summary>{more}</details>
<section><h2>Before this goes in for review</h2><ul>
<li>Every line was written by me and read once by a second model; none has been read by a native speaker. The headline, the ring's word and three card strings per language sit in one table (<code>scripts/store_art/gpt/locales.py</code>): fix a word there and every picture of that language re-renders in seconds.</li>
<li>Those strings should become the app's own when it is localized (its catalog is English only today), so the store and the app say the same thing.</li>
<li>Each language added on the App Store page needs its own listing text before submission (name, subtitle, description, keywords), and the app should speak it.</li>
{"<li>Read back by Vision with a differing result (look at these by eye): " + html.escape(", ".join(soft)) + ".</li>" if soft else ""}
</ul><p class="muted">Masters: <code>Cramless/build/store-art/locales/&lt;language&gt;/header-&lt;language&gt;.png</code> and <code>search-&lt;language&gt;.png</code> (png, no alpha). Code: <code>build_locales.py</code>.</p></section>
</main><script>{bp.JS}</script></body></html>"""
    with open(os.path.join(a.site, "index.html"), "w") as f:
        f.write(page)
    print(a.site, "ok;", n_ok, "of", n_read, "read back exact;", "check by eye:" if soft else "", soft)
    return 0


if __name__ == "__main__":
    sys.exit(main())
