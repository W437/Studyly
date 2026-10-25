# Capling (iOS)

**The name.** The product is **Capling** (it was Cramless until 2026-10-25, when two other student products turned out to use that
name, with all its domains). The code keeps the old name as its code name: the module (`import Cramless`), the targets, the folders
and file names, type names (`CramlessLink`), the DEBUG switches (`CRAMLESS_*`) and the backend's database functions
(`cramless_*`). What people see, and what becomes permanent, says Capling: the display name, the bundle ids
(`com.loopware.Capling`, `.Widgets`), the App Group, the StoreKit product ids, the `capling://` scheme, the Squad link
(`capling.app/squad/…`), the notification and defaults key prefixes. `scripts/rename_brand.py <Old> <New>` does a rename like this
again (dry run first). The domain `capling.app` and an App Store Connect record are still to be registered by the owner.

An exam-readiness study coach for iPhone: capture class material (scan, PDF, paste, lectures, Quizlet and Anki
imports), turn it into checked questions linked to their source, study 10–15 minutes a day with answers graded in
your own words, and see readiness per exam and topic. The product plan and market research are in
`../docs/rethink/` (the plan page is `../docs/rethink/site/plan.html`; the clickable web prototype that is the
visual spec is `../docs/rethink/site/app/` with screenshots in `../docs/rethink/site/shots/`).

This folder replaces the old Flutter "Studyly" app at the repo root, which is left untouched.

SwiftUI, iOS 26.0+ (built with Xcode 27 / SDK 27), SwiftData, StoreKit 2, WidgetKit/ActivityKit/AppIntents,
Vision/VisionKit, Speech (SpeechAnalyzer), Foundation Models. Backend: Supabase in `supabase/` (Postgres with RLS,
Edge Functions: the AI relay, entitlements, Squad, account). XcodeGen generates the project from `project.yml`.

## Build, run, test

```bash
scripts/xc.sh build                                   # app + widget extension → ** BUILD SUCCEEDED **
SIM_ID=<udid> scripts/xc.sh test                      # CramlessTests on that simulator
SIM_ID=<udid> scripts/xc.sh test -only-testing:CramlessTests/FooTests
DERIVED=build-x scripts/xc.sh build                   # another derived-data folder
```

- Success signals: `** BUILD SUCCEEDED **`; `** TEST SUCCEEDED **` plus the `Executed N tests` line. If the helper
  and the log disagree, trust the log (`build/xc-*.log`).
- Tests are app-hosted: the whole app must compile before any test runs.
- Simulators: other sessions share this Mac. Create your own (`xcrun simctl create "Cramless <You>"
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0`), use only its
  id, shut it down when you stop using it, and never boot, shut down or erase anyone else's.
- `Secrets.xcconfig` is gitignored; blank values mean no relay (the app runs on-device and offline). The helper
  writes a blank one when missing.
- Backend: `cd supabase/functions && deno task test` (see `supabase/README.md`).
- Against real things (each one says what it needs):
  - `scripts/fm_live/run.sh`: the app's AI code on the real Foundation Models model on this Mac. Run it after
    changing an on-device prompt, schema or mapping.
  - `scripts/speech_live/run.sh`: lecture transcription on this Mac's speech models.
  - `scripts/local_stack.sh up|env|down`: a local Supabase stack. With it running, the opt-in
    `CramlessTests/LocalStackTests` drive the app's networking against it.
  - `ANTHROPIC_API_KEY=… deno task live`: real Claude through the relay's code path.
  - `scripts/device_isolated.sh <udid>`: installs on a phone with the wildcard profile, no capabilities.
  - `scripts/device_probe.sh <udid>`: on-device AI, speech, VisionKit, a Live Activity and haptics on the phone, with
    a report.
  - `scripts/device_shots.sh <udid>`: real screenshots.
