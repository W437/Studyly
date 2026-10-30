#!/usr/bin/env python3
"""Builds the review page for Phase 6, the game loop: build/review/game-loop/index.html.

The films (scripts/cap_anim/films_game.sh), stills of each screen it touches, and what changed. The look, the film players and
their fallbacks are build_alive_page.py's, as in build_welcome_page.py.

    build_game_page.py [--notes notes.json]     notes.json: {"summary": [...], "ask": [...], "film_notes": {"name": "..."}}
"""
import html, json, sys
from pathlib import Path

import build_alive_page as alive

ROOT = alive.ROOT
OUT = ROOT / "build/review/game-loop"

FILMS = [
    ("milestone-7", "A streak reaches 7 days",
     "The summary's hero becomes the milestone: Cap proud, the week's flame popping in beside him and bouncing once, \"7 days.\" and one "
     "warm line about the memory. The streak tile rolls to 7. The celebration is the policy's (a burst of confetti for 7)."),
    ("milestone-30", "30 days",
     "The same, a month in: the flame has a warm glow and two embers, and the confetti comes from both corners. (A big celebration plays at "
     "most once a day.)"),
    ("milestone-100", "100 days",
     "A hundred days: the flame is gold, with glints. At 365 it gets a star over it."),
    ("quests", "The day's quests tick off",
     "Three quests, none done, 7 of 12 this week. After the session the quests it finished tick off one by one (a light tick each), the "
     "week's count moves from 7 to 9, and the one still on its way shows how far: \"1 of 5\"."),
    ("new-sky", "The week's twelfth quest lights a sky",
     "The last quest of the week makes 12: a card appears with a swatch of Dusk and \"Use it\". Using it puts the sky behind the stars, "
     "and Done goes back to Today, now in Dusk, with the week's meter full."),
    ("badge", "A badge, and its medal",
     "The 7-day badge is earned: its card in the summary, then its sheet. The medal is a metal disc with a sheen that slides as the phone "
     "tilts and turns up to 12 degrees with it; the Simulator has no motion sensor, so here it sways on its own."),
    ("sky-tour", "The six skies",
     "Night (the one Capling always had), Dusk, Aurora, Ember, Bloom and Glacier behind Today, two and a half seconds each. The stars keep "
     "their course colours; the sky, the dusk at the horizon, the hills, the lake and the ground change."),
]

STILLS = [
    ("today-quests", "Today: the day's quests", "Under the day's button: three quests, the one done checked, the week's twelve pips and what they light."),
    ("today-quests-dark", "Today, dark", "The same in dark mode."),
    ("streak", "The streak screen", "The flame has the stage the streak has reached; a streak on hold is an outline."),
    ("streak-milestones", "Milestones", "Each with its own flame, a check for those reached and the way to the next."),
    ("progress-badges", "Progress: badges", "The latest earned, then the ones that are close. See all opens every badge."),
    ("badges", "Every badge", "Earned ones are medals; the rest are silhouettes with how far along they are."),
    ("badge-earned", "A badge up close", "The sheet hugs its content; the medal follows the phone's tilt."),
    ("badge-unearned", "A badge not earned yet", "A silhouette, and how far along."),
    ("appearance-sky", "Settings ▸ Appearance ▸ Sky", "The skies a week of quests has lit, and the ones still dark."),
    ("appearance-icon", "Settings ▸ Appearance ▸ App icon", "Cap on blue, and four icons a best streak unlocks at 7, 30, 100 and 365 days."),
    ("summary-quests", "The summary: quests and a new sky", "Under the numbers: the quests, then the sky the week lit."),
    ("summary-badge", "The summary: a new badge", "Tapping it opens the badge."),
]
SKIES = [
    ("today-dusk", "Dusk"), ("today-aurora", "Aurora"), ("today-ember", "Ember"), ("today-bloom", "Bloom"), ("today-glacier", "Glacier"),
]
ART = [
    ("flames", "The flame, in its five stages", "Drawn in code, so the widgets draw it too. At the bottom: the outline, for no streak."),
    ("medals", "The 13 medals", "Earned, tilted, and still to earn."),
    ("icons", "The four new icons", "Made from the main icon: Cap is cut out of the blue and set on four new skies (the gold one is his fur regraded)."),
    ("skies", "The six skies", "As the picker shows them."),
]
CHECKS = [
    ("ax-badges", "Largest text size: badges", "Two columns, the names wrap."),
    ("ax-quests", "Largest text size: quests", "The header stacks and the rows wrap."),
    ("calm-milestone", "Reduce Motion: the milestone", "Its final state at once: the gold flame beside Cap, no bounce, no confetti."),
]
REMINDERS = [
    ("29 days, today not done", "19:00", "One session today makes it 30 days."),
    ("29 days, today not done", "20:30", "15 minutes tonight makes it 30 days."),
    ("6 days, today done", "tomorrow 19:00", "One session today makes it 7 days."),
    ("12 days, today not done", "19:00", "15 minutes keeps Chem 110 on track. 18 cards are due. (as before)"),
]

