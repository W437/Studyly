#!/usr/bin/env python3
"""Builds the review page for Ask Cap's assistant: build/review/ask-cap-assistant/index.html.

The films and stills come from scripts/cap_anim/films_assistant.sh (run it first, into build/review/ask-cap-assistant/). The look, the
film players and their fallbacks are build_alive_page.py's, as in build_game_page.py. The numbers come from the live test
(supabase/functions/tools/assistant_bakeoff, results in build/assistant-bakeoff/<run>/results.json).

    build_assistant_page.py [--notes notes.json] [--run run3]
        notes.json: {"summary": [...], "ask": [...], "decided": [...], "film_notes": {"name": "..."}}
"""
import html, json, sys
from collections import OrderedDict
from pathlib import Path

import build_alive_page as alive

ROOT = alive.ROOT
OUT = ROOT / "build/review/ask-cap-assistant"

GROUPS = [
    ("Making things", [
        ("cards", "Flashcards, written and checked",
         "You ask for flashcards on mitosis. Cap reads your notes, then six cards appear one at a time as they are written, each with a soft "
         "note. Then each is checked against your notes, one by one, with a rising note: a tick and the page it rests on, or “Cap’s own words” "
         "when nothing in your notes backs it. Then the card waits for you."),
        ("cards-add", "Add, then Undo",
         "Add 6 flashcards: the cards join Bio 101, the tick draws itself and the “saved” note plays. Later, Undo takes exactly those six back."),
        ("cards-auto", "“Let Cap do it”",
         "The same request with that switched on for flashcards and questions. Cap adds them itself, says so (“Cap did this because you switched "
         "on Let Cap do it”), and Undo is one tap."),
        ("quiz", "Questions: pick one, in your words, fill in the blank",
         "Three kinds of question, each with its options and, once checked, the page it comes from. The right option of a multiple-choice "
         "question is shuffled by the app, because models put it first."),
        ("note", "A note, written on a page",
         "The words arrive as the model writes them, with a pen, on a white page. When it’s done you can read it all, change the words, or add it."),
        ("exam", "An exam, on a calendar tile",
         "“Plan my midterm for 12 November”: a tile flips onto the page with the day, “In 17 days”, and a way to change the day or the time."),
    ]),
    ("Looking things up", [
        ("research", "Web research: the part you asked about",
         "The search types itself into a search bar. The pages it found pop up as the sites’ tiles (OpenStax, Britannica, Khan Academy, "
         "Wikipedia…), a ring of light reads across them, the summary writes itself with the key words in bold, and the pages it rests on come "
         "last as links you can open. Trusted study sites only."),
        ("research-save", "Save it as a note",
         "Nothing from the web is saved until you say so. Save as note makes “From the web: …” in your course, with its sources at the end."),
        ("multi", "A lookup, then a deck",
         "“Look through my notes and make cards on anaphase”: Cap reads your notes (a small page is scanned, chips show where it found things), "
         "then writes three cards that rest on your slides and your lecture, each with the page or the minute it comes from. A quote that is "
         "not in your material would be marked “Cap’s own words” instead."),
    ]),
    ("Control and limits", [
        ("practice", "A button, not a surprise",
         "Cap offers a 10-minute practice session. Nothing opens until you tap Start."),
        ("limit", "The free plan’s limit",
         "The free plan gets 3 drafts a day. After that Cap says it can’t make new cards today and still answers from your notes, and the app "
         "explains why, once, with a way to Capling Pro."),
        ("research-pro", "Web research needs Capling Pro",
         "What a free account sees: the card says why, in a sentence, with one button, and Cap says it couldn’t do that one."),
    ]),
]