- Films and sounds (the owner reviews each phase as films on their Tailscale link):
  - `scripts/film.sh <udid> <out> <name> <seconds> [KEY=VALUE …]`: records a hooked launch and lays the app's own
    sounds over it from the cue log (simulator recordings are silent). It also writes a half-speed copy and a poster
    frame, and keeps the cue times.
    - The app draws a timecode strip on film launches (`FilmTimecode`, `CRAMLESS_FILM_SYNC=1`). film.sh reads it off
      every frame, so sounds stay on their frames through the recorder's drops and stalls, then crops it off.
    - Films come out as H.264 High at a constant 60 fps, level 5.1. The recorder's own stream is variable-rate at about
      100-120 fps and encodes as level 6.1; the Phase 5 films made that way would not play on the owner's iPhone. Check
      a new film with `ffprobe` (level 51, 60 fps) before it goes on the review page.
  - `scripts/xcq.sh build|test …`: `scripts/xc.sh`, retried while the Mac's shared build queue (`simq`) has no slot.
    Get a simulator with `simq sim --udid` (not `simctl create`, which simq shuts down as idle) and give it back with
    `simq sim release`; run heavy ffmpeg and recordings through `simq run media -- …`.
  - `scripts/sound_audition/run.sh`: renders every cue on every palette to `docs/shots/audition/`.
  - `scripts/review_server.py`: serves `build/review/<phase>/` with byte ranges (Safari needs them for video),
    on port 8824, exposed with `tailscale serve`.
  - `scripts/cap_anim/`: the Cap animation work (see docs/BUILD.md). It needs `FAL_KEY`, and each script refuses to pass its
    spend cap (`BUDGET`): `cap_anim.py` (round one: stills on magenta, image-to-video, cut-out), `round2.py` (the character
    sheet, Kling 4.0 with Cap as a character, other directions), `sheet_compose.py`, `build_page.py`, `build_page2.py` and
    `build_alive_page.py` (the review pages), `produce.py` with its prompt book `clips.json` (makes the shipped clips: see
    `docs/cap/README.md`; its `check` counts the new pictures a second in a take and warns under 24, and `smooth` draws the pictures
    a clip animated "on twos" or "on threes" is missing, with `inbetween.swift`: a 24 fps file that changes only every 2nd or 3rd
    frame is choppy on a 120 Hz phone), `pink_audit.py` (leftover pink pixels per frame; run it on every new clip), `residue_audit.py`
    (the frames of the shipped clips with a smear of the video model's background; `produce.py scrub` recolours one), `film_gaps.py` (the
    frames where Cap vanishes in a film; run it on the cast film after touching how he changes pose),
    `hevc_planes.swift` and `produce.py audit` (what a clip stores under its transparent pixels: it must be black, or Cap
    gets a lighter rectangle on a dark screen), `films.sh` and
    `film_alts.sh` (the review films and their fallback encodings) and `keyer_check.py` (the keyer against video-like
    composites). NumPy 2.2 on Python 3.14 can change a big array in place with `~a`,
    `a | b` or `a - b`: use ufunc calls or `out=` buffers when you work on frames.

## Seeing the app (headless)

DEBUG launch hooks (`App/TestHarness.swift`), passed with the `SIMCTL_CHILD_` prefix:

```bash
xcrun simctl install <udid> build/Build/Products/Debug-iphonesimulator/Cramless.app
SIMCTL_CHILD_CRAMLESS_UITEST=1 SIMCTL_CHILD_CRAMLESS_ROUTE=exam xcrun simctl launch <udid> com.loopware.Capling
sleep 4; xcrun simctl io <udid> screenshot shot.png
```

- `CRAMLESS_UITEST=1`: in-memory store, the seeded demo world (`Model/SampleData.swift`), mock AI, onboarding
  skipped. `CRAMLESS_SEED=0` empty world; `CRAMLESS_MOCK_AI=0` local AI instead of mock.
- `CRAMLESS_ROUTE=<name>[:<arg>]`: one screen; the list is `TestHarness.apply(route:)`.
- `CRAMLESS_ONBOARDING=1`, `CRAMLESS_ROUTE=onboarding:<page>`, `CRAMLESS_NOW=<ISO 8601>`, `CRAMLESS_THEME=dark`,
  `CRAMLESS_DYSLEXIC=1`, `CRAMLESS_PLAN=pro`, `CRAMLESS_CONSENT=0`.
