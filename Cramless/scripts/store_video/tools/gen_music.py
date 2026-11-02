#!/usr/bin/env python3
"""Generates an ad's music with ElevenLabs Music v2.5 on fal, from a composition plan.

    python3 tools/gen_music.py sources/v6/music-plan.json --seeds 11 29 --out sources/v6
    python3 tools/gen_music.py --example > sources/v6/music-plan.json   # a plan to edit
    python3 tools/gen_music.py plan.json --dry-run                      # check it + the cost

The plan (JSON):
    {"name": "speedrun",
     "base": ["instrumental", "energetic modern electronic", "150 bpm", …],   # every chunk
     "avoid": ["vocals", "singing", …],                                       # every chunk
     "chunks": [{"text": "[Intro]", "seconds": 3.2, "add": [...], "avoid": [...]},
                {"text": "[Main]", "seconds": 14.4, "add": [...]},
                {"text": "[Ending]", "seconds": 4.4, "styles": [...], "avoid": [...]}]}
A chunk's `styles` replaces `base` (the ending usually wants its own short list).

Hard-won rules this script enforces or warns about:
  * every chunk ≥ 3 s (shorter ones fail);
  * an "[Ending]" chunk with one final hit and a decaying tail, or the track just stops;
  * no brand, company or artist names (prompts get flagged: "Apple keynote style" was rejected);
  * pick a BPM whose beat is a whole number of frames at 30 fps (120 → 15, 150 → 12, 100 → 18,
    90 → 20, 96 → 18.75 is fine too but rounds) so cuts land exactly;
  * at most 3 candidates (≈ $0.60 per minute of audio each); --force to go past it.
Writes <out>/<name>-<seed>.mp3 (kept if it exists) and <out>/<name>-plan.sent.json.
Reads FAL_KEY from the environment; never prints it.
"""
import argparse
import concurrent.futures as cf
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

ENDPOINT = "elevenlabs/music/v2.5"
PRICE_PER_MIN = 0.60
NEVER = ["vocals", "singing", "voice", "humming", "whistling", "lyrics", "spoken words", "lo-fi hiss", "distortion", "abrupt cut"]
# Names that got (or would get) a prompt flagged. Not exhaustive: describe the sound instead.
FLAGGED = ["apple", "keynote", "iphone", "google", "tiktok", "instagram", "netflix", "disney", "marvel", "nintendo", "mario",
           "pokemon", "zelda", "daft punk", "hans zimmer", "zimmer", "billie eilish", "taylor swift", "drake", "beyonce",
           "coldplay", "imagine dragons", "skrillex", "deadmau5", "calvin harris", "kanye", "weeknd", "spotify", "youtube"]

EXAMPLE = {
    "name": "speedrun",
    "base": ["instrumental", "energetic modern electronic dance", "150 bpm", "playful video game speedrun energy",
             "bright chiptune square-wave lead melody", "punchy four-on-the-floor kick", "crisp snappy snare",
             "driving sidechained synth bass", "clean, loud, modern mix", "made for a fun, fast app advert"],
    "avoid": NEVER + ["dark", "sad"],
    "chunks": [
        {"text": "[Intro]", "seconds": 3.2, "add": ["race start countdown build-up", "a tense pulsing synth note every two beats",
                                                    "a snare roll and filter sweep rising faster", "tension builds into a huge drop at the very end"],
         "avoid": ["full drums", "melody", "groove"]},
        {"text": "[Main]", "seconds": 14.4, "add": ["the full groove drops in hard on the very first beat", "catchy, bouncy lead",
                                                    "short snare fills and quick upward sweeps"],
         "avoid": ["breakdown", "silence", "slow", "intro"]},
        {"text": "[Ending]", "seconds": 4.4, "styles": ["instrumental", "one massive final hit on the very first beat",
                                                        "kick, crash cymbal and a triumphant bright major chord together",
                                                        "then the chord rings out and decays to complete silence"],
         "avoid": ["drums after the first beat", "groove continues", "melody continues", "vocals", "abrupt cut"]},
    ],
}


