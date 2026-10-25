#!/usr/bin/env python3
"""Builds the review page for tapping Cap: build/review/cap-touch/index.html.

The page shows the two fixes with their proof (the + button's flash, the rectangle behind Cap), films of Cap being tapped, his
19 reactions to a tap, and every line he can say (read straight from CapLines.swift, so the page can't drift from the app).
The look, the film players and their fallbacks are build_alive_page.py's.

    build_touch_page.py [--notes notes.json]     notes.json: {"summary": [...], "ask": [...], "film_notes": {"name": "…"}}
"""
import html, json, re, shutil, sys
from pathlib import Path

import build_alive_page as alive

ROOT = alive.ROOT
OUT = ROOT / "build/review/cap-touch"
PROD = alive.PROD
LINES = ROOT / "Cramless/DesignSystem/Components/CapLines.swift"
CLIPS = [c for c in json.loads((PROD / "manifest.json").read_text())["clips"] if c["role"] == "poke"]
BOOK = alive.BOOK

FIXES = [
    ("plus-before", "The + button before: the page flashes",
     "A real tap on +, recorded on the simulator. The page behind vanishes for a moment (white here, black in dark mode) and comes back."),
    ("plus-after", "The + button now",
     "The same tap. The page stays where it is and the sheet rises over it."),
]
FILMS = [
    ("touch-today", "Today: tap him in the sky",
     "Cap squashes, plays his reaction and says something. Four quick taps and he gets flustered. Nothing else in the sky moved: "
     "tap anywhere but him and it still opens the sky."),
    ("touch-cast", "Every pose, then a tap on it",
     "Each of his 19 poses plays its own clip, then gets tapped: his reaction clip, a squash that is different every time, and a line."),
    ("touch-session", "In a session",
     "The same in the answer panel: he reacts to a right answer, then to a tap."),
]
ORDER = ["wave", "study", "celebrate", "sleep", "think", "point", "scan", "plan", "mic", "relax", "nice", "almost", "notYet", "listen",
         "ask", "sleepy", "proud", "stargaze", "tuckIn"]
TITLES = {"wave": "Waving", "study": "Reading", "celebrate": "Celebrating", "sleep": "Asleep", "think": "Thinking", "point": "Pointing",
          "scan": "Scanning", "plan": "Planning", "mic": "At the microphone", "relax": "Relaxing", "nice": "Nice!", "almost": "Almost",
          "notYet": "Not yet", "listen": "Listening", "ask": "Asking", "sleepy": "Sleepy", "proud": "Proud", "stargaze": "Stargazing",
          "tuckIn": "Tucking in"}


def esc(s):
    return html.escape(str(s), quote=True)


def lines_by_pool():
    """{'wave': [...], 'general': [...], 'morning': [...], 'flustered': [...]} from CapLines.swift."""
    text = LINES.read_text()
    pools = {}
    for m in re.finditer(r"static let (\w+): \[LocalizedStringResource\] = \[(.*?)\n    \]", text, re.S):
        pools[m.group(1)] = [bytes(s, "utf-8").decode("unicode_escape") if "\\" in s else s for s in re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(2))]
    return pools


def lines_section(pools):
    def block(title, key, note=""):
        items = "".join(f"<li>{esc(l)}</li>" for l in pools.get(key, []))
        return (f'<details><summary>{esc(title)} <span class="count">{len(pools.get(key, []))}</span></summary>'
                f'{f"<p class=note>{esc(note)}</p>" if note else ""}<ul class="says">{items}</ul></details>')
    out = [block("Anywhere", "general", "Mixed in with any pose's own lines, about one in six taps.")]
    out.append(block("Tapped again and again", "flustered", "After four quick taps in a row."))
    for key, name in (("morning", "Morning (5 to 11)"), ("afternoon", "Afternoon (noon to 5)"), ("evening", "Evening (5 to 10)"),
                      ("night", "Night (10 to 5)")):
        out.append(block(name, key, "Greets the hour; about one in six taps."))
    out.append("<h3>By pose</h3>")
    for pose in ORDER:
        out.append(block(TITLES[pose], pose))
    total = sum(len(v) for v in pools.values())
    return total, "".join(out)


def poke_card(c):
    cid = c["id"]
    pose = c["pose"]
    entry = BOOK.get(cid, {})
    return f"""
    <article class="clip">
      <div class="stage"><img src="img/{cid}.webp" width="360" height="360" loading="lazy" decoding="async" alt="Cap's reaction when he is tapped as {esc(TITLES.get(pose, pose))}"></div>
      <h3>{esc(TITLES.get(pose, pose))}</h3>
      <p class="meta">{c['duration']:.1f} s · {c['bytes'] / 1024:.0f} KB</p>
      <p class="note">{esc(entry.get('action', ''))}</p>
    </article>"""


