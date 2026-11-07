# Capling

A little every day. Ready on exam day.

Capling (code name Cramless: the folders, targets and module keep it) is an exam-readiness study coach for iPhone. You snap pages, import PDFs, record lectures or bring
your Quizlet and Anki decks. It turns them into questions you approve, each linked to the page or the moment it
came from. You study 10–15 minutes a day, with answers graded in your own words. You see how ready you are per
exam and per topic, with a plan that bends when life happens.

The plan, the market research and the web prototype that preceded this app are in `../docs/rethink/`.

## What's here

| Folder | What it is |
|---|---|
| `Cramless/` | The iOS app (SwiftUI, iOS 26+, built with Xcode 27) |
| `CramlessWidgets/` | Home and Lock Screen widgets, Live Activities, the Start control |
| `Shared/` | Code compiled into both the app and the widgets |
| `CramlessTests/` | Unit and hosted-view tests |
| `supabase/` | The backend: schema with row-level security, the AI relay, accounts, Squad, App Store notifications |
| `docs/` | `BUILD.md` (what was built, by whom, what's left), `design.md`, `relay-contract.md` |
| `scripts/` | `xc.sh` (build and test), `shots.sh` (headless screenshots) |

`CLAUDE.md` is the working guide: architecture, rules, the design system and the launch hooks.

## Run it

```bash
brew install xcodegen                       # once
scripts/xc.sh build                         # generates the project and builds for the simulator
open Cramless.xcodeproj                     # or run from Xcode (the scheme attaches Cramless.storekit)
```

The app needs no keys or backend to run. With `Secrets.xcconfig` blank (the default), it works on this iPhone
alone:
- Questions, grades and Cap's answers come from the offline rules on the iPhone (Apple's on-device model is switched off in this build, `AIBuild.onDeviceModelEnabled`).
- Nothing syncs.

With a Supabase project configured, three more things work:
- cloud AI through the relay, after the person agrees
- accounts and sync
- Squad

For demos and screenshots, launch with `CRAMLESS_UITEST=1`. It gives you an in-memory demo world, canned AI
replies with realistic timing, and a route per screen; see `CLAUDE.md`.

Tests:

```bash
SIM_ID=<your simulator udid> scripts/xc.sh test
cd supabase/functions && deno task test
```

## Before the App Store

The owner provides these, and nothing in the repo invents them:

1. **A Supabase project.** Put its host and anon key in `Secrets.xcconfig`. Apply the migrations with
   `supabase db push` and deploy the functions with `supabase functions deploy ai account appstore-notify`.
2. **Function secrets:**
   - `OPENAI_API_KEY` (every AI route runs on OpenAI)
   - `APPLE_APP_ID` (the numeric App Store id)
   - the App Store Connect values listed in `supabase/README.md`
3. **In Supabase:**
   - Sign in with Apple, using the bundle id `com.loopware.Capling` as the client id
   - the email template that sends a 6-digit code
4. **App Store Connect:**
   - the four products from `Cramless.storekit`: Pro Yearly with a 7-day trial, Pro Monthly, Squad Yearly with a
     7-day trial, and the Exam Pass (non-renewing)
   - the server notifications URL
   - Terms and Privacy URLs: both are set in `StoreCatalog` (Apple's standard terms and loopware.app/privacy), and App Review
     requires both for subscriptions
5. **Run the two checks that need you** (see `docs/BUILD.md`, "Verified against real services", for what is
   already proven on this Mac and on a local Supabase stack):
   - `OPENAI_API_KEY=… deno task live`, in `supabase/functions`: real OpenAI on the sample page, with verdicts
     and cost.
   - With your iPhone unlocked, `scripts/device_probe.sh <udid>`. The debug build is already installed on your
     iPhone 15 Pro. It covers the phone's own AI, speech round trip, VisionKit, a Live Activity and haptics hardware.
   - Then by hand: scan a page with the camera, record a minute of a lecture with the screen locked, feel the
     haptics, and try Sign in with Apple once the Supabase provider is set up.
6. **A domain for Squad invite links.** `capling.app/squad/<code>` is a placeholder.
7. **A final name check.** "Cramless" was the plan's pick, not yet trademark-searched.
