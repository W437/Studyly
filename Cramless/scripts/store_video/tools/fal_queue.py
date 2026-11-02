"""Tiny fal.ai queue client shared by gen_music.py, gen_sfx.py and gen_image.py.

Reads FAL_KEY from the environment only when a request is actually sent, and never
prints it. Standard library only.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

QUEUE = "https://queue.fal.run/"


def _key():
    key = os.environ.get("FAL_KEY")
    if not key:
        sys.exit("FAL_KEY is not set in the environment (it is never read from files or printed).")
    return key


def _req(url, data=None, key=None):
    body = json.dumps(data).encode() if data is not None else None
    r = urllib.request.Request(url, data=body, headers={"Authorization": "Key " + (key or _key()),
                                                        "Content-Type": "application/json"})
    with urllib.request.urlopen(r, timeout=300) as f:
        return json.loads(f.read())


def run(endpoint, body, poll=4.0, tries=150):
    """Submits to the queue, waits for completion, returns the result JSON.
    Raises RuntimeError with the service's message on failure (e.g. a flagged prompt)."""
    key = _key()
    try:
        sub = _req(QUEUE + endpoint, body, key)
        for _ in range(tries):
            time.sleep(poll)
            status = _req(sub["status_url"], key=key).get("status")
            if status == "COMPLETED":
                break
        else:
            raise RuntimeError("timed out waiting for the queue")
        return _req(sub["response_url"], key=key)
    except urllib.error.HTTPError as e:
        raise RuntimeError(f"HTTP {e.code}: {e.read().decode(errors='replace')[:400]}") from None


def download(url, dest):
    urllib.request.urlretrieve(url, dest)
    return dest


def media_url(result, *keys):
    """The first URL found under result[key]['url'] (audio, audio_file, images[0]…)."""
    for k in keys:
        v = result.get(k)
        if isinstance(v, list) and v:
            v = v[0]
        if isinstance(v, dict) and v.get("url"):
            return v["url"]
    raise RuntimeError(f"no media URL in result keys {list(result)}")