EXTRA_CSS = """
  .compare { display: grid; gap: 14px; grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr)); margin: 14px 0; }
  .compare figure { margin: 0; display: grid; gap: 6px; justify-items: stretch; }
  .compare img { width: 100%; height: auto; border-radius: 16px; border: 1px solid var(--line); display: block; }
  .compare figcaption { max-width: none; font-size: 14px; color: var(--ink2); }
  details { background: var(--surface); border: 1px solid var(--line); border-radius: 16px; padding: 4px 16px; margin: 8px 0; }
  summary { min-height: 44px; display: flex; align-items: center; gap: 8px; cursor: pointer; font-weight: 600; }
  summary .count { font-weight: 500; font-size: 13px; color: var(--ink3); }
  ul.says { columns: 2 220px; column-gap: 28px; margin: 4px 0 12px; padding-left: 18px; }
  ul.says li { break-inside: avoid; margin: 3px 0; }
"""


def main():
    notes = {}
    if "--notes" in sys.argv:
        notes = json.loads(Path(sys.argv[sys.argv.index("--notes") + 1]).read_text())
    (OUT / "img").mkdir(parents=True, exist_ok=True)
    for c in CLIPS:
        shutil.copy(PROD / "out" / f"{c['id']}-final.webp", OUT / "img" / f"{c['id']}.webp")
    available = {p.stem for p in OUT.glob("*.mp4") if not p.stem.endswith("-half")}
    film_notes = notes.get("film_notes", {})

    fixes = "".join(alive.film_card_in(OUT, n, t, film_notes.get(n, d), available) for n, t, d in FIXES)
    films = "".join(alive.film_card_in(OUT, n, t, film_notes.get(n, d), available) for n, t, d in FILMS)
    clips = "".join(poke_card(c) for c in sorted(CLIPS, key=lambda c: ORDER.index(c["pose"]) if c["pose"] in ORDER else 99))
    total, says = lines_section(lines_by_pool())
    compare = ""
    if (OUT / "rect-before.png").exists() and (OUT / "rect-after.png").exists():
        compare = ('<div class="compare"><figure><img src="rect-before.png" alt="Today\'s sky around Cap before, with a lighter rectangle behind him">'
                   '<figcaption><strong>Before.</strong> Contrast turned up on Today\'s sky: the clip\'s rectangle is plain to see behind Cap.</figcaption></figure>'
                   '<figure><img src="rect-after.png" alt="The same crop now, with no rectangle">'
                   '<figcaption><strong>Now.</strong> The same crop, the same contrast: the sky runs straight behind him.</figcaption></figure></div>')
    mb = sum(c["bytes"] for c in CLIPS) / 1048576

    head = alive.TEMPLATE[:alive.TEMPLATE.index("<body>")].replace("<title>Cap is alive</title>", "<title>Tap Cap</title>")
    head = head.replace("</style>", EXTRA_CSS + "</style>")
    script = alive.TEMPLATE[alive.TEMPLATE.index("<script>"):]
    body = f"""<body>
<main data-bg="night">
  <div class="eyebrow">Cramless · Cap, in the app · Oct 25, 2026</div>
  <h1>Tap Cap</h1>
  <p>Two things fixed, and Cap now answers a tap: his own reaction for each of his 19 poses, a squash and bounce that is different every time, and something short to say.</p>
  <nav><a href="#fixes">The two fixes</a><a href="#films">Tapping him</a><a href="#clips">19 reactions</a><a href="#says">What he says</a><a href="#ask">What I need from you</a></nav>

  <div class="card"><strong>What was done</strong><ul>{"".join(f"<li>{s.replace('{{LINES}}', str(total))}</li>" for s in notes.get("summary", []))}</ul></div>

  <h2 id="fixes">The two things you didn't like</h2>
  <div class="films">{fixes}</div>
  {compare}

  <h2 id="films">Tapping him</h2>
  <p>Recorded in the simulator on the real app. Each has a half-speed button.</p>
  <div class="films">{films}</div>

  <h2 id="clips">His 19 reactions ({mb:.1f} MB in the app)</h2>
  <p>What he does when he is tapped in each pose. Each starts and ends on his drawing, so it plays from wherever he is and hands back. The squash is added on top in the app. Switch the background to see he is transparent.</p>
  <div class="bgs" role="group" aria-label="Background behind Cap">
    <span>Behind Cap:</span>
    <button type="button" data-bg="night" aria-pressed="true">Night sky</button>
    <button type="button" data-bg="light" aria-pressed="false">Light</button>
    <button type="button" data-bg="checker" aria-pressed="false">Checkerboard</button>
  </div>
  <div class="grid">{clips}</div>

  <h2 id="says">What he says: {total} lines</h2>
  <p>Every line he can say, read from the app's code. He never repeats one until a pool is used up, and he remembers across launches. Tell me any you want gone or changed.</p>
  {says}

  <h2 id="ask">What I need from you</h2>
  <div class="card ask"><ul>{"".join(f"<li>{s}</li>" for s in notes.get("ask", []))}</ul></div>
  <p class="foot">Nothing is committed. The films are H.264 at 60 frames a second; if one shows a crossed-out play icon on your phone, "Open file" is the same film, and the page then tries a second and a third encoding by itself.</p>
</main>
"""
    (OUT / "index.html").write_text(head + body + script)
    print("wrote", OUT / "index.html", f"({len(available)} films, {len(CLIPS)} reactions, {total} lines)")


if __name__ == "__main__":
    main()
