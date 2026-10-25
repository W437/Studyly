#!/usr/bin/env python3
"""Cap's production clips: one transparent clip per pose, made with Kling 4.0, checked, and encoded for the app.

    produce.py prompts [id ...]                  print the prompts and what a run would cost (costs nothing)
    produce.py gen <ref|pin> <id ...> [--take N] make clips (needs FAL_KEY); refuses to pass the budget
    produce.py check <clip ...>                  key a raw clip and judge it: start, loop, pink, colour, motion, pictures a second
    produce.py smooth <clip ...>                 draw the pictures a clip is missing (see below) as a new take, <clip>s
    produce.py repair <clip ...>                 draw again the frames that carry a smear of the model's background, as <clip>r
    produce.py look <clip ...>                   a contact strip of the clip (12 frames) on grey, to look at
    produce.py finalize <id> <clip>              polish the loop, encode HEVC with alpha, verify, add to the manifest
    produce.py reencode [id ...]                 encode shipped clips again from their saved final frames (costs nothing)
    produce.py audit [id ...]                    read the planes of the files in the app: colour under transparency
    produce.py install                           copy the final clips and the manifest into the app's resources
    produce.py status                            every clip: its takes and verdicts, and what has been spent

Modes: `ref` is Kling 4.0 reference-to-video with Cap defined by the character sheet and the pose's still as the first
frame (best identity: his eyes, teeth and tongue are the sheet's); `pin` is image-to-video with the still as the first AND
last frame (the loop closes exactly, but the model invents details). Clip names are <id>-<mode>-<take>.

A clip has to draw a new picture on every frame. The video model sometimes animates "on twos" or "on threes": a new drawing every
2nd or 3rd frame and the same one held in between, so a 24 fps file moves only 12 or 8 times a second, which looks choppy on a
120 Hz screen (the welcome's wave did it, and 6 more of the 38 clips; the owner saw it on the phone). `check` counts the pictures
and warns; `smooth` keeps the frames that are new and draws the rest between them (inbetween.swift: Apple's frame-rate
conversion, one optical flow moving Cap's colour and his alpha), as the take <clip>s, which is finalized like any other.

Everything is under build/cap-clips/ (start, raw, frames, final, manifest.json, ledger.jsonl). The budget is in dollars at
fal's list price ($0.157 per second of video) over everything this tool has ever submitted: the owner approved about $25.
"""
import argparse, base64, colorsys, fcntl, io, json, os, shutil, statistics, subprocess, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageStat

import cap_anim as ca

HERE = Path(__file__).resolve().parent
ROOT = ca.ROOT
PROD = ROOT / "build/cap-clips"
ca.BUILD = PROD                                   # key_clip, pack_clip and prep now work inside this folder
BOOK = json.loads((HERE / "clips.json").read_text())
COMMON = BOOK["common"]
CLIPS = {c["id"]: c for c in BOOK["clips"]}
PANELS = ROOT / "docs/cap/panels"
PICKS = json.loads((ROOT / "docs/cap/picks.json").read_text())
APP_RESOURCES = ROOT / "Cramless/Resources/CapClips"

# Dollars at fal's list price over everything this tool has ever submitted. The owner approved about $25 for the 19 base clips
# ($22.14 spent), then up to $20 more on 2026-10-25 for the 19 poke clips: $42.14 in all.
BUDGET = 42.14
PER_SECOND = 0.157
MODES = {"ref": "kling/v4/reference-to-video", "pin": "kling/v4/image-to-video"}
ENCODE = ["-c:v", "hevc_videotoolbox", "-q:v", "65", "-alpha_quality", "0.75", "-pix_fmt", "bgra", "-tag:v", "hvc1", "-movflags", "+faststart"]


# ---- prompts --------------------------------------------------------------------------------------------------------

def prompt(clip, mode):
    c = COMMON
    entry = CLIPS[clip]
    text = (c["ref_intro"] if mode == "ref" else c["pin_intro"]) + " " + entry["action"] + c["look"]
    text += {"open": c["eyes_open"], "shut": c["eyes_shut"]}.get(entry["eyes"], c["eyes_closed"])
    if entry.get("teeth"):
        text += c["teeth"]
    return text + c["scene"] + c["ending"]


# ---- the ledger -----------------------------------------------------------------------------------------------------

def entries():
    path = PROD / "ledger.jsonl"
    return [json.loads(l) for l in path.read_text().splitlines() if l.strip()] if path.exists() else []


def spent():
    """What has been submitted, less what fal refused before doing any work (a rejected request is not charged)."""
    rows = entries()
    return sum(e["cost"] for e in rows if e.get("event") == "submit") - sum(e["cost"] for e in rows if e.get("event") == "refund")


def log(entry):
    PROD.mkdir(parents=True, exist_ok=True)
    with open(PROD / "ledger.jsonl", "a") as f:
        f.write(json.dumps(entry) + "\n")


