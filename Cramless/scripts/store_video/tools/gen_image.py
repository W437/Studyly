#!/usr/bin/env python3
"""Generates or edits images with GPT Image 2.5 (Sunburst) on fal: props, backgrounds,
fictional documents, textures. About $0.05 each. Only when an ad truly needs art the app
and the gallery can't give; the app's real screens always come from footage.

    python3 tools/gen_image.py jobs.json [ids…] --out sources/v6/art
    python3 tools/gen_image.py --edit src.png --prompt "…" --size 1024x1536 --dest out.png
    python3 tools/gen_image.py --example

jobs.json: [{"id": "desk", "prompt": "…", "size": [1024, 1536], "transparent": false}, …]
Keep every prompt and script in sources/v<N>/: generation isn't repeatable.
Everything invented stays fictional: no real brands, logos, people or replica system UIs.
Reads FAL_KEY from the environment; never prints it.
"""
import argparse
import base64
import concurrent.futures as cf
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

T2I = "openai/gpt-image-2.5/sunburst/text-to-image"
EDIT = "openai/gpt-image-2.5/sunburst/edit"
EXAMPLE = [
    {"id": "desk", "prompt": "A top-down photo of a light oak desk in soft morning window light, a coffee cup at the edge, "
                             "empty space in the middle, photorealistic, no text, no logos", "size": [1024, 1536]},
    {"id": "receipt", "prompt": "A crumpled paper receipt from a fictional cafe called 'Juniper Cafe', itemised, "
                                "isolated cut-out on a transparent background, photorealistic", "size": [1024, 1536], "transparent": True},
]


def body_for(prompt, w, h, transparent=False, image=None):
    b = {"prompt": prompt, "output_format": "png", "quality": "high", "image_size": {"width": w, "height": h}, "num_images": 1}
    if transparent:
        b["background"] = "transparent"
    if image:
        b["image_urls"] = ["data:image/png;base64," + base64.b64encode(open(image, "rb").read()).decode()]
    return b


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("jobs", nargs="?", help="jobs JSON")
    ap.add_argument("ids", nargs="*", help="only these ids")
    ap.add_argument("--out", default=".")
    ap.add_argument("--edit", help="a source image to edit (with --prompt, --size, --dest)")
    ap.add_argument("--prompt")
    ap.add_argument("--size", default="1024x1536")
    ap.add_argument("--dest")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--example", action="store_true")
    a = ap.parse_args()
    if a.example:
        print(json.dumps(EXAMPLE, indent=2))
        return
    if a.edit:
        if not (a.prompt and a.dest):
            ap.error("--edit needs --prompt and --dest")
        w, h = map(int, a.size.split("x"))
        print("1 edit ≈ $0.05")
        if a.dry_run:
            return
        import fal_queue
        res = fal_queue.run(EDIT, body_for(a.prompt, w, h, image=a.edit), poll=5)
        fal_queue.download(fal_queue.media_url(res, "images"), a.dest)
        print("saved", a.dest)
        return
    if not a.jobs:
        ap.error("a jobs JSON is required (or --edit / --example)")
    jobs = [j for j in json.load(open(a.jobs)) if not a.ids or j["id"] in a.ids]
    print(f"{len(jobs)} images ≈ ${0.05 * len(jobs):.2f}")
    if a.dry_run:
        return
    import fal_queue
    os.makedirs(a.out, exist_ok=True)

    def one(j):
        dest = os.path.join(a.out, j["id"] + ".png")
        if os.path.exists(dest):
            return dest + " kept"
        w, h = j.get("size", [1024, 1536])
        try:
            res = fal_queue.run(T2I, body_for(j["prompt"], w, h, j.get("transparent", False)), poll=5)
            return fal_queue.download(fal_queue.media_url(res, "images"), dest)
        except RuntimeError as e:
            return f"{dest} FAILED {e}"
    with cf.ThreadPoolExecutor(6) as ex:
        for line in ex.map(one, jobs):
            print(line, flush=True)


if __name__ == "__main__":
    main()
