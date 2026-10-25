#!/usr/bin/env python3
"""Builds the review page for the new welcome and intro: build/review/welcome-v2/index.html.

The films (scripts/cap_anim/films_welcome.sh), stills of the welcome in its states and of the six intro pages, and what changed.
The look, the film players and their fallbacks are build_alive_page.py's, as in build_pull_page.py.

    build_welcome_page.py [--notes notes.json]     notes.json: {"summary": [...], "ask": [...], "film_notes": {"name": "..."}}
"""
import html, json, sys
from pathlib import Path

import build_alive_page as alive

ROOT = alive.ROOT
OUT = ROOT / "build/review/welcome-v2"

FILMS = [
    ("welcome-touch", "The welcome, with touches",
     "Cap waves and says hello. A touch on a star lights it: the next note up, a ring and a small glint that fade, a ripple, and the lake keeps "
     "it as a short dash. Lines between lit stars draw themselves. The third star lights the rest of the cap in a sweep; a soft gold glow and "
     "one thin shooting star cross the sky, Cap cheers, and the star in \"capling\" lights. Between touches a faint ring marks the star he "
     "would light next. The notes you hear are the app's own."),
    ("welcome-alone", "The welcome, with nobody touching",
     "Nothing is required. He says hello, says \"Go on, tap one.\", and lights the first star himself; then a star every four seconds, "
     "and the cap is lit about 17 seconds in. The buttons are there the whole time."),
    ("welcome-calm", "With Reduce Motion",
     "No clips, no ripples, no ignition: the stars simply light, the sky brightens evenly, Cap changes pose with a cross-fade. The notes "
     "still play (they follow the Sounds setting, not Reduce Motion)."),
    ("intro-snap", "Intro page 1: snap a page",
     "The scan now ends on three cards of three kinds, each marked: a flashcard, a multiple choice question and an own-words question."),
    ("intro-flashcards", "Intro page 2: flashcards (new)",
     "A card turns to its answer, the four ratings say when it would come back, Good is tapped, and a week lights the day it returns. "
     "The words below say Anki and Quizlet decks come along."),
]

STILLS = [
    ("start", "Welcome: at the start", "Cap's hello, the constellation waiting, a ring on the star he would light."),
    ("done", "Welcome: the cap lit", "Every star lit, Cap cheering, the star in the wordmark lit, the promise brighter."),
    ("calm", "Welcome: Reduce Motion", "The same, with nothing in motion."),
    ("ax", "Welcome: largest text size", "The sky is a short band above the words, which scroll."),
]
PAGES = ["Snap a page", "Flashcards", "Own words", "Readiness", "Plan", "Ask Cap"]

EXTRA_CSS = """
  .stills { display: grid; gap: 14px; grid-template-columns: repeat(auto-fit, minmax(min(100%, 170px), 1fr)); margin: 12px 0 24px; }
  .stills figure { margin: 0; display: grid; gap: 6px; }
  .stills img { width: 100%; height: auto; border-radius: 18px; border: 1px solid var(--line); display: block; }
  .stills figcaption { max-width: none; font-size: 13px; color: var(--ink3); }
  .stills figcaption strong { display: block; color: var(--ink); font-size: 14px; }
"""


def esc(s):
    return html.escape(str(s), quote=True)


def stills_html(prefix, items, folder):
    out = []
    for key, title, note in items:
        img = OUT / folder / f"{prefix}{key}.jpg"
        if not img.exists():
            continue
        out.append(f'<figure><img src="{folder}/{img.name}" alt="{esc(title)}" loading="lazy" decoding="async">'
                   f"<figcaption><strong>{esc(title)}</strong>{esc(note)}</figcaption></figure>")
    return "".join(out)


def pages_html():
    out = []
    for i, name in enumerate(PAGES):
        img = OUT / "stills" / f"page-{i + 1}.jpg"
        if img.exists():
            out.append(f'<figure><img src="stills/{img.name}" alt="Intro page {i + 1}: {esc(name)}" loading="lazy" decoding="async">'
                       f"<figcaption><strong>{i + 1}. {esc(name)}</strong></figcaption></figure>")
    return "".join(out)


def main():
    notes = {}
    if "--notes" in sys.argv:
        notes = json.loads(Path(sys.argv[sys.argv.index("--notes") + 1]).read_text())
    OUT.mkdir(parents=True, exist_ok=True)
    available = {p.stem for p in OUT.glob("*.mp4") if not p.stem.endswith("-half")}
    film_notes = notes.get("film_notes", {})
    films = "".join(alive.film_card_in(OUT, n, t, film_notes.get(n, d), available) for n, t, d in FILMS)

    head = alive.TEMPLATE[:alive.TEMPLATE.index("<body>")].replace("<title>Cap is alive</title>", "<title>A better welcome</title>")
    head = head.replace("</style>", EXTRA_CSS + "</style>")
    script = alive.TEMPLATE[alive.TEMPLATE.index("<script>"):]
    body = f"""<body>
<main data-bg="night">
  <div class="eyebrow">First minute · Oct 25, 2026</div>
  <h1>A welcome that teaches the idea, and an intro that shows flashcards</h1>
  <p>The welcome is a small, quiet night world with Cap's cap drawn in seven stars, waiting to be lit; the sky is now lighter to look at and
  to draw. The intro has six pages, and flashcards are one of them.</p>
  <nav><a href="#films">Films</a><a href="#stills">Stills</a><a href="#pages">The six pages</a><a href="#ask">What I need from you</a></nav>

  <div class="card"><strong>What was done</strong><ul>{"".join(f"<li>{s}</li>" for s in notes.get("summary", []))}</ul></div>

  <h2 id="films">Films</h2>
  <p>Recorded in the Simulator on the real app, with its own sounds mixed in. Each has a half-speed button.</p>
  <div class="films">{films}</div>

  <h2 id="stills">Stills</h2>
  <div class="stills">{stills_html("", STILLS, "stills")}</div>

  <h2 id="pages">The six intro pages</h2>
  <p>Snap a page, flashcards (new), own words, readiness, plan, Ask Cap. The first now ends on three kinds of card.</p>
  <div class="stills">{pages_html()}</div>

  <h2 id="ask">What I need from you</h2>
  <div class="card ask"><ul>{"".join(f"<li>{s}</li>" for s in notes.get("ask", []))}</ul></div>
  <p class="foot">Nothing is committed. The films are H.264 at 60 frames a second; if one shows a crossed-out play icon on your phone, "Open file" is the same film, and the page then tries a second and a third encoding by itself.</p>
</main>
"""
    (OUT / "index.html").write_text(head + body + script)
    print("wrote", OUT / "index.html", f"({len(available)} films)")


if __name__ == "__main__":
    main()
