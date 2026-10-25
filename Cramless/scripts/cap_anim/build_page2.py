#!/usr/bin/env python3
"""Builds the review page for round 2: build/review/cap-character/index.html.

Cap's character sheet, the animations made with it (next to last round's), and the other directions. Everything it shows
was made by round2.py, sheet_compose.py and cap_anim.py; the words about each picture are written here, by hand.
"""
import html, json, shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent.parent
B1, B2 = ROOT / "build/cap-anim", ROOT / "build/cap-anim2"
OUT = ROOT / "build/review/cap-character"
IMG = OUT / "img"


def esc(s):
    return html.escape(str(s), quote=True)


def jpg(src, name, width=720, q=86):
    """A web-sized JPEG of a picture; returns its path relative to the page."""
    im = Image.open(src).convert("RGB")
    if im.width > width:
        im = im.resize((width, int(im.height * width / im.width)), Image.LANCZOS)
    dest = IMG / "pics" / f"{name}.jpg"
    dest.parent.mkdir(parents=True, exist_ok=True)
    im.save(dest, quality=q, optimize=True)
    return f"img/pics/{name}.jpg"


# ---- what each picture is, in words ----------------------------------------------------------------------------------

PANELS = [("turn-front-2", "Front"), ("turn-threeq-1", "Three-quarter"), ("turn-side-1", "Side"), ("turn-back-1", "Back"),
          ("expr-content", "Content"), ("expr-open", "Eyes open"), ("expr-wink", "Wink"), ("expr-laugh", "Laugh"), ("expr-yawn", "Yawn"),
          ("expr-surprised", "Surprised"), ("expr-thinking", "Thinking"), ("expr-notyet", "Kind: not yet"), ("expr-sleepy", "Sleepy"),
          ("expr-proud", "Proud"), ("detail-teeth", "Teeth and tongue"), ("detail-eyes", "Eyes, open"), ("detail-eyes_closed", "Eyes, closed"),
          ("detail-paws", "Paws and feet"), ("detail-hat", "Mortarboard and headphones")]

STYLES = [
    ("plush3d", "Soft 3D plush", "The most striking. A premium animated-film look, and it moves beautifully (see the clip). Heavier to produce and a clear step away from the flat Cap."),
    ("knit", "Knitted toy", "Adorable and very tactile. Better as a seasonal or sticker style than as the main face."),
    ("sticker", "Glossy sticker", "Readable at tiny sizes with its white outline. A strong fit for Messages stickers and the App Store."),
    ("chibi", "Chibi", "Cute, but the big sparkly eyes change his calm character."),
    ("clay", "Claymation", "Warm and handmade. Great for a trailer, too textured for the interface."),
    ("watercolor", "Storybook", "Soft and gentle. It came out more felted than watercolour, and it is hard to animate cleanly."),
    ("papercut", "Paper cut", "Calm and crafty. Its layers would animate well, but it loses his fur."),
    ("geometric", "Geometric", "Modern and very simple, but he loses his warmth and detail."),
    ("lineart", "Line art", "Elegant and premium for editorial or the paywall, not for a mascot you play with."),
    ("pixel", "Pixel art", "Fun and retro. A different app, not this one."),
]
MASCOTS = [
    ("firefly", "Glim, the firefly", "My favourite new idea. A firefly glows when you remember, which is your memory sky as a character. Glim could live in the sky while Cap stays your coach."),
    ("star", "Nova, the star", "The same idea as a star: bright when remembered, dim when fading. Simple to draw and animate, a little generic."),
    ("moth", "Mo, the moth", "Soft and sleepy, with constellations on its wings. A gentle night character."),
    ("otter", "Otto, the otter", "Friendly and playful with a pencil behind his ear. Lively, but less calm than Cap."),
    ("redpanda", "Ruby, the red panda", "Smart and charming with glasses. A fine alternative to a capybara, but not clearly better."),
    ("axolotl", "Axel, the axolotl", "Distinctive and very cute. More whimsical than studious."),
    ("hedgehog", "Hazel, the hedgehog", "Cosy and bookish. Her quills make her harder to animate."),
    ("koala", "Kiki, the koala", "Sleepy and sweet, but close to Cap in feeling, so no reason to switch."),
]

