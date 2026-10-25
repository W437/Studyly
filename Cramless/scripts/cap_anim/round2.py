#!/usr/bin/env python3
"""Round 2 of the Cap animation work: a character sheet, Kling 4.0 animations that use it, and other mascots.

    round2.py img <set> [--only name ...] [--force]    run an image job set (see JOB_SETS) with GPT Image 2.5 on fal
    round2.py contact <glob> <out.jpg> [--cols N]      a labelled contact sheet of images, to look at
    round2.py kling <pose> <take> [--no-sheet]         one Kling 4.0 reference-to-video clip: Cap as an element
    round2.py key <clip> | pack <clip>                 the same cut-out and packing as cap_anim.py, in build/cap-anim2
    round2.py ledger                                   what this round has spent

Everything lands in build/cap-anim2/. The spend cap is BUDGET (estimated, with a margin), shared by every command,
and each run is logged before it is sent.
"""
import argparse, base64, io, json, os, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

import cap_anim as ca

ROOT = ca.ROOT
B2 = ROOT / "build/cap-anim2"
BRAND = ROOT.parent / "docs/rethink/brand/raw"
ASSETS = ca.ASSETS
BUDGET = 12.0           # the cap I set for this round (the owner gave no number): estimated dollars, margin included
MARGIN = 1.2
IMG_EP = "openai/gpt-image-2.5/sunburst/edit"
TXT_EP = "openai/gpt-image-2.5/sunburst/text-to-image"
PRICE = {"low": 0.0059, "medium": 0.0132, "high": 0.0527}      # 1024 x 1024; each reference image adds about $0.008
ca.BUILD = B2                                                  # cap_anim's key/pack/prep now work inside this round


# ---- ledger ---------------------------------------------------------------------------------------------------------

def entries():
    path = B2 / "ledger.jsonl"
    return [json.loads(l) for l in path.read_text().splitlines() if l.strip()] if path.exists() else []


def spent():
    return sum(e["est"] for e in entries() if e.get("event") == "submit")


def log(entry):
    B2.mkdir(parents=True, exist_ok=True)
    with open(B2 / "ledger.jsonl", "a") as f:
        f.write(json.dumps(entry) + "\n")