- Lectures: the harness (or `CRAMLESS_FAKE_LECTURE=1`) records with a demo transcriber that replays Lecture 6;
  `CRAMLESS_LECTURE_PREFILL=<n>` shows its first n lines at once, `CRAMLESS_LECTURE_ELAPSED=<seconds>` starts the
  clock there (`Lecture/LectureDemo.swift`).
- The harness keeps settings in a `cramless.harness` suite wiped at launch, and never touches StoreKit
  (`CRAMLESS_STOREKIT=1` opts in). StoreKit purchase-flow tests are opt-in
  (`TEST_RUNNER_CRAMLESS_STOREKIT_TESTS=1`): they can leave a "Sign in to Apple Account" prompt on a simulator until
  it's erased.
- Screen states (each documented beside its view):
  - Today: `CRAMLESS_TODAY=catchup|examEve|eveDone|done|caughtUp|noMaterial|empty`; `CRAMLESS_TODAY_SCROLL=1` scrolls
    down the page and back (for a film); `CRAMLESS_TODAY_OPEN=<ms>` opens the sky that long after launch, as a tap
    on it would.
  - Sessions:
    - `CRAMLESS_SESSION_STATE=ownwords|graded|mcq(-answered)|cloze(-answered)|diagram(-filled|-answered)|flashcard|flipped|summary|exameve-summary|fix-summary`
    - `CRAMLESS_SESSION_PICK=wrong`, `CRAMLESS_SESSION_ANSWER=<text>`
    - `CRAMLESS_SESSION_AUTOPLAY=rrrrrpwk` answers every question by that pattern (`r` right, `p` partly, `w` wrong,
      `k` "I don't know") and presses Continue `CRAMLESS_AUTOPLAY_BEAT` ms after each panel, through to the summary.
      Film it with `CRAMLESS_MOCK_AI=0`, so the feedback is the real offline grade of that answer.
    - `CRAMLESS_SESSION_MINUTES=<n>` makes the session that long (a 5-minute one reaches its summary inside a film).
    - `CRAMLESS_SESSION_STATE=flashcard-saved|mcq-saved` makes the first flashcard (or multiple-choice question) a
      fading memory and answers it right: a save, with the sky's flare.
    - `CRAMLESS_SUMMARY_SKY=<ms>` opens the memory sky that long after a summary's choreography, as a tap on its
      "See the sky" strip would (films follow a real session into the sky it relit).
  - Onboarding steps: `CRAMLESS_STEP=firstSession|readiness|plan` (with `CRAMLESS_SEED=0`);
    `CRAMLESS_FIRSTSET=choose|processing|review` (with `CRAMLESS_ROUTE=scanner`).
  - Capture: `CRAMLESS_CAPTURE_PHASE=reading|ideas|writing|checking|done|review|error:<kind>`,
    `CRAMLESS_CAPTURE_INPUT=photo|text`, `CRAMLESS_REVIEW_EDIT|UNTICK|SCROLL|PEEK|APPROVE|ALLOW`,
    `CRAMLESS_RECORD_FLAG|PAUSE|STOP`, `CRAMLESS_NOTES_FOCUS`, `CRAMLESS_IMPORT`, `CRAMLESS_PASTE_TEXT`,
    `CRAMLESS_CANVAS=375x667` (SE size).
  - Library and exams: `CRAMLESS_SCENARIO=eve|past|graded|missed|repair`, `CRAMLESS_SCROLL=<section>`,
    `CRAMLESS_SEARCH=<words>`, `CRAMLESS_GRADE=<n>`.
  - Ask, Settings and Squad: `CRAMLESS_ASK`, `CRAMLESS_CHAT`, `CRAMLESS_AGE`, `CRAMLESS_TUTOR`, `CRAMLESS_CARDS`,
    `CRAMLESS_EXPLAIN`, `CRAMLESS_SYNC`, `CRAMLESS_NOTIFY`, `CRAMLESS_SQUAD`, `CRAMLESS_ACCOUNT=apple|email`.
  - Paywall and onboarding: `CRAMLESS_PAYWALL_PLAN`, `CRAMLESS_PAYWALL_STATE=purchasing|pending|cancelled|failed|purchased|restored`,
    `CRAMLESS_PAYWALL_TRIAL=0`, `CRAMLESS_PAYWALL_SCROLL`, `CRAMLESS_ONB_REMINDER=1`.