def reserve(name, endpoint, cost):
    """The budget check and the log line in one locked step, so runs started together can't all pass the check."""
    PROD.mkdir(parents=True, exist_ok=True)
    with open(PROD / "ledger.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        total = spent()
        if total + cost > BUDGET + 1e-9:
            print(f"{name}: REFUSED. Spent ${total:.2f} + ${cost:.2f} would pass the ${BUDGET:.2f} budget.", flush=True)
            return False
        log({"event": "submit", "clip": name, "endpoint": endpoint, "cost": round(cost, 4), "at": time.strftime("%H:%M:%S")})
        return True


# ---- fal ------------------------------------------------------------------------------------------------------------

def uri(path, max_side=1024):
    im = Image.open(path)
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        white = Image.new("RGB", im.size, (255, 255, 255))
        white.paste(im, mask=im.split()[3])
        im = white
    im = im.convert("RGB")
    im.thumbnail((max_side, max_side), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=94)
    return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()


def png_uri(path):
    return "data:image/png;base64," + base64.b64encode(Path(path).read_bytes()).decode()


def body_for(clip, mode):
    entry = CLIPS[clip]
    start = ca.prep(entry["pose"])
    if mode == "pin":
        return {"start_image_url": png_uri(start), "end_image_url": png_uri(start), "prompt": prompt(clip, mode),
                "duration": entry["seconds"], "resolution": "720p"}
    panel = lambda name: uri(PANELS / f"{name}.jpg")
    return {"prompt": prompt(clip, mode), "duration": entry["seconds"], "resolution": "720p", "aspect_ratio": "1:1",
            "start_image_url": png_uri(start),
            "elements": [{"frontal_image_url": panel(PICKS["front"]),
                          "reference_image_urls": [panel(PICKS[k]) for k in ("threeq", "side", "face")]}],
            "image_urls": [panel(n) for n in PICKS["extra"]]}


def gen(mode, clip, take):
    name = f"{clip}-{mode}-{take}"
    entry = CLIPS[clip]
    endpoint = MODES[mode]
    cost = entry["seconds"] * PER_SECOND
    body = body_for(clip, mode)
    if not reserve(name, endpoint, cost):
        return None
    t0 = time.time()
    try:
        q = ca.fal(f"https://queue.fal.run/{endpoint}", body)
        for _ in range(450):
            if ca.fal(q["status_url"])["status"] == "COMPLETED":
                break
            time.sleep(4)
        out = ca.fal(q["response_url"])
        raw = PROD / "raw"
        raw.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(out["video"]["url"], raw / f"{name}.mp4")
        log({"event": "done", "clip": name, "secs": round(time.time() - t0)})
        print(f"{name}: ok in {round(time.time() - t0)} s (${cost:.2f})", flush=True)
        return name
    except Exception as e:
        detail = e.read().decode()[:500] if hasattr(e, "read") else ""
        log({"event": "failed", "clip": name, "error": f"{e} {detail}"[:700]})
        if getattr(e, "code", 0) in (400, 401, 403, 404, 422):
            log({"event": "refund", "clip": name, "cost": round(cost, 4), "why": "refused before any work"})
        print(f"{name}: FAILED {e} {detail}", flush=True)
        return None


# ---- judging a clip -------------------------------------------------------------------------------------------------

def load(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(np.float32) / 255


def premultiplied(frame):
    out = np.empty(frame.shape[:2] + (3,), dtype=np.float32)
    np.multiply(frame[..., :3], frame[..., 3:4], out=out)
    return out


def solid_colour(frame):
    mask = np.greater(frame[..., 3], 0.97)
    return frame[..., :3][mask].mean(0) if mask.any() else np.zeros(3, dtype=np.float32)


def still_canvas(pose):
    """The pose's still on the same transparent 720 px canvas the clips use (straight RGBA, 0..1)."""
    art = Image.open(ca.pose_png(pose)).convert("RGBA")
    canvas = Image.new("RGBA", (ca.CANVAS, ca.CANVAS), (0, 0, 0, 0))
    canvas.alpha_composite(art, (ca.PAD, ca.PAD))
    return np.asarray(canvas).astype(np.float32) / 255


def best_cut(frames, still):
    """The frame to end the clip on: the one in its last 45% closest to the still, leaning a little to later ones.
    Returns (index, difference from the still)."""
    target = premultiplied(still)
    n = len(frames)
    best, best_score, best_d = n - 1, 9.0, 9.0
    for i in range(int(n * 0.55), n):
        d = float(np.abs(np.subtract(premultiplied(frames[i]), target)).mean())
        score = d + 0.002 * (1 - i / n)
        if score < best_score:
            best, best_score, best_d = i, score, d
    return best, best_d


def picture_steps(files):
    """How much each frame differs from the one before it (the mean over the three colour channels, 0..255), with Cap drawn over
    grey at 240 px. Pillow only, on purpose: with Python 3.14 and NumPy 2.2 an expression like `a - b` can overwrite `a` in place,
    and the first version of this count measured nonsense."""
    steps, previous = [], None
    for path in files:
        im = Image.open(path).convert("RGBA").resize((240, 240))
        base = Image.new("RGBA", im.size, (128, 128, 128, 255))
        base.alpha_composite(im)
        current = base.convert("RGB")
        if previous is not None:
            steps.append(sum(ImageStat.Stat(ImageChops.difference(current, previous)).mean) / 3)
        previous = current
    return steps


def hold_pattern(steps):
    """(period, ratio): 1 when the clip draws a new picture on every frame, 2 or 3 when it draws one every 2nd or 3rd frame and holds
    it in between ("on twos", "on threes"). The ratio is how much bigger the steps on the beat are than the ones between; held
    frames differ only by the video's noise, so a held beat reads 5 to 20 and a clip that moves smoothly reads about 1."""
    body = steps[6:-6] if len(steps) > 30 else steps          # the ends are eased onto the still
    best = (1, 1.0)
    for period in (2, 3, 4):
        for phase in range(period):
            on = [v for i, v in enumerate(body) if i % period == phase]
            off = [v for i, v in enumerate(body) if i % period != phase]
            if on and off:
                ratio = (sum(on) / len(on)) / max(sum(off) / len(off), 1e-6)
                if ratio > best[1]:
                    best = (period, ratio)
    return best if best[1] > 2.5 else (1, best[1])


def new_pictures(steps):
    """The frames that are new drawings: the first, and every frame that differs from the one before it. A held frame differs only
    by the video's noise, which grows with the motion next to it (about 5 % of the step beside it), so a step counts as a hold when
    it is under a third of its bigger neighbour or under the noise floor (0.05); the beat can change phase inside a clip, so this
    is judged step by step and not from one period."""
    out = [0]
    for i, v in enumerate(steps):
        beside = max(steps[i - 1] if i > 0 else 0.0, steps[i + 1] if i + 1 < len(steps) else 0.0)
        if v >= 0.05 and v >= 0.3 * beside:
            out.append(i + 1)
    return out


def pink_residue(path):
    """Visible pixels of a keyed frame that are saturated red-pink or magenta (hue 315 to 360 and 0 to 8 degrees), at 360 px. Cap has
    none bar a tongue; a smear of the background that the cut-out let through reads in the hundreds (the wave's fast paw: 425 on one
    frame against about 60 on a clean one). `check` counts the magenta-purple band only, and this one the red-pink band beside it."""
    im = Image.open(path).convert("RGBA").resize((360, 360))
    data = im.tobytes()
    count = 0
    for i in range(0, len(data), 4):
        r, g, b, a = data[i], data[i + 1], data[i + 2], data[i + 3]
        if a < 64 or r < 90 or r < g or r < b:
            continue
        h, sat, val = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if sat > 0.3 and val > 0.35 and (h * 360 >= 315 or h * 360 <= 8):
            count += 1
    return count


def check(clip, force=False):
    """Key the raw clip and judge it. Returns the verdict dict (also saved as frames/<clip>/qa.json)."""
    work = PROD / "frames" / clip
    metrics_file = work / "metrics.json"
    if metrics_file.exists() and (work / "rgba").is_dir() and not force:
        m = json.loads(metrics_file.read_text())          # already keyed: the keying is the slow part
    else:
        m = ca.key_clip(clip)
    files = sorted((work / "rgba").glob("*.png"))
    pose = CLIPS[clip.split("-")[0]]["pose"]
    still = still_canvas(pose)
    first, last = load(files[0]), load(files[-1])
    pink = []
    for f in files:
        frame = load(f)
        pink.append(int(np.logical_and(ca.pinkish(frame[..., :3].astype(np.float64)), np.greater(frame[..., 3], 0.25)).sum()))
    # how far the clip's first and last frame are from the still itself, not just from each other
    d_first = float(np.abs(np.subtract(premultiplied(first), premultiplied(still))).mean())
    d_last = float(np.abs(np.subtract(premultiplied(last), premultiplied(still))).mean())
    # the clip can end on any frame in its last 45%: the one closest to the still (a little later is better)
    cut, d_cut = best_cut([load(f) for f in files], still)
    colour = float(np.abs(np.subtract(solid_colour(first), solid_colour(still))).max())
    steps = picture_steps(files)
    holds, _ = hold_pattern(steps)
    pictures = round(m["fps"] * (len(new_pictures(steps)) - 1) / max(len(steps), 1), 1)
    a = m["align"]
    reasons, level = [], "PASS"

    def mark(severity, why):
        nonlocal level
        reasons.append(why)
        if severity == "FAIL" or level == "PASS":
            level = severity if not (level == "FAIL") else level

    if abs(a["dx"]) > 4 or abs(a["dy"]) > 4 or not 0.96 <= a["size"] <= 1.04:
        mark("FAIL", f"does not start on the still (off {a['dx']},{a['dy']} px, size x{a['size']})")
    elif abs(a["dx"]) > 2 or abs(a["dy"]) > 2 or not 0.98 <= a["size"] <= 1.02:
        mark("WARN", f"starts a little off the still ({a['dx']},{a['dy']} px, size x{a['size']})")
    if d_cut > 0.02:
        mark("FAIL", f"never comes back to the still (closest {d_cut:.4f})")
    elif d_cut > 0.008:
        mark("WARN", f"comes back near the still (closest {d_cut:.4f}); the ending is eased onto it")
    if max(pink) > 400:
        mark("FAIL", f"pink left in a frame ({max(pink)} px)")
    elif max(pink) > 120:
        mark("WARN", f"some pink left ({max(pink)} px)")
    if colour > 0.06:
        mark("FAIL", f"colours drifted from the still ({colour:.3f})")
    elif colour > 0.03:
        mark("WARN", f"colours differ a little from the still ({colour:.3f})")
    if m["step_median"] < 0.0003:
        mark("WARN", f"barely moves (typical step {m['step_median']:.5f})")
    if holds > 1:
        mark("WARN", f"draws a new picture only every {holds}{'nd' if holds == 2 else 'rd' if holds == 3 else 'th'} frame "
                     f"({pictures:g} a second): `produce.py smooth {clip}` draws the rest")
    qa = {"clip": clip, "verdict": level, "reasons": reasons, "frames": len(files), "fps": m["fps"],
          "pictures_per_second": pictures, "holds": holds,
          "start_off": [a["dx"], a["dy"]], "start_size": a["size"], "first_vs_still": round(d_first, 5), "last_vs_still": round(d_last, 5),
          "cut": cut, "cut_vs_still": round(d_cut, 5),
          "seam": m["seam"], "pink_worst": max(pink), "colour_vs_still": round(colour, 4), "step_median": m["step_median"]}
    (work / "qa.json").write_text(json.dumps(qa))
    print(f"{clip:22s} {level:4s} frames {len(files)} @{m['fps']:g}  start off ({a['dx']},{a['dy']}) x{a['size']}  "
          f"back to still {d_cut:.4f} @frame {cut + 1}/{len(files)}  pink {max(pink)}  colour {colour:.3f}  step {m['step_median']:.4f}  "
          f"pictures {pictures:g}/s"
          + ("  | " + "; ".join(reasons) if reasons else ""), flush=True)
    return qa


def look(clip):
    work = PROD / "frames" / clip
    files = sorted((work / "rgba").glob("*.png"))
    pick = [files[int(i * (len(files) - 1) / 11)] for i in range(12)]
    cell = 300
    sheet = Image.new("RGB", (cell * 6, cell * 2), (128, 128, 128))
    for k, path in enumerate(pick):
        im = Image.open(path).convert("RGBA").resize((cell, cell), Image.LANCZOS)
        tile = Image.new("RGBA", (cell, cell), (128, 128, 128, 255))
        tile.alpha_composite(im)
        sheet.paste(tile.convert("RGB"), ((k % 6) * cell, (k // 6) * cell))
    out = PROD / "look"
    out.mkdir(parents=True, exist_ok=True)
    sheet.save(out / f"{clip}.jpg", quality=88)
    print(out / f"{clip}.jpg")


def inbetween_tool():
    """The compiled in-between tool, made when it is missing or older than its source."""
    source = HERE / "inbetween.swift"
    exe = PROD / "bin" / "inbetween"
    if not exe.exists() or exe.stat().st_mtime < source.stat().st_mtime:
        exe.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["swiftc", "-O", str(source), "-o", str(exe)], check=True)
    return exe


def spikes(counts):
    """The frames whose red-pink residue (`pink_residue`) spikes against the six around them: over 150 and over 2.5 times their middle
    value. A pose that is pink all through (a tongue, a blush) reads high on every frame and has none; confetti is the exception that
    needs a look (`celebrate` has some, and they are no smear)."""
    out = []
    for i, c in enumerate(counts):
        around = counts[max(0, i - 3):i] + counts[i + 1:i + 4]
        if c > max(150, 2.5 * statistics.median(around or [0])):
            out.append(i)
    return out


def redraw(clip, keys, suffix):
    """Make the take `<clip><suffix>` from `clip`'s own frames (the video model's, before the cut-out): the frames in `keys` kept exactly,
    every other frame drawn again from the two keys around it by inbetween.swift. It is encoded as a raw take and keyed and judged like
    any other, so the cut-out treats the drawn frames as it treats real ones; then `finalize` as usual."""
    work = PROD / "frames" / clip
    sources = sorted((work / "src").glob("*.png"))
    target = f"{clip}{suffix}"
    dst = PROD / "frames" / target
    shutil.rmtree(dst, ignore_errors=True)
    (dst / "src").mkdir(parents=True)
    plan = {"out": str(dst / "src"), "frames": len(sources), "keys": [{"file": str(sources[n]), "n": n} for n in keys]}
    (dst / "plan.json").write_text(json.dumps(plan))
    subprocess.run([str(inbetween_tool()), str(dst / "plan.json")], check=True)
    fps = json.loads((work / "metrics.json").read_text())["fps"]
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-framerate", f"{fps:g}", "-i", str(dst / "src/%04d.png"),
                    "-c:v", "libx264", "-crf", "8", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(PROD / "raw" / f"{target}.mp4")], check=True)
    shutil.rmtree(dst / "src")                  # key_clip takes the frames out of the video again, as for any take
    check(target, force=True)
    return target


def smooth(clip):
    """Draw the pictures a clip is missing. A clip animated "on twos" or "on threes" (see hold_pattern) keeps the frames that are
    new drawings, and the frames held between them are drawn again from the two drawings around them (see `redraw`), as the take
    `<clip>s`. (The first version drew them on the keyed frames, colour and alpha in two passes, and the fast paw came out
    pink-speckled.)"""
    work = PROD / "frames" / clip
    keyed = sorted((work / "rgba").glob("*.png"))
    sources = sorted((work / "src").glob("*.png"))
    if not keyed or len(sources) != len(keyed):
        sys.exit(f"{clip} is not keyed yet: run `produce.py check {clip}` first")
    steps = picture_steps(keyed)
    holds, ratio = hold_pattern(steps)
    if holds == 1:
        print(f"{clip}: draws a new picture on every frame already (beat ratio {ratio:.1f}); nothing to draw")
        return clip
    keys = new_pictures(steps)
    # A key frame the video model smeared (pink round a fast paw) would be copied as it is and drawn into its neighbours: leave it
    # out and let the two clean keys around it draw that stretch instead. A smear is a spike among the keys around it: a pose that is
    # pink all through (a blush, a pillow) is no smear.
    residue = {n: pink_residue(keyed[n]) for n in keys}
    around = {n: statistics.median([residue[k] for k in keys[max(0, i - 2):i] + keys[i + 1:i + 3]] or [0]) for i, n in enumerate(keys)}
    smeared = [n for n in keys if 0 < n < len(keyed) - 1 and residue[n] > max(150, 2.5 * around[n])]
    if smeared:
        print(f"{clip}: key frames with a pink smear, drawn again from their neighbours instead: {smeared} "
              f"({[residue[n] for n in smeared]} px against about {[round(around[n]) for n in smeared]} round them)")
        keys = [n for n in keys if n not in smeared]
    return redraw(clip, keys, "s")


def repair(clip):
    """Draw again the frames of a take that carry a smear of the video model's background (a spike of `pink_residue`; see `spikes`):
    every other frame is kept exactly, the smeared ones are drawn from the clean frames either side, as the take `<clip>r`."""
    work = PROD / "frames" / clip
    keyed = sorted((work / "rgba").glob("*.png"))
    if not keyed or not (work / "src").is_dir():
        sys.exit(f"{clip} is not keyed yet: run `produce.py check {clip}` first")
    bad = [n for n in spikes([pink_residue(f) for f in keyed]) if 0 < n < len(keyed) - 1]
    if not bad:
        print(f"{clip}: no frame with a smear; nothing to draw")
        return clip
    print(f"{clip}: frames with a pink smear, drawn again from their neighbours: {[n + 1 for n in bad]}")
    return redraw(clip, [n for n in range(len(keyed)) if n not in bad], "r")


def smeared(frame, box):
    """The pixels inside `box` (x0, y0, x1, y1) that are red-pink or mauve and not Cap's: saturated, not dark (his outlines are), with
    the lighter peach ones counted only at the silhouette, where the fur's own orange (hue 25 and over) can't be mistaken for it."""
    h, s, v = ca.hue_sat_val(frame[..., :3])
    a = frame[..., 3]
    seen = np.logical_and(np.greater(a, 0.05), np.greater(s, 0.35))
    red = np.logical_and(np.logical_and(seen, np.greater(v, 0.4)), np.logical_or(np.greater_equal(h, 330.0), np.less_equal(h, 12.0)))
    peach = np.logical_and(np.logical_and(seen, np.greater(v, 0.6)), np.less_equal(h, 20.0))
    peach = np.logical_and(peach, ca._grow(np.less(a, 0.2), 6))
    inside = np.zeros(a.shape, dtype=bool)
    x0, y0, x1, y1 = box
    inside[y0:y1, x0:x1] = True
    return np.logical_and(np.logical_or(red, peach), inside)


def scrub_frame(frame, box):
    """`frame` with the smear in `box` recoloured from the fur and paw solid beside it. The shape (alpha) is kept."""
    bad = np.logical_and(ca._grow(smeared(frame, box), 1), np.greater(frame[..., 3], 0.02))     # with the soft rim of each smear
    solid = np.logical_and(np.greater(frame[..., 3], 0.9), np.logical_not(ca._grow(bad, 1)))
    carried, have = ca._spread(frame[..., :3], solid, 20)
    out = frame.copy()
    out[..., :3] = np.where(np.logical_and(bad, have)[..., None], carried, frame[..., :3])
    return out, int(bad.sum())


def scrub(clip, first, last, box):
    """Recolour the red-pink smear that a take keeps on a fast paw, in frames `first` to `last` (numbered as in the file names) and
    inside `box` (x0, y0, x1, y1 on the 720 canvas), as the take `<clip>c`. `repair` draws a smeared frame again from its neighbours,
    but the video model's blur is in the neighbours' moving edges too (scanPoke's, 46 to 48: a mauve paw and a salmon lump on the arm),
    and a cross-dissolve of the two ghosts the paw. This keeps every shape and takes only the colour from the fur next to the smear.
    Look at the result (`look`) and run `residue_audit.py` on the final; a box that reaches a tongue or a blush recolours that too."""
    work = PROD / "frames" / clip
    files = sorted((work / "rgba").glob("*.png"))
    if not files:
        sys.exit(f"{clip} is not keyed yet: run `produce.py check {clip}` first")
    target = f"{clip}c"
    dst = PROD / "frames" / target
    shutil.rmtree(dst, ignore_errors=True)
    shutil.copytree(work, dst, ignore=shutil.ignore_patterns("src"))
    for n in range(first, last + 1):
        path = dst / "rgba" / f"{n:04d}.png"
        frame, count = scrub_frame(load(path), box)
        before = pink_residue(work / "rgba" / f"{n:04d}.png")
        Image.fromarray((np.clip(frame, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(path)
        print(f"{target}: frame {n}: {count} px recoloured, pink {before} -> {pink_residue(path)}", flush=True)
    qa_path = dst / "qa.json"
    qa = json.loads(qa_path.read_text())
    qa["clip"] = target
    qa["pink_worst"] = max(pink_residue(f) for f in sorted((dst / "rgba").glob("*.png")))
    qa_path.write_text(json.dumps(qa))
    return target


# ---- finishing --------------------------------------------------------------------------------------------------------

def grade_for(first, still):
    """Per-channel gain and offset that bring the clip's colours onto the still's, fitted on the pixels of Cap that are solid
    in both and away from every edge. The video model returns Cap about 2% darker than the picture it was given; without
    this the colours would pulse as a clip takes over from the still and hands back. None when there is too little to fit."""
    both = np.logical_and(np.greater(first[..., 3], 0.97), np.greater(still[..., 3], 0.97))
    inner = np.logical_and(both, np.logical_not(ca._grow(np.logical_not(both), 3)))
    if int(inner.sum()) < 3000:
        return None
    coeffs = []
    for c in range(3):
        x = first[..., c][inner].astype(np.float64)
        y = still[..., c][inner].astype(np.float64)
        (a, b), *_ = np.linalg.lstsq(np.stack([x, np.ones_like(x)], axis=1), y, rcond=None)
        if not (0.9 <= a <= 1.15 and abs(b) <= 0.06):
            return None
        coeffs.append((float(a), float(b)))
    return coeffs


def apply_grade(frame, coeffs):
    if coeffs is None:
        return frame
    out = frame.copy()
    for c, (a, b) in enumerate(coeffs):
        out[..., c] = np.clip(np.add(np.multiply(frame[..., c], np.float32(a)), np.float32(b)), 0, 1)
    return out


def polish(frames, still, cut, grade=None):
    """End the clip on frame `cut`, then make it start and end exactly on the still.

    The first 3 frames ease in from the still and the last 6 ease onto it, in premultiplied colour so edges don't gain a
    halo. A clip that starts and ends on the still can take over from it and hand back with nothing visible, and chains with
    the clips before and after it. All arithmetic goes through ufunc calls (NumPy 2.2 on Python 3.14 can change an array
    in place under an operator)."""
    loaded = [apply_grade(load(f), grade) for f in frames[:cut + 1]]
    p_still = premultiplied(still)
    a_still = still[..., 3:4]

    def toward(frame, t):
        """`frame` moved a fraction t of the way to the still."""
        t = np.float32(t)
        p = np.add(np.multiply(premultiplied(frame), np.float32(1) - t), np.multiply(p_still, t))
        a = np.add(np.multiply(frame[..., 3:4], np.float32(1) - t), np.multiply(a_still, t))
        rgb = np.where(np.greater(a, 0.004), np.divide(p, np.maximum(a, 0.004)), frame[..., :3])
        return np.concatenate([np.clip(rgb, 0, 1), a], axis=-1).astype(np.float32)

    head, tail = 3, 6
    raw_end = float(np.abs(np.subtract(premultiplied(loaded[-1]), p_still)).mean())
    raw_start = float(np.abs(np.subtract(premultiplied(loaded[0]), p_still)).mean())
    for k in range(head):
        loaded[k] = toward(loaded[k], 1.0 - k / head)
    for k in range(tail):
        i = len(loaded) - tail + k
        loaded[i] = toward(loaded[i], (k + 1) / tail)
    return loaded, raw_start, raw_end


def write_premultiplied(src, dst):
    """The straight RGBA frames in `src`, with colour multiplied by alpha, in `dst`: the only thing the encoder may be given.

    The file says its colour is premultiplied (AlphaChannelMode), so a player draws the colour planes as they are and adds
    them to whatever is behind Cap. Straight frames leave colour under every transparent pixel (the keyer's leftovers, from a
    few levels of grey to full white beside the outline): on a dark screen that is a lighter rectangle the size of the clip and
    a halo round Cap, while a Mac reading the file as BGRA multiplies it away and shows nothing wrong. Found when the owner saw
    the rectangle behind Cap in Today's sky."""
    if dst.exists():
        shutil.rmtree(dst)
    dst.mkdir(parents=True)
    for f in sorted(src.glob("*.png")):
        a = load(f)
        rgb = np.empty(a.shape[:2] + (3,), dtype=np.float32)
        np.multiply(a[..., :3], a[..., 3:4], out=rgb)
        out = np.concatenate([rgb, a[..., 3:4]], axis=-1)
        Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(dst / f.name)


def encode(clip_id, fps):
    """final-frames/<id> (straight RGBA) to final/cap-<id>.mov, through premultiplied copies. Returns the file."""
    src = PROD / "final-frames" / clip_id
    pm = PROD / "final-frames-pm" / clip_id
    write_premultiplied(src, pm)
    final = PROD / "final"
    final.mkdir(parents=True, exist_ok=True)
    mov = final / f"cap-{clip_id}.mov"
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-framerate", f"{fps:g}", "-i", str(pm / "%04d.png")]
                   + ENCODE + [str(mov)], check=True)
    shutil.rmtree(pm, ignore_errors=True)
    return mov


def planes(mov):
    """What the file stores under its transparent pixels, read in the decoder's own planes (hevc_planes.swift):
    (Y of the empty border band, share of all transparent pixels lifted more than 2 above black, brightest Y there).
    Video-range black is Y 16. A clean clip reads (16, 0.0, small)."""
    r = subprocess.run(["swift", str(HERE / "hevc_planes.swift"), str(mov), "0", "-1"], capture_output=True, text=True)
    border, lifted, brightest = 0, 0.0, 0
    for line in r.stdout.splitlines():
        if line.startswith("frame") and "Y " in line:
            border = max(border, int(line.split("Y ")[1].split("...")[1].split(" ")[0]))
        elif "transparent px" in line:
            lifted = max(lifted, float(line.split("(")[1].split("%")[0]))
            brightest = max(brightest, int(line.rsplit("brightest Y ", 1)[1]))
    return border, lifted, brightest


def planes_ok(clip_id, mov):
    border, lifted, brightest = planes(mov)
    ok = border <= 17 and lifted < 1.0 and brightest <= 70
    print(f"{clip_id}: under the transparent pixels Y {border} at the border (black is 16), {lifted:.2f}% of them lifted, "
          f"brightest Y {brightest}{'' if ok else '  ** COLOUR UNDER TRANSPARENCY: a lighter rectangle on a dark screen **'}", flush=True)
    return ok


def finalize(clip_id, clip):
    entry = CLIPS[clip_id]
    qa = json.loads((PROD / "frames" / clip / "qa.json").read_text())
    files = sorted((PROD / "frames" / clip / "rgba").glob("*.png"))
    still = still_canvas(entry["pose"])
    grade = grade_for(load(files[0]), still)
    frames, raw_start, raw_end = polish(files, still, qa["cut"], grade)
    seam = 0.0
    out = PROD / "final-frames" / clip_id
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    for i, frame in enumerate(frames):
        Image.fromarray((np.clip(frame, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(out / f"{i + 1:04d}.png")
    mov = encode(clip_id, qa["fps"])
    verify = subprocess.run(["swift", str(HERE / "hevc_frames.swift"), str(mov), str(PROD / "verify" / clip_id), "0"],
                            capture_output=True, text=True)
    line = verify.stdout.strip().splitlines()
    head = line[0] if line else ""
    ok = "alpha=true" in head and "720x720" in head and f"frames read: {len(frames)}" in verify.stdout
    if not ok:
        print(f"{clip_id}: VERIFY FAILED\n{verify.stdout}\n{verify.stderr}")
        return False
    if not planes_ok(clip_id, mov):
        return False
    manifest_path = PROD / "manifest.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {"version": 1, "canvas": ca.CANVAS, "pose": ca.POSE, "clips": []}
    manifest["clips"] = [c for c in manifest["clips"] if c["id"] != clip_id]
    manifest["clips"].append({
        "id": clip_id, "pose": entry["pose"], "role": entry["role"], "file": f"cap-{clip_id}.mov", "fps": qa["fps"],
        "frames": len(frames), "duration": round(len(frames) / qa["fps"], 3), "bytes": mov.stat().st_size,
        "source": clip, "easedFromStill": round(raw_start, 5), "easedOntoStill": round(raw_end, 5),
        "grade": [[round(a, 4), round(b, 4)] for a, b in grade] if grade else None})
    manifest["clips"].sort(key=lambda c: c["id"])
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    # for the review page: the animated image and the strip, from what ships
    ca.BUILD = PROD
    shutil.rmtree(PROD / "frames" / f"{clip_id}-final", ignore_errors=True)
    (PROD / "frames" / f"{clip_id}-final").mkdir(parents=True)
    shutil.copytree(out, PROD / "frames" / f"{clip_id}-final" / "rgba")
    (PROD / "frames" / f"{clip_id}-final" / "metrics.json").write_text(json.dumps({"fps": qa["fps"]}))
    ca.pack_clip(f"{clip_id}-final")
    print(f"{clip_id}: final {len(frames)} frames, {mov.stat().st_size // 1024} KB, starts and ends on the still "
          f"(eased from {raw_start:.4f} and onto {raw_end:.4f}; from {clip})", flush=True)
    return True


def reencode(ids):
    """Encode again, from final-frames, the clips already finished: after a change to how they are encoded."""
    manifest_path = PROD / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    failed = []
    for c in manifest["clips"]:
        if ids and c["id"] not in ids:
            continue
        mov = encode(c["id"], c["fps"])
        if not planes_ok(c["id"], mov):
            failed.append(c["id"])
            continue
        c["bytes"] = mov.stat().st_size
        print(f"  {c['id']}: {c['bytes'] // 1024} KB", flush=True)
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print("failed: " + ", ".join(failed) if failed else "all clean")
    return not failed


def audit(ids):
    """The planes of every clip in the app's resources, without making anything."""
    bad = []
    for c in json.loads((APP_RESOURCES / "cap-clips.json").read_text())["clips"]:
        if ids and c["id"] not in ids:
            continue
        if not planes_ok(c["id"], APP_RESOURCES / c["file"]):
            bad.append(c["id"])
    print("with colour under transparency: " + ", ".join(bad) if bad else "all clean")
    return not bad


def install():
    manifest = json.loads((PROD / "manifest.json").read_text())
    APP_RESOURCES.mkdir(parents=True, exist_ok=True)
    for c in manifest["clips"]:
        shutil.copy(PROD / "final" / c["file"], APP_RESOURCES / c["file"])
    shutil.copy(PROD / "manifest.json", APP_RESOURCES / "cap-clips.json")
    total = sum(c["bytes"] for c in manifest["clips"])
    print(f"installed {len(manifest['clips'])} clips ({total / 1024 / 1024:.1f} MB) into {APP_RESOURCES}")


def status():
    qas = {}
    for p in sorted((PROD / "frames").glob("*/qa.json")):
        q = json.loads(p.read_text())
        qas.setdefault(q["clip"].split("-")[0], []).append(q)
    manifest_path = PROD / "manifest.json"
    done = {c["id"]: c for c in json.loads(manifest_path.read_text())["clips"]} if manifest_path.exists() else {}
    print(f"{'id':10s} {'role':12s} takes (verdict)                                   final")
    for cid, entry in CLIPS.items():
        takes = ", ".join(f"{q['clip'].split('-', 1)[1]}={q['verdict']}" for q in qas.get(cid, [])) or "-"
        print(f"{cid:10s} {entry['role']:12s} {takes:46s} {'cap-' + cid + '.mov ' + str(done[cid]['bytes'] // 1024) + ' KB' if cid in done else ''}")
    print(f"spent ${spent():.2f} of ${BUDGET:.2f} (list price)")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("prompts"); s.add_argument("ids", nargs="*")
    g = sub.add_parser("gen"); g.add_argument("mode", choices=MODES); g.add_argument("ids", nargs="+"); g.add_argument("--take", type=int, default=1)
    c = sub.add_parser("check"); c.add_argument("clips", nargs="+"); c.add_argument("--rekey", action="store_true")
    sub.add_parser("smooth").add_argument("clips", nargs="+")
    sub.add_parser("repair").add_argument("clips", nargs="+")
    sc = sub.add_parser("scrub"); sc.add_argument("clip"); sc.add_argument("frames", help="first-last, as in the file names")
    sc.add_argument("box", help="x0,y0,x1,y1 on the 720 canvas")
    sub.add_parser("look").add_argument("clips", nargs="+")
    f = sub.add_parser("finalize"); f.add_argument("id"); f.add_argument("clip")
    sub.add_parser("reencode").add_argument("ids", nargs="*")
    sub.add_parser("audit").add_argument("ids", nargs="*")
    sub.add_parser("install"); sub.add_parser("status")
    a = ap.parse_args()
    if a.cmd == "prompts":
        ids = a.ids or list(CLIPS)
        total = 0.0
        for cid in ids:
            c = CLIPS[cid]
            total += c["seconds"] * PER_SECOND
            print(f"== {cid} ({c['role']}, {c['seconds']} s, ${c['seconds'] * PER_SECOND:.2f})\n{prompt(cid, 'ref')}\n")
        print(f"one take of these: ${total:.2f}")
    elif a.cmd == "gen":
        ids = list(CLIPS) if a.ids == ["all"] else a.ids
        with ThreadPoolExecutor(max_workers=6) as ex:
            list(ex.map(lambda cid: gen(a.mode, cid, a.take), ids))
    elif a.cmd == "check":
        for c in a.clips:
            check(c, force=a.rekey)
    elif a.cmd == "smooth":
        for c in a.clips:
            smooth(c)
    elif a.cmd == "repair":
        for c in a.clips:
            repair(c)
    elif a.cmd == "scrub":
        first, last = (int(x) for x in a.frames.split("-"))
        scrub(a.clip, first, last, tuple(int(x) for x in a.box.split(",")))
    elif a.cmd == "look":
        for c in a.clips:
            look(c)
    elif a.cmd == "finalize":
        sys.exit(0 if finalize(a.id, a.clip) else 1)
    elif a.cmd == "reencode":
        sys.exit(0 if reencode(a.ids) else 1)
    elif a.cmd == "audit":
        sys.exit(0 if audit(a.ids) else 1)
    elif a.cmd == "install":
        install()
    elif a.cmd == "status":
        status()


if __name__ == "__main__":
    main()