def build(plan):
    """The composition_plan fal expects, plus a list of problems (errors) and warnings."""
    errors, warnings, chunks = [], [], []
    base, avoid = plan.get("base", []), plan.get("avoid", NEVER)
    for c in plan.get("chunks", []):
        secs = float(c["seconds"])
        if secs < 3:
            errors.append(f"chunk {c['text']!r} is {secs} s: every chunk must be at least 3 s")
        pos = list(c.get("styles", base)) + list(c.get("add", []))
        neg = list(dict.fromkeys(list(avoid) + list(c.get("avoid", []))))
        chunks.append({"text": c["text"], "duration_ms": int(round(secs * 1000)), "positive_styles": pos, "negative_styles": neg})
    if not chunks:
        errors.append("no chunks")
    if not any("end" in c["text"].lower() or "outro" in c["text"].lower() for c in chunks):
        warnings.append("no [Ending] chunk: ask for one final hit and a decaying tail, or the track cuts off")
    words = " ".join(" ".join(c["positive_styles"]) for c in chunks).lower()
    for name in FLAGGED:
        if re.search(rf"\b{re.escape(name)}\b", words):
            errors.append(f"{name!r} in the prompt: brand, company and artist names get flagged; describe the sound")
    if "instrumental" not in words:
        warnings.append("say 'instrumental' (ads with lyrics fight the captions)")
    bpm = re.search(r"(\d+(?:\.\d+)?)\s*bpm", words)
    if bpm:
        frames = 60 / float(bpm.group(1)) * 30
        if abs(frames - round(frames)) > 0.02:
            warnings.append(f"{bpm.group(1)} BPM is {frames:.3f} frames a beat at 30 fps: cuts will round (fine, but whole numbers are easier)")
    return {"chunks": chunks}, errors, warnings


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("plan", nargs="?", help="the plan JSON")
    ap.add_argument("--seeds", type=int, nargs="+", default=[11], help="one candidate per seed (≤ 3)")
    ap.add_argument("--out", default=".", help="folder for the candidates")
    ap.add_argument("--dry-run", action="store_true", help="validate and print the cost, send nothing")
    ap.add_argument("--force", action="store_true", help="allow more than 3 candidates")
    ap.add_argument("--example", action="store_true", help="print an example plan and exit")
    a = ap.parse_args()
    if a.example:
        print(json.dumps(EXAMPLE, indent=2))
        return
    if not a.plan:
        ap.error("a plan JSON is required (or --example)")
    plan = json.load(open(a.plan))
    comp, errors, warnings = build(plan)
    total = sum(c["duration_ms"] for c in comp["chunks"]) / 1000
    cost = total / 60 * PRICE_PER_MIN * len(a.seeds)
    for w in warnings:
        print("warning:", w)
    for e in errors:
        print("ERROR:", e)
    print(f"{plan.get('name', 'music')}: {len(comp['chunks'])} chunks, {total:.1f} s, {len(a.seeds)} candidate(s) ≈ ${cost:.2f}")
    if errors:
        sys.exit(1)
    if len(a.seeds) > 3 and not a.force:
        sys.exit("more than 3 candidates: analyse the ones you have first (or --force)")
    if a.dry_run:
        return
    import fal_queue
    os.makedirs(a.out, exist_ok=True)
    name = plan.get("name", "music")
    json.dump(comp, open(os.path.join(a.out, f"{name}-plan.sent.json"), "w"), indent=2)

    def one(seed):
        dest = os.path.join(a.out, f"{name}-{seed}.mp3")
        if os.path.exists(dest):
            return f"{dest} kept"
        try:
            res = fal_queue.run(ENDPOINT, {"composition_plan": comp, "seed": seed, "output_format": "mp3_48000_192"})
            fal_queue.download(fal_queue.media_url(res, "audio", "audio_file"), dest)
            return dest
        except RuntimeError as e:
            return f"{dest} FAILED {e}"
    with cf.ThreadPoolExecutor(3) as ex:
        for line in ex.map(one, a.seeds):
            print(line, flush=True)
    print("next: python3 tools/analyse_audio.py <candidate>.mp3  (tempo, first beat, sections, loudness, the tail)")


if __name__ == "__main__":
    main()
