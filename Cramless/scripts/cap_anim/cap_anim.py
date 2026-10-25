#!/usr/bin/env python3
"""Cap animation test: animate Cap's still poses with fal image-to-video models and cut him out onto transparency.

    cap_anim.py prep <pose>...                  start frames: the pose on flat magenta (720 square, and 16:9 for Gemini)
    cap_anim.py selftest <pose>                 key a still back out and compare with the real alpha (costs nothing)
    cap_anim.py gen <pose> <model> [--take N]   one fal run (needs FAL_KEY); refuses to pass the spend cap
    cap_anim.py key <clip>                      raw mp4 -> keyed RGBA frames + numbers (loop seam, colour drift)
    cap_anim.py pack <clip>                     animated WebP with alpha, filmstrip and poster for the review page
    cap_anim.py ledger                          what has been spent

A clip is named <pose>-<model>-<take>. Everything lands in build/cap-anim/ (start, raw, frames, out, ledger.jsonl).

Why magenta: Cap's art has no magenta at all (hues 0-50, 130 and 200-230 only), so a flat magenta background can be
removed with no loss on him. The pose sits at its true 600 px size in the middle of the 720 px frame, so a keyed frame
lines up pixel for pixel with the still and the 60 px margin gives motion room.
"""
import argparse, base64, json, math, os, subprocess, sys, time, urllib.error, urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
ASSETS = ROOT / "Cramless/Resources/Assets.xcassets"
BUILD = ROOT / "build/cap-anim"
BG = (255, 0, 255)
CANVAS, POSE = 720, 600
PAD = (CANVAS - POSE) // 2
BUDGET = 9.00        # hard stop, in dollars, over everything this tool has ever submitted (the owner's cap is $10)
MARGIN = 1.15        # estimates are inflated by this, because fal gives no way to read the real charge back

STYLE = ("Flat vector illustration, exactly the same drawing style, colours and proportions as the first frame. "
         "The background is one solid flat magenta (#FF00FF) in every frame: no shadow, no gradient, no floor, no "
         "vignette, no other objects. Static locked camera, no zoom, no pan. The character stays the same size and in "
         "the same place, with the same navy graduation cap, gold tassel, white headphones and orange fur in every frame. "
         "Soft, gentle, natural motion. The video ends in exactly the pose it began.")
PROMPTS = {
    "wave": ("Cap, a friendly cartoon capybara, waves hello with his raised paw: three small relaxed waves with a warm "
             "smile and one slow blink, his body barely moving. Then the paw settles back to exactly the starting "
             "pose. " + STYLE),
    "stargaze": ("Cap, a cartoon capybara, looks through a golden telescope on a wooden tripod. A very subtle idle loop: "
                 "slow breathing so his chest and shoulders rise and fall a little, one slow blink, a tiny ear twitch, "
                 "and the two small yellow stars beside the telescope twinkle gently. The telescope and tripod stay "
                 "perfectly still and rigid. " + STYLE),
    "celebrate": ("Cap, a cartoon capybara, celebrates with a joyful little hop, both arms up and a big happy smile. "
                  "The colourful confetti pieces flutter and drift down slowly. He lands softly and settles back to "
                  "exactly the starting pose. " + STYLE),
}


def pose_png(pose):
    return ASSETS / f"Cap-{pose}.imageset/cap-{pose}.png"


