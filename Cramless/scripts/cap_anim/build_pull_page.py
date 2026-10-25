#!/usr/bin/env python3
"""Builds the review page for pulling Today down (the hero stays put, the pull refreshes the sky): build/review/hero-pull/index.html.

The real drag before and now, films of the refresh in each state, and what it does. The look, the film players and their fallbacks
are build_alive_page.py's, as in build_hero_page.py.

    build_pull_page.py [--notes notes.json]     notes.json: {"summary": [...], "ask": [...], "film_notes": {"name": "…"}}
"""
import html, json, sys
from pathlib import Path

import build_alive_page as alive

ROOT = alive.ROOT
OUT = ROOT / "build/review/hero-pull"

FILMS = [
    ("pull-real", "A real drag, before and now",
     "The Simulator's swipe, recorded. Left: the page and the hero come down together and a white band opens behind the status bar. "
     "Right: the hero stays where it is and the page moves under it; the flick carries the page past the line, so the sky refreshes. "
     "(Not the same pull: the swipe's strength varies from run to run.)"),
    ("hero-pull", "Pull to refresh",
     "A deliberate pull, held: the world leans into it and the sky wakes; past the line there is a tick and the far ridge lights up. "
     "Let go: an arc of light climbs from behind the hills and the stars flash as it passes, a star falls, Cap says something and "
     "the pill says \"Sky refreshed\". Then a short pull that springs back and does nothing. (Here the page itself stays still, so you "
     "see only the world's answer.)"),
    ("hero-pull-calm", "Reduce Motion",
     "Nothing leans or moves. The ridge still lights when you are past the line, and the sky brightens evenly for a moment."),
    ("hero-pull-empty", "Nothing studied yet", "The outlines of the constellations to come get the light too."),
    ("hero-pull-focus", "While a constellation is in focus", "Refreshing looks at the whole sky again: the camera lets go as the arc climbs."),
    ("hero-pull-eve", "Exam eve", "The exam's region glows; the arc passes through it like everything else."),
]

STILLS = [
    ("peak", "At the bottom of a real pull"),
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
    "<strong>The pin:</strong> pulled past its top, the page moves under the hero and the hero doesn't. It is the same frame, not a frame later, so it can't jitter.",
    "<strong>The lean:</strong> background stars, clouds and the sky lean down as you pull, the nearer the further; the ground never moves. The sky's own stars glow and the dusk brightens.",
    "<strong>The line:</strong> about 140 points of drag. A tick under the finger, and the far ridge catches the light so you can see it is ready. Pull back and it lets go.",
    "<strong>The flourish:</strong> 1.3 seconds. An arc of light climbs from behind the hills, every star it passes flashes, a star falls.",
    "<strong>Cap and the pill:</strong> Cap reacts like a tap and says one of 14 new lines (&ldquo;Fresh as a pond at dawn.&rdquo;); the pill says &ldquo;Sky refreshed&rdquo; for two seconds.",
    "<strong>What it refreshes:</strong> the day's rollover, what other devices changed (when you are signed in; it waits five seconds at most), and the sky as of now. If your account can't be reached it says so.",
    "<strong>A hard flick counts</strong> even if the finger lifts early, as long as the momentum carries the page past the line. A page flung up that bounces off its top never does.",
    "<strong>Reduce Motion and VoiceOver:</strong> nothing moves, the sky brightens evenly; VoiceOver gets a &ldquo;Refresh&rdquo; action and hears &ldquo;Sky refreshed&rdquo;.",
]


def main():
    notes = {}
    if "--notes" in sys.argv:
        notes = json.loads(Path(sys.argv[sys.argv.index("--notes") + 1]).read_text())
    OUT.mkdir(parents=True, exist_ok=True)
    available = {p.stem for p in OUT.glob("*.mp4") if not p.stem.endswith("-half")}
    film_notes = notes.get("film_notes", {})
    films = "".join(alive.film_card_in(OUT, n, t, film_notes.get(n, d), available) for n, t, d in FILMS)

    head = alive.TEMPLATE[:alive.TEMPLATE.index("<body>")].replace("<title>Cap is alive</title>", "<title>Pull to refresh</title>")
    head = head.replace("</style>", EXTRA_CSS + "</style>")
    script = alive.TEMPLATE[alive.TEMPLATE.index("<script>"):]
    body = f"""<body>
<main data-bg="night">
  <div class="eyebrow">Today · Oct 25, 2026</div>
  <h1>Pull down: the hero stays, the sky refreshes</h1>
  <p>Pulling Today down no longer drags the hero with it, and the pull does something now: it refreshes your sky, with a flourish of light.</p>
  <nav><a href="#before">Before and now</a><a href="#films">Films</a><a href="#layers">What it does</a><a href="#ask">What I need from you</a></nav>

  <div class="card"><strong>What was done</strong><ul>{"".join(f"<li>{s}</li>" for s in notes.get("summary", []))}</ul></div>

  <h2 id="before">Before and now</h2>
  <p>The same drag in the Simulator, at the bottom of the pull. Left is what you had on your phone, right is now.</p>
  {stills_html()}

  <h2 id="films">Films</h2>
  <p>Recorded in the simulator on the real app. Each has a half-speed button.</p>
  <div class="films">{films}</div>

  <h2 id="layers">What it does</h2>
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
