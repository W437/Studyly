#!/usr/bin/env python3
"""The owner's page for the launch store refresh: old beside new, the description and what changed, the video, the header and search card.

    python3 -P scripts/store_art/build_launch_page.py --old <folder of the old 01..08.png> --new build/listing/launch/final/en-US \
        --video scripts/store_video/renders/capling-app-preview.mp4 --art <folder with header-en-US.png, search-en-US.png> \
        --old-words <old description.txt> --out ~/Sites/capling-launch-store

Self-contained: every picture sits beside the page. `content` below holds the words; the numbers in them are read off the screens by hand.
"""
import argparse
import html
import json
import os
import shutil
import subprocess

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
COPY = os.path.join(HERE, "..", "asc", "capling_copy.json")

FRAMES = [
    ("01", "Get ready for Exams", "Same design. The path now says what the fixed engine says: 53% today, 91% on exam day, labelled “Projected, if you follow the plan”. Dates are now in US format."),
    ("02", "Answer in your own Words", "Same answer, retaken on today's screen."),
    ("03", "Know your Readiness", "The big change. The grade card is gone: readiness is the only percentage, and the sentence ends “A projection from your recall so far, not a promise.” It's now the Bio 101 Midterm, the same exam as image 1, and the free mock starts at the bottom."),
    ("04", "Snap pages into Questions", "Same step, retaken on today's screen."),
    ("05", "Ask Cap for Quizzes", "Ask's calmer chat. I changed the word from “Cards” to “Quizzes”: the app now says “questions”, and this reply is a clean one. See the choice below."),
    ("06", "Record Lectures", "Now with playback. The player is the page's real bar, lifted up from the bottom of the screen so it fits in the picture."),
    ("07", "Light up your Memory", "Real numbers now: 63 stars, 20 dim, 11 not yet lit, the same 20 that Today shows. The old one had 103 from a test setting, so this sky has fewer stars and looks a little quieter."),
    ("08", "Keep your Streak", "The month now marks exams and exam eves."),
]
OPTIONS_WORD = [("05", "Quizzes", "My pick. Says “Add 3 questions”, the app's own word."), ("05-cards", "Cards", "The old word. The chat behind the header shows through more, and it shows flashcards."), ("05-help", "Help", "A snapped problem with hints first. Strong, and new, but it says less about making things.")]
OPTIONS_EXTRA = [("x-notice", "Mix-ups", "Cap speaking first, the biggest new thing. My first pick."), ("x-mock", "Mock", "Says mock exams are free. My second pick."), ("x-loud", "Loud", "Study out loud. Lovely, but a quieter screen.")]
NEEDS = [
    "<b>The 8 screenshots.</b> Good to upload?",
    "<b>Image 5's word:</b> Quizzes (my pick), Cards or Help.",
    "<b>Two more images?</b> Apple takes 10, and the set has 8. I'd add Mix-ups and Mock.",
    "<b>The description.</b> Read the English. Once it's right, the 35 translated languages still need a native read: they are my drafts. (The other three of the 39 are English.)",
    "<b>The video.</b> Apple's rule says previews must be screen captures, and this one is drawn. I'd keep it out of the preview slot for the first submission, so it can't hold up the launch, and film a real one for that slot. Your call.",
    "<b>The header and search card.</b> I'd leave them. One small thing: see below.",
]
CHANGES = [
    ("Dropped", "“A projected grade, always labelled as a projection”. There's no projected grade any more; a letter shows only after real grades are logged."),
    ("Fixed", "The Pro sentence said plans and readiness were paid. They're free, and so are mocks. It now says what the paywall says, including “Fair use applies”."),
    ("Added", "Cap's cards, mock exams, the syllabus scan, studying out loud, Teach Cap, snapping a problem, hearing a lecture again, Quiet mode."),
    ("Corrected", "“Import PDFs and slides”: the app opens PDF files only, so it now says slides saved as PDF."),
    ("Corrected", "“Every question links back to the page”: imported and hand-made ones don't. Now “Questions from your notes … Anything else is marked”."),
    ("Corrected", "“Nothing to lose”: a streak can break. Now “your best streak is kept”."),
    ("Corrected", "“An exam on your calendar”: Cap adds it to the app, not to the phone's calendar. Now “an exam date”."),
    ("Corrected", "“Unlimited scans”: there's a fair-use ceiling. Now “no weekly limit”, as the paywall says."),
    ("Corrected", "Pro and the free AI allowance do nothing until Cloud AI is on, so both now start “With Cloud AI on”. Multiple choice and fill-ins aren't graded by Cloud AI, so it says “own-words answers”, and web research says “18 and over”."),
    ("Left alone", "Subtitle, keywords and promotional text: nothing stale. One thought: the subtitle says “10 minutes a day” while the screens say 15. Both are real settings."),
]
UPLOAD = [
    "Screenshots, English: the chosen images as 01 to 10, replacing what's there.",
    "Words: the description in all 39 languages (only the description changes).",
    "Video: replace the old one (it still says 42% to 91%), or take it off the preview slot.",
    "App Review notes: the new draft is in the words file, with a list of what to check on your phone first.",
    "Then check what's still missing. You submit; I never do.",
]


