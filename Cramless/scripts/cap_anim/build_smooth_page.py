#!/usr/bin/env python3
"""Builds the review page for Cap's smoothed clips: build/review/cap-smooth/index.html.

Before and after, side by side over the app's night blue, for every clip whose missing pictures were drawn (`produce.py smooth`).
Both sides are read back from the HEVC files with the app's own decoder (hevc_frames.swift), so the right side is what the phone
plays. The numbers are the ones `produce.py check` counted on the keyed takes (frames/<take>/qa.json, frames/<take>s/qa.json).

    build_smooth_page.py [--notes notes.json] [id ...]       notes.json: {"summary": [...], "ask": [...]}
"""
import html, json, shutil, subprocess, sys
from pathlib import Path

import build_alive_page as alive
import produce as p

HERE = Path(__file__).resolve().parent
ROOT = p.ROOT
OUT = ROOT / "build/review/cap-smooth"
WORK = p.PROD / "smooth-compare"
BEFORE = p.PROD / "final-before-smooth"
NIGHT = "0x0B1222"
DEFAULT = ["wave", "almost", "sleepy", "sleepyPoke", "sleepPoke", "mic", "scanPoke", "tuckInPoke"]

WORDS = {
    "wave": "Cap's hello on the welcome screen",
    "almost": "the \"Almost\" reaction in a session",
    "sleepy": "Cap sleepy",
    "mic": "Cap holding a microphone",
    "sleepyPoke": "what Cap does when you tap him while he is sleepy",
    "sleepPoke": "what Cap does when you tap him while he sleeps",
    "scanPoke": "what Cap does when you tap him while he scans",
    "tuckInPoke": "what Cap does when you tap him while he tucks the sky in",
}

EXTRA_CSS = """
  .films.wide { grid-template-columns: 1fr; justify-items: center; }
  figure.wide { width: 100%; max-width: 680px; }
  figure.wide video { max-width: 680px; aspect-ratio: 2 / 1; border-radius: 16px; }
  .rate { width: 100%; border-collapse: collapse; margin: 10px 0 4px; font-variant-numeric: tabular-nums; }
  .rate th, .rate td { text-align: left; padding: 7px 8px; border-bottom: 1px solid var(--line); font-size: 14px; }
  .rate th { color: var(--ink3); font-weight: 600; font-size: 12px; text-transform: uppercase; letter-spacing: .04em; }
  .rate td.n { text-align: right; }
  .rate td.better { color: var(--accent, inherit); font-weight: 600; }
"""


def esc(s):
    return html.escape(str(s), quote=True)


def tool(name):
    """A Swift tool of this folder, compiled once."""
    exe = p.PROD / "bin" / name
    source = HERE / f"{name}.swift"
    if not exe.exists() or exe.stat().st_mtime < source.stat().st_mtime:
        exe.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["swiftc", "-O", str(source), "-o", str(exe)], check=True)
    return exe


def decode(mov, dst):
    shutil.rmtree(dst, ignore_errors=True)
    subprocess.run([str(tool("hevc_frames")), str(mov), str(dst), "all"], check=True, capture_output=True)
    return len(list(dst.glob("*.png")))


def run(*cmd):
    subprocess.run(["simq", "run", "media", "--", *map(str, cmd)], check=True)


