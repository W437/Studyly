#!/usr/bin/env python3
"""Counts the leftover magenta / pink-purple pixels in every keyed clip, and shows the worst frames.

    pink_audit.py                    a table for every clip in build/cap-anim and build/cap-anim2 (worst frame, average)
    pink_audit.py --look <clip> ...  also writes build/cap-anim2/pink-audit/<clip>.jpg: the worst three frames on the app's
                                     night blue, with the leftover pixels painted green, next to the plain frame

Cap's own colours have no hue between 262 and 350 degrees (cap_anim.PINK_HUES), so any visible pixel of that hue is
background that the cut-out let through. A clean clip has next to none. The first version of the cut-out left hundreds
to thousands per frame on fast-moving arms and tassels, where video smears the background into streaks.
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image

import cap_anim as ca

ROOT = ca.ROOT
NIGHT = np.array([11, 18, 34], dtype=np.float64) / 255


def load(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.float64) / 255


def pink_mask(frame, visible=0.25):
    return np.logical_and(ca.pinkish(frame[..., :3]), np.greater(frame[..., 3], visible))


def composite(frame):
    a = frame[..., 3:]
    out = np.add(np.multiply(frame[..., :3], a), np.multiply(NIGHT, np.subtract(1.0, a)))
    return (np.clip(out, 0, 1) * 255).astype(np.uint8)


def clips():
    for root in ("build/cap-anim", "build/cap-anim2"):
        for d in sorted((ROOT / root / "frames").glob("*")):
            if (d / "rgba").is_dir() and any((d / "rgba").glob("*.png")):
                yield d.name, d


def audit(look):
    rows = []
    for name, d in clips():
        files = sorted((d / "rgba").glob("*.png"))
        counts = [int(pink_mask(load(f)).sum()) for f in files]
        worst = int(np.argmax(counts))
        rows.append((name, len(files), counts[worst], worst + 1, float(np.mean(counts)), counts, files))
    print(f"{'clip':28s} frames   worst frame (pink px)   average per frame")
    for name, n, w, wf, avg, _, _ in sorted(rows, key=lambda r: -r[2]):
        print(f"{name:28s} {n:5d}   frame {wf:3d}: {w:6d}         {avg:8.1f}")
    for name, n, w, wf, avg, counts, files in rows:
        if name not in look:
            continue
        out = ROOT / "build/cap-anim2/pink-audit"
        out.mkdir(parents=True, exist_ok=True)
        picks = np.argsort(counts)[::-1][:3]
        tiles = []
        for k in picks:
            frame = load(files[k])
            plain = composite(frame)
            marked = plain.copy()
            marked[pink_mask(frame)] = (0, 255, 80)
            tiles += [Image.fromarray(plain).resize((480, 480)), Image.fromarray(marked).resize((480, 480))]
        sheet = Image.new("RGB", (480 * len(tiles), 480))
        for i, t in enumerate(tiles):
            sheet.paste(t, (i * 480, 0))
        sheet.save(out / f"{name}.jpg", quality=88)
        print("wrote", out / f"{name}.jpg", "frames", [int(k) + 1 for k in picks])


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--look", nargs="*", default=[])
    audit(ap.parse_args().look)
