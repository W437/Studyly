#!/usr/bin/env python3
"""Reads the words in every picture of out/ (Apple's Vision, ocr.swift) and checks two things per picture:

  text_ok  every word the brief asked for is there, spelled exactly (a fuzzy match on what the OCR read, so a one-letter slip fails)
  in_box   the lines that matched sit inside Apple's art safe area for their slot (a small tolerance)

It writes out/../checks.json, which the review page shows. Words on the phone screens are read too and kept (`lines`) so a stray
or garbled word can be looked for by eye; only the brief's own words are judged.

    python3 -P check.py                                   # every picture in out/
    python3 -P check.py --files a.png --fmt card --expect "Snap" --expect "your notes"      # one picture, by hand (a test)
"""
import argparse
import difflib
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks  # noqa: E402

BIN = os.path.join(looks.OUT_DIR, "bin", "ocr")
TOL = 0.015


def norm(s):
    return re.sub(r"[\W_]+", "", s.lower().replace("’", "'"))


def build_tool():
    if os.path.exists(BIN) and os.path.getmtime(BIN) > os.path.getmtime(os.path.join(HERE, "ocr.swift")):
        return
    os.makedirs(os.path.dirname(BIN), exist_ok=True)
    subprocess.run(["swiftc", "-O", os.path.join(HERE, "ocr.swift"), "-o", BIN], check=True)


def read(path, langs=None):
    out = subprocess.run([BIN, path] + ([",".join(langs)] if langs else []), capture_output=True, text=True, check=True).stdout
    return json.loads(out)


def with_wraps(rows):
    """The OCR rows plus each run of two or three rows that sit under each other (a caption wrapped onto the next line)."""
    out = list(rows)
    for i, r in enumerate(rows):
        text, x0, y0, x1, y1 = r["text"], r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"]
        for nxt in rows[i + 1:i + 3]:
            if abs(nxt["x"] - r["x"]) > 0.12 and abs((nxt["x"] + nxt["w"] / 2) - (r["x"] + r["w"] / 2)) > 0.06:
                continue
            if not (0 <= nxt["y"] - y1 <= 1.8 * r["h"]):
                continue
            text += " " + nxt["text"]
            x0, y0 = min(x0, nxt["x"]), min(y0, nxt["y"])
            x1, y1 = max(x1, nxt["x"] + nxt["w"]), max(y1, nxt["y"] + nxt["h"])
            out.append(dict(text=text, conf=min(r["conf"], nxt["conf"]), x=x0, y=y0, w=x1 - x0, h=y1 - y0))
    return out


def judge(path, fmt, expect, langs=None):
    rows = read(path, langs)
    safe = looks.SAFE[fmt]
    found, missing, outside = [], [], []
    wrapped = with_wraps(rows)
    for want in expect:
        w = norm(want)
        best, score = None, 0.0
        for r in wrapped:
            n = norm(r["text"])
            ratio = 1.0 if (w and w in n) else difflib.SequenceMatcher(None, w, n).ratio()
            if ratio > score:
                best, score = r, ratio
        if best is not None and score >= 0.86:
            found.append(want)
            x0, y0, x1, y1 = best["x"], best["y"], best["x"] + best["w"], best["y"] + best["h"]
            if x0 < safe[0] - TOL or x1 > safe[2] + TOL or y0 < safe[1] - TOL or y1 > safe[3] + TOL:
                outside.append(want)
        else:
            missing.append(want)
    return dict(text_ok=not missing, missing=missing, in_box=not outside, outside=outside, found=found,
                lines=[dict(text=r["text"], conf=round(r["conf"], 2), x=round(r["x"], 3), y=round(r["y"], 3),
                            w=round(r["w"], 3), h=round(r["h"], 3)) for r in rows])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--files", nargs="*")
    ap.add_argument("--fmt", default="card", choices=("card", "header"))
    ap.add_argument("--expect", action="append", default=[])
    a = ap.parse_args()
    build_tool()
    if a.files:
        for f in a.files:
            r = judge(f, a.fmt, a.expect)
            print(f, json.dumps({k: v for k, v in r.items() if k != "lines"}))
            for line in r["lines"][:14]:
                print("   ", line["text"], line["x"], line["y"], line["w"], line["h"])
        return 0
    checks = {}
    for look in looks.LOOKS:
        expect = list(look.get("lines", [])) + list(look.get("captions", []))
        for fmt in ("card", "header"):
            jid = f"{look['id']}-{fmt}"
            path = os.path.join(looks.OUT_DIR, "out", f"{jid}.png")
            if not os.path.exists(path):
                continue
            checks[jid] = judge(path, fmt, expect)
            c = checks[jid]
            print(f"{jid:18s} text {'ok' if c['text_ok'] else 'MISSING ' + str(c['missing'])}   box {'ok' if c['in_box'] else 'OUTSIDE ' + str(c['outside'])}")
    with open(os.path.join(looks.OUT_DIR, "checks.json"), "w") as f:
        json.dump(checks, f, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