def jpg(src, dst, width):
    im = Image.open(src).convert("RGB")
    im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    im.save(dst, quality=86, optimize=True)


def figure(path, full, caption, alt):
    return (f'<figure><a href="{full}"><img src="{path}" alt="{html.escape(alt)}" loading="lazy" width="645" height="1398"></a>'
            f"<figcaption>{caption}</figcaption></figure>")


def description_html(old, new):
    old_lines = set(old.splitlines())
    rows = []
    for line in new.splitlines():
        cls = "" if line in old_lines or not line.strip() else ' class="new"'
        head = line.isupper() and line.strip()
        tag = "h4" if head else "p"
        rows.append(f"<{tag}{cls}>{html.escape(line)}</{tag}>" if line.strip() else "")
    return "\n".join(r for r in rows if r)


def build(a):
    out = os.path.expanduser(a.out)
    if os.path.isdir(out):
        shutil.rmtree(out)
    os.makedirs(out)
    for n, _, _ in FRAMES:
        jpg(os.path.join(a.old, f"{n}.png"), os.path.join(out, "shots", f"old-{n}.jpg"), 645)
        jpg(os.path.join(a.new, f"{n}.png"), os.path.join(out, "shots", f"new-{n}.jpg"), 645)
    full = os.path.join(out, "full")
    os.makedirs(full)
    for f in sorted(os.listdir(a.new)):
        if f.endswith(".png"):
            shutil.copy(os.path.join(a.new, f), os.path.join(full, f))
    for n, _, _ in OPTIONS_WORD + OPTIONS_EXTRA:
        jpg(os.path.join(a.new, f"{n}.png"), os.path.join(out, "shots", f"new-{n}.jpg"), 645)
    os.makedirs(os.path.join(out, "video"))
    shutil.copy(a.video, os.path.join(out, "video", "capling-app-preview.mp4"))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-ss", "13.2", "-i", a.video, "-frames:v", "1", "-q:v", "3", os.path.join(out, "video", "poster.jpg")], check=True)
    for name in ("header-en-US", "search-en-US"):
        jpg(os.path.join(a.art, f"{name}.png"), os.path.join(out, "shots", f"{name}.jpg"), 1200)

    en = json.load(open(COPY))["en-US"]
    old = open(a.old_words).read()
    pairs = "\n".join(
        f'<section class="pair"><h3>{n}. {html.escape(t)}</h3><div class="two">'
        + figure(f"shots/old-{n}.jpg", f"shots/old-{n}.jpg", "Old", f"Old image {n}")
        + figure(f"shots/new-{n}.jpg", f"full/{n}.png", "New", f"New image {n}, {t}")
        + f"</div><p>{html.escape(c)}</p></section>" for n, t, c in FRAMES)
    word = "".join(figure(f"shots/new-{n}.jpg", f"full/{n}.png", f"<b>{t}</b><br>{html.escape(c)}", t) for n, t, c in OPTIONS_WORD)
    extra = "".join(figure(f"shots/new-{n}.jpg", f"full/{n}.png", f"<b>{t}</b><br>{html.escape(c)}", t) for n, t, c in OPTIONS_EXTRA)
    needs = "".join(f"<li>{x}</li>" for x in NEEDS)
    changes = "".join(f"<li><b>{k}.</b> {html.escape(v)}</li>" for k, v in CHANGES)
    upload = "".join(f"<li>{html.escape(x)}</li>" for x in UPLOAD)
    page = TEMPLATE.format(needs=needs, pairs=pairs, word=word, extra=extra, changes=changes, upload=upload, commit=html.escape(a.commit),
                           description=description_html(old, en["description"]), subtitle=html.escape(en["subtitle"]), promo=html.escape(en["promotionalText"]),
                           length=len(en["description"]), duo=a.duo_note)
    open(os.path.join(out, "index.html"), "w").write(page)
    print(os.path.join(out, "index.html"))