def film(clip_id):
    """build/review/cap-smooth/smooth-<id>.mp4: before on the left, after on the right; plus half speed, poster and fallbacks.
    Left as it is when it is newer than the clip in the app (the page's words can change without making every film again)."""
    name = f"smooth-{clip_id}"
    shipped = p.PROD / "final" / f"cap-{clip_id}.mov"
    if (OUT / f"{name}.mp4").exists() and (OUT / "alt" / f"{name}-small-half.mp4").exists() \
            and (OUT / f"{name}.mp4").stat().st_mtime > shipped.stat().st_mtime:
        return name
    old, new = WORK / clip_id / "old", WORK / clip_id / "new"
    decode(BEFORE / f"cap-{clip_id}.mov", old)
    decode(p.PROD / "final" / f"cap-{clip_id}.mov", new)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "alt").mkdir(exist_ok=True)
    graph = (f"color=c={NIGHT}:s=720x720:r=24[bgl];color=c={NIGHT}:s=720x720:r=24[bgr];"
             "[bgl][0:v]overlay=shortest=1[l];[bgr][1:v]overlay=shortest=1[r];[l][r]hstack,scale=1080:540:flags=lanczos,format=yuv420p[v]")
    run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-framerate", "24", "-i", old / "%04d.png", "-framerate", "24",
        "-i", new / "%04d.png", "-filter_complex", graph, "-map", "[v]", "-r", "24", "-c:v", "libx264", "-preset", "medium", "-crf", "20",
        "-profile:v", "high", "-level", "4.0", "-movflags", "+faststart", OUT / f"{name}.mp4")
    run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", OUT / f"{name}.mp4", "-vf", "setpts=2*PTS,fps=24", "-c:v", "libx264",
        "-preset", "medium", "-crf", "20", "-profile:v", "high", "-level", "4.0", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
        OUT / f"{name}-half.mp4")
    run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-ss", "1.2", "-i", OUT / f"{name}.mp4", "-frames:v", "1", "-q:v", "3", OUT / f"{name}.jpg")
    for suffix in ("", "-half"):
        src = OUT / f"{name}{suffix}.mp4"
        run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", src, "-c:v", "hevc_videotoolbox", "-q:v", "60", "-pix_fmt", "yuv420p",
            "-tag:v", "hvc1", "-movflags", "+faststart", OUT / "alt" / f"{name}-hevc{suffix}.mp4")
        run("ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", src, "-vf", "scale=720:-2:flags=lanczos", "-c:v", "libx264",
            "-profile:v", "main", "-level", "3.1", "-crf", "26", "-pix_fmt", "yuv420p", "-movflags", "+faststart", OUT / "alt" / f"{name}-small{suffix}.mp4")
    return name


def rates(clip_id):
    """(before, after, take): pictures a second as `produce.py check` counted them."""
    entry = next(c for c in json.loads((p.PROD / "manifest.json").read_text())["clips"] if c["id"] == clip_id)
    after_take = entry["source"]
    before_take = after_take[:-1] if after_take.endswith("c") else after_take        # scrubbed (`produce.py scrub`), after smoothed
    before_take = before_take[:-1] if before_take.endswith("s") else before_take      # smoothed (`produce.py smooth`)
    qa = lambda take: json.loads((p.PROD / "frames" / take / "qa.json").read_text())
    return qa(before_take)["pictures_per_second"], qa(after_take)["pictures_per_second"], before_take