STILLS = [
    ("empty", "A new chat", "Cap can answer, and it can make things: the chips put the first words in the box."),
    ("cards-writing", "Cards being written", "Each card appears as the model writes it, and Cap says what he is doing."),
    ("cards-checking", "Being checked", "Then ticks come in one at a time, each with the page it rests on."),
    ("cards-ready", "Your call", "Tick or untick, edit any card, add them all or skip."),
    ("cards-added", "Added", "The tick drew itself; Undo is right there."),
    ("cards-added-auto", "Added by “Let Cap do it”", "And it says so."),
    ("quiz-ready", "Questions", "Pick one, in your words, fill in the blank."),
    ("note-writing", "A note being written", "A pen on a white page."),
    ("note-ready", "The note", "Read it, change the words, or add it."),
    ("exam-ready", "The exam", "A calendar tile and when."),
    ("research-searching", "Research: searching", "The query types itself into the bar."),
    ("research-reading", "Research: reading", "The sites’ tiles, and a ring of light passing over them."),
    ("research-writing", "Research: writing the summary", "The summary writes itself while the ring keeps reading."),
    ("research-ready", "Research: the summary and its sources", "Every claim can be followed to a page."),
    ("research-pro", "Research on the free plan", "Says why, with one button."),
    ("multi-ready", "A lookup, then cards", "Two steps in one reply; the cards whose quote isn’t in your notes are marked."),
    ("limit", "The free limit", "Said once, with the way to lift it."),
    ("practice", "A practice button", "Nothing opens until you tap."),
    ("cards-dark", "Dark mode", "The same cards."),
    ("research-dark", "Research in dark mode", "The sites’ tiles keep their colours."),
]
SETTINGS = [
    ("settings", "Settings ▸ What Cap can do", "Ask first by default; a switch for each kind; web research on or off."),
    ("settings-added", "Everything Cap added, with Undo", "The foot of the page: found even after the chat is closed."),
    ("settings-teen", "An account under 18", "Every switch locked on ask-first, and no web."),
    ("ai-privacy", "AI and privacy", "The foot of the page now says what else Cap sees when it makes things (course, topic and exam names, exam dates, readiness) and that a research topic is searched on trusted sites."),
]

EXTRA_CSS = """
  .stills { display: grid; gap: 14px; grid-template-columns: repeat(auto-fit, minmax(min(100%, 170px), 1fr)); margin: 12px 0 24px; }
  .stills figure { margin: 0; display: grid; gap: 6px; align-content: start; justify-items: stretch; }
  .stills img { width: 100%; height: auto; border-radius: 18px; border: 1px solid var(--line); display: block; }
  .stills figcaption { max-width: none; font-size: 13px; color: var(--ink3); }
  .stills figcaption strong { display: block; color: var(--ink); font-size: 14px; }
  table.t { border-collapse: collapse; width: 100%; margin: 10px 0 22px; font-size: 14px; }
  table.t td, table.t th { text-align: left; padding: 8px 10px; border-bottom: 1px solid var(--line); vertical-align: top; }
  table.t th { color: var(--ink3); font-weight: 600; font-size: 12px; text-transform: uppercase; letter-spacing: .06em; }
  table.t td.n { text-align: right; font-variant-numeric: tabular-nums; white-space: nowrap; }
  .big { display: grid; gap: 12px; grid-template-columns: repeat(auto-fit, minmax(min(100%, 150px), 1fr)); margin: 12px 0 8px; }
  .big div { background: var(--surface); border: 1px solid var(--line); border-radius: 18px; padding: 12px 14px; }
  .big b { display: block; font-size: 26px; line-height: 1.1; color: var(--ink); }
  .big span { font-size: 13px; color: var(--ink3); }
  .tools { display: grid; gap: 10px; grid-template-columns: repeat(auto-fit, minmax(min(100%, 260px), 1fr)); margin: 12px 0 8px; }
  .tools div { background: var(--surface); border: 1px solid var(--line); border-radius: 18px; padding: 12px 14px; }
  .tools b { display: block; color: var(--ink); font-size: 15px; margin-bottom: 2px; }
  .tools span { font-size: 14px; color: var(--ink2); }
"""


def esc(s):
    return html.escape(str(s), quote=True)


def figures(items):
    out = []
    for key, title, note in items:
        img = OUT / "stills" / f"{key}.jpg"
        if img.exists():
            out.append(f'<figure><img src="stills/{img.name}" alt="{esc(title)}" loading="lazy" decoding="async">'
                       f"<figcaption><strong>{esc(title)}</strong>{esc(note)}</figcaption></figure>")
    return "".join(out)


def convert_stills():
    """The simulator's screenshots are 1206 px wide PNGs; the page wants light JPGs."""
    from PIL import Image
    for png in sorted((OUT / "stills").glob("*.png")):
        jpg = png.with_suffix(".jpg")
        if jpg.exists() and jpg.stat().st_mtime >= png.stat().st_mtime:
            continue
        im = Image.open(png).convert("RGB")
        w = 640
        im = im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)
        im.save(jpg, "JPEG", quality=84, optimize=True)


