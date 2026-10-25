# Studyly rethink (October 2026)

The plan, market research, brand options and a clickable prototype for rebuilding Studyly as **Cramless**: a native SwiftUI study app that turns class material into a daily plan, grades answers in the student's own words and shows readiness per exam. Nothing here is the app itself: the app was built from this plan and lives in `../../Cramless/` (it is called Capling now; Cramless is its code name).

- **Plan (artifact):** https://claude.ai/artifact/4myxZn4yKAd2T1nukFuxfb (private; published from the w@startbase.ai account)
- **On the tailnet:** https://macbook-pro.tail9699dc.ts.net:8823/ (plan) and https://macbook-pro.tail9699dc.ts.net:8823/app/ (prototype)

## Layout

| Path | What it is |
|---|---|
| `site/plan.html` | The plan page. Artifact source, so it has no `<!doctype>`/`<head>` skeleton |
| `site/index.html` | Generated from `plan.html` by `tools/build.py` for local and Tailscale viewing. Don't edit |
| `site/app/` | The prototype: `index.html`, `app.css`, `core.js` (navigation, sheets, rings), `scenes.js` (live onboarding demos), `screens.js`, `data.js` (sample content and prices) |
| `site/img/` | Icon options, Cap mascot poses, the scanned textbook page, touch icon |
| `site/shots/` | Prototype screenshots used in the plan |
| `brand/prompts.json`, `brand/generate.py` | The GPT Image 2.5 (fal) prompt book and renderer. `brand/raw/` holds the 1024 px masters (~16 MB) |
| `tools/serve.py`, `tools/build.py` | No-cache static server; plan wrapper |

Jump straight to a prototype screen with a hash, for example `app/index.html#screen=session` or `#embed&screen=paywall` (`embed` draws a simulated status bar).

## Serving it to the phone

```bash
python3 docs/rethink/tools/serve.py 8823                     # binds 127.0.0.1 only
tailscale serve --bg --https=8823 http://127.0.0.1:8823       # already configured; persists
```

Stop with `lsof -ti :8823 | xargs kill` and `tailscale serve --https=8823 off`.

## Updating

Edit `site/plan.html` (or the prototype files), run `python3 docs/rethink/tools/build.py`, reload the phone. To update the artifact, republish `site/plan.html` to the same URL with the `app/`, `img/` and `shots/` files.

Regenerate brand art with `FAL_KEY=… python3 docs/rethink/brand/generate.py [job_id …]` (no ids renders only the jobs without a PNG yet), then convert to WebP with `cwebp` as in the existing `site/img/` files.