def prep(pose):
    """The pose on flat magenta, at its real size, centred in 720 square and in 1280x720."""
    art = Image.open(pose_png(pose)).convert("RGBA")
    assert art.size == (POSE, POSE), art.size
    out = BUILD / "start"
    out.mkdir(parents=True, exist_ok=True)
    for name, size in (("", (CANVAS, CANVAS)), ("-16x9", (1280, 720))):
        canvas = Image.new("RGBA", size, BG + (255,))
        canvas.alpha_composite(art, ((size[0] - POSE) // 2, (size[1] - POSE) // 2))
        canvas.convert("RGB").save(out / f"{pose}{name}.png")
    return out / f"{pose}.png"


# ---- keying ---------------------------------------------------------------------------------------------------------

def _op(fn, a, b):
    """fn(a, b) into a fresh buffer. With Python 3.14 and NumPy 2.2, `a - b` on a local array can overwrite `a`."""
    out = np.empty(np.broadcast(a, b).shape, dtype=np.float32)
    fn(a, b, out=out)
    return out


def _erode(mask):
    """A one-pixel erosion (3 x 3) of a boolean mask."""
    out = mask.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            np.logical_and(out, np.roll(np.roll(mask, dy, 0), dx, 1), out=out)
    return out


def _grow(mask, rings):
    """A boolean mask grown by `rings` pixels (square neighbourhood)."""
    out = mask.copy()
    for dy in range(-rings, rings + 1):
        for dx in range(-rings, rings + 1):
            np.logical_or(out, np.roll(np.roll(mask, dy, 0), dx, 1), out=out)
    return out


# NumPy 2.2 on Python 3.14: an operator (`~a`, `a | b`, `a - b`) on a big array held by one local name can be done in place,
# silently changing `a`. Everything below therefore uses function calls (np.logical_not, np.subtract, ...), which don't.

def hue_sat_val(rgb):
    """Hue (degrees), saturation and value of an RGB array in 0..1. Function calls only (see the note above _spread)."""
    r, g, b = rgb[..., 0].copy(), rgb[..., 1].copy(), rgb[..., 2].copy()
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    d = np.maximum(np.subtract(mx, mn), 1e-6)
    h = np.multiply(np.where(mx == r, np.mod(np.divide(np.subtract(g, b), d), 6.0),
                             np.where(mx == g, np.add(np.divide(np.subtract(b, r), d), 2.0),
                                      np.add(np.divide(np.subtract(r, g), d), 4.0))), 60.0)
    return h, np.divide(d, np.maximum(mx, 1e-6)), mx


# Cap's colours (see the sheet's palette) have hues 0-50 degrees (fur, gold, tongue), 130 (a green prop) and 200-230 (navy
# and blue): nothing between 262 and 350, the magenta to pink-purple of the backgrounds Kling is asked to draw. Anything
# that hue and saturated is therefore background, or background smeared into Cap by motion blur and video compression.
PINK_HUES = (262.0, 350.0)


def pinkish(rgb):
    h, s, v = hue_sat_val(rgb)
    return np.logical_and(np.logical_and(np.greater_equal(h, PINK_HUES[0]), np.less_equal(h, PINK_HUES[1])),
                          np.logical_and(np.greater(s, 0.22), np.greater(v, 0.25)))


def _spread(rgb, seeds, reach):
    """Cap's colour carried outward from the seed pixels, one ring at a time, `reach` rings at most."""
    F = np.where(seeds[..., None], rgb, 0).astype(np.float32)
    have = seeds.copy()
    for _ in range(reach):
        acc = np.zeros_like(F)
        cnt = np.zeros(seeds.shape, np.float32)
        weighted = _op(np.multiply, F, have[..., None].astype(np.float32))
        solid = have.astype(np.float32)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy or dx:
                    np.add(acc, np.roll(np.roll(weighted, dy, 0), dx, 1), out=acc)
                    np.add(cnt, np.roll(np.roll(solid, dy, 0), dx, 1), out=cnt)
        new = np.logical_and(np.logical_not(have), np.greater(cnt, 0))
        F[new] = np.divide(acc[new], cnt[new][:, None])
        np.logical_or(have, new, out=have)
    return F, have


def key_frame(rgb, bg, tau=0.07, near=4, reach=6):
    """RGB (0..1, h x w x 3) on a flat background of colour `bg` -> RGBA. Any flat background colour will do.

    Background is any pixel whose colour lies on the line from black to the background colour (the background itself,
    a slightly lighter or darker patch of it, and the soft ground shadow some models add: a darker copy of the same
    colour), within `tau`. Cap's colours never do: even a brown close to a rose background is off that line. Pixels
    more than `near` pixels from any background are Cap: fully opaque and untouched, so his navy and cream can't drift.
    The thin band between is part Cap, part background: its coverage is how far a pixel lies along the line from the
    background colour to the colour of the Cap beside it, and the background's share is subtracted back out of its
    colour, so there is no halo. Features thinner than the band (fur tips, tripod legs, sparkles) take their colour
    from their most distinct pixels.
    """
    B = np.asarray(bg, dtype=np.float32)
    scale = np.divide(_op(np.multiply, rgb, B).sum(-1), float(B @ B))          # how much of B this pixel is
    off = _op(np.subtract, rgb, _op(np.multiply, scale[..., None], B))          # what is left over
    resid = np.sqrt(_op(np.multiply, off, off).sum(-1))
    is_bg = np.logical_and(np.logical_and(np.less(resid, tau), np.greater(scale, 0.5)), np.less(scale, 1.2))
    bg_hue = float(hue_sat_val(B.reshape(1, 1, 3))[0][0, 0])
    if PINK_HUES[0] <= bg_hue <= PINK_HUES[1]:                                 # a pink background: its smears are background too
        is_bg = np.logical_or(is_bg, pinkish(rgb))
    near_bg = _grow(is_bg, near)
    core = np.logical_not(near_bg)
    F, have = _spread(rgb, core, reach)
    band = np.logical_and(near_bg, np.logical_not(is_bg))
    thin = np.logical_and(np.logical_and(band, np.logical_not(have)), np.greater(resid, 0.2))   # nothing solid nearby
    F2, have2 = _spread(rgb, thin, 2)
    use2 = np.logical_and(np.logical_not(have), have2)
    F = np.where(use2[..., None], F2, F)
    have = np.logical_or(have, have2)
    diff = _op(np.subtract, rgb, B)
    along = _op(np.subtract, F, B)
    num = _op(np.multiply, diff, along).sum(-1)
    den = _op(np.multiply, along, along).sum(-1)
    alpha = np.where(have, np.clip(np.divide(num, np.maximum(den, 1e-4)), 0, 1), np.clip(np.divide(resid, 0.3), 0, 1))
    alpha = np.where(core, 1.0, np.where(is_bg, 0.0, alpha)).astype(np.float32)
    a3 = alpha[..., None]
    behind = _op(np.multiply, np.subtract(1.0, a3), B)                          # the background's share of each pixel
    unmixed = np.clip(np.divide(_op(np.subtract, rgb, behind), np.maximum(a3, 0.1)), 0, 1)
    # Edge pixels take the colour of the Cap just inside them (the art is flat colour, so that is what they were before the
    # background bled in); only where no Cap is near enough do they fall back to subtracting the background out.
    fg = np.where(core[..., None], rgb, np.where(have[..., None], F, unmixed))
    return np.dstack([fg, alpha]).astype(np.float32)


def border_background(rgb):
    """The background colour of a frame: the median of its outer 6 px ring."""
    ring = np.concatenate([rgb[:6].reshape(-1, 3), rgb[-6:].reshape(-1, 3), rgb[:, :6].reshape(-1, 3), rgb[:, -6:].reshape(-1, 3)])
    return np.median(ring, axis=0)


def selftest(pose):
    """Key the magenta start frame back out and compare with the true alpha: how clean is the cut-out itself?"""
    start = np.asarray(Image.open(prep(pose)).convert("RGB")).astype(np.float32) / 255
    truth = np.asarray(Image.open(pose_png(pose)).convert("RGBA")).astype(np.float32) / 255
    bg = border_background(start)
    keyed = key_frame(start, bg)[PAD:PAD + POSE, PAD:PAD + POSE]
    err = np.abs(keyed[..., 3] - truth[..., 3])
    edge = (truth[..., 3] > 0.02) & (truth[..., 3] < 0.98)
    # Colour error where it is visible, premultiplied, so invisible pixels count for nothing.
    pm = np.abs(keyed[..., :3] * keyed[..., 3:] - truth[..., :3] * truth[..., 3:]).mean(-1)
    print(f"{pose}: background estimated {np.round(bg * 255).astype(int).tolist()}")
    print(f"  alpha error: mean {err.mean():.4f}, 99.9th percentile {np.percentile(err, 99.9):.3f}, pixels off by more than 0.1: {int((err > 0.1).sum())}")
    print(f"  edge pixels: {int(edge.sum())}, mean alpha error there {err[edge].mean():.3f}; premultiplied colour error {pm.mean():.5f}")
    out = BUILD / "selftest"
    out.mkdir(parents=True, exist_ok=True)
    img = Image.fromarray((keyed * 255).astype(np.uint8), "RGBA")
    img.save(out / f"{pose}-keyed.png")
    for name, colour in (("dark", (11, 18, 34)), ("light", (244, 247, 251))):
        base = Image.new("RGBA", (POSE, POSE), colour + (255,))
        base.alpha_composite(img)
        base.convert("RGB").save(out / f"{pose}-{name}.png")
    return err.mean()


# ---- fal ------------------------------------------------------------------------------------------------------------

def data_uri(path):
    return "data:image/png;base64," + base64.b64encode(Path(path).read_bytes()).decode()


def seedance_cost(secs, side=720, fps=24):          # (width x height x fps x seconds) / 1024 tokens, $0.0214 per 1000
    return side * side * fps * secs / 1024 / 1000 * 0.0214


# estimate is dollars for the clip as requested; body builds the request from the start image (and the end image, the same)
MODELS = {
    "kling4": dict(ep="kling/v4/image-to-video", secs=5, est=lambda: 0.157 * 5,
                   body=lambda a, b, p: {"start_image_url": a, "end_image_url": b, "prompt": p, "duration": 5, "resolution": "720p"}),
    "seedance25": dict(ep="bytedance/seedance-2.5/image-to-video", secs=4, est=lambda: seedance_cost(4),
                       body=lambda a, b, p: {"image_url": a, "end_image_url": b, "prompt": p, "duration": 4, "resolution": "720p",
                                             "aspect_ratio": "1:1", "generate_audio": False}),
    "flux3max": dict(ep="blackforestlabs/flux-3-max/keyframes-to-video", secs=5, est=lambda: 0.02125 * 5 * 2,
                     body=lambda a, b, p: {"keyframes": [{"image_url": a, "frame_index": 0}, {"image_url": b, "frame_index": 120}],
                                           "prompt": p, "duration": 5, "resolution": "720p", "aspect_ratio": "1:1", "generate_audio": False}),
    "h3max": dict(ep="minimax/h3-max/image-to-video", secs=5, est=lambda: 0.0325 * 5 * 1.5,
                  body=lambda a, b, p: {"image_url": a, "end_image_url": b, "prompt": p, "duration": 5, "resolution": "768P",
                                        "prompt_expansion_mode": "disabled"}),
    "wan3prime": dict(ep="alibaba/wan-3.0-prime/image-to-video", secs=5, est=lambda: 0.05 * 5 * 1.5,
                      body=lambda a, b, p: {"start_image_url": a, "end_image_url": b, "prompt": p, "duration": 5, "resolution": "720p",
                                            "aspect_ratio": "1:1", "audio": False}),
    "gemini": dict(ep="google/gemini-omni-flash/v1.1/image-to-video", secs=5, est=lambda: 0.03 * 5 * 1.5, wide=True,
                   body=lambda a, b, p: {"image_url": a, "end_image_url": b, "prompt": p, "duration": 5, "resolution": "720p",
                                         "aspect_ratio": "16:9"}),
    "pixelcut": dict(ep="pixelcut/looping-video", secs=5, est=lambda: 0.08 * 5 * 1.5,
                     body=lambda a, b, p: {"image_url": a, "prompt": p, "duration": 5, "motion": "subtle", "resolution": "768p",
                                           "include_audio": False}),
}


def ledger_entries():
    path = BUILD / "ledger.jsonl"
    return [json.loads(l) for l in path.read_text().splitlines() if l.strip()] if path.exists() else []


def spent():
    return sum(e["est"] for e in ledger_entries() if e.get("event") == "submit")


def log(entry):
    BUILD.mkdir(parents=True, exist_ok=True)
    with open(BUILD / "ledger.jsonl", "a") as f:
        f.write(json.dumps(entry) + "\n")


def fal(url, data=None):
    headers = {"Authorization": f"Key {os.environ['FAL_KEY']}", "Content-Type": "application/json"}
    req = urllib.request.Request(url, data=json.dumps(data).encode() if data is not None else None, headers=headers,
                                 method="POST" if data is not None else "GET")
    with urllib.request.urlopen(req, timeout=300) as f:
        return json.load(f)


def reserve(clip, spec, est):
    """Check the spend cap and log the submission in one locked step, so runs started together can't all pass the check."""
    import fcntl
    BUILD.mkdir(parents=True, exist_ok=True)
    with open(BUILD / "ledger.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        total = spent()
        if total + est > BUDGET:
            print(f"{clip}: REFUSED. Spent so far (estimated) ${total:.2f} + ${est:.2f} would pass the ${BUDGET:.2f} cap.")
            return False
        log({"event": "submit", "clip": clip, "endpoint": spec["ep"], "est": round(est, 4), "at": time.strftime("%H:%M:%S")})
        return True


def gen(pose, model, take=1):
    spec = MODELS[model]
    clip = f"{pose}-{model}-{take}"
    est = spec["est"]() * MARGIN
    start = BUILD / "start" / (f"{pose}-16x9.png" if spec.get("wide") else f"{pose}.png")
    if not start.exists():
        prep(pose)
    img = data_uri(start)
    body = spec["body"](img, img, PROMPTS[pose])
    if not reserve(clip, spec, est):
        return None
    t0 = time.time()
    try:
        q = fal(f"https://queue.fal.run/{spec['ep']}", body)
        for _ in range(400):
            st = fal(q["status_url"])
            if st["status"] == "COMPLETED":
                break
            time.sleep(4)
        out = fal(q["response_url"])
        url = (out.get("video") or {}).get("url") or next(v["url"] for v in out.values() if isinstance(v, dict) and "url" in v)
        raw = BUILD / "raw"
        raw.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(url, raw / f"{clip}.mp4")
        info = {k: v for k, v in out.items() if k not in ("video",) and not isinstance(v, (dict, list))}
        log({"event": "done", "clip": clip, "secs": round(time.time() - t0), "extra": info})
        print(f"{clip}: ok in {round(time.time() - t0)} s, est ${est:.2f}", flush=True)
        return clip
    except Exception as e:
        detail = e.read().decode()[:500] if hasattr(e, "read") else ""
        log({"event": "failed", "clip": clip, "error": f"{e} {detail}"[:700]})
        print(f"{clip}: FAILED {e} {detail}", flush=True)
        return None


# ---- keying a clip, numbers, packing --------------------------------------------------------------------------------

def probe_fps(mp4):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=avg_frame_rate",
                          "-of", "csv=p=0", str(mp4)], capture_output=True, text=True).stdout.strip()
    n, d = out.split("/")
    return float(n) / float(d)


def bbox(mask):
    ys, xs = np.where(mask)
    return (int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())) if len(xs) else (0, 0, 0, 0)


