#!/usr/bin/env python3
"""The approved sunny poster (header and Search card) in every App Store Connect language, from the table in locales.py.

    python3 -P scripts/store_art/gpt/build_locales.py [--only de-DE,ja] [--fmt card|header] [--jobs 3] [--out DIR]

Writes <out>/<code>/header-<code>.png and search-<code>.png (3840 x 1646 and 3840 x 2560, png, no alpha: the sizes Apple takes), and
<out>/report.json: per picture the headline size, whether the words sit inside Apple's art safe area, how far the ring is from the
words, and any character the chosen fonts lack (a missing glyph would show as a box). English variants and Canadian French reuse
another language's pictures (locales.REUSE), so they have no folder of their own.
"""
import argparse
import json
import os
import sys
import time
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import directions as dr  # noqa: E402
import locales as lc  # noqa: E402
import looks  # noqa: E402
import store_ring as sr  # noqa: E402

OUT = os.path.join(os.path.dirname(looks.OUT_DIR), "locales")      # build/store-art/locales
NAMES = {"card": "search", "header": "header"}


def one(job):
    code, fmt, out = job
    row = dict(lc.LOCALES[code], code=code)
    t0 = time.time()
    img, hl, extras = dr.d_poster2_row(fmt, row)
    box = sr.box_px(fmt)
    d = os.path.join(out, code)
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, f"{NAMES[fmt]}-{code}.png")
    img.save(path)
    inside = all(dr.inside(box, b) for b in dr.ink_boxes(hl)) and dr.inside(box, hl["pill"])
    return dict(code=code, fmt=fmt, file=path, size=list(img.size), headline_px=hl["px"], inside_box=inside, ring_gap=hl.get("ring_gap"),
                secs=round(time.time() - t0, 1))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--fmt", choices=("card", "header"))
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--out", default=OUT)
    a = ap.parse_args()
    codes = [c for c in a.only.split(",") if c] or list(lc.LOCALES)
    bad = [c for c in codes if c not in lc.LOCALES]
    if bad:
        sys.exit(f"unknown language(s): {bad}")
    missing = {c: lc.missing_glyphs(c) for c in codes}
    for c, m in missing.items():
        if m:
            print(f"WARNING {c}: the fonts have no glyph for {m}", flush=True)
    jobs = [(c, f, a.out) for c in codes for f in ([a.fmt] if a.fmt else ["card", "header"])]
    os.makedirs(a.out, exist_ok=True)
    rpath = os.path.join(a.out, "report.json")
    report = json.load(open(rpath)) if os.path.exists(rpath) else {}
    t0 = time.time()
    with ProcessPoolExecutor(max_workers=a.jobs) as ex:
        for r in ex.map(one, jobs):
            report[f"{r['code']}/{r['fmt']}"] = dict(r, missing_glyphs=missing[r["code"]])
            flag = "" if r["inside_box"] and not missing[r["code"]] else "   <-- CHECK"
            print(f"{r['code']:6s} {r['fmt']:6s} headline {r['headline_px']:4d} px  inside box {r['inside_box']}  ring gap {r['ring_gap']}  {r['secs']}s{flag}", flush=True)
    with open(rpath, "w") as f:
        json.dump(report, f, indent=1, ensure_ascii=False)
    print(f"{len(jobs)} pictures in {time.time() - t0:.0f}s -> {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