- Feel:
  - The harness is silent unless `CRAMLESS_SOUNDS=1`, but logs every cue to `Documents/feel-log.jsonl` for
    `film.sh`.
  - `CRAMLESS_SOUND_PALETTE=marimba|kalimba|glass` picks the palette.
  - `CRAMLESS_FEELLAB=sounds|cap|cast|confetti` opens that section of the Feel lab and plays all of it in turn: every
    cue, each of Cap's moments, every pose with its clip, each size of celebration.
  - Cap shows as a drawing in the harness (screenshots must repeat) unless `CRAMLESS_CAP_CLIPS=1`; films pass it
    (`scripts/cap_anim/films.sh <udid> <out>` films him in his places; `film_alts.sh <folder>` makes the fallback
    encodings; `build_alive_page.py` builds the review page). Cap's clips, their rules and how to make one are in
    `docs/cap/README.md`.
  - Cap answers a tap (squash, a reaction clip, a few words). `CRAMLESS_CAP_POKE=3000,6500` taps every Cap on screen at
    those times, in ms after he appears; `CRAMLESS_CAP_SEED=7` makes his rolls and his words repeat;
    `CRAMLESS_FEELLAB=cast CRAMLESS_CAST_POKE=1` taps each pose of the cast after its clip. Needs `CRAMLESS_CAP_CLIPS=1`
    for the clips and the squash; the words alone work without. After any change to `CapClipPlayer`, `CapStage` or the clip
    handling in `CapView`, run `scripts/cap_anim/stress_taps.sh <udid>` (18 taps, audited at 60 fps): the hand-offs between
    a video layer and the drawing under it race, and a blink of a frame or two only shows in a film.
  - `CRAMLESS_CELEBRATION=none|nudge|small|medium|big|calm` sets the size of the summary's celebration (with
    `CRAMLESS_SESSION_STATE=summary`); the reason and the title stay the real ones.
  - Today's hero is a world (`HeroWorld`): `CRAMLESS_HERO=3000:c2,9500:close,12000:x300y160` taps constellation 2's first star,
    closes its card, then taps the point (300, 160), at those milliseconds after launch, through the same code as a finger.
    With no motion sensor (the Simulator) the layers sway on their own, so films show the depth.
    `scripts/hero_shot.sh <udid> <name> [KEY=VALUE …]` screenshots the hero (`HERO_WAIT=3.5 scripts/hero_shot.sh …` waits that long).
    The hero is pinned when the page is pulled down, and the pull is a pull to refresh (`HeroRefresh.swift`):
    `CRAMLESS_HERO_PULL=2500:100:500,9000:50:400` pulls by 100 points at 2.5 s, holds 0.5 s and lets go, then a short pull that
    springs back (the readings a finger gives the page; the page itself doesn't move, so films of it show the world's answer, not
    the pin: for that, drag for real with the `mobile` tools' swipe and `simctl io recordVideo`, starting inside the hero and
    ending above y = 600 (a swipe that ends at the bottom edge triggers iOS's app switcher)). `CRAMLESS_PULL_LOG=1` logs every
    reading the scroll view gives it, to work out a gesture that didn't count.
  - The welcome is a small world with a constellation to light (`WelcomeWorld`, `WelcomeStage`, pure parts in `WelcomeSky`):
    `CRAMLESS_WELCOME=lit1|lit2|lit3` shows the sky after that many stars at once, `CRAMLESS_WELCOME=3200:s1,5200:s4,7200:s0`
    taps stars by index (0 to 6, left to right) at those milliseconds, through the finger's own code; with neither, Cap lights them
    himself (`scripts/cap_anim/films_welcome.sh`). `CRAMLESS_SKY_PERF=1` logs its frame time and `CRAMLESS_FEEL_PERF=1` how long each sound held the main thread. `CRAMLESS_ROUTE=onboarding:<n>` numbers welcome 0, the six intro pages 1 to 6, the
    four questions 7 to 10, then the first set (11), first session (12), readiness (13), plan (14), paywall (15).
  - `CRAMLESS_ROUTE=sky` opens the memory sky; `CRAMLESS_SKY=still|relight[:n]|flare|age:<days>|lapse:<days>|focus:<n>|tour|list|fill:<n>`
    (comma-separated) sets its state: a still frame, a relight after a session, the save's flare on a loop, the sky
    some days on, a time-lapse of forgetting, a focused constellation or a tour of three, the list, more stars.
  - `CRAMLESS_REDUCE_MOTION=1` and `CRAMLESS_DWC=1` force Reduce Motion and Differentiate Without Color, which the
    Simulator can't switch on.
- A deeper state (a graded answer, scene N mid-play) is a hook in its own view, read with
  `TestHarness.once("CRAMLESS_…")`, documented beside the view, inside `#if DEBUG`.
- App boot takes 1–2.5 s after launch returns; screenshot after 3–4 s. Animated scenes need 2–4 shots.

## Architecture

- `App/` — `CramlessApp`, `AppModel` (the one `@MainActor @Observable` model: store, settings, router, services;
  `AppModel.live`), `AppConfig` (the one seam: `relay`, `local` or `mock` AI; logs one startup line), `Router`
  (tabs, per-tab paths, one sheet, one cover, one toast; every destination is a case in `Route`/`AppSheet`/
  `AppCover`, mapped in `RootView.swift`), `TestHarness`, `DeepLinks`.
  - The tab bar's + is a `Tab` that must never be selected: `AddTabAction` (in each tab's content) stands in front of
    SwiftUI's tab delegate and answers "may it be selected?" with no, running the action instead. A selected + swaps the
    whole page for an empty one for four frames and re-runs every `onAppear` on the page behind it (a flash and a refresh).
    Test a change to it with a real tap (the `mobile` tools can tap a simulator) and a screen recording, not a screenshot.
- `Model/` — SwiftData models (`Models.swift`), the values stored in them (`ModelTypes.swift`), `AppSettings`
  (UserDefaults JSON), `Persistence` and `FileStore` (page images, PDFs, audio under Application Support/Files),
  `ItemFactory` (every generated item becomes a model here), `SamplePage` (the bundled sample, release content),
  `SampleData` (the DEBUG demo world).
  - The demo world seeds inside `ModelID.seeded`, so its ids are identical on every launch.
  - New model inits take `id: UUID = ModelID.make()`.
- `Engine/` — pure, clock-free logic: FSRS-6, scheduling, session building, readiness, plans, streaks. Engines
  take values and snapshots (never a `@Model`) and `now`, and are unit-tested.
- `AI/` — the relay contract (`RelayContract.swift`, spec in `docs/relay-contract.md`, examples in
  `supabase/functions/_shared/fixtures`), transports (HTTP, mock), `OnDevice/` (Foundation Models), `Local/`
  (the offline rules), `AIRouter` (the feature-facing service).
- `Capture/`, `Lecture/` — scanning, text recognition, PDFs, imports (Anki, Quizlet, CSV), recording and
  transcription.
- `Store/` — StoreKit 2. `Sync/` — Supabase auth, REST, sync, Squad, account. `Services/` — notifications, widget
  snapshot, Live Activities, read-aloud.
- `Features/<Area>/` — screens. `DesignSystem/` — tokens and components. `Shared/` — compiled into the widget
  too: palette, readiness ring, snapshot and activity types.
  - `Shared/Core/` is Foundation-only (snapshot, copy, links, `CourseColor`), so the Watch can share it.
- `CramlessWidgets/` — widgets, the Live Activity, controls. A blind subset: it sees only `Shared/` and its own
  files.

### Rules that keep it coherent

- **Mutations only in AppModel extensions** (`App/AppModel+<Area>.swift`): stamp with `touch(_:)`, then `save()`.
  Views never set a model property. `save()` bumps `revision` and debounces the outward effects (widget snapshot,
  sync push, reminders); `flushSideEffects()` runs them now (App Intents that finish in the background).
- **Models**: never add a stored `isDeleted` (SwiftData owns it); soft delete is `deletedAt`. Structured values
  are Codable blobs behind computed accessors. A view holding a model that can be deleted checks
  `item.modelContext != nil` before reading blobs. Count days with `calendar.dayDistance(from:to:)`.
- **Engines are pure**: no `Date()`, no `@Model`, no SwiftData; `now` and `calendar` are parameters.
- **AI never blocks and never commits on its own.** Every AI job has an offline answer first (the rules),
  then the on-device model, then the relay (cloud) only after consent and within quota. Generated sets arrive
  as drafts the person approves. Grading highlights only quotes found verbatim in the answer. Tutor answers cite
  the person's material or say it isn't covered. Failures fall back quietly to the offline path. Cloud requests
  are built from what is true after any wait (consent sheet, network).
- **Consent**: cloud AI is opt-in (`settings.cloudConsentVersion`), sending page photos is a separate switch
  (`settings.sendPhotos`). Copy never says "nothing leaves your device" where a cloud path exists.
- **Under-18**: `settings.isMinor` keeps the tutor on hints first and teen-safe; no essay writing or
  "humanizing", for anyone.
- **iOS 27 symbols** sit inside `#if HAS_IOS27_SDK` with `@available(iOS 27.0, *)`; the deployment target is 26.0.
- **No new package dependencies** unless there is no reasonable alternative; say why in the change.
- **No secrets in the repo.** Provider keys live only in Supabase function secrets.

### Design system (use it; don't invent local styles)

- Colour: `CLColor` (`Shared/BrandPalette.swift`). Brand fills take Night ink (`CLColor.onFill`), never white.
  Coloured text uses the `…Ink` tokens. Readiness colours: `CLColor.readiness(_:)` (80+ mint, 50+ sun, else rose).
- Type: `.clFont(.title2)` etc. (`DesignSystem/Theme.swift`), never `.font(...)` for reading text, so the
  dyslexia-friendly font reaches it. Bricolage (`.display`, `.brandTitle`, `.brandHeading`) only for the wordmark,
  onboarding titles, the paywall headline and big feedback words. Numbers: `.number(size)`.
- Spacing and shape: `CLSpace`, `CLRadius`, `CLMetrics`. Cards `.clCard()`, the night card `.clNightCard()`,
  lists `CLList` + `CLRow`, `CLSectionHeader`, `CLChip`, `CLSourceChip`, `CLPill`, `CLBar`, `ReadinessRing`,
  `HighlightedText`, `CapView`/`CapFace`, buttons `.buttonStyle(.cl(.primary))`. Floating controls use the
  system's Liquid Glass (`.glassEffect`, `.buttonStyle(.glass)`).
- Motion: `CLMotion` tokens only (they handle Reduce Motion). Scripted sequences use `nap(_:)` (throws on
  cancel). Views read `@Environment(\.clReduceMotion)` and `\.clDifferentiateWithoutColor`, never the system keys,
  so the DEBUG overrides reach them.
- Cap: `CapView(.nice)` takes a `CapMoment` (pose, motion, sparkles, how Cap waits); the table of moments is in
  `docs/design.md`. A tap on him squashes him, plays his reaction clip and has him say something (`interactive: false`
  where a tap already means something); his lines are `CapLines`, dealt by `CapLineBag` (short, warm, no emoji). All 19 poses are drawn; one that arrives early shows its stand-in until its art and its name in
  `CapPose.drawn` land. `scripts/cap_post.sh` frames new art onto the shared feet line.
- The memory sky: `SkyEngine` (`Engine/Sky.swift`, pure) lays out and lights it; `AppModel.skyScene(aspect:at:)` reads
  it; `MemorySkyView` draws it (`Features/Sky/`). A star is an active item, a constellation a topic. Layout depends on
  ids and counts only, so nothing moves as days pass. "Relit" means a star visibly changed in a session. Saves and
  the flare use `ReviewOutcome.isSave`.
  - Today's top is a world (`TodaySkyHero` over `HeroWorld`: the sky, background stars, hills and a lake, Cap standing in it, a
    constellation you can tap; its pure parts are `HeroWorldModel.swift`); what each day says and offers is one pure value,
    `TodayHeroContent`. Progress shows pieces of it: an exam's region (`SkyScene.region(of:)`, drawn by
    `SkyRegionStill`) and a topic's glyph (`SkyScene.glyph(of:)`, `SkyGlyphView`).
  - An exam's region records the constellations it covers (`SkyLayout.Region.covers`); use that, never "is it inside the
    circle", to decide what belongs to an exam.