def key_clip(clip):
    """Raw mp4 -> keyed RGBA frames on disk, then the numbers read back from those frames."""
    raw = BUILD / "raw" / f"{clip}.mp4"
    work = BUILD / "frames" / clip
    for sub in ("src", "rgba"):
        (work / sub).mkdir(parents=True, exist_ok=True)
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(raw), "-vsync", "0", str(work / "src/%04d.png")], check=True)
    frames = sorted((work / "src").glob("*.png"))
    first = np.asarray(Image.open(frames[0]).convert("RGB")).astype(np.float32) / 255
    h, w = first.shape[:2]
    bg = border_background(first)
    crop = None
    if w != h:                                   # 16:9: the middle square, where the pose sits
        x0 = (w - h) // 2
        crop = (x0, 0, x0 + h, h)
    for i, path in enumerate(frames):
        im = Image.open(path).convert("RGB")
        if crop:
            im = im.crop(crop)
        rgb = np.asarray(im).astype(np.float32) / 255
        rgba = key_frame(rgb, border_background(rgb))                # per frame: some models let the background drift
        img = Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")
        if img.size != (CANVAS, CANVAS):
            img = img.resize((CANVAS, CANVAS), Image.LANCZOS)
        img.save(work / "rgba" / f"{i + 1:04d}.png")
    metrics = measure(clip, work, len(frames), probe_fps(raw), [w, h], bg)
    (work / "metrics.json").write_text(json.dumps(metrics))
    print(json.dumps(metrics))
    return metrics