MODEL = {"kling4ref": "Kling 4.0, with Cap as a character", "kling4": "Kling 4.0, from the picture alone"}
# (clip, root, title, ratings (looks like Cap, edges, starts on still, motion), note)
BEFORE = {"wave": "wave-kling4-1", "stargaze": "stargaze-kling4-1", "celebrate": "celebrate-kling4-1"}
CLIPS = {
    "wave": ("Wave hello", [
        ("wave-kling4-1", B1, "Before: from the picture alone", ("Good", "Good", "Good", "Good"),
         "Last round's Kling clip. Good, but the model invented his open eyes and the way he winks."),
        ("wave-kling4ref-1", B2, "Now: with the character sheet", ("Good", "Good", "Good", "Good"),
         "Three small waves, a blink to his open eyes (dark, round, one white highlight, as on the sheet) and back. The closest to the sheet yet."),
        ("wave-kling4ref-60", B2, "Now, smoothed to 60 frames a second", ("Good", "Good", "Good", "Good"),
         "The same clip with in-between frames made. Silkier on a 120 Hz phone; 20 seconds of work per clip.")]),
    "stargaze": ("Idle: Cap at his telescope", [
        ("stargaze-kling4-1", B1, "Before: from the picture alone", ("Good", "Good", "Good", "Good"),
         "Last round's best idle. Breathing, a blink, twinkling stars, a steady telescope."),
        ("stargaze-kling4ref-1", B2, "Now: with the character sheet", ("Good", "Good", "Good", "Good"),
         "Quieter: breathing, a tiny ear twitch, stars twinkling, the tripod rock-steady. Kling added a faint ground shadow; the cut-out removes it.")]),
    "celebrate": ("Celebrate", [
        ("celebrate-kling4-1", B1, "Before: from the picture alone", ("Mixed", "Good", "Good", "Good"),
         "Joyful, and it returns to the starting pose. But his laugh was the model's guess: a wide mouth and a tongue, with no teeth."),
        ("celebrate-kling4ref-1", B2, "Now: with the character sheet", ("Good", "Good", "Mixed", "Good"),
         "His laugh is now exactly the sheet's: two small upper teeth and a pink tongue. He starts on the still but lands in a new pose (standing, arms out), so it suits a one-off win, with that landing as his resting pose. The confetti keeps the still's colours: orange, gold and blue.")]),
    "nice": ("Cheer", [
        ("nice-kling4ref-1", B2, "With the character sheet", ("Good", "Good", "Poor", "Mixed"),
         "This one did not begin on the still: Kling followed the sheet's front view instead (he starts 14% smaller and 11 pixels off, facing front). The reference mode can override the picture when a pose resembles a sheet view."),
        ("nice-kling4-1", B2, "Retake: picture pinned as first and last frame", ("Good", "Good", "Good", "Mixed"),
         "Starts and ends exactly on the still, and the loop closes. On the hop his mortarboard pops up and drops back on, a gesture the model invented.")]),
    "sleep": ("Asleep on the cards", [
        ("sleep-kling4ref-1", B2, "With the character sheet", ("Good", "Good", "Good", "Good"),
         "Slow breathing, a rare ear twitch, eyes closed, ends where it began. Hard to fault.")]),
}
ALTS = [
    ("style-plush3d-kling4-1", B2, "Soft 3D plush Cap, waving", ("Good", "Good", "Good", "Good"),
     "He keeps the plush toy look all the way through, and even the fuzzy fur edge cuts out cleanly. A different look from the flat Cap, so only if you want a hero style.", True),
    ("mascot-firefly-kling4-1", B2, "Glim the firefly, glowing", None,
     "He floats, his wings flutter and his belly glows brighter and dimmer, like breathing. Shown on night blue, because a glow belongs on additive light, not a cut-out.", False),
]

