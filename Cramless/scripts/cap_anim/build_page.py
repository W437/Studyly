#!/usr/bin/env python3
"""Builds the Cap animation test page for the review site: build/review/cap-animation-test/index.html.

Reads what cap_anim.py wrote (build/cap-anim/: frames/<clip>/metrics.json, out/<clip>.webp, out/<clip>-strip.jpg,
ledger.jsonl) and the human judgement in build/cap-anim/verdicts.json:

    {"summary": ["…"], "next": ["…"], "models": {"kling4": {"name": "Kling 4.0", "cost": "$0.79", "note": "…"}},
     "clips": {"wave-kling4-1": {"on_model": "Good", "edges": "Good", "loop": "Good", "motion": "Good", "note": "…"}}}

Clips are listed under their pose, in the order given by "order" (best first), with the original still first.
"""
import html, json, shutil, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
BUILD = ROOT / "build/cap-anim"
OUT = ROOT / "build/review/cap-animation-test"
ASSETS = ROOT / "Cramless/Resources/Assets.xcassets"

POSE_TITLES = {
    "stargaze": ("Idle: Cap at his telescope", "The Today screen's Cap. He should breathe, blink and twinkle, and hold still where he must: the telescope and tripod."),
    "wave": ("Wave hello", "A simple friendly motion: one paw moving, the rest of him still."),
    "celebrate": ("Celebrate", "The hardest one: a hop, both arms up, confetti drifting."),
}
RATING_CLASS = {"Good": "good", "Mixed": "mixed", "Poor": "poor"}


def esc(s):
    return html.escape(str(s), quote=True)


def rating(label, value):
    cls = RATING_CLASS.get(value, "")
    return f'<li><span>{esc(label)}</span><b class="{cls}">{esc(value)}</b></li>'


def clip_card(clip, models, verdicts):
    metrics = json.loads((BUILD / "frames" / clip / "metrics.json").read_text())
    model = clip.split("-")[1]
    info = models.get(model, {})
    v = verdicts.get(clip, {})
    name = v.get("name", info.get("name", model))
    align = metrics.get("align", {})
    off = (align.get("dx", 0) ** 2 + align.get("dy", 0) ** 2) ** 0.5
    size = align.get("size", 1)
    start_text = f"starts {off:.1f} px from the still" + (f", {abs(size - 1) * 100:.0f}% {'bigger' if size > 1 else 'smaller'}" if abs(size - 1) > 0.01 else "")
    img = f"img/{clip}.webp"
    strip = f"img/{clip}-strip.jpg"
    return f"""
    <article class="clip">
      <div class="stage"><img src="{img}" width="480" height="480" loading="lazy" decoding="async" alt="{esc(name)} animating Cap"></div>
      <h3>{esc(name)}</h3>
      <p class="meta">{esc(v.get('cost', info.get('cost', '')))} · {metrics['frames']} frames at {metrics['fps']:g} fps · {esc(start_text)}</p>
      <ul class="rate">{rating('Looks like Cap', v.get('on_model', '–'))}{rating('Edges', v.get('edges', '–'))}{rating('Loop', v.get('loop', '–'))}{rating('Motion', v.get('motion', '–'))}</ul>
      <p class="note">{esc(v.get('note', ''))}</p>
      <details><summary>Twelve frames, left to right</summary><img class="strip" loading="lazy" src="{strip}" alt="Twelve frames spread over the clip" width="1440" height="480"></details>
    </article>"""


