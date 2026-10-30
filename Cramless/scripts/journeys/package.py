#!/usr/bin/env python3
"""Packages one finished recording for the tour page: a small web film, a poster, WebVTT captions and a chapters file.

    python3 package.py <film.mp4> <out-dir> --name onboarding [--marks film.marks.json] [--title "..."] [--blurb "..."] [--poster-at 6]

<film.mp4> is the recording (any size). <marks.json> is a list of {"t": seconds into the film, "text": caption} (what the driver's
`p.mark()` wrote, mapped to film time by record.sh); an entry {"text": "_cut", "t": a, "until": b} is a stretch to drop (the driver
was waiting on the app): it is taken out of the picture and the sound, and every later mark moves up by its length.

Writes <out-dir>/<name>.mp4 (a portrait film, such as a phone, 540 px wide; a landscape one, such as a game window, 960 px wide;
H.264 High level 4.2, 60 fps, AAC, +faststart: 1 to 5 MB for a few minutes of an app), <name>.jpg (the poster; POSTER_AT=<seconds> or
--poster-at picks the frame, by default a moment after the second mark), <name>.vtt (captions) and <name>.json
({title, blurb, duration, aspect, marks, bytes, cut_seconds}), which tour_page.py reads.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
from pathlib import Path


def stamp(t: float) -> str:
    return f"{int(t // 3600):02d}:{int(t % 3600 // 60):02d}:{t % 60:06.3f}"


def probe(src: Path, entries: str, stream: str | None = None) -> str:
    cmd = ["ffprobe", "-v", "error"] + (["-select_streams", stream] if stream else []) + ["-show_entries", entries, "-of", "csv=p=0", str(src)]
    return subprocess.run(cmd, capture_output=True, text=True, check=True).stdout.strip()


def package(src: Path, out_dir: Path, name: str, marks_file: Path | None, title: str = "", blurb: str = "", poster_at: float | None = None) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    duration = float(probe(src, "format=duration") or 0)
    w, h = (int(x) for x in probe(src, "stream=width,height", "v:0").split(",")[:2])
    landscape = w > h
    width = 960 if landscape else 540
    raw = json.loads(marks_file.read_text()) if marks_file and marks_file.exists() else []
    cuts = sorted((m["t"], m["until"]) for m in raw if m["text"] == "_cut" and m.get("until", 0) - m["t"] > 1.0)

    def kept(t: float) -> float:
        return t - sum(min(max(t - a, 0.0), b - a) for a, b in cuts)

    marks = [{"t": round(kept(m["t"]), 3), "text": m["text"]} for m in raw if not m["text"].startswith("_")]   # _cut, _ready: not captions
    drop = "".join(f"*not(between(t,{a:.3f},{b:.3f}))" for a, b in cuts)
    vf = f"scale={width}:-2:flags=lanczos" + (f",select='1{drop}',setpts=N/FRAME_RATE/TB" if cuts else "")
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(src), "-vf", vf]
    if probe(src, "stream=index", "a"):
        if cuts:
            cmd += ["-af", f"aselect='1{drop}',asetpts=N/SR/TB"]
        cmd += ["-c:a", "aac", "-b:a", "96k", "-ar", "44100"]
    else:
        cmd += ["-an"]
    cmd += ["-c:v", "libx264", "-preset", "slow", "-crf", os.environ.get("WEB_CRF", "27"), "-profile:v", "high", "-level:v", "4.2",
            "-pix_fmt", "yuv420p", "-r", "60", "-movflags", "+faststart", str(out_dir / f"{name}.mp4")]
    subprocess.run(cmd, check=True)
    duration = kept(duration)
    if poster_at is None:
        poster_at = float(os.environ["POSTER_AT"]) if os.environ.get("POSTER_AT") else (marks[1]["t"] + 0.6 if len(marks) > 1 else duration * 0.35)
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-ss", f"{min(poster_at, max(duration - 0.5, 0)):.2f}",
                    "-i", str(out_dir / f"{name}.mp4"), "-frames:v", "1", "-q:v", "4", str(out_dir / f"{name}.jpg")], check=True)
    cues = ["WEBVTT", ""]
    for i, m in enumerate(marks):
        end = marks[i + 1]["t"] if i + 1 < len(marks) else duration
        end = min(end, m["t"] + 6)
        cues += [stamp(m["t"]), f"{stamp(m['t'])} --> {stamp(max(end - 0.05, m['t'] + 0.5))}", m["text"], ""]
    (out_dir / f"{name}.vtt").write_text("\n".join(cues))
    cut_seconds = round(sum(b - a for a, b in cuts), 1)
    meta = {"name": name, "title": title or name, "blurb": blurb, "duration": round(duration, 2), "aspect": round(w / h, 4), "marks": marks,
            "bytes": (out_dir / f"{name}.mp4").stat().st_size, "cut_seconds": cut_seconds}
    (out_dir / f"{name}.json").write_text(json.dumps(meta, indent=1))
    print(f"{out_dir / f'{name}.mp4'}  {duration:.1f}s  {meta['bytes'] / 1e6:.1f} MB  {len(marks)} marks"
          + (f"  (cut {cut_seconds:.0f}s of waiting)" if cuts else ""))
    return meta


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("film", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--name", required=True)
    ap.add_argument("--marks", type=Path)
    ap.add_argument("--title", default="")
    ap.add_argument("--blurb", default="")
    ap.add_argument("--poster-at", type=float)
    a = ap.parse_args()
    package(a.film, a.out, a.name, a.marks, a.title, a.blurb, a.poster_at)