SUMMARY = [
    "<b>The character sheet is done.</b> Turnaround, ten faces, close-ups of his teeth, tongue, eyes, paws and hat, a palette with exact colours and a list of what he always and never does. It is one picture you can download and share.",
    "<b>Kling 4.0 can use it.</b> It takes a character defined by several pictures. I gave it Cap's front, three-quarter, side and laugh, plus seven more panels. His laugh now has the sheet's two teeth and tongue, and his open eyes match.",
    "<b>It redid the animations.</b> Wave, idle, celebrate and sleep all came out consistent and clean. One clip, the cheer, did not start on its still, so I retook it with the picture pinned to compare.",
    "<b>The pink edges are fixed (Oct 24).</b> Where an arm or the tassel moved fast, the video smeared the pink background into streaks, and my cut-out kept them: up to about 4,500 stray pixels in a single frame. The cut-out now treats that pink as background. The worst frame of any clip here has under 50 left, which you can't see on night blue, light or the checkerboard. The confetti in the celebrate clip is back to the still's colours too.",
    "<b>Decided: Cap stays as he is.</b> You like him, so the flat Cap is the mascot. The other directions are below only to look at; none is adopted.",
]
NEXT = [
    "<b>Approve the sheet,</b> or tell me what to change: a face, a colour, a rule. Everything else is built from it, so this is the cheap moment to change anything.",
    "<b>Choose how clips start.</b> The character mode gives the best identity but can ignore the starting picture; pinning the first and last frame keeps the loop exact. For production I would use pinned loops for idles and the character mode for one-off reactions that end on a new pose, and check every clip.",
    "<b>Go or no-go on the full set:</b> about 12 to 15 clips at roughly $0.79 each, so about $25 with re-runs, then 3 to 4 days to play them in the app as transparent video.",
    "<b>Glim the firefly</b> is the one idea I'd still keep on the shelf: a small companion that lives in the memory sky while Cap stays your coach. Say so if you want it explored; otherwise I will leave it.",
]


def rating(label, value):
    cls = {"Good": "good", "Mixed": "mixed", "Poor": "poor"}.get(value, "")
    return f'<li><span>{esc(label)}</span><b class="{cls}">{esc(value)}</b></li>'


def clip_card(clip, root, title, ratings, note, copy=True, transparent=True):
    metrics_file = root / "frames" / clip / "metrics.json"
    metrics = json.loads(metrics_file.read_text()) if metrics_file.exists() else None
    for ext in (".webp", "-strip.jpg"):
        if (root / "out" / f"{clip}{ext}").exists():
            shutil.copy(root / "out" / f"{clip}{ext}", IMG / f"{clip}{ext}")
    meta = ""
    if metrics:
        a = metrics["align"]
        off = (a["dx"] ** 2 + a["dy"] ** 2) ** 0.5
        meta = f'{metrics["frames"]} frames at {metrics["fps"]:g} fps · starts {off:.0f} px from the still' + (
            f', {abs(a["size"] - 1) * 100:.0f}% {"bigger" if a["size"] > 1 else "smaller"}' if abs(a["size"] - 1) > 0.02 else "")
    rate = ""
    if ratings:
        rate = ('<ul class="rate">' + rating("Looks like Cap", ratings[0]) + rating("Edges", ratings[1]) + rating("Starts and ends on the still", ratings[2])
                + rating("Motion", ratings[3]) + "</ul>")
    strip = f'<details><summary>Twelve frames, left to right</summary><img class="strip" loading="lazy" src="img/{clip}-strip.jpg" alt="Twelve frames of the clip"></details>' \
        if (IMG / f"{clip}-strip.jpg").exists() else ""
    stage = "stage" if transparent else "stage night-only"
    return f"""
    <article class="clip">
      <div class="{stage}"><img src="img/{clip}.webp" width="480" height="480" loading="lazy" decoding="async" alt="{esc(title)}"></div>
      <h3>{esc(title)}</h3>
      <p class="meta">{esc(meta)}</p>
      {rate}
      <p class="note">{esc(note)}</p>
      {strip}
    </article>"""


