#!/usr/bin/env python3
"""Generates sound effects with ElevenLabs Sound Effects v2 on fal, then makes them safe.

    python3 tools/gen_sfx.py sources/v6/sfx.json --out public/v6/audio
    python3 tools/gen_sfx.py --example > sources/v6/sfx.json
    python3 tools/gen_sfx.py sources/v6/sfx.json --dry-run

The list (JSON): [{"name": "sfx-whoosh", "text": "…", "seconds": 0.8, "influence": 0.7}, …]
Cost ≈ $0.002 per second. Each result gets a 30 ms trim and fade at the end (the last MP3
frame of a generated effect often clicks), then a level/spectrum check: generated effects
are sometimes near-silent or a piercing tone (a "beep" came back as a 5.4 kHz whistle).
Synthesize simple beeps and ticks in code instead (numpy: a band-limited square with a
3 ms attack), tuned to the track's key. Reads FAL_KEY from the environment; never prints it.
"""
import argparse
import concurrent.futures as cf
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ENDPOINT = "fal-ai/elevenlabs/sound-effects/v2"
PRICE_PER_SEC = 0.002
DRY = "very close microphone, dry, crisp, clean, no music, no reverb"
EXAMPLE = [
    {"name": "sfx-whoosh", "text": "A short, smooth, airy whoosh transition, modern UI swipe, clean and soft", "seconds": 0.8, "influence": 0.6},
    {"name": "sfx-pop", "text": "A tiny soft UI pop tap sound, clean, subtle", "seconds": 0.5, "influence": 0.7},
    {"name": "sfx-snap", "text": "One crisp satisfying magnetic snap, a single solid clack with a soft body, " + DRY, "seconds": 0.5, "influence": 0.8},
    {"name": "sfx-chime", "text": "A gentle, pleasant two-note success chime, soft marimba and glass, modern app notification, clean", "seconds": 1.2, "influence": 0.6},
    {"name": "sfx-riser", "text": "A short rising filtered noise sweep building tension for one second, clean, ends abruptly on its peak", "seconds": 1.0, "influence": 0.6},
]


def finish(path):
    """Trim 30 ms off the end and fade the last 30 ms (click-free), in place."""
    dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                               capture_output=True, text=True).stdout or 0)
    if dur <= 0.12:
        return
    tmp = path + ".tmp.mp3"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-af", f"atrim=0:{dur - 0.03},afade=t=out:st={dur - 0.06}:d=0.03",
                    "-ar", "48000", "-c:a", "libmp3lame", "-b:a", "192k", tmp], check=True)
    os.replace(tmp, path)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("list", nargs="?", help="the SFX list JSON")
    ap.add_argument("--out", default=".", help="folder for the effects")
    ap.add_argument("--only", nargs="*", help="only these names")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-finish", action="store_true", help="skip the trim/fade")
    ap.add_argument("--example", action="store_true", help="print an example list and exit")
    a = ap.parse_args()
    if a.example:
        print(json.dumps(EXAMPLE, indent=2))
        return
    if not a.list:
        ap.error("a list JSON is required (or --example)")
    jobs = [j for j in json.load(open(a.list)) if not a.only or j["name"] in a.only]
    total = sum(float(j.get("seconds", 1)) for j in jobs)
    print(f"{len(jobs)} effects, {total:.1f} s ≈ ${total * PRICE_PER_SEC:.3f}")
    if a.dry_run:
        return
    import fal_queue
    os.makedirs(a.out, exist_ok=True)

    def one(j):
        dest = os.path.join(a.out, j["name"] + ("" if j["name"].endswith(".mp3") else ".mp3"))
        if os.path.exists(dest):
            return dest + " kept"
        body = {"text": j["text"], "duration_seconds": float(j.get("seconds", 1)), "prompt_influence": float(j.get("influence", 0.6))}
        try:
            res = fal_queue.run(ENDPOINT, body, poll=3)
            fal_queue.download(fal_queue.media_url(res, "audio", "audio_file"), dest)
            if not a.no_finish:
                finish(dest)
            return dest
        except (RuntimeError, subprocess.CalledProcessError) as e:
            return f"{dest} FAILED {e}"
    made = []
    with cf.ThreadPoolExecutor(8) as ex:
        for line in ex.map(one, jobs):
            print(line, flush=True)
            if not line.endswith(("kept",)) and "FAILED" not in line:
                made.append(line)
    if made:
        here = os.path.dirname(os.path.abspath(__file__))
        subprocess.run([sys.executable, os.path.join(here, "analyse_audio.py"), "--sfx", *made])


if __name__ == "__main__":
    main()
