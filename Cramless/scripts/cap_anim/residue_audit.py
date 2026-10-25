#!/usr/bin/env python3
"""Finds the frames of the shipped clips where a smear of the video model's background is left on Cap: a spike of red-pink or magenta
pixels against the frames around it (the old wave had two on its fast paw: 425 and 250 pixels against about 50).

    residue_audit.py                 every clip in build/cap-clips/final-frames
    residue_audit.py wave sleepy     just these

A pose that is pink all through (a tongue, a blush) reads high on every frame and is no spike: a frame counts only when it is over
150 and over 2.5 times the middle value of the six frames around it (`produce.pink_residue`, the same count `produce.py smooth` uses
to leave a smeared key out). Exits 1 when any clip has one.

Two readings are known and are no smear: `celebrate` (frames 96 and 97: its confetti is red-pink) and `tuckIn` (93 and 94: the ease
onto the still mixes two poses, and the take itself is clean). A real one is cleaned with `produce.py scrub <take> <first>-<last>
<x0,y0,x1,y1>` (`repair` draws the frame again from its neighbours, which only helps when they are clean), then `finalize`.
"""
import sys
from pathlib import Path

import produce as p


def main():
    ids = [a for a in sys.argv[1:] if not a.startswith("-")] or sorted(d.name for d in (p.PROD / "final-frames").iterdir() if d.is_dir())
    bad = 0
    print(f"{'clip':14} frames  worst  spikes (frame: pixels)")
    for cid in ids:
        files = sorted((p.PROD / "final-frames" / cid).glob("*.png"))
        counts = [p.pink_residue(f) for f in files]
        found = [(i, counts[i]) for i in p.spikes(counts)]
        bad += bool(found)
        print(f"{cid:14} {len(files):6} {max(counts):6}  " + (", ".join(f"{i + 1}: {c}" for i, c in found) if found else "-"), flush=True)
    print(f"\n{bad} clip(s) with a smeared frame" if bad else "\nno clip has a smeared frame")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