def main():
    notes = {}
    if "--notes" in sys.argv:
        notes = json.loads(Path(sys.argv[sys.argv.index("--notes") + 1]).read_text())
    ids = [a for a in sys.argv[1:] if not a.startswith("--") and not a.endswith(".json")] or DEFAULT
    OUT.mkdir(parents=True, exist_ok=True)
    rows, cards = [], []
    for clip_id in ids:
        name = film(clip_id)
        before, after, take = rates(clip_id)
        rows.append(f"<tr><td>{esc(clip_id)}</td><td>{esc(WORDS.get(clip_id, ''))}</td><td class=\"n\">{before:g}</td><td class=\"n better\">{after:g}</td></tr>")
        card = alive.film_card_in(OUT, name, f"{clip_id}: before | after",
                                  f"{WORDS.get(clip_id, clip_id).capitalize()}. Left: what you had, {before:g} new pictures a second. "
                                  f"Right: now, {after:g}.", {name})
        cards.append(card.replace("<figure data-base=", '<figure class="wide" data-base=', 1))
    app = notes.get("app", {})
    app_card = ""
    if (OUT / "welcome.mp4").exists():
        words = "The welcome screen as the app plays it, in the Simulator at 60 frames a second."
        if app:
            words += (f" Counted on the recordings, the wave showed about {app['before']:g} different pictures a second before and about "
                      f"{app['after']:g} now.")
        app_card = alive.film_card_in(OUT, "welcome", "In the app: the welcome screen", words, {"welcome"})
    head = alive.TEMPLATE[:alive.TEMPLATE.index("<body>")].replace("<title>Cap is alive</title>", "<title>Smoother Cap</title>")
    head = head.replace("</style>", EXTRA_CSS + "</style>")
    script = alive.TEMPLATE[alive.TEMPLATE.index("<script>"):]
    body = f"""<body>
<main data-bg="night">
  <div class="eyebrow">Cap · Oct 25, 2026</div>
  <h1>Cap's wave was choppy: why, and the fix</h1>
  <p>Eight of Cap's clips were drawn on twos or threes: the video model changed the picture only every 2nd or 3rd frame and held it in between,
  so a 24 frames-a-second file moved 8 or 12 times a second. That is fine on a cinema screen and choppy on a 120 Hz phone. The missing pictures
  are now drawn between the real ones.</p>
  <nav><a href="#inapp">In the app</a><a href="#films">Before and after</a><a href="#rates">The numbers</a><a href="#how">How</a><a href="#ask">What I need from you</a></nav>

  <div class="card"><strong>What was done</strong><ul>{"".join(f"<li>{s}</li>" for s in notes.get("summary", []))}</ul></div>

  <h2 id="inapp">In the app</h2>
  <div class="films">{app_card}</div>

  <h2 id="films">Before and after</h2>
  <p>Each film is the clip over the app's night blue, the old one on the left and the new one on the right, both read back from the
  files the app plays. Use half speed to see the steps.</p>
  <div class="films wide">{"".join(cards)}</div>

  <h2 id="rates">The numbers</h2>
  <p>New pictures a second: how many frames differ from the one before, counted on the clip's frames. A clip that moves on every frame
  would read 24; stretches where Cap holds still count as no new picture, so none reads exactly 24.</p>
  <table class="rate"><thead><tr><th>Clip</th><th>Where</th><th class="n">Before</th><th class="n">Now</th></tr></thead><tbody>{"".join(rows)}</tbody></table>
  <p>The other 30 clips already moved on every frame.</p>

  <h2 id="how">How</h2>
  <div class="card"><ul>
    <li><strong>Found:</strong> the frames of each clip were compared one with the next. In these eight, every second or third step was close to zero.</li>
    <li><strong>Fixed:</strong> the frames that are really new are kept exactly as they were; each frame in between is drawn from the two around it by
    Apple's frame-rate conversion (optical flow), on the video model's own frames, and then cut out of its background like every other frame.</li>
    <li><strong>A flaw found on the way:</strong> a key frame the model had smeared (pink round a fast paw) is left out and that stretch is drawn from the
    clean pictures around it. The old wave had two of them. All 38 clips were then scanned for the same smear: scanPoke's raised paw had it
    on four frames (a mauve paw and a salmon lump on the arm, in the clip you had before too). Those frames are recoloured from the fur
    beside them, with every shape kept.</li>
    <li><strong>Nothing else changed:</strong> same length, same start and end on Cap's still, same look. The eight clips are about 0.5 MB bigger in all, because they hold more distinct pictures (16.7 MB of clips instead of 16.2).</li>
    <li><strong>Next time:</strong> <code>produce.py check</code> now counts pictures a second and warns when a clip is drawn on twos or threes.</li>
  </ul></div>

  <h2 id="ask">What I need from you</h2>
  <div class="card ask"><ul>{"".join(f"<li>{s}</li>" for s in notes.get("ask", []))}</ul></div>
  <p class="foot">Nothing is committed. If a film shows a crossed-out play icon on your phone, "Open file" is the same film, and the page then tries a second and a third encoding by itself.</p>
</main>
"""
    (OUT / "index.html").write_text(head + body + script)
    print("wrote", OUT / "index.html", f"({len(ids)} clips)")


if __name__ == "__main__":
    main()
