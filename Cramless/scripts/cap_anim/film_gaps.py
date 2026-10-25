#!/usr/bin/env python3
"""Finds the frames where Cap thins out or vanishes in a film: a dropout audit.

    film_gaps.py <film.mp4> --box X Y W H [--fail 0.2] [--report 0.7] [--skip 0.6]

X Y W H is a box in the film's own pixels that holds Cap and nothing else orange. Every frame is cut down to that box and the
share of its pixels that look like Cap's fur (orange: red well above blue and above green) is counted. A frame's share is
compared with the middle value of the second around it, so a pose that is simply smaller doesn't count as a gap.

  - A frame under --fail of its neighbourhood (default 0.2) is a dropout: Cap is gone. Any dropout exits 1.
  - A stretch under --report (default 0.7) is listed with its deepest frame: a dissolve between two poses dips a little
    (two half-faded Caps are not one whole one) and a dip to about a half is normal; a dip to nothing is a blink.
  - The first --skip seconds (default 0.6) are left out: a film opens on the app's first frames, before Cap is there.

Tested on the Feel lab's cast film (box 420 660 420 540 on a 1206 x 2608 film). The old pose change under a looping clip
(letting the AVPlayerLooper go took its frame off the layer at once, so the clip cut out and the next drawing faded in from
nothing) showed as a dropout of 4 to 6 frames at 60 fps at every change out of an idle clip; the fixed one shows none.
"""
import subprocess
import sys

import numpy as np


def coverage(film, box):
    x, y, w, h = box
    sw, sh = max(8, w // 5), max(8, h // 5)
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", film,
           "-vf", f"crop={w}:{h}:{x}:{y},scale={sw}:{sh}:flags=area,format=rgb24", "-f", "rawvideo", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    frames = np.frombuffer(raw, dtype=np.uint8).reshape(-1, sh, sw, 3).astype(np.int16)
    r, g, b = frames[..., 0], frames[..., 1], frames[..., 2]
    fur = (r - b > 70) & (r - g > 30)
    return fur.mean(axis=(1, 2))


def fps_of(film):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=r_frame_rate",
                          "-of", "csv=p=0", film], capture_output=True, text=True, check=True).stdout.strip()
    n, d = out.split("/")
    return float(n) / float(d)


def runs(mask):
    out, i = [], 0
    while i < len(mask):
        if mask[i]:
            j = i
            while j < len(mask) and mask[j]:
                j += 1
            out.append((i, j))
            i = j
        else:
            i += 1
    return out


def main():
    args = sys.argv[1:]
    if not args or "--box" not in args:
        sys.exit(__doc__)
    film = args[0]
    at = args.index("--box")
    box = tuple(int(v) for v in args[at + 1:at + 5])
    fail = float(args[args.index("--fail") + 1]) if "--fail" in args else 0.2
    report = float(args[args.index("--report") + 1]) if "--report" in args else 0.7
    skip = float(args[args.index("--skip") + 1]) if "--skip" in args else 0.6
    fps = fps_of(film)
    cov = coverage(film, box)
    first = int(skip * fps)
    window = int(fps)
    local = np.array([np.median(cov[max(0, i - window):i + window + 1]) for i in range(len(cov))])
    ratio = np.divide(cov, local, out=np.ones_like(cov), where=local > 0.02)
    ratio[:first] = 1.0
    print(f"{film}: {len(cov)} frames at {fps:g} fps")
    dips = runs(ratio < report)
    dropouts = 0
    for a, b in dips:
        low = ratio[a:b].min()
        kind = "DROPOUT" if low < fail else "dip"
        dropouts += low < fail
        print(f"  {a / fps:7.2f}s  {b - a:3d} frame(s) {kind:8s} deepest {low:4.2f}")
    print(f"{dropouts} dropout(s), {len(dips) - dropouts} dip(s)")
    sys.exit(1 if dropouts else 0)


if __name__ == "__main__":
    main()