- Celebrations: `CelebrationPolicy` (`Engine/Celebration.swift`) picks one per screen, for learning only (never a
  purchase); `CLConfetti` draws it. Exam eve and quiet hours stay calm.
- Feel: a moment with a sound plays `CLFeel.play(.right(combo:))`, `.saved`, `.done`, …
  (`DesignSystem/Feel/`), which plays the sound and its paired haptic together.
  - Plain taps, ticks and page turns stay on `CLHaptics` and make no sound.
  - Both are for the person's own actions; demo scenes and loops fire none.
  - Sounds are synthesized (`CLSynth`, no audio files), mix with other audio and obey the Silent switch.
  - Anything that takes the audio session claims `AudioFocus` first.
- "Saved it" is `ReviewOutcome.isSave`: a right answer (Good or Easy, not "Almost.") on a studied item whose recall
  was below 0.7 at that moment. It's the one definition for the headline, the sky's flare and "saved" count, quests
  and badges. The flare is published where the views play the verdict's cues (`SessionRunner.flareSave(of:)`), not
  when the answer is recorded.
- Copy is localizable (String Catalogs: `Cramless/Resources/Localizable.xcstrings`,
  `CramlessWidgets/Localizable.xcstrings`; `scripts/xc.sh` syncs them after every successful build).
  - Components take `LocalizedStringResource`, so a literal is localizable: `CLRow(title: "Accessibility")`.
  - The person's own words, AI text, or a line already built from localized copy goes through
    `.verbatim(text)`.
  - Computed copy returns `LocalizedStringResource` (or `String(localized:)`), never a plain `String`.
  - A count is one key with plural forms in `docs/l10n/plurals.json` (`"\(n) minutes"`), never `n == 1 ? … : …`.
  - Older screens still have plain-String copy (the sweep before translation converts it).
  - `PSEUDO=bounded scripts/shots.sh …` shows what's left: localized text is bracketed.
- Voice: short, warm, specific, sentence case. Cap never guilt-trips ("22 minutes tonight and you're done", never
  "You're letting Cap down"). No emoji in the chrome. Projections are labelled projections.
- Accessibility: Dynamic Type everywhere (no fixed heights on text containers), VoiceOver labels and values on
  custom controls, 44 pt tap targets, Reduce Motion settles to the final frame, never colour alone.

## Status

The launch scope is built (2026-10-22): every screen in the plan, the services behind them, the widgets, and the
backend, with about 600 Swift tests and 95 Deno tests green.

The "featured by Apple" plan (`~/.claude/plans/cozy-meandering-flamingo.md`, approved 2026-10-22) is under way.
Progress is logged in `docs/BUILD.md` under "Featuring plan". `docs/BUILD.md` records what each part does, the
integration fixes, and what the owner must still provide (Supabase project and keys, App Store Connect products
and URLs) and check on a device (camera, microphone, Foundation Models, Sign in with Apple, Live Activities).
