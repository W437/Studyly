"""Render the brand prompt book (prompts.json) with GPT Image 2.5 on fal.

Usage: python3 generate.py [--candidates N] [job_id ...]   (no ids = every job without a PNG yet)
Needs FAL_KEY. Writes raw/<id>.png and appends to raw/log.jsonl. With --candidates N, renders each job N times into
raw/candidates/<id>-1.png … <id>-N.png to pick from; copy the pick to raw/<id>.png.
"""
import base64, json, os, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
book = json.load(open(os.path.join(HERE, "prompts.json")))
RAW = os.path.join(HERE, "raw")
os.makedirs(RAW, exist_ok=True)
H = {"Authorization": f"Key {os.environ['FAL_KEY']}", "Content-Type": "application/json"}


def req(url, data=None, method="GET"):
    r = urllib.request.Request(url, data=json.dumps(data).encode() if data is not None else None, headers=H, method=method)
    with urllib.request.urlopen(r, timeout=300) as f:
        return json.load(f)


def run(job, take=None):
    body = dict(book["defaults"])
    body["prompt"] = job["prompt"]
    endpoint = book["endpoint"]
    if "image_size" in job:
        body["image_size"] = job["image_size"]
    if job.get("transparent"):
        body["background"] = "transparent"
    if "ref" in job:  # reference-guided edit: keeps a character consistent across poses
        refs = job["ref"] if isinstance(job["ref"], list) else [job["ref"]]
        body["image_urls"] = []
        for ref in refs:
            with open(os.path.join(HERE, ref), "rb") as f:
                body["image_urls"].append("data:image/png;base64," + base64.b64encode(f.read()).decode())
        endpoint = book["edit_endpoint"]
    name = job["id"] if take is None else f"{job['id']}-{take}"
    folder = RAW if take is None else os.path.join(RAW, "candidates")
    os.makedirs(folder, exist_ok=True)
    t0 = time.time()
    try:
        q = req(f"https://queue.fal.run/{endpoint}", body, "POST")
        for _ in range(200):
            st = req(q["status_url"])["status"]
            if st == "COMPLETED":
                break
            time.sleep(3)
        out = req(q["response_url"])
        url = out["images"][0]["url"]
        path = os.path.join(folder, f"{name}.png")
        urllib.request.urlretrieve(url, path)
        rec = {"id": name, "ok": True, "secs": round(time.time() - t0), "path": path}
    except Exception as e:  # keep going; one failed job must not sink the batch
        detail = e.read().decode()[:400] if hasattr(e, "read") else ""
        rec = {"id": name, "ok": False, "error": f"{e} {detail}"}
    with open(os.path.join(RAW, "log.jsonl"), "a") as f:
        f.write(json.dumps(rec) + "\n")
    print(json.dumps(rec), flush=True)
    return rec


args = sys.argv[1:]
candidates = 1
if args[:1] == ["--candidates"]:
    candidates, args = int(args[1]), args[2:]
ids = set(args)
jobs = [j for j in book["jobs"] if (j["id"] in ids) or (not ids and not os.path.exists(os.path.join(RAW, f"{j['id']}.png")))]
work = [(j, None) for j in jobs] if candidates == 1 else [(j, k) for j in jobs for k in range(1, candidates + 1)]
print(f"rendering {len(work)} images for {len(jobs)} jobs", flush=True)
with ThreadPoolExecutor(max_workers=5) as ex:
    results = list(ex.map(lambda w: run(*w), work))
print(f"done: {sum(r['ok'] for r in results)}/{len(results)} ok")