def live_numbers(run):
    path = ROOT / f"build/assistant-bakeoff/{run}/results.json"
    if not path.exists():
        return None
    results = json.loads(path.read_text())
    groups = OrderedDict()
    for r in results:
        g = groups.setdefault(r["group"], {"n": 0, "ok": 0, "cost": 0.0, "ms": []})
        g["n"] += 1
        g["ok"] += 1 if not r["failed"] else 0
        g["cost"] += r["costUsd"]
        g["ms"].append(r["totalMs"])
    total = sum(r["costUsd"] for r in results)
    ms = sorted(r["totalMs"] for r in results)
    first = sorted((r["firstVisibleMs"] or r["totalMs"]) for r in results)
    ev = {"exact": 0, "elsewhere": 0, "fabricated": 0, "none": 0}
    for r in results:
        for k in ev:
            ev[k] += r["evidence"][k]
    return {"results": results, "groups": groups, "total": total, "ms": ms, "first": first, "ev": ev}


GROUP_NAMES = {
    "cards": "Flashcards", "quiz": "Questions", "note": "Notes", "exam": "Exams", "practice": "Practice", "open": "Open a screen",
    "research": "Web research and off-topic", "multi": "Lookup then make", "ask": "Plain answers", "uncovered": "Not in your notes",
    "injection": "Hostile text in notes or course name", "ambiguous": "Which course?",
    "free": "Free plan, drafts used up",
}