def reserve(name, endpoint, est):
    import fcntl
    B2.mkdir(parents=True, exist_ok=True)
    with open(B2 / "ledger.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        total = spent()
        if total + est > BUDGET:
            print(f"{name}: REFUSED. Spent so far (estimated) ${total:.2f} + ${est:.2f} would pass the ${BUDGET:.2f} cap.", flush=True)
            return False
        log({"event": "submit", "name": name, "endpoint": endpoint, "est": round(est, 4), "at": time.strftime("%H:%M:%S")})
        return True


# ---- fal helpers ----------------------------------------------------------------------------------------------------

def data_uri(path, max_side=None, jpeg=False):
    """A file as a data URI. Transparent art goes onto white; references are shrunk and sent as JPEG to keep requests small."""
    im = Image.open(path)
    if im.mode in ("RGBA", "LA", "P"):
        im = im.convert("RGBA")
        white = Image.new("RGB", im.size, (255, 255, 255))
        white.paste(im, mask=im.split()[3])
        im = white
    im = im.convert("RGB")
    if max_side:
        im.thumbnail((max_side, max_side), Image.LANCZOS)
    buf = io.BytesIO()
    if jpeg:
        im.save(buf, "JPEG", quality=93)
        return "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
    im.save(buf, "PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def queue(endpoint, body, name, minutes=14):
    q = ca.fal(f"https://queue.fal.run/{endpoint}", body)
    for _ in range(int(minutes * 15)):
        if ca.fal(q["status_url"])["status"] == "COMPLETED":
            break
        time.sleep(4)
    return ca.fal(q["response_url"])


def image_job(job, force=False):
    """job: name, prompt, refs (paths), size (w, h), quality, dir. Writes build/cap-anim2/<dir>/<name>.png."""
    out = B2 / job.get("dir", "images") / f"{job['name']}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists() and not force:
        print(f"{job['name']}: exists, skipped", flush=True)
        return out
    refs = [Path(r) for r in job.get("refs", [])]
    w, h = job.get("size", (1024, 1024))
    quality = job.get("quality", "high")
    est = (PRICE[quality] * (w * h) / (1024 * 1024) ** 1 * 0.9 + 0.008 * len(refs)) * MARGIN
    body = {"prompt": job["prompt"], "image_size": {"width": w, "height": h}, "quality": quality, "num_images": 1, "output_format": "png"}
    endpoint = TXT_EP
    if refs:
        body["image_urls"] = [data_uri(r, max_side=768, jpeg=True) for r in refs]
        endpoint = IMG_EP
    if not reserve(job["name"], endpoint, est):
        return None
    t0 = time.time()
    try:
        result = queue(endpoint, body, job["name"])
        urllib.request.urlretrieve(result["images"][0]["url"], out)
        log({"event": "done", "name": job["name"], "secs": round(time.time() - t0)})
        print(f"{job['name']}: ok in {round(time.time() - t0)} s (est ${est:.2f})", flush=True)
        return out
    except Exception as e:
        detail = e.read().decode()[:400] if hasattr(e, "read") else ""
        log({"event": "failed", "name": job["name"], "error": f"{e} {detail}"[:600]})
        print(f"{job['name']}: FAILED {e} {detail}", flush=True)
        return None


def run_images(jobs, force=False, workers=5):
    with ThreadPoolExecutor(max_workers=workers) as ex:
        return list(ex.map(lambda j: image_job(j, force), jobs))


# ---- the character sheet --------------------------------------------------------------------------------------------

def pose(name):
    return ASSETS / f"Cap-{name}.imageset/cap-{name}.png"


# Cap as the earlier art defined him: the canonical bust, a standing pose, a side view, open eyes, a yawn with a tongue.
BASE_REFS = [BRAND / "cramless-capy.png", pose("wave"), pose("stargaze"), pose("study"), pose("sleepy")]

LOOK = ("The same capybara mascot as in the reference images, named Cap: identical design in every detail. Chunky rounded "
        "body in warm tangerine-brown fur with a few darker brown fur strokes, a broad darker brown muzzle with two dark "
        "nostrils and a small curved mouth line, small round ears with a brown inner, off-white cream over-ear headphones "
        "with a taupe inner cup and brown rim, and a navy graduation mortarboard with a short gold tassel. Flat vector "
        "mascot illustration with the same colours, the same soft simple shading and the same level of detail as the "
        "references, no outline around the character. Plain pure white background, no shadow, no ground, nothing else "
        "in the image, no text or letters anywhere. ")
BODY = ("Full body, standing upright on his hind legs, arms relaxed at his sides, feet side by side, calm default "
        "expression: closed content arc eyes and a small closed smile. Centred with a generous margin. ")


def turnaround(takes=(1, 2)):
    views = {
        "front": "Seen exactly from the FRONT. ",
        "threeq": "Turned three-quarters to his left, so we see the front of his chest and his right cheek, the same pose and proportions as the front view. ",
        "side": "Seen in pure SIDE PROFILE facing right, the same pose and proportions as the front view, with the snout, ear and headphone in profile. ",
        "back": "Seen from the BACK, the same pose and proportions as the front view: the back of the mortarboard with the tassel hanging at his left side, the headphone band over his head, the fur on his back and the soles of his hind feet. ",
    }
    return [{"name": f"turn-{v}-{t}", "dir": "sheet", "refs": BASE_REFS, "prompt": LOOK + BODY + text}
            for v, text in views.items() for t in takes]


FACE = ("Head and shoulders only, in a three-quarter front view with the same framing, size and angle in every panel, "
        "centred with a generous margin. ")
EXPRESSIONS = {
    "content": "Default calm face: closed content arc eyes, a small closed smile.",
    "open": "Eyes open: large round dark brown eyes, each with one small white highlight and no eyebrows, a small closed smile, calm and attentive.",
    "wink": "A playful wink: one eye a closed arc, the other open and round with a white highlight, a small smile.",
    "laugh": "Laughing out loud: happy closed arc eyes, the mouth wide open showing two small rounded cream-white upper front teeth and a soft pink tongue with a faint centre line.",
    "yawn": "A big sleepy yawn: eyes closed, the mouth a large open oval with a pink tongue and the two small cream upper front teeth visible.",
    "surprised": "Surprised and delighted: eyes wide open and round with white highlights, the mouth a small round open O showing a little pink tongue.",
    "thinking": "Thinking it over: eyes open and looking up and to the side, the mouth a small flat curve, the head tilted a little.",
    "notyet": "A kind 'not yet' face, never sad: warm open eyes, a gentle small smile, the head tilted slightly, encouraging.",
    "sleepy": "Nearly asleep: eyes closed in soft downward arcs, a tiny relaxed smile, the mortarboard slightly askew.",
    "proud": "Quietly proud: happy closed arc eyes, the chin lifted a little, a confident gentle smile.",
}
DETAILS = {
    "teeth": "Extreme close-up of Cap's open mouth in a laugh, seen from the front: the broad dark brown muzzle, two small rounded cream-white upper front teeth, a soft pink tongue with a faint centre line, the dark nostrils above. Fills the frame.",
    "eyes": "Close-up of the upper half of Cap's face from the front, showing both eyes OPEN: large round dark brown eyes, each with one small white highlight and no eyebrows, the brown inner of both small ears, the headphone cups and the brim of the mortarboard. Fills the frame.",
    "eyes_closed": "Close-up of the upper half of Cap's face from the front, showing both eyes CLOSED in happy arcs (his default content look), the brown inner of both small ears, the headphone cups and the brim of the mortarboard. Fills the frame.",
    "paws": "Two studies side by side on white: Cap's front paw, open, in dark brown with three small rounded toes and soft pads, and one hind foot with three toes. Close-up, flat vector, the same fur colour on the leg.",
    "hat": "Two studies side by side on white: the navy graduation mortarboard with its gold tassel, and the cream over-ear headphones with the taupe inner cup and brown rim, each shown from three-quarters, isolated, no character.",
}


def expressions(refs):
    jobs = [{"name": f"expr-{k}", "dir": "sheet", "refs": refs, "prompt": LOOK + FACE + text} for k, text in EXPRESSIONS.items()]
    jobs += [{"name": f"detail-{k}", "dir": "sheet", "refs": refs, "prompt": LOOK + text} for k, text in DETAILS.items()]
    return jobs


# ---- other directions -----------------------------------------------------------------------------------------------

SCENE = ("Cap the capybara, the same character as in the reference images (navy graduation mortarboard with a gold "
         "tassel, cream headphones, tangerine-brown fur, broad brown muzzle, calm content closed arc eyes), standing and "
         "waving hello with one front paw, full body, centred on a soft plain pale-blue background. ")
STYLES = {
    "plush3d": "Redrawn as a soft 3D rendered plush toy, like a premium animated film character: velvety fur texture, gentle studio lighting, shallow soft shadow, rounded squishy forms.",
    "watercolor": "Redrawn as a hand-painted children's storybook watercolor and gouache illustration: visible brush strokes, soft bleeding edges, paper texture, warm muted colours.",
    "sticker": "Redrawn as a bold glossy sticker: thick clean white outline all round, saturated colours, strong simple highlights, a very slight drop shadow, super readable at small sizes.",
    "geometric": "Redrawn as a minimal geometric mascot built from a few perfect circles, rounded rectangles and semicircles, five flat colours only, no shading, no fur strokes, very modern.",
    "clay": "Redrawn as a handmade claymation / stop-motion figure: modelled plasticine with soft fingerprint texture, tiny imperfections, warm studio lighting, shallow depth of field.",
    "pixel": "Redrawn as detailed pixel art, a 64 by 64 pixel sprite scaled up with crisp square pixels, a limited 16-colour palette, retro game style.",
    "papercut": "Redrawn as a layered paper-cut collage: flat coloured paper shapes stacked with soft shadows between the layers, visible paper grain.",
    "chibi": "Redrawn as a super-cute chibi kawaii character: a very large round head, a tiny round body, rosy cheeks, big sparkly eyes (open, with highlights), soft pastel shading.",
    "lineart": "Redrawn as an elegant editorial line illustration: confident single-weight dark navy line art with only one warm orange accent fill, lots of white space, sophisticated and calm.",
    "knit": "Redrawn as a hand-knitted amigurumi crochet toy: visible yarn stitches, felt eyes, a tiny felt mortarboard, soft woolly texture, warm light.",
}
MASCOT_BASE = ("A friendly mascot character for a calm, kind study app for students who want to remember what they learn. "
               "Warm, a little wise, never guilt-tripping, never hyper. Full body, standing or sitting happily, centred on a "
               "soft plain pale-blue background, flat vector mascot illustration with soft simple shading and no outline, "
               "clean and charming, no text or letters. ")
MASCOTS = {
    "otter": "An otter named Otto: sleek warm brown fur, cream chest, a cosy teal scarf, a pencil tucked behind one small ear, and an open notebook held on his tummy as if floating on his back in calm water.",
    "redpanda": "A red panda named Ruby: russet and cream fur with the ringed tail, small round glasses, a tiny satchel, holding a stack of index cards and smiling softly.",
    "axolotl": "An axolotl named Axel: soft pink with feathery gills, a gentle smile and tiny arms, wearing a little yellow backpack and a small floppy sun hat of knitted wool.",
    "hedgehog": "A hedgehog named Hazel: round and cosy, quills tipped with colourful bookmarks, tiny reading glasses on her nose, reading a small open book with a warm smile.",
    "firefly": "A tiny firefly named Glim: a round friendly little face and big kind eyes, small translucent wings, and a soft warm glowing lantern belly that shines golden; it glows brighter the more you remember. Floating gently in a calm night.",
    "star": "A little star named Nova: a plump rounded five-pointed star with a sleepy-sweet face, rosy cheeks, tiny stubby arms and legs, glowing softly in pale gold; it dims gently when a memory is fading and shines when remembered.",
    "moth": "A soft fluffy moth named Mo: a round fuzzy body, big feathery antennae, large dusty-lavender wings with tiny constellation dots, a gentle sleepy smile, resting on a stack of index cards.",
    "koala": "A koala named Kiki: grey fluffy fur, big round ears, a calm sleepy smile, a tiny graduation cap and a hot mug of tea held in both paws, sitting on a pile of cushions.",
}


def directions(style_refs, takes=1):
    jobs = []
    for k, text in STYLES.items():
        jobs.append({"name": f"style-{k}", "dir": "directions", "refs": style_refs, "prompt": SCENE + text + " No text or letters anywhere."})
    for k, text in MASCOTS.items():
        jobs.append({"name": f"mascot-{k}", "dir": "directions", "refs": [], "prompt": MASCOT_BASE + text})
    return jobs


# ---- Kling 4.0 with Cap as an element --------------------------------------------------------------------------------

KLING_LOOK = (" Keep Cap exactly as the character element defines him: the same face, ears, teeth, tongue, eyes, fur, navy "
              "mortarboard with its gold tassel and cream headphones, in a flat vector illustration style. The background is one "
              "solid flat magenta (#FF00FF) in every frame, with no shadow, no gradient and no other objects. Static locked "
              "camera, no zoom, no pan. He stays the same size and in the same place. Soft, gentle, natural motion. By the end he "
              "has returned to exactly the pose of the first frame.")
KLING_PROMPTS = {
    "wave": "@Element1 is Cap, a friendly flat-vector capybara mascot. As in the first frame he stands facing us and waves hello with his raised paw: three small relaxed waves with a warm closed-mouth smile and happy closed arc eyes; on the third wave he opens his round eyes for a moment and then closes them again." + KLING_LOOK,
    "stargaze": "@Element1 is Cap, a friendly flat-vector capybara mascot, as in the first frame looking through a golden telescope on a wooden tripod. A very subtle idle loop: slow breathing so his chest and shoulders rise and fall a little, a tiny ear twitch, and the small yellow stars beside the telescope twinkle gently. The telescope and tripod stay perfectly still and rigid; his eye stays a happy closed arc." + KLING_LOOK,
    "celebrate": "@Element1 is Cap, a friendly flat-vector capybara mascot, as in the first frame mid-jump in celebration. He does one joyful hop with both arms up, laughing out loud with his mouth open showing his two small upper teeth and pink tongue, as defined in the element; the colourful confetti pieces from the first frame flutter and drift down slowly (no new confetti). He lands softly and settles back to the first frame's pose." + KLING_LOOK,
    "nice": "@Element1 is Cap, a friendly flat-vector capybara mascot, as in the first frame with a small fist pump. A quick happy cheer: one little hop and a firm fist pump with a proud closed-mouth grin and happy closed arc eyes, then he settles back to the first frame's pose." + KLING_LOOK,
    "sleep": "@Element1 is Cap, a friendly flat-vector capybara mascot, as in the first frame fast asleep on a pile of index cards. A very subtle sleeping loop: slow, deep breathing so his back rises and falls, an occasional tiny ear twitch. His eyes stay closed." + KLING_LOOK,
}


def element_files(pick):
    """Cap as a Kling element: the front view, and three other views (up to three allowed). Picks are file names in sheet/."""
    s = B2 / "sheet"
    return {"frontal": s / f"{pick['front']}.png", "refs": [s / f"{pick[k]}.png" for k in ("threeq", "side", "face")],
            "extra": [s / f"{n}.png" for n in pick.get("extra", [])]}


def kling_clip(pose_name, take, pick, seconds=5):
    clip = f"{pose_name}-kling4ref-{take}"
    start = ca.prep(pose_name)
    el = element_files(pick)
    uri = lambda p, jpeg=False: data_uri(p, max_side=1024, jpeg=jpeg)
    body = {"prompt": KLING_PROMPTS[pose_name], "duration": seconds, "resolution": "720p", "aspect_ratio": "1:1",
            "start_image_url": data_uri(start),
            "elements": [{"frontal_image_url": uri(el["frontal"], True), "reference_image_urls": [uri(p, True) for p in el["refs"]]}]}
    if el["extra"]:
        body["image_urls"] = [uri(p, True) for p in el["extra"][:8]]
    est = 0.157 * seconds * MARGIN
    ep = "kling/v4/reference-to-video"
    if not reserve(clip, ep, est):
        return None
    t0 = time.time()
    try:
        result = queue(ep, body, clip, minutes=18)
        url = (result.get("video") or {}).get("url")
        raw = B2 / "raw"
        raw.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(url, raw / f"{clip}.mp4")
        log({"event": "done", "name": clip, "secs": round(time.time() - t0)})
        print(f"{clip}: ok in {round(time.time() - t0)} s (est ${est:.2f})", flush=True)
        return clip
    except Exception as e:
        detail = e.read().decode()[:500] if hasattr(e, "read") else ""
        log({"event": "failed", "name": clip, "error": f"{e} {detail}"[:700]})
        print(f"{clip}: FAILED {e} {detail}", flush=True)
        return None


def kling_i2v(clip, start_path, prompt, seconds=5):
    """Kling 4.0 image-to-video with the picture as both the first and the last frame (a loop). No character sheet."""
    uri = data_uri(start_path)
    body = {"start_image_url": uri, "end_image_url": uri, "prompt": prompt, "duration": seconds, "resolution": "720p"}
    est = 0.157 * seconds * MARGIN
    ep = "kling/v4/image-to-video"
    if not reserve(clip, ep, est):
        return None
    t0 = time.time()
    try:
        result = queue(ep, body, clip, minutes=18)
        raw = B2 / "raw"
        raw.mkdir(parents=True, exist_ok=True)
        urllib.request.urlretrieve(result["video"]["url"], raw / f"{clip}.mp4")
        log({"event": "done", "name": clip, "secs": round(time.time() - t0)})
        print(f"{clip}: ok in {round(time.time() - t0)} s (est ${est:.2f})", flush=True)
        return clip
    except Exception as e:
        detail = e.read().decode()[:500] if hasattr(e, "read") else ""
        log({"event": "failed", "name": clip, "error": f"{e} {detail}"[:700]})
        print(f"{clip}: FAILED {e} {detail}", flush=True)
        return None


I2V_PROMPTS = {
    "nice": "Cap, a friendly flat-vector capybara mascot, as in the first frame with a small raised fist. A quick happy cheer: one little hop and a firm fist pump with a proud closed-mouth grin and happy closed arc eyes, then he settles back to exactly the first frame's pose. Keep him exactly as drawn: the same face, ears, fur, navy mortarboard with its gold tassel and cream headphones, in a flat vector illustration style. The background is one solid flat magenta (#FF00FF) in every frame, with no shadow, no gradient and no other objects. Static locked camera, no zoom, no pan; he stays the same size and in the same place.",
    "style-plush3d": "A soft 3D plush capybara toy wearing a navy graduation cap with a gold tassel and cream headphones waves hello with one paw: three gentle, relaxed waves with a warm smile, his plush body swaying a little, then he settles back to exactly the first frame's pose. Premium animated-film quality, the same soft fur, the same colours, one solid flat magenta (#FF00FF) background in every frame, no floor, no shadow. Static locked camera, no zoom.",
    "mascot-firefly": "A tiny friendly firefly floats gently in place in a calm night: it bobs softly up and down, its translucent wings flutter lightly, and the warm golden glow of its lantern belly slowly swells brighter and then dims again, like breathing. Everything else stays still, the camera is locked, and by the end it is back in exactly the first frame's pose and glow.",
}


# ---- contact sheets -------------------------------------------------------------------------------------------------

def contact(paths, out, cols=4, cell=320):
    font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 15)
    rows = (len(paths) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 22)), (245, 245, 245))
    d = ImageDraw.Draw(sheet)
    for i, p in enumerate(paths):
        im = Image.open(p).convert("RGBA")
        bg = Image.new("RGBA", im.size, (255, 255, 255, 255)); bg.alpha_composite(im)
        im = bg.convert("RGB"); im.thumbnail((cell - 8, cell - 8), Image.LANCZOS)
        x, y = (i % cols) * cell, (i // cols) * (cell + 22)
        sheet.paste(im, (x + (cell - im.width) // 2, y + 20 + (cell - im.height) // 2))
        d.text((x + 6, y + 3), Path(p).stem, fill=(60, 60, 60), font=font)
    sheet.save(out, quality=88)
    print(out, sheet.size)


JOB_SETS = {"turnaround": lambda a: turnaround(), "directions": lambda a: directions(BASE_REFS[:3])}


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("img"); i.add_argument("set"); i.add_argument("--only", nargs="*"); i.add_argument("--force", action="store_true")
    i.add_argument("--front"); i.add_argument("--threeq")
    c = sub.add_parser("contact"); c.add_argument("glob"); c.add_argument("out"); c.add_argument("--cols", type=int, default=4)
    k = sub.add_parser("kling"); k.add_argument("pose"); k.add_argument("take", type=int); k.add_argument("--picks", default=str(B2 / "picks.json"))
    v = sub.add_parser("i2v"); v.add_argument("name"); v.add_argument("image")
    for name in ("key", "pack"):
        sub.add_parser(name).add_argument("clips", nargs="+")
    sub.add_parser("ledger")
    a = ap.parse_args()
    if a.cmd == "img":
        if a.set == "expressions":
            refs = [B2 / "sheet" / f"{a.front}.png", B2 / "sheet" / f"{a.threeq}.png"] + [BASE_REFS[0], BASE_REFS[3], BASE_REFS[4]]
            jobs = expressions(refs)
        else:
            jobs = JOB_SETS[a.set](a)
        if a.only:
            jobs = [j for j in jobs if j["name"] in a.only]
        run_images(jobs, a.force)
    elif a.cmd == "contact":
        import glob
        contact(sorted(glob.glob(a.glob)), a.out, a.cols)
    elif a.cmd == "i2v":
        kling_i2v(f"{a.name}-kling4-1", Path(a.image), I2V_PROMPTS[a.name])
    elif a.cmd == "kling":
        kling_clip(a.pose, a.take, json.loads(Path(a.picks).read_text()))
    elif a.cmd == "key":
        for c_ in a.clips: ca.key_clip(c_)
    elif a.cmd == "pack":
        for c_ in a.clips: ca.pack_clip(c_)
    elif a.cmd == "ledger":
        for e in entries(): print(json.dumps(e))
        print(f"estimated spend so far: ${spent():.2f} of ${BUDGET:.2f}")


if __name__ == "__main__":
    main()