def main(extra=None):
    IMG.mkdir(parents=True, exist_ok=True)
    extra = extra or {}
    # the sheet
    shutil.copy(B2 / "cap-character-sheet.png", IMG / "cap-character-sheet.png")
    sheet = Image.open(B2 / "cap-character-sheet.png").convert("RGB")
    sheet.resize((1500, int(sheet.height * 1500 / sheet.width)), Image.LANCZOS).save(IMG / "sheet.jpg", quality=88, optimize=True)
    panels = "".join(
        f'<a href="{jpg(B2 / "sheet" / (n + ".png"), "panel-" + n, 1000)}"><img loading="lazy" src="{jpg(B2 / "sheet" / (n + ".png"), "thumb-" + n, 360, 82)}" alt="{esc(label)}"><span>{esc(label)}</span></a>'
        for n, label in PANELS)
    # animations
    sections = []
    for pose, (title, clips) in CLIPS.items():
        cards = ""
        for clip, root, label, ratings, note in clips:
            if (root / "out" / f"{clip}.webp").exists():
                if note is None:
                    note = extra.get(clip, {}).get("note", "")
                    ratings = extra.get(clip, {}).get("ratings")
                cards += clip_card(clip, root, label, ratings, note)
        sections.append(f'<section><h3 class="pose">{esc(title)}</h3><div class="grid">{cards}</div></section>')
    alts = "".join(clip_card(c, r, t, rt, n, transparent=tr) for c, r, t, rt, n, tr in ALTS)
    styles = "".join(f'<figure><img loading="lazy" src="{jpg(B2 / "directions" / ("style-" + k + ".png"), "style-" + k)}" alt="{esc(t)}"><figcaption><b>{esc(t)}</b>{esc(n)}</figcaption></figure>' for k, t, n in STYLES)
    mascots = "".join(f'<figure><img loading="lazy" src="{jpg(B2 / "directions" / ("mascot-" + k + ".png"), "mascot-" + k)}" alt="{esc(t)}"><figcaption><b>{esc(t)}</b>{esc(n)}</figcaption></figure>' for k, t, n in MASCOTS)
    page = (TEMPLATE.replace("{{SUMMARY}}", "".join(f"<li>{s}</li>" for s in SUMMARY)).replace("{{PANELS}}", panels)
            .replace("{{ANIMATIONS}}", "".join(sections)).replace("{{ALTS}}", alts).replace("{{STYLES}}", styles)
            .replace("{{MASCOTS}}", mascots).replace("{{NEXT}}", "".join(f"<li>{s}</li>" for s in NEXT))
            .replace("{{SPENT}}", extra.get("spent", "about $9")))
    (OUT / "index.html").write_text(page)
    print("wrote", OUT / "index.html", "|", sum(f.stat().st_size for f in OUT.rglob("*") if f.is_file()) // (1024 * 1024), "MB")


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Cap character sheet</title>
<style>
  :root { --bg: #F4F7FB; --surface: #FFFFFF; --ink: #14213D; --ink2: #56627A; --ink3: #6B7489; --line: #E3E8F0; --link: #1866AE; --tangerine: #FF7A1A;
          --good: #1E7F4F; --mixed: #9A6200; --poor: #B3261E; --night1: #0B1222; --night2: #1B2A4A; }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) { --bg: #0B1222; --surface: #151E30; --ink: #F1F4FA; --ink2: #A9B4C8; --ink3: #8B97AD; --line: #24304A; --link: #8FD0FF;
          --good: #6FD6A0; --mixed: #F2C066; --poor: #FF9C93; }
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--ink); font: 16px/1.5 -apple-system, system-ui, sans-serif; }
  main { max-width: 1000px; margin: 0 auto; padding: 28px max(16px, env(safe-area-inset-right, 0px)) 80px max(16px, env(safe-area-inset-left, 0px)); }
  h1 { font-size: 30px; line-height: 1.15; margin: 4px 0 8px; }
  h2 { font-size: 24px; margin: 48px 0 6px; }
  h3 { font-size: 17px; margin: 10px 0 2px; }
  h3.pose { font-size: 19px; margin: 34px 0 0; }
  p { color: var(--ink2); margin: 0 0 12px; }
  a { color: var(--link); }
  ul { margin: 0; padding-left: 20px; color: var(--ink2); }
  li { margin: 7px 0; }
  .eyebrow { font-size: 13px; font-weight: 600; letter-spacing: .06em; text-transform: uppercase; color: var(--ink3); }
  .card { background: var(--surface); border: 1px solid var(--line); border-radius: 22px; padding: 16px 18px; margin: 18px 0; }
  .ask { border-left: 4px solid var(--tangerine); }
  nav { display: flex; gap: 8px; flex-wrap: wrap; margin: 16px 0 0; }
  nav a, .btn { display: inline-flex; align-items: center; min-height: 40px; padding: 0 16px; border-radius: 20px; border: 1px solid var(--line); background: var(--surface); color: var(--ink); text-decoration: none; font-weight: 600; font-size: 14px; }
  .sheet { width: 100%; height: auto; border-radius: 18px; border: 1px solid var(--line); display: block; background: #fff; }
  .panels { display: grid; gap: 10px; grid-template-columns: repeat(auto-fill, minmax(104px, 1fr)); margin-top: 10px; }
  .panels a { text-decoration: none; color: var(--ink2); font-size: 12px; text-align: center; }
  .panels img { width: 100%; height: auto; display: block; border-radius: 12px; border: 1px solid var(--line); background: #fff; }
  .bgs { position: sticky; top: 0; z-index: 5; display: flex; gap: 8px; padding: 10px 0; background: var(--bg); align-items: center; flex-wrap: wrap; }
  .bgs span { font-size: 13px; color: var(--ink3); margin-right: 4px; }
  @media (max-width: 480px) { .bgs span { display: none; } }
  .bgs button { min-height: 38px; padding: 0 13px; border-radius: 20px; border: 1px solid var(--line); background: var(--surface); color: var(--ink); font: 600 14px/1 -apple-system, system-ui, sans-serif; cursor: pointer; }
  .bgs button[aria-pressed="true"] { background: var(--tangerine); border-color: var(--tangerine); color: #14213D; }
  .grid { display: grid; gap: 22px 18px; grid-template-columns: repeat(auto-fit, minmax(min(100%, 280px), 1fr)); align-items: start; margin-top: 10px; }
  .clip { min-width: 0; }
  .stage { aspect-ratio: 1; border-radius: 22px; overflow: hidden; border: 1px solid var(--line); display: grid; place-items: center; }
  .stage img { width: 100%; height: 100%; display: block; object-fit: contain; }
  main[data-bg="night"] .stage, .stage.night-only { background: linear-gradient(180deg, var(--night1), var(--night2)); }
  main[data-bg="light"] .stage { background: #F4F7FB; }
  main[data-bg="checker"] .stage { background: conic-gradient(#d9dde5 25%, #fff 0 50%, #d9dde5 0 75%, #fff 0) 0 0 / 24px 24px; }
  .stage.night-only { background: linear-gradient(180deg, var(--night1), var(--night2)) !important; }
  .meta { font-size: 13px; color: var(--ink3); margin: 0 0 8px; }
  .rate { list-style: none; padding: 0; display: grid; grid-template-columns: 1fr 1fr; gap: 2px 14px; font-size: 14px; margin: 0 0 8px; }
  .rate li { display: flex; justify-content: space-between; margin: 0; border-bottom: 1px solid var(--line); padding: 3px 0; }
  .rate b.good { color: var(--good); } .rate b.mixed { color: var(--mixed); } .rate b.poor { color: var(--poor); }
  .note { font-size: 14px; margin: 0 0 6px; }
  details { font-size: 14px; color: var(--ink2); }
  summary { cursor: pointer; min-height: 32px; }
  .strip { width: 100%; height: auto; border-radius: 12px; border: 1px solid var(--line); margin-top: 6px; }
  .gallery { display: grid; gap: 18px 16px; grid-template-columns: repeat(auto-fill, minmax(min(100%, 210px), 1fr)); margin-top: 12px; }
  figure { margin: 0; }
  figure img { width: 100%; height: auto; display: block; border-radius: 18px; border: 1px solid var(--line); }
  figcaption { font-size: 13px; color: var(--ink2); margin-top: 6px; line-height: 1.4; }
  figcaption b { display: block; color: var(--ink); font-size: 15px; }
  .foot { margin-top: 40px; font-size: 14px; color: var(--ink3); }
</style>
</head>
<body>
<main data-bg="night">
  <div class="eyebrow">Cramless · Cap, round two · Oct 24, 2026</div>
  <h1>Cap's character sheet, and what it unlocks</h1>
  <p>You said the animations drifted because we never wrote Cap down. So I did: a full character sheet, then I gave it to Kling 4.0 and redid the animations. Below that are other styles and other mascots to look at. Spend this round: {{SPENT}} (the cap I set was $12).</p>
  <nav><a href="#sheet">The sheet</a><a href="#animations">Animations</a><a href="#directions">Other directions</a><a href="#next">What I need from you</a></nav>

  <div class="card ask"><strong>What happened</strong><ul>{{SUMMARY}}</ul></div>

  <h2 id="sheet">The character sheet</h2>
  <p>One picture with everything: turnaround, faces, close-ups, palette and rules. Tap it for the full size.</p>
  <a href="img/cap-character-sheet.png"><img class="sheet" src="img/sheet.jpg" alt="Cap's character sheet" loading="lazy"></a>
  <p style="margin-top:12px"><a class="btn" href="img/cap-character-sheet.png" download>Download the sheet (PNG)</a></p>
  <details><summary>All 19 panels, one by one</summary><div class="panels">{{PANELS}}</div></details>

  <h2 id="animations">The animations, redone</h2>
  <p>Each starts on the real still and is cut out onto transparency. Switch the background to prove it. Where there was a clip last round, it sits next to the new one.</p>
  <div class="bgs" role="group" aria-label="Background behind Cap">
    <span>Behind Cap:</span>
    <button type="button" data-bg="night" aria-pressed="true">Night sky</button>
    <button type="button" data-bg="light" aria-pressed="false">Light</button>
    <button type="button" data-bg="checker" aria-pressed="false">Checkerboard</button>
  </div>
  {{ANIMATIONS}}

  <h2 id="directions">Other directions</h2>
  <p>Two of these move: a plush 3D Cap, and a glowing firefly.</p>
  <div class="grid">{{ALTS}}</div>
  <h3 class="pose">Ten styles of Cap</h3>
  <p>The same capybara, drawn ten ways. My notes are under each.</p>
  <div class="gallery">{{STYLES}}</div>
  <h3 class="pose">Eight other mascots</h3>
  <p>Each was briefed to be calm, kind and a little wise, never guilt-tripping.</p>
  <div class="gallery">{{MASCOTS}}</div>

  <h2 id="next">What I need from you</h2>
  <div class="card"><ul>{{NEXT}}</ul></div>
  <p class="foot">The clips here are animated images because every phone plays them. In the app they would be transparent HEVC video, which this Mac can make and Apple's player reads with its transparency. Prices are fal's list prices; fal doesn't report the real charge of a single run.</p>
</main>
<script>
  var main = document.querySelector('main');
  document.querySelectorAll('.bgs button').forEach(function (b) {
    b.addEventListener('click', function () {
      main.dataset.bg = b.dataset.bg;
      document.querySelectorAll('.bgs button').forEach(function (o) { o.setAttribute('aria-pressed', o === b ? 'true' : 'false'); });
    });
  });
</script>
</body>
</html>
"""

if __name__ == "__main__":
    main()
