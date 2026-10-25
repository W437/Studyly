#!/usr/bin/env python3
"""Builds the review page for Today's hero as a world: build/review/hero-world/index.html.

Before and after stills of the same states, films of the world being tapped, and what each layer is. The look, the film players
and their fallbacks are build_alive_page.py's, as in build_touch_page.py.

    build_hero_page.py [--notes notes.json]     notes.json: {"summary": [...], "ask": [...], "film_notes": {"name": "…"}}
"""
import html, json, sys
from pathlib import Path

import build_alive_page as alive

ROOT = alive.ROOT
OUT = ROOT / "build/review/hero-world"

FILMS = [
    ("hero-live", "The world, and tapping it",
     "Tap a star: the camera glides to its constellation, Cap steps aside and one card offers to relight it. Close it, tap empty "
     "sky (a ripple), pick another, then tap Cap and he answers. The layers sway on their own here because the Simulator has no "
     "motion sensor; on the phone they follow how you tilt it."),
    ("hero-eve", "Exam eve", "One exam's region glows and everything else recedes. It holds still."),
    ("hero-empty", "Nothing studied yet", "Unlit outline constellations across the whole sky, ready to be lit. Tapping it only ripples."),
]

STILLS = [
    ("live", "A normal day"),
    ("examEve", "Exam eve"),
    ("empty", "Nothing studied yet"),
    ("done", "The day's work done"),
]

EXTRA_CSS = """
  .pair { display: grid; gap: 12px; grid-template-columns: 1fr 1fr; margin: 12px 0 22px; }
  .pair figure { margin: 0; display: grid; gap: 6px; }
  .pair img { width: 100%; height: auto; border-radius: 16px; border: 1px solid var(--line); display: block; }
  .pair figcaption { max-width: none; font-size: 13px; color: var(--ink3); text-align: center; }
  .layers { margin: 0; padding-left: 20px; color: var(--ink2); }
  .layers li { margin: 7px 0; }
"""


def esc(s):
    return html.escape(str(s), quote=True)


def stills_html():
    out = []
    for key, title in STILLS:
        before, after = OUT / f"before-{key}.jpg", OUT / f"after-{key}.jpg"
        if not (before.exists() and after.exists()):
            continue
        out.append(f"""
  <h3>{esc(title)}</h3>
  <div class="pair">
    <figure><img src="before-{key}.jpg" alt="Before: {esc(title)}" loading="lazy" decoding="async"><figcaption>Before</figcaption></figure>
    <figure><img src="after-{key}.jpg" alt="Now: {esc(title)}" loading="lazy" decoding="async"><figcaption>Now</figcaption></figure>
  </div>""")
    return "".join(out)


LAYERS = [
    "<strong>The dusk:</strong> violet high up, rose, and a little peach where the hills begin.",
    "<strong>A Milky Way</strong> across the sky, and <strong>240 faint stars</strong> at three depths. A few of them glint.",
    "<strong>A cloud of each course's colour</strong> behind its constellations, so the world reads as places before it reads as stars.",
    "<strong>Your stars, bigger and glowier</strong>: the brightest have a four-point glint, and the lines are a little heavier. A constellation you zoom into is lifted so even its dimmest stars show.",
    "<strong>A shooting star</strong> now and then.",
    "<strong>Hills</strong> lit along the ridge with a mist, and <strong>a lake</strong> that mirrors the brightest stars as broken ripples.",
    "<strong>Cap, large, standing on the shore</strong> and not small beside the sky. He answers a tap.",
    "<strong>Depth:</strong> tilt the phone and each layer moves by its own amount.",
]


def main():
    notes = {}
    if "--notes" in sys.argv:
        notes = json.loads(Path(sys.argv[sys.argv.index("--notes") + 1]).read_text())
    OUT.mkdir(parents=True, exist_ok=True)
    available = {p.stem for p in OUT.glob("*.mp4") if not p.stem.endswith("-half")}
    film_notes = notes.get("film_notes", {})
    films = "".join(alive.film_card_in(OUT, n, t, film_notes.get(n, d), available) for n, t, d in FILMS)

    head = alive.TEMPLATE[:alive.TEMPLATE.index("<body>")].replace("<title>Cap is alive</title>", "<title>Today's world</title>")
    head = head.replace("</style>", EXTRA_CSS + "</style>")
    script = alive.TEMPLATE[alive.TEMPLATE.index("<script>"):]
    body = f"""<body>
<main data-bg="night">
  <div class="eyebrow">Cramless · Today · Oct 25, 2026</div>
  <h1>Today's world</h1>
  <p>The hero is a place now, about half the screen: your sky across the whole width, with Cap standing in it, large, and a sky you can tap.</p>
  <nav><a href="#before">Before and now</a><a href="#films">Films</a><a href="#layers">What's in it</a><a href="#ask">What I need from you</a></nav>

  <div class="card"><strong>What was done</strong><ul>{"".join(f"<li>{s}</li>" for s in notes.get("summary", []))}</ul></div>

  <h2 id="before">Before and now</h2>
  <p>The same states, from the simulator. Left is what you had on your phone, right is the new hero.</p>
  {stills_html()}

  <h2 id="films">Films</h2>
  <p>Recorded in the simulator on the real app. Each has a half-speed button.</p>
  <div class="films">{films}</div>

  <h2 id="layers">What's in it</h2>
  <div class="card"><ul class="layers">{"".join(f"<li>{s}</li>" for s in LAYERS)}</ul></div>

  <h2 id="ask">What I need from you</h2>
  <div class="card ask"><ul>{"".join(f"<li>{s}</li>" for s in notes.get("ask", []))}</ul></div>
  <p class="foot">Nothing is committed. The films are H.264 at 60 frames a second; if one shows a crossed-out play icon on your phone, "Open file" is the same film, and the page then tries a second and a third encoding by itself.</p>
</main>
"""
    (OUT / "index.html").write_text(head + body + script)
    print("wrote", OUT / "index.html", f"({len(available)} films)")


if __name__ == "__main__":
    main()
