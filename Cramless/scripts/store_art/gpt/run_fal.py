#!/usr/bin/env python3
"""Renders the GPT Image 2.5 concept set on fal (openai/gpt-image-2.5/sunburst/edit: the real screens and Cap go in as references).

    lockbox run FAL_KEY -- python3 -P scripts/store_art/gpt/run_fal.py [--only night,ring] [--format card|header] [--force]
    python3 -P scripts/store_art/gpt/run_fal.py --dry         # the briefs, sizes and the estimate; no key, no network

The key comes from the environment (lockbox puts it there for this one command). Each job: POST to queue.fal.run, poll, download
the png into raw/, crop-to-fit into out/ (the exact ratio of Apple's size, at half its pixels), one line in ledger.jsonl.
fal does not publish this model's price, so the estimate is a stated assumption (--per-mp), replaced by fal's own pricing answer
when it gives one; the run refuses to start jobs past --budget by that estimate. Nothing is sent but the briefs and the references.
"""
import argparse
import base64
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import looks  # noqa: E402

EDIT = "openai/gpt-image-2.5/sunburst/edit"
TEXT = "openai/gpt-image-2.5/sunburst/text-to-image"
RAW = os.path.join(looks.OUT_DIR, "raw")
OUT = os.path.join(looks.OUT_DIR, "out")
LEDGER = os.path.join(looks.OUT_DIR, "ledger.jsonl")
LOCK = threading.Lock()


