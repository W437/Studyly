#!/usr/bin/env python3
"""Builds the review page for Cap in the app: build/review/cap-alive/index.html.

Reads the final clips (build/cap-clips/manifest.json, out/<id>-final.webp), the films scripts/cap_anim/films.sh made into
build/review/cap-alive/, and writes the page. The words are written here, by hand; the numbers come from the files.

    build_alive_page.py [--notes notes.json]     notes.json: {"summary": [...], "ask": [...], "film_notes": {"cast": "…"}}
"""
import html, json, shutil, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
PROD = ROOT / "build/cap-clips"
OUT = ROOT / "build/review/cap-alive"
CLIPS = json.loads((PROD / "manifest.json").read_text())["clips"]
BOOK = {c["id"]: c for c in json.loads((Path(__file__).parent / "clips.json").read_text())["clips"]}

FILMS = [
    ("cast", "Every pose, one after another",
     "All 19 poses in the Feel lab, in one view, so every change of pose is the app's real transition: the old clip melts away "
     "while the next drawing fades in, then the new clip plays. Waiting poses loop; reactions play once."),
    ("today-sky", "Today: Cap at his telescope", "The sky is yours; Cap breathes, blinks and twitches an ear while the stars twinkle."),
    ("today-done", "Today: the day's work done", "Proud, with a glint on his star."),
    ("today-rest", "Today: nothing due", "In the beanbag with his tea."),
    ("today-eve", "Today: exam eve, nothing left to do", "Asleep on the cards, with z's drifting up."),
    ("session", "A session", "Five right in a row, then partly, wrong and \"I don't know\": his cheer, his sparkles at five, "
     "\"Almost\", the kind \"Not yet\", and pointing at the answer."),
    ("summary", "The summary", "He arrives and celebrates, with the confetti."),
    ("welcome", "The welcome", "A wave hello, then he waits and waves again now and then."),
    ("cast-reduced", "The same cast with Reduce Motion on", "Cap is a drawing and a change of pose is a cross-fade."),
]


def esc(s):
    return html.escape(str(s), quote=True)


def film_card(name, title, note, available):
    return film_card_in(OUT, name, title, note, available)


def film_card_in(out, name, title, note, available):
    """One film's card for the review page in `out` (the other review pages share it)."""
    if name not in available:
        return ""
    half = (out / f"{name}-half.mp4").exists()
    return f"""
    <figure data-base="{name}">
      <video controls loop playsinline preload="metadata" poster="{name}.jpg"></video>
      <figcaption>
        <h3>{esc(title)}</h3>
        <p>{esc(note)}</p>
        <div class="row">
          {'<button class="speed" type="button" aria-pressed="false">Half speed</button>' if half else ''}
          <a class="open" href="{name}.mp4">Open file</a>
        </div>
        <p class="note" role="status" hidden></p>
      </figcaption>
    </figure>"""


def clip_card(c):
    cid = c["id"]
    entry = BOOK.get(cid, {})
    still = f"img/still-{c['pose']}.png"
    return f"""
    <article class="clip">
      <div class="stage"><img src="img/{cid}.webp" width="360" height="360" loading="lazy" decoding="async" alt="Cap, {esc(cid)}"></div>
      <h3>{esc(cid)}</h3>
      <p class="meta">{esc(c['role'])} · {c['duration']:.1f} s · {c['bytes'] / 1048576:.1f} MB</p>
      <p class="note">{esc(entry.get('action', ''))}</p>
    </article>"""