def main():
    verdicts = json.loads((BUILD / "verdicts.json").read_text())
    models = verdicts.get("models", {})
    order = verdicts.get("order", {})
    ledger = [json.loads(l) for l in (BUILD / "ledger.jsonl").read_text().splitlines() if l.strip()]
    estimated = sum(e["est"] for e in ledger if e.get("event") == "submit")
    clips = sorted(p.name for p in (BUILD / "frames").iterdir() if (p / "metrics.json").exists())
    (OUT / "img").mkdir(parents=True, exist_ok=True)
    for clip in clips:
        for ext in (".webp", "-strip.jpg"):
            shutil.copy(BUILD / "out" / f"{clip}{ext}", OUT / "img" / f"{clip}{ext}")
    sections = []
    for pose, (title, blurb) in POSE_TITLES.items():
        mine = [c for c in clips if c.startswith(pose + "-")]
        if not mine:
            continue
        ranked = [c for c in order.get(pose, []) if c in mine] + [c for c in mine if c not in order.get(pose, [])]
        shutil.copy(ASSETS / f"Cap-{pose}.imageset/cap-{pose}.png", OUT / "img" / f"{pose}-still.png")
        cards = "".join(clip_card(c, models, verdicts.get("clips", {})) for c in ranked)
        sections.append(f"""
  <section>
    <h2>{esc(title)}</h2>
    <p>{esc(blurb)}</p>
    <div class="grid">
      <article class="clip still">
        <div class="stage"><img src="img/{pose}-still.png" width="480" height="480" alt="The still of Cap, for comparison"></div>
        <h3>The still</h3>
        <p class="meta">What the clips start and end on</p>
      </article>{cards}
    </div>
  </section>""")
    labels = ["Model", "About, per clip", "Stays Cap", "Motion", "Verdict"]
    rows = "".join("<tr>" + "".join(f'<td data-label="{l}">{c}</td>' for l, c in zip(labels, r)) + "</tr>" for r in verdicts.get("table", []))
    summary = "".join(f"<li>{s}</li>" for s in verdicts.get("summary", []))
    nxt = "".join(f"<li>{s}</li>" for s in verdicts.get("next", []))
    page = TEMPLATE.replace("{{SECTIONS}}", "".join(sections)).replace("{{SUMMARY}}", summary).replace("{{TABLE}}", rows).replace("{{NEXT}}", nxt) \
        .replace("{{COUNT}}", str(len(clips))).replace("{{SPENT}}", f"{round(estimated / 1.15)}")
    (OUT / "index.html").write_text(page)
    print(f"wrote {OUT / 'index.html'} with {len(clips)} clips")


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Cap animation test</title>
<style>
  :root { --bg: #F4F7FB; --surface: #FFFFFF; --ink: #14213D; --ink2: #56627A; --ink3: #6B7489; --line: #E3E8F0; --link: #1866AE; --tangerine: #FF7A1A;
          --good: #1E7F4F; --mixed: #9A6200; --poor: #B3261E; --night1: #0B1222; --night2: #1B2A4A; }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) { --bg: #0B1222; --surface: #151E30; --ink: #F1F4FA; --ink2: #A9B4C8; --ink3: #8B97AD; --line: #24304A; --link: #8FD0FF;
          --good: #6FD6A0; --mixed: #F2C066; --poor: #FF9C93; }
  }
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--bg); color: var(--ink); font: 16px/1.5 -apple-system, system-ui, sans-serif; }
  main { max-width: 1000px; margin: 0 auto; padding: 28px max(16px, env(safe-area-inset-right, 0px)) 72px max(16px, env(safe-area-inset-left, 0px)); }
  h1 { font-size: 30px; line-height: 1.15; margin: 4px 0 8px; }
  h2 { font-size: 22px; margin: 40px 0 6px; }
  h3 { font-size: 17px; margin: 10px 0 2px; }
  p { color: var(--ink2); margin: 0 0 12px; }
  a { color: var(--link); }
  ul { margin: 0; padding-left: 20px; color: var(--ink2); }
  li { margin: 6px 0; }
  .eyebrow { font-size: 13px; font-weight: 600; letter-spacing: .06em; text-transform: uppercase; color: var(--ink3); }
  .card { background: var(--surface); border: 1px solid var(--line); border-radius: 22px; padding: 16px 18px; margin: 18px 0; }
  .ask { border-left: 4px solid var(--tangerine); }
  .bgs { position: sticky; top: 0; z-index: 5; display: flex; gap: 8px; padding: 10px 0; background: var(--bg); align-items: center; flex-wrap: wrap; }
  .bgs span { font-size: 13px; color: var(--ink3); margin-right: 4px; }
  @media (max-width: 480px) { .bgs span { display: none; } }
  .bgs button { min-height: 38px; padding: 0 13px; border-radius: 20px; border: 1px solid var(--line); background: var(--surface); color: var(--ink); font: 600 14px/1 -apple-system, system-ui, sans-serif; cursor: pointer; }
  .bgs button[aria-pressed="true"] { background: var(--tangerine); border-color: var(--tangerine); color: #14213D; }
  .grid { display: grid; gap: 22px 18px; grid-template-columns: repeat(auto-fit, minmax(min(100%, 260px), 1fr)); align-items: start; margin-top: 12px; }
  .clip { min-width: 0; }
  .stage { aspect-ratio: 1; border-radius: 22px; overflow: hidden; border: 1px solid var(--line); display: grid; place-items: center; }
  .stage img { width: 100%; height: 100%; display: block; object-fit: contain; }
  main[data-bg="night"] .stage { background: linear-gradient(180deg, var(--night1), var(--night2)); }
  main[data-bg="light"] .stage { background: #F4F7FB; }
  main[data-bg="checker"] .stage { background: conic-gradient(#d9dde5 25%, #fff 0 50%, #d9dde5 0 75%, #fff 0) 0 0 / 24px 24px; }
  .meta { font-size: 13px; color: var(--ink3); margin: 0 0 8px; }
  .rate { list-style: none; padding: 0; display: grid; grid-template-columns: 1fr 1fr; gap: 2px 14px; font-size: 14px; margin: 0 0 8px; }
  .rate li { display: flex; justify-content: space-between; margin: 0; border-bottom: 1px solid var(--line); padding: 3px 0; }
  .rate b.good { color: var(--good); } .rate b.mixed { color: var(--mixed); } .rate b.poor { color: var(--poor); }
  .note { font-size: 14px; margin: 0 0 6px; }
  details { font-size: 14px; color: var(--ink2); }
  summary { cursor: pointer; min-height: 32px; }
  .strip { width: 100%; height: auto; border-radius: 12px; border: 1px solid var(--line); margin-top: 6px; }
  .still .stage { background: var(--surface); }
  main[data-bg="night"] .still .stage { background: linear-gradient(180deg, var(--night1), var(--night2)); }
  main[data-bg="checker"] .still .stage { background: conic-gradient(#d9dde5 25%, #fff 0 50%, #d9dde5 0 75%, #fff 0) 0 0 / 24px 24px; }
  .wrap { overflow-x: auto; }
  .table { width: 100%; border-collapse: collapse; font-size: 14px; margin-top: 8px; }
  .table th, .table td { text-align: left; padding: 7px 8px 7px 0; border-bottom: 1px solid var(--line); vertical-align: top; color: var(--ink2); }
  .table th { color: var(--ink3); font-weight: 600; font-size: 12px; }
  .table td:first-child { color: var(--ink); font-weight: 600; white-space: nowrap; }
  @media (max-width: 640px) {
    .table thead { display: none; }
    .table, .table tbody, .table tr, .table td { display: block; width: 100%; }
    .table tr { padding: 10px 0; border-bottom: 1px solid var(--line); }
    .table td { border: 0; padding: 1px 0; }
    .table td::before { content: attr(data-label) ": "; color: var(--ink3); font-weight: 600; }
    .table td:first-child { font-size: 16px; white-space: normal; }
    .table td:first-child::before { content: ""; }
    .table td:last-child { color: var(--ink); font-weight: 600; }
  }
  .foot { margin-top: 40px; font-size: 14px; color: var(--ink3); }
</style>
</head>
<body>
<main data-bg="night">
  <div class="eyebrow">Cramless · Cap in motion · Oct 24, 2026</div>
  <h1>Can Cap really move?</h1>
  <p>A test, not a feature: {{COUNT}} short clips made from Cap's own pictures by the newest video models on fal. Each starts and ends on the still, on a flat background that is cut away afterwards, so he sits on any colour. About ${{SPENT}} spent of the $10 allowed.</p>

  <div class="card ask">
    <strong>What I found</strong>
    <ul>{{SUMMARY}}</ul>
  </div>

  <div class="card">
    <strong>The models, side by side</strong>
    <div class="wrap"><table class="table"><thead><tr><th>Model</th><th>About, per clip</th><th>Stays Cap</th><th>Motion</th><th>Verdict</th></tr></thead><tbody>{{TABLE}}</tbody></table></div>
  </div>

  <div class="bgs" role="group" aria-label="Background behind Cap">
    <span>Behind Cap:</span>
    <button type="button" data-bg="night" aria-pressed="true">Night sky</button>
    <button type="button" data-bg="light" aria-pressed="false">Light</button>
    <button type="button" data-bg="checker" aria-pressed="false">Checkerboard</button>
  </div>
  {{SECTIONS}}

  <div class="card">
    <strong>What I'd do next</strong>
    <ul>{{NEXT}}</ul>
  </div>
  <p class="foot">These are animated images, because every phone plays them; in the app they would be transparent HEVC video, which iOS plays natively (checked on this Mac: the alpha channel survives).</p>
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