def measure(clip, work, count, fps, size, bg):
    """Numbers from the saved frames. Every array is built into its own buffer: with Python 3.14 and NumPy 2.2 an
    expression like `pm - prev` can overwrite `pm` in place (the interpreter lends NumPy a reference it counts as a
    temporary), and the first version of this check silently measured corrupted frames."""
    files = sorted((work / "rgba").glob("*.png"))

    def load(path):
        return np.asarray(Image.open(path).convert("RGBA")).astype(np.float64) / 255.0

    def premultiplied(f):
        out = np.empty(f.shape[:2] + (3,))
        np.multiply(f[..., :3], f[..., 3:4], out=out)
        return out

    def mad(x, y):                                # mean absolute difference, through an explicit output buffer
        buf = np.empty_like(x)
        np.subtract(x, y, out=buf)
        np.abs(buf, out=buf)
        return float(buf.mean())

    pose_file = pose_png(clip.split("-")[0])
    still_box = None
    if pose_file.exists():                                              # clips of other mascots have no pose to compare with
        still = np.asarray(Image.open(pose_file).convert("RGBA"))[..., 3] > 127
        still_box = bbox(np.pad(still, PAD, constant_values=False))     # where prep() put the pose in the 720 frame
    diffs, drift, haze = [], [], []
    prev = base = first_pm = last_pm = first_box = None
    for k, path in enumerate(files):
        f = load(path)
        pm = premultiplied(f)
        if prev is not None:
            diffs.append(mad(pm, prev))
        prev = pm.copy()
        alpha = f[..., 3].copy()
        haze.append(float(((alpha > 0.004) & (alpha < 0.08)).mean()))
        solid = alpha > 0.95
        colour = f[..., :3][solid].mean(0) if solid.any() else np.zeros(3)
        base = colour.copy() if base is None else base
        drift.append(float(np.abs(colour - base).max()))
        if k == 0:
            first_pm = pm.copy()
            first_box = bbox(alpha > 0.5)
        last_pm = pm.copy()
    seam = mad(last_pm, first_pm)
    med = float(np.median(diffs)) if diffs else 0.0
    return {"clip": clip, "frames": count, "fps": round(fps, 2), "size": size,
            "background": np.round(bg * 255).astype(int).tolist(),
            "seam": round(seam, 5), "step_median": round(med, 5), "seam_ratio": round(seam / med, 2) if med else None,
            "colour_drift_max": round(max(drift), 4), "haze": round(float(np.mean(haze)), 5),
            # how far the first frame's Cap sits from the still's, in pixels of the 720 frame, and his size against it
            "align": ({"dx": round((first_box[0] + first_box[2]) / 2 - (still_box[0] + still_box[2]) / 2, 1),
                       "dy": round((first_box[1] + first_box[3]) / 2 - (still_box[1] + still_box[3]) / 2, 1),
                       "size": round((first_box[2] - first_box[0]) / max(still_box[2] - still_box[0], 1), 3)} if still_box else {"dx": 0, "dy": 0, "size": 1})}