def main():
    notes = {}
    if "--notes" in sys.argv:
        notes = json.loads(Path(sys.argv[sys.argv.index("--notes") + 1]).read_text())
    (OUT / "img").mkdir(parents=True, exist_ok=True)
    for c in CLIPS:
        shutil.copy(PROD / "out" / f"{c['id']}-final.webp", OUT / "img" / f"{c['id']}.webp")
    available = {p.stem for p in OUT.glob("*.mp4") if not p.stem.endswith("-half")}
    films = "".join(film_card(n, t, notes.get("film_notes", {}).get(n, d), available) for n, t, d in FILMS)
    clips = "".join(clip_card(c) for c in sorted(CLIPS, key=lambda c: (c["role"], c["id"])))
    total = sum(c["bytes"] for c in CLIPS)
    page = (TEMPLATE.replace("{{FILMS}}", films).replace("{{CLIPS}}", clips)
            .replace("{{SUMMARY}}", "".join(f"<li>{s}</li>" for s in notes.get("summary", [])))
            .replace("{{ASK}}", "".join(f"<li>{s}</li>" for s in notes.get("ask", [])))
            .replace("{{COUNT}}", str(len(CLIPS))).replace("{{MB}}", f"{total / 1048576:.1f}"))
    (OUT / "index.html").write_text(page)
    print("wrote", OUT / "index.html", f"({len(available)} films, {len(CLIPS)} clips)")


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Cap is alive</title>
<style>
  :root { --bg: #F4F7FB; --surface: #FFFFFF; --ink: #14213D; --ink2: #56627A; --ink3: #6B7489; --line: #E3E8F0; --link: #1866AE; --tangerine: #FF7A1A; --night1: #0B1222; --night2: #1B2A4A; }
  @media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) { --bg: #0B1222; --surface: #151E30; --ink: #F1F4FA; --ink2: #A9B4C8; --ink3: #8B97AD; --line: #24304A; --link: #8FD0FF; } }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--ink); font: 16px/1.5 -apple-system, system-ui, sans-serif; }
  main { max-width: 1000px; margin: 0 auto; padding: 28px max(16px, env(safe-area-inset-right, 0px)) 80px max(16px, env(safe-area-inset-left, 0px)); }
  h1 { font-size: 30px; line-height: 1.15; margin: 4px 0 8px; }
  h2 { font-size: 24px; margin: 48px 0 6px; }
  h3 { font-size: 17px; margin: 8px 0 2px; }
  p { color: var(--ink2); margin: 0 0 12px; }
  a { color: var(--link); }
  ul { margin: 0; padding-left: 20px; color: var(--ink2); }
  li { margin: 7px 0; }
  .eyebrow { font-size: 13px; font-weight: 600; letter-spacing: .06em; text-transform: uppercase; color: var(--ink3); }
  .card { background: var(--surface); border: 1px solid var(--line); border-radius: 22px; padding: 16px 18px; margin: 18px 0; }
  .ask { border-left: 4px solid var(--tangerine); }
  nav { display: flex; gap: 8px; flex-wrap: wrap; margin: 16px 0 0; }
  nav a { display: inline-flex; align-items: center; min-height: 40px; padding: 0 16px; border-radius: 20px; border: 1px solid var(--line); background: var(--surface); color: var(--ink); text-decoration: none; font-weight: 600; font-size: 14px; }
  .films { display: grid; gap: 32px 24px; grid-template-columns: repeat(auto-fit, minmax(min(100%, 250px), 1fr)); align-items: start; margin-top: 12px; }
  figure { margin: 0; min-width: 0; display: grid; gap: 12px; justify-items: center; }
  video { width: 100%; max-width: 300px; aspect-ratio: 1206 / 2608; height: auto; display: block; border-radius: 30px; background: #000; border: 1px solid var(--line); }
  figcaption { width: 100%; max-width: 300px; min-width: 0; }
  figcaption p { font-size: 15px; }
  .row { display: flex; flex-wrap: wrap; align-items: center; gap: 8px 14px; }
  .speed { min-height: 44px; padding: 0 18px; border-radius: 22px; cursor: pointer; border: 1px solid var(--line); background: var(--surface); color: var(--ink); font: 600 15px/1 -apple-system, system-ui, sans-serif; }
  .speed[aria-pressed="true"] { background: var(--tangerine); border-color: var(--tangerine); color: #14213D; }
  .open { font-size: 14px; }
  .note { font-size: 14px; }
  .bgs { position: sticky; top: 0; z-index: 5; display: flex; gap: 8px; padding: 10px 0; background: var(--bg); align-items: center; flex-wrap: wrap; }
  .bgs span { font-size: 13px; color: var(--ink3); margin-right: 4px; }
  @media (max-width: 480px) { .bgs span { display: none; } }
  .bgs button { min-height: 38px; padding: 0 13px; border-radius: 20px; border: 1px solid var(--line); background: var(--surface); color: var(--ink); font: 600 14px/1 -apple-system, system-ui, sans-serif; cursor: pointer; }
  .bgs button[aria-pressed="true"] { background: var(--tangerine); border-color: var(--tangerine); color: #14213D; }
  .grid { display: grid; gap: 22px 18px; grid-template-columns: repeat(auto-fill, minmax(min(100%, 200px), 1fr)); margin-top: 10px; }
  .stage { aspect-ratio: 1; border-radius: 22px; overflow: hidden; border: 1px solid var(--line); display: grid; place-items: center; }
  .stage img { width: 100%; height: 100%; display: block; object-fit: contain; }
  main[data-bg="night"] .stage { background: linear-gradient(180deg, var(--night1), var(--night2)); }
  main[data-bg="light"] .stage { background: #F4F7FB; }
  main[data-bg="checker"] .stage { background: conic-gradient(#d9dde5 25%, #fff 0 50%, #d9dde5 0 75%, #fff 0) 0 0 / 24px 24px; }
  .meta { font-size: 13px; color: var(--ink3); margin: 0 0 6px; }
  a:focus-visible, button:focus-visible, video:focus-visible { outline: 3px solid var(--link); outline-offset: 3px; }
  .foot { margin-top: 40px; font-size: 14px; color: var(--ink3); }
</style>
</head>
<body>
<main data-bg="night">
  <div class="eyebrow">Cramless · Cap, in the app · Oct 24, 2026</div>
  <h1>Cap is alive</h1>
  <p>Every pose of Cap now moves, everywhere he appears in the app, with the same Cap you approved: made from his character sheet, on a transparent background, starting and ending on his drawing so nothing jumps.</p>
  <nav><a href="#films">The films</a><a href="#clips">All {{COUNT}} clips</a><a href="#ask">What I need from you</a></nav>

  <div class="card"><strong>What was done</strong><ul>{{SUMMARY}}</ul></div>

  <h2 id="films">In the app</h2>
  <p>Recorded in the simulator on the real app. Each has a half-speed button.</p>
  <div class="films">{{FILMS}}</div>

  <h2 id="clips">All {{COUNT}} clips ({{MB}} MB in the app)</h2>
  <p>Switch the background to see he is transparent. These are animated images; in the app they are HEVC video with an alpha channel.</p>
  <div class="bgs" role="group" aria-label="Background behind Cap">
    <span>Behind Cap:</span>
    <button type="button" data-bg="night" aria-pressed="true">Night sky</button>
    <button type="button" data-bg="light" aria-pressed="false">Light</button>
    <button type="button" data-bg="checker" aria-pressed="false">Checkerboard</button>
  </div>
  <div class="grid">{{CLIPS}}</div>

  <h2 id="ask">What I need from you</h2>
  <div class="card ask"><ul>{{ASK}}</ul></div>
  <p class="foot">Nothing is committed. The films are H.264 at 60 frames a second; if one shows a crossed-out play icon on your phone, "Open file" is the same film, and the page then tries a second and a third encoding by itself.</p>
</main>
<script>
  var main = document.querySelector('main');
  document.querySelectorAll('.bgs button').forEach(function (b) {
    b.addEventListener('click', function () {
      main.dataset.bg = b.dataset.bg;
      document.querySelectorAll('.bgs button').forEach(function (o) { o.setAttribute('aria-pressed', o === b ? 'true' : 'false'); });
    });
  });
  // Each film comes in three encodings: the standard one (H.264, full size), HEVC, and a smaller H.264. If the browser
  // refuses one, the page moves to the next and says which it shows.
  var VERSIONS = [
    { note: '', file: function (b, half) { return b + (half ? '-half' : '') + '.mp4'; } },
    { note: "Showing the HEVC version: this browser couldn't play the standard one.", file: function (b, half) { return 'alt/' + b + '-hevc' + (half ? '-half' : '') + '.mp4'; } },
    { note: "Showing the smaller version: this browser couldn't play the full-size ones.", file: function (b, half) { return 'alt/' + b + '-small' + (half ? '-half' : '') + '.mp4'; } }
  ];
  document.querySelectorAll('figure[data-base]').forEach(function (figure) {
    var base = figure.dataset.base, video = figure.querySelector('video'), button = figure.querySelector('.speed');
    var link = figure.querySelector('.open'), note = figure.querySelector('.note');
    var version = 0, half = false, wantsPlay = false;
    function show(resume) {
      var url = VERSIONS[version].file(base, half);
      video.src = url; video.load(); link.href = url;
      note.hidden = !VERSIONS[version].note; note.textContent = VERSIONS[version].note;
      if (resume) video.play().catch(function () {});
    }
    video.addEventListener('play', function () { wantsPlay = true; });
    video.addEventListener('error', function () {
      if (version < VERSIONS.length - 1) { version += 1; show(wantsPlay); }
      else { note.hidden = false; note.textContent = "This browser can't play this film (error " + (video.error ? video.error.code : '?') + '). Try "Open file".'; }
    });
    if (button) button.addEventListener('click', function () {
      var wasPlaying = !video.paused; half = !half;
      button.setAttribute('aria-pressed', half ? 'true' : 'false'); show(wasPlaying);
    });
    show(false);
  });
</script>
</body>
</html>
"""

if __name__ == "__main__":
    main()