EXTRA_CSS = """
  .stills { display: grid; gap: 14px; grid-template-columns: repeat(auto-fit, minmax(min(100%, 170px), 1fr)); margin: 12px 0 24px; }
  .stills figure { margin: 0; display: grid; gap: 6px; align-content: start; }
  .stills img { width: 100%; height: auto; border-radius: 18px; border: 1px solid var(--line); display: block; }
  .stills figcaption { max-width: none; font-size: 13px; color: var(--ink3); }
  .stills figcaption strong { display: block; color: var(--ink); font-size: 14px; }
  .art { display: grid; gap: 18px; margin: 12px 0 24px; }
  .art figure { margin: 0; display: grid; gap: 8px; }
  .art img { max-width: 100%; height: auto; border-radius: 18px; border: 1px solid var(--line); display: block; }
  .art figcaption { max-width: none; font-size: 13px; color: var(--ink3); }
  .art figcaption strong { display: block; color: var(--ink); font-size: 14px; }
  table.copy { border-collapse: collapse; width: 100%; margin: 10px 0 22px; font-size: 14px; }
  table.copy td, table.copy th { text-align: left; padding: 8px 10px; border-bottom: 1px solid var(--line); vertical-align: top; }
  table.copy th { color: var(--ink3); font-weight: 600; font-size: 12px; text-transform: uppercase; letter-spacing: .06em; }
"""


def esc(s):
    return html.escape(str(s), quote=True)


def figures(items, folder="stills"):
    out = []
    for key, title, note in items:
        img = OUT / folder / f"{key}.jpg"
        if img.exists():
            out.append(f'<figure><img src="{folder}/{img.name}" alt="{esc(title)}" loading="lazy" decoding="async">'
                       f"<figcaption><strong>{esc(title)}</strong>{esc(note)}</figcaption></figure>")
    return "".join(out)


def art(items):
    out = []
    for key, title, note in items:
        img = OUT / "stills" / f"{key}.jpg"
        if img.exists():
            out.append(f'<figure><img src="stills/{img.name}" alt="{esc(title)}" loading="lazy" decoding="async">'
                       f"<figcaption><strong>{esc(title)}</strong>{esc(note)}</figcaption></figure>")
    return "".join(out)


def main():
    notes = {}
    if "--notes" in sys.argv:
        notes = json.loads(Path(sys.argv[sys.argv.index("--notes") + 1]).read_text())
    OUT.mkdir(parents=True, exist_ok=True)
    available = {p.stem for p in OUT.glob("*.mp4") if not p.stem.endswith("-half")}
    film_notes = notes.get("film_notes", {})
    films = "".join(alive.film_card_in(OUT, n, t, film_notes.get(n, d), available) for n, t, d in FILMS)
    rows = "".join(f"<tr><td>{esc(a)}</td><td>{esc(b)}</td><td>{esc(c)}</td></tr>" for a, b, c in REMINDERS)

    head = alive.TEMPLATE[:alive.TEMPLATE.index("<body>")].replace("<title>Cap is alive</title>", "<title>The game loop</title>")
    head = head.replace("</style>", EXTRA_CSS + "</style>")
    script = alive.TEMPLATE[alive.TEMPLATE.index("<script>"):]
    body = f"""<body>
<main data-bg="night">
  <div class="eyebrow">Phase 6 · Oct 26, 2026</div>
  <h1>A flame that grows, quests for the day, badges you keep, and skies and icons to unlock</h1>
  <p>Nothing here is a currency, a shop or a way to lose something. A quest finished stays finished, a badge earned stays earned, an
  icon or a sky unlocked stays unlocked, and each part lives on a screen that was already there.</p>
  <nav><a href="#films">Films</a><a href="#stills">Stills</a><a href="#art">The art</a><a href="#reminders">Reminders</a><a href="#ask">What I need from you</a></nav>

  <div class="card"><strong>What was done</strong><ul>{"".join(f"<li>{s}</li>" for s in notes.get("summary", []))}</ul></div>

  <h2 id="films">Films</h2>
  <p>Recorded in the Simulator on the real app, with its own sounds mixed in. Each has a half-speed button.</p>
  <div class="films">{films}</div>

  <h2 id="stills">Stills</h2>
  <div class="stills">{figures(STILLS)}</div>
  <h3>Today in the five new skies</h3>
  <div class="stills">{figures([(k, n, "") for k, n in SKIES])}</div>
  <h3>Checked at the largest text size and with Reduce Motion</h3>
  <div class="stills">{figures(CHECKS)}</div>

  <h2 id="art">The art</h2>
  <div class="art">{art(ART)}</div>

  <h2 id="reminders">The reminder the day before a milestone</h2>
  <p>On the day one session makes a milestone (3, 7, 30, 100 or 365 days) the reminder and the evening nudge say so. Every other day they
  say what they said before.</p>
  <table class="copy"><tr><th>When</th><th>At</th><th>It says</th></tr>{rows}</table>

  <h2 id="ask">What I need from you</h2>
  <div class="card ask"><ul>{"".join(f"<li>{s}</li>" for s in notes.get("ask", []))}</ul></div>
  <p class="foot">These changes are not committed yet. The films are H.264 at 60 frames a second; if one shows a crossed-out play icon on your phone, "Open file" is the same film, and the page then tries a second and a third encoding by itself.</p>
</main>
"""
    (OUT / "index.html").write_text(head + body + script)
    print("wrote", OUT / "index.html", f"({len(available)} films)")


if __name__ == "__main__":
    main()