TEMPLATE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Capling store page</title>
<style>
:root {{ --bg:#f4f7fb; --card:#fff; --ink:#14213d; --ink2:#56627a; --line:#dde4ee; --new:#e3f7ef; --accent:#b84a00; color-scheme: light dark; }}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{ --bg:#0b1220; --card:#151f33; --ink:#eef2f8; --ink2:#a4afc4; --line:#2a3650; --new:#143a2e; --accent:#ffa45c; }} }}
:root[data-theme="dark"] {{ --bg:#0b1220; --card:#151f33; --ink:#eef2f8; --ink2:#a4afc4; --line:#2a3650; --new:#143a2e; --accent:#ffa45c; }}
* {{ box-sizing:border-box; }}
html {{ -webkit-text-size-adjust:100%; }}
body {{ margin:0; background:var(--bg); color:var(--ink); font:17px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }}
main {{ max-width:980px; margin:0 auto; padding:24px 16px 80px; }}
h1 {{ font-size:30px; line-height:1.15; margin:0 0 6px; }}
h2 {{ font-size:23px; margin:44px 0 10px; }}
h3 {{ font-size:17px; margin:0 0 10px; }}
h4 {{ font-size:14px; letter-spacing:.04em; margin:18px 0 4px; }}
p {{ margin:0 0 10px; }}
.sub {{ color:var(--ink2); }}
.card {{ background:var(--card); border:1px solid var(--line); border-radius:16px; padding:16px; }}
ol, ul {{ margin:0; padding-left:22px; }} li {{ margin:0 0 8px; }}
.pair {{ background:var(--card); border:1px solid var(--line); border-radius:16px; padding:16px; margin:0 0 14px; }}
.two {{ display:grid; grid-template-columns:1fr 1fr; gap:10px; margin-bottom:10px; }}
.three {{ display:grid; grid-template-columns:repeat(auto-fit, minmax(150px, 1fr)); gap:12px; }}
figure {{ margin:0; min-width:0; }}
img, video {{ display:block; max-width:100%; height:auto; border-radius:10px; }}
figcaption {{ font-size:14px; color:var(--ink2); margin-top:6px; }}
.words p, .words h4 {{ padding:2px 6px; margin:0 -6px; border-radius:6px; }}
.words p {{ margin-bottom:4px; }}
.words .new {{ background:var(--new); }}
video {{ width:100%; max-width:320px; background:#000; }}
.wide {{ margin-bottom:12px; }}
@media (min-width:760px) {{ .pairs {{ display:grid; grid-template-columns:1fr 1fr; gap:14px; }} .pair {{ margin:0; }} }}
</style></head><body><main>
<h1>Capling's store page, redone</h1>
<p class="sub">7 November 2026. Screens from commit {commit}. Nothing is uploaded: this is for you to approve.</p>

<h2>What I need from you</h2>
<div class="card"><ol>{needs}</ol></div>

<h2>The screenshots, old and new</h2>
<p class="sub">Same look you picked: the Gizmo style on the Sky ground. Every number is what the app shows with the demo's clock pinned. Tap a new one to see it full size.</p>
<div class="pairs">{pairs}</div>

<h2>Image 5: which word?</h2>
<div class="three">{word}</div>

<h2>Two more images?</h2>
<p class="sub">What the first set never showed. Apple's limit is 10, so two at most.</p>
<div class="three">{extra}</div>

<h2>The description</h2>
<p class="sub">Green lines are new or changed. {length} characters of Apple's 4,000.</p>
<div class="card"><ul>{changes}</ul></div>
<div class="card words" style="margin-top:14px">{description}</div>
<p class="sub" style="margin-top:12px">Subtitle (unchanged): {subtitle}<br>Promotional text (unchanged): {promo}</p>
<p class="sub">Every claim was checked against the app's code. The 35 translated languages are updated and within Apple's limits, in the repo's words files. They are drafts for a native read.</p>

<h2>The video</h2>
<div class="card">
<video src="video/capling-app-preview.mp4" poster="video/poster.jpg" controls playsinline preload="metadata"></video>
<p style="margin-top:12px">The readiness part now goes from 53% to 91%, the same exam and numbers as images 1 and 3, and the sky says 20 dim. The “Nice!” line uses the app's current words. Timing and sound are unchanged, with no new music spend. The chart stays labelled “Projected, if you follow the plan”.</p>
<p><b>The risk is still there.</b> Apple says previews may use only screen captures of the app, and this is drawn. It might pass, but a refusal would delay the launch. I'd film a real 25-second preview for that slot and keep this one for the header and search video slots, which take any video. The sound is checked by analysis only, so please listen.</p>
</div>

<h2>Header and search card</h2>
<div class="card">
<img class="wide" src="shots/search-en-US.jpg" alt="The search card: Ready on exam day." width="1200" height="800">
<img class="wide" src="shots/header-en-US.jpg" alt="The header: Ready on exam day." width="1200" height="514">
<p><b>Does it promise?</b> “Ready on exam day.” is the app's own welcome line. It's a goal, with no grade in it, so I'm comfortable. It is the strongest words on the page, though, next to an exam page that says “not a promise”.</p>
<p><b>Does it still match?</b> Yes in look and wording: the app's session card still says “ready · 2 days left” and “On track for 80%”. Its example numbers (42% to 78%) came from the old engine; the same card in today's demo says 41% to 71%. It's an example, not a claim about any student, so I left it. Changing it means redrawing and re-uploading the pictures for all 39 languages, if you want it exact.</p>
</div>

<h2>Other languages and iPhone Duo</h2>
<div class="card">
<p><b>Screenshots in other languages:</b> not done. The big words have no translations, the 3D lettering has no fonts for many alphabets, and the app's own screens are English only, so translated words would sit over English screens. Apple shows the English set in every language that has none. I'd do these when the app itself is translated.</p>
<p><b>iPhone Duo:</b> {duo}</p>
</div>

<h2>When you approve</h2>
<div class="card"><ol>{upload}</ol></div>
</main></body></html>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--old", required=True)
    ap.add_argument("--new", required=True)
    ap.add_argument("--video", required=True)
    ap.add_argument("--art", required=True)
    ap.add_argument("--old-words", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--commit", required=True)
    ap.add_argument("--duo-note", required=True)
    build(ap.parse_args())


if __name__ == "__main__":
    main()
