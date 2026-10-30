#!/usr/bin/env python3
"""Background plates for the rebuilt picks: the model paints only the scenery (no words, no UI, no character) at the largest size fal
allows, and code puts everything exact on top (store_ring.py).

    lockbox run FAL_KEY -- python3 -P scripts/store_art/gpt/run_plates.py [--only ring-card,ring-header] [--force]
    python3 -P scripts/store_art/gpt/run_plates.py --dry          # the briefs, sizes and the estimate; no key, no network

fal's limit is 8.29 MP, so a 3:2 card is asked at 3520x2352 (the compositor scales it to Apple's 3840x2560) and the 21:9 header at
3840x1648 (cropped to 1646). The concept the owner picked goes in as image 1, so the plate keeps its sky, mountains and lake.
Raw pictures land in build/store-art/gpt/plates/, one line per job in ledger.jsonl.
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks  # noqa: E402
import run_fal as rf  # noqa: E402

PLATES = os.path.join(looks.OUT_DIR, "plates")

COMMON = (
    "Image 1 is a finished store banner for a study app. Paint the clean BACKGROUND PLATE for it: only the landscape of image 1, in "
    "exactly the same illustration style, palette, lighting and mood (painterly flat vector, soft simple shading, soft glows), "
    "filling the whole canvas edge to edge with no border, frame or rounded corners.\n"
    "KEEP from image 1: the deep navy night sky with fine stars of different sizes (more of them toward the top) and a faint soft "
    "blue haze like a Milky Way; a few small four-point gold sparkle stars near the edges; layered dark blue mountain ridges with "
    "soft mist between them; a still lake that mirrors the sky with soft warm golden glints; dark pine-tree silhouettes along the "
    "left and right edges.\n"
    "REMOVE completely: every word and number, the big glowing ring, all frosted-glass cards, the capybara, the telescope and "
    "tripod, the foreground rocks, and any interface element. Nothing stands in the foreground.\n"
    "PALETTE: night navy #14213D, deep night #0B1220, sky blue #7CC8FF, sun yellow #FFCF3F in tiny sparkles only, a touch of warm "
    "amber at the horizon.\n"
    "RULES: no characters, no people, no animals, no text of any kind, no letters, no numbers, no logos, no watermarks, no circles "
    "or rings, no moon, no sun."
)

JOBS = {
    "ring-card": dict(
        size=(3520, 2352), ref="concept_ring_card.jpg",
        prompt=COMMON + "\nCOMPOSITION: 3:2 landscape. The far shore and the mountain ridges sit at about 68% of the height; the lake "
        "fills the bottom third. The middle of the picture, the central 60% of the width and the central 45% of the height, is calm, "
        "dark, low-detail sky with only tiny sparse stars, because large text and graphics will be added there later. Put the "
        "brighter details (sparkles, glints, the warm horizon glow) toward the edges and along the horizon."),
    "ring-header": dict(
        size=(3840, 1648), ref="concept_ring_header.jpg",
        prompt=COMMON + "\nCOMPOSITION: ultra-wide 21:9 band. The far shore and the mountain ridges sit at about 72% of the height; "
        "the lake fills the bottom quarter. The middle of the picture, the central 55% of the width and the central 50% of the "
        "height, is calm, dark, low-detail sky with only tiny sparse stars, because large text and graphics will be added there "
        "later. Put the brighter details (sparkles, glints, the warm horizon glow) toward the edges and along the horizon."),
}


def ref_path(job):
    return os.path.join(looks.REFS_DIR, job["ref"])


def make_refs():
    """JPEG copies of the picked concepts (the endpoint is sent small JPEGs, as for the concepts)."""
    from PIL import Image
    for jid, src in (("concept_ring_card.jpg", "ring-card.png"), ("concept_ring_header.jpg", "ring-header.png")):
        dst = os.path.join(looks.REFS_DIR, jid)
        if not os.path.exists(dst):
            Image.open(os.path.join(looks.OUT_DIR, "out", src)).convert("RGB").save(dst, quality=90, optimize=True)


def render(jid, job, key, quality, est):
    t0 = time.time()
    body = {"prompt": job["prompt"], "image_size": {"width": job["size"][0], "height": job["size"][1]}, "quality": quality,
            "num_images": 1, "output_format": "png", "image_urls": [rf.data_uri(ref_path(job))]}
    rec = {"id": f"plate-{jid}", "endpoint": rf.EDIT, "size": job["size"], "quality": quality, "est_usd": est}
    for attempt in (1, 2):
        try:
            q = rf.call(f"https://queue.fal.run/{rf.EDIT}", key, body, "POST")
            for _ in range(900):
                st = rf.call(q["status_url"], key)
                if st.get("status") == "COMPLETED":
                    break
                time.sleep(4)
            res = rf.call(q["response_url"], key)
            path = os.path.join(PLATES, f"{jid}.png")
            urllib.request.urlretrieve(res["images"][0]["url"], path)
            from PIL import Image
            rec.update(ok=True, got=list(Image.open(path).size), secs=round(time.time() - t0))
            break
        except urllib.error.HTTPError as e:
            rec.update(ok=False, error=rf.err_text(e))
            if e.code < 500:
                break
        except Exception as e:
            rec.update(ok=False, error=rf.err_text(e))
    with rf.LOCK:
        with open(rf.LEDGER, "a") as f:
            f.write(json.dumps(rec) + "\n")
        print(json.dumps({k: v for k, v in rec.items() if k != "endpoint"}), flush=True)
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--quality", default="high", choices=("low", "medium", "high", "xhigh", "max"))
    ap.add_argument("--budget", type=float, default=4.0, help="stop starting jobs past this many US dollars (by the estimate)")
    ap.add_argument("--per-mp", type=float, default=0.17, help="assumed US dollars per megapixel at high quality (an assumption)")
    a = ap.parse_args()
    os.makedirs(PLATES, exist_ok=True)
    make_refs()
    with open(os.path.join(PLATES, "prompts.json"), "w") as f:
        json.dump({k: v["prompt"] for k, v in JOBS.items()}, f, indent=1)
    only = [s for s in a.only.split(",") if s]
    todo = [(k, v) for k, v in JOBS.items() if (not only or k in only) and (a.force or not os.path.exists(os.path.join(PLATES, f"{k}.png")))]
    run, spent = [], 0.0
    for k, v in todo:
        e = round(v["size"][0] * v["size"][1] / 1e6 * a.per_mp, 3)
        if spent + e > a.budget:
            print(f"budget: skipping {k} (would pass ${a.budget:.2f})")
            continue
        run.append((k, v, e))
        spent += e
    print(f"{len(run)} plates, estimated ${spent:.2f} (assumed ${a.per_mp:.3f}/MP at {a.quality}; budget ${a.budget:.2f})")
    for k, v, e in run:
        print(f"  {k:12s} {v['size'][0]}x{v['size'][1]} = {v['size'][0] * v['size'][1] / 1e6:.2f} MP  ~${e:.2f}  ref {os.path.getsize(ref_path(v)) // 1024} KB")
    if a.dry or not run:
        return 0
    key = os.environ.get("FAL_KEY")
    if not key:
        sys.exit("FAL_KEY is not in the environment: run this through `lockbox run FAL_KEY -- ...`")
    with ThreadPoolExecutor(max_workers=2) as ex:
        results = list(ex.map(lambda r: render(r[0], r[1], key, a.quality, r[2]), run))
    ok = sum(1 for r in results if r.get("ok"))
    print(f"done: {ok}/{len(results)} ok, estimated ${sum(r['est_usd'] for r in results if r.get('ok')):.2f} spent")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