def call(url, key, body=None, method="GET", timeout=300):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method,
                                 headers={"Authorization": f"Key {key}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as f:
        return json.load(f)


def err_text(e):
    if hasattr(e, "read"):
        try:
            return f"{e} {e.read().decode()[:500]}"
        except Exception:
            pass
    return str(e)


def data_uri(path):
    with open(path, "rb") as f:
        return "data:image/jpeg;base64," + base64.b64encode(f.read()).decode()


def fit(im, size):
    """Cover-fit to `size`: scale until both sides are at least as large, then crop from the centre."""
    tw, th = size
    if im.size == (tw, th):
        return im
    s = max(tw / im.width, th / im.height)
    im = im.resize((max(tw, round(im.width * s)), max(th, round(im.height * s))), Image.LANCZOS)
    left, top = (im.width - tw) // 2, (im.height - th) // 2
    return im.crop((left, top, left + tw, top + th))


def probe_price(key):
    """Ask fal for this endpoint's price. Returns (usd, unit) or None; the answer's shape is not documented, so read it loosely."""
    try:
        d = call("https://api.fal.ai/v1/models/pricing?endpoint_id=" + EDIT, key, timeout=20)
    except Exception as e:
        print("pricing: no answer (" + err_text(e)[:120] + ")", flush=True)
        return None
    print("pricing answer:", json.dumps(d)[:400], flush=True)
    rows = d.get("prices") if isinstance(d, dict) else d
    for row in rows or []:
        if isinstance(row, dict) and "unit_price" in row:
            return float(row["unit_price"]), str(row.get("unit", ""))
    return None


def estimate(job, per_mp, per_image=None):
    if per_image is not None:
        return per_image
    w, h = job["size"]
    return round(w * h / 1e6 * per_mp, 3)


def render(job, key, quality, est):
    out_png = os.path.join(OUT, f"{job['id']}.png")
    t0 = time.time()
    body = {"prompt": job["prompt"], "image_size": {"width": job["size"][0], "height": job["size"][1]},
            "quality": quality, "num_images": 1, "output_format": "png"}
    endpoint = TEXT
    if job["refs"]:
        body["image_urls"] = [data_uri(p) for p in job["refs"]]
        endpoint = EDIT
    rec = {"id": job["id"], "endpoint": endpoint, "size": job["size"], "quality": quality, "est_usd": est}
    for attempt in (1, 2):
        try:
            q = call(f"https://queue.fal.run/{endpoint}", key, body, "POST")
            for _ in range(600):
                st = call(q["status_url"], key)
                if st.get("status") == "COMPLETED":
                    break
                time.sleep(3)
            res = call(q["response_url"], key)
            url = res["images"][0]["url"]
            raw_path = os.path.join(RAW, f"{job['id']}.png")
            urllib.request.urlretrieve(url, raw_path)
            im = Image.open(raw_path).convert("RGB")
            rec["got"] = list(im.size)
            fit(im, job["keep"]).save(out_png)
            rec.update(ok=True, secs=round(time.time() - t0))
            break
        except urllib.error.HTTPError as e:
            rec.update(ok=False, error=err_text(e))
            if e.code < 500:           # a refusal (moderation, a bad field) will not change on a retry
                break
        except Exception as e:
            rec.update(ok=False, error=err_text(e))
    with LOCK:
        with open(LEDGER, "a") as f:
            f.write(json.dumps(rec) + "\n")
        print(json.dumps({k: v for k, v in rec.items() if k != "endpoint"}), flush=True)
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="comma-separated look ids")
    ap.add_argument("--format", choices=("card", "header"))
    ap.add_argument("--force", action="store_true", help="render again even when out/<id>.png exists")
    ap.add_argument("--dry", action="store_true")
    ap.add_argument("--quality", default="high", choices=("low", "medium", "high", "xhigh", "max"))
    ap.add_argument("--budget", type=float, default=8.0, help="stop starting jobs past this many US dollars (by the estimate)")
    ap.add_argument("--per-mp", type=float, default=0.17, help="assumed US dollars per megapixel at high quality (an assumption)")
    ap.add_argument("--workers", type=int, default=4)
    a = ap.parse_args()

    for d in (RAW, OUT):
        os.makedirs(d, exist_ok=True)
    only = [s for s in a.only.split(",") if s]
    todo = looks.jobs(only or None, a.format)
    # the briefs, for the review page
    with open(os.path.join(looks.OUT_DIR, "prompts.json"), "w") as f:
        json.dump({j["id"]: j["prompt"] for j in looks.jobs()}, f, indent=1)
    todo = [j for j in todo if a.force or not os.path.exists(os.path.join(OUT, f"{j['id']}.png"))]

    key = os.environ.get("FAL_KEY")
    per_image = None
    if not a.dry:
        if not key:
            sys.exit("FAL_KEY is not in the environment: run this through `lockbox run FAL_KEY -- ...`")
        price = probe_price(key)
        if price and ("megapixel" in price[1].lower() or price[1].lower() == "mp"):
            a.per_mp = price[0]
        elif price and "image" in price[1].lower():
            per_image = price[0]
    run, spent = [], 0.0
    for j in todo:
        e = estimate(j, a.per_mp, per_image)
        if spent + e > a.budget:
            print(f"budget: skipping {j['id']} (would pass ${a.budget:.2f}; estimate so far ${spent:.2f})")
            continue
        run.append((j, e))
        spent += e
    print(f"{len(run)} of {len(todo)} jobs, estimated ${spent:.2f} (assumed ${a.per_mp:.3f}/MP at {a.quality}; budget ${a.budget:.2f})")
    if a.dry:
        for j, e in run:
            kb = sum(os.path.getsize(p) for p in j["refs"] if os.path.exists(p)) // 1024
            miss = [os.path.basename(p) for p in j["refs"] if not os.path.exists(p)]
            print(f"  {j['id']:18s} {j['size'][0]}x{j['size'][1]}  {len(j['refs'])} refs {kb} KB  ~${e:.2f}  {len(j['prompt'].split())} words"
                  + (f"  MISSING {miss}" if miss else ""))
        return 0
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        results = list(ex.map(lambda je: render(je[0], key, a.quality, je[1]), run))
    ok = sum(1 for r in results if r.get("ok"))
    print(f"done: {ok}/{len(results)} ok, estimated ${sum(r['est_usd'] for r in results if r.get('ok')):.2f} spent")
    return 0 if ok == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