def median(xs):
    return xs[len(xs) // 2] if xs else 0


def main():
    notes = {}
    if "--notes" in sys.argv:
        notes = json.loads(Path(sys.argv[sys.argv.index("--notes") + 1]).read_text())
    run = sys.argv[sys.argv.index("--run") + 1] if "--run" in sys.argv else "run3"
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "stills").mkdir(exist_ok=True)
    convert_stills()
    available = {p.stem for p in OUT.glob("*.mp4") if not p.stem.endswith("-half")}
    film_notes = notes.get("film_notes", {})

    film_html = ""
    for title, items in GROUPS:
        cards = "".join(alive.film_card_in(OUT, n, t, film_notes.get(n, d), available) for n, t, d in items)
        if cards:
            film_html += f"<h3>{esc(title)}</h3><div class=\"films\">{cards}</div>"

    live = live_numbers(run)
    live_html = ""
    if live:
        rows = "".join(
            f"<tr><td>{esc(GROUP_NAMES.get(g, g))}</td><td class=\"n\">{v['ok']} of {v['n']}</td>"
            f"<td class=\"n\">{v['cost'] / v['n'] * 100:.2f}¢</td><td class=\"n\">{median(sorted(v['ms'])) / 1000:.1f} s</td></tr>"
            for g, v in live["groups"].items())
        n = len(live["results"])
        ok = sum(1 for r in live["results"] if not r["failed"])
        ev = live["ev"]
        live_html = f"""
  <div class="big">
    <div><b>{ok} of {n}</b><span>real requests did what they should</span></div>
    <div><b>{live['total'] / n * 100:.2f}¢</b><span>average cost of a request</span></div>
    <div><b>{median(live['first']) / 1000:.1f} s</b><span>to the first sign of work</span></div>
    <div><b>{median(live['ms']) / 1000:.1f} s</b><span>typical whole reply ({live['ms'][int(len(live['ms']) * .9) - 1] / 1000:.0f} s slowest tenth)</span></div>
    <div><b>{ev['fabricated']}</b><span>made-up quotes out of {ev['exact'] + ev['elsewhere'] + ev['fabricated']}</span></div>
  </div>
  <table class="t"><tr><th>What was asked</th><th>Right</th><th>Cost each</th><th>Typical time</th></tr>{rows}</table>
  <p>Each request ran through the relay’s real code with the real model (GPT 6.1 Terra at low reasoning), playing the app’s part: a lookup was
  answered from a small set of notes, a draft was marked “proposed”. Each was checked for the right tool, the right course, the right count,
  quotes that are really in the notes, a date that is really that day, a short note afterwards that never claims it added anything, and for
  hostile text in the notes or in a course name being ignored, and, for a free account that has used its three drafts, that asking for something to
  be made ends the reply with the limit while a plain question never meets it. {ev['none']} cards had no quote: those were the ones where the student said
  “from your own knowledge”, and they are marked as Cap’s own words.</p>"""

    head = alive.TEMPLATE[:alive.TEMPLATE.index("<body>")].replace("<title>Cap is alive</title>", "<title>Ask Cap, the assistant</title>")
    head = head.replace("</style>", EXTRA_CSS + "</style>")
    script = alive.TEMPLATE[alive.TEMPLATE.index("<script>"):]
    body = f"""<body>
<main data-bg="night">
  <div class="eyebrow">Ask Cap · Oct 27, 2026</div>
  <h1>Ask Cap now does things for you, and you stay in charge</h1>
  <p>Ask for flashcards, questions, a note, an exam or some research, and watch Cap do it: the cards appear as they are written and are
  checked against your notes, a note is written on a page, the web search types itself and the sites’ tiles pop up. Nothing is added until you
  say so, unless you switch “Let Cap do it” on. Everything Cap adds can be taken back.</p>
  <nav><a href="#tools">What Cap can do</a><a href="#films">Films</a><a href="#stills">Stills</a><a href="#trust">How you stay in charge</a><a href="#test">The real-model test</a><a href="#ask">What I need from you</a></nav>

  <div class="card"><strong>What was done</strong><ul>{"".join(f"<li>{s}</li>" for s in notes.get("summary", []))}</ul></div>

  <h2 id="tools">What Cap can do</h2>
  <div class="tools">
    <div><b>Flashcards</b><span>Short fronts and backs, each resting on a quote from your notes. Usually 6, never more than 12; a card you already have is left out.</span></div>
    <div><b>Questions</b><span>Pick one, in your own words (with the ideas a good answer holds), or fill in the blank.</span></div>
    <div><b>Notes</b><span>A summary or study sheet from your material, or what you dictate.</span></div>
    <div><b>Exams</b><span>Put one on your calendar from a day you give: “in two weeks”, “12 November”.</span></div>
    <div><b>Practice</b><span>Offers a session on a course or topic. A button you tap.</span></div>
    <div><b>Open a screen</b><span>Progress, the sky, a course, an exam. A button you tap.</span></div>
    <div><b>Look up your notes</b><span>A page that is scanned once, with chips for where it found things. Finds a lecture by its name.</span></div>
    <div><b>Research online</b><span>Trusted study sites only, with sources you can open. Capling Pro, 3 a day, never for under-18s.</span></div>
  </div>

  <h2 id="films">Films</h2>
  <p>Recorded in the Simulator on the real app, with its own sounds mixed in, playing the mock relay’s scripts at the real pace. Each has a
  half-speed button where it matters.</p>
  {film_html}

  <h2 id="stills">Stills</h2>
  <div class="stills">{figures(STILLS)}</div>
  <h3>Settings</h3>
  <div class="stills">{figures(SETTINGS)}</div>

  <h2 id="trust">How you stay in charge</h2>
  <div class="card"><ul>
    <li><strong>Ask first is the default.</strong> Cap proposes; you add, change or skip. Settings ▸ What Cap can do has a “Let Cap do it” switch for flashcards and questions, notes and exams. Practice and screens are buttons you tap.</li>
    <li><strong>It can’t pass off a guess as your notes.</strong> Every card carries a quote. The app looks for it in your material; if it isn’t there the card says “Cap’s own words, not from your notes”.</li>
    <li><strong>Cap is told the truth.</strong> It hears “proposed” or “added”, so its note never claims more than happened.</li>
    <li><strong>Web text is only text.</strong> The research step has no tools, and what it finds becomes a note only when you tap Save.</li>
    <li><strong>Under 18:</strong> every switch is locked on ask-first, no web research, hints first as before.</li>
    <li><strong>Everything Cap added is listed</strong> in Settings with Undo, even after the chat is closed.</li>
    <li><strong>It is cloud only.</strong> It needs Cloud AI on, and the consent you give names the new things Cap sees (the names of your courses, topics and exams, exam dates, readiness, and a research topic). Anyone who agreed before is asked again.</li>
  </ul></div>

  <h2 id="test">The test on the real model</h2>
  {live_html}

  <h2 id="ask">What I need from you</h2>
  <h3>Decided</h3>
  <div class="card"><ul>{"".join(f"<li>{s}</li>" for s in notes.get("decided", []))}</ul></div>
  <h3>What is left</h3>
  <div class="card ask"><ul>{"".join(f"<li>{s}</li>" for s in notes.get("ask", []))}</ul></div>
  <p class="foot">Nothing here is committed or on your phone. The films are H.264 at 60 frames a second; if one shows a crossed-out play icon on your phone, "Open file" is the same film, and the page then tries a second and a third encoding by itself.</p>
</main>
"""
    (OUT / "index.html").write_text(head + body + script)
    print("wrote", OUT / "index.html", f"({len(available)} films, {len(list((OUT / 'stills').glob('*.jpg')))} stills)")


if __name__ == "__main__":
    main()