def pack_clip(clip, show=480):
    work = BUILD / "frames" / clip
    out = BUILD / "out"
    out.mkdir(parents=True, exist_ok=True)
    metrics = json.loads((work / "metrics.json").read_text())
    fps = metrics["fps"]
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-framerate", str(fps), "-i", str(work / "rgba/%04d.png"),
                    "-vf", f"scale={show}:{show}:flags=lanczos,format=yuva420p", "-c:v", "libwebp_anim", "-lossless", "0", "-q:v", "62",
                    "-compression_level", "5", "-loop", "0", str(out / f"{clip}.webp")], check=True)
    frames = sorted((work / "rgba").glob("*.png"))
    pick = [frames[int(i * (len(frames) - 1) / 11)] for i in range(12)]
    cell = 240
    sheet = Image.new("RGB", (cell * 6, cell * 2), (128, 128, 128))
    for k, path in enumerate(pick):
        im = Image.open(path).convert("RGBA").resize((cell, cell), Image.LANCZOS)
        tile = Image.new("RGBA", (cell, cell), (128, 128, 128, 255))
        tile.alpha_composite(im)
        sheet.paste(tile.convert("RGB"), ((k % 6) * cell, (k // 6) * cell))
    sheet.save(out / f"{clip}-strip.jpg", quality=86)
    print(f"{clip}: {(out / f'{clip}.webp').stat().st_size // 1024} KB webp")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("prep", "selftest"):
        sub.add_parser(name).add_argument("poses", nargs="+")
    g = sub.add_parser("gen"); g.add_argument("pose"); g.add_argument("model"); g.add_argument("--take", type=int, default=1)
    for name in ("key", "pack"):
        sub.add_parser(name).add_argument("clips", nargs="+")
    sub.add_parser("ledger")
    a = ap.parse_args()
    if a.cmd == "prep":
        for p in a.poses: print(prep(p))
    elif a.cmd == "selftest":
        for p in a.poses: selftest(p)
    elif a.cmd == "gen":
        gen(a.pose, a.model, a.take)
    elif a.cmd == "key":
        for c in a.clips: key_clip(c)
    elif a.cmd == "pack":
        for c in a.clips: pack_clip(c)
    elif a.cmd == "ledger":
        for e in ledger_entries(): print(json.dumps(e))
        print(f"estimated spend (with a {MARGIN}x margin): ${spent():.2f} of ${BUDGET:.2f}")


if __name__ == "__main__":
    main()
