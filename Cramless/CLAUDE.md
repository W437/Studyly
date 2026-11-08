# Capling (iOS)

**The name.** The product is **Capling** (it was Cramless until 2026-10-25, when two other student products turned out to use that
name, with all its domains). The code keeps the old name as its code name: the module (`import Cramless`), the targets, the folders
and file names, type names (`CramlessLink`), the DEBUG switches (`CRAMLESS_*`) and the backend's database functions
(`cramless_*`). What people see, and what becomes permanent, says Capling: the display name, the bundle ids
(`com.loopware.Capling`, `.Widgets`), the App Group, the StoreKit product ids, the `capling://` scheme, the Squad link
(`capling.app/squad/…`), the notification and defaults key prefixes. `scripts/rename_brand.py <Old> <New>` does a rename like this
again (dry run first). The App Store Connect record exists on the Loopware team (created 2026-10-30: app id 6828649543, `com.loopware.Capling`,
SKU `capling-ios`, name "Capling"). By 2026-11-01 its listing text in 39 languages (the translations are drafts for a native read), the
English screenshots, the header and Search card, the price (Free), categories, age rating, purchases and App Privacy are filled in, and build
1.0 (1) is uploaded; nothing is submitted. `docs/BUILD.md` ▸ "App Store Connect" says what is done and what is open, and
`node scripts/asc/capling_asc.mjs --account loopware ready` lists what the version still lacks. The domain `capling.app` and the trademark
filing are still to be done by the owner.

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
- Which tests: the global rule ("Test in proportion to the change", `~/.claude/CLAUDE.md`) applies. The suite is about 1,100 tests and
  needs a simulator slot on a shared Mac (a half-hour queue is normal), so it is a gate, not a per-change check.
  - Run classes, not files: `-only-testing:CramlessTests/<Class>`, as many as needed (`xc.sh test` passes them on). A file can hold
    several classes (`TodayHeroTests.swift` has `TodayHeroContentTests` and `TodaySkySnapshotTests`; `HeroWorldTests.swift` has
    `HeroWorldGeometryTests` and the band's other pure parts; `SkyCopyTests` is in
    `SkyViewTests.swift`; `TutorTests.swift` has `TutorTests`, `TutorSelectionTests`, `TutorHonestyTests`, `RelayLimitsTests` and `TutorPrivacyCopyTests`). `grep -n "class .*TestCase" CramlessTests/<File>.swift` lists a file's classes, and
    `grep -l -w -E "TypeA|TypeB" CramlessTests/*.swift` finds the files that use the types you changed.
  - No tests: wording, comments, docs, art, `scripts/`. Words a test asserts (`TodayHeroContentTests`, `TodayCopyTests`, `SkyCopyTests`,
    `PaywallCopyTests`) are updated along with the words. A string-catalog edit has `LocalizationTests` (the catalogs parse, plural
    forms resolve, `docs/l10n/plurals.json` names only keys the app uses).
  - Test files by area (in `CramlessTests/`, without `.swift`; `Ask*`, `Capture*`, `Import*`, `Library*` and `Widget*` stand for the
    files with that prefix):
    - Cap's cards: `NoticeEngineTests` (deck, kinds, pings, words, the look-alike corpus gate, speed), `NotificationPlannerTests`, `TodayTests`, `StudyAppModelTests`. Busy days: `BusyDayTests` and the Busy days section of `NoticeEngineTests`. The last look: `LastLookEngineTests`, `LastLookAppModelTests` (in `LastLookTests.swift`).
    - Today: `TodayHeroTests`, `TodayTests`, `TodayCopyTests`, `TodayReasonsTests`, `TodayPlanStripTests`, `TodayRenderTests` (PNGs of
      every card state in `build/review/s1-today/render/`, and the SE fit), `HeroWorldTests`, `HeroRefreshTests`, `WelcomeSkyTests`. The memory sky: `SkyEngineTests`,
      `SkyViewTests`, `SkyDerivedTests`, `SkyAppModelTests`.
    - A session and the engines (`Engine/`): `SessionTests`, `SessionFeelTests`, `EngineFSRSTests`, `EngineSchedulerTests`,
      `EngineSessionBuilderTests`, `EngineSessionFocusTests`, `EngineStudyHabitsTests`, `EngineReadinessTests`, `EngineStreakTests`.
    - The game loop (quests, badges, skies, icons, celebrations): `GameEngineTests`, `GameAppModelTests`, `GameRenderTests`,
      `CelebrationTests`. Cap and the feel: `CapClipTests`, `CapTouchTests`, `FeelTests`.
    - Progress, exams, library: `ProgressPresentationTests`, `ExamPresentationTests`, `Library*Tests`, `DraftTests`,
      `StudyAppModelTests`, `StudyDemoWorldTests`. An exam's scope: `SyllabusTests`, `ExamGapTests`, and `ExamDateFinderTests` (in `LectureTests.swift`).
    - Capture, imports, lectures: `Capture*Tests`, `Import*Tests`, `OCRTests`, `GeneratorTests`, `LectureTests`, `AILectureTests`.
    - Voice: `SpokenAnswerTests`, `SpokenVerdictTests` (in `SpokenAnswerTests.swift`), `SpeechEndpointTests`, `HeardWordsTests` (in `SpeechEndpointTests.swift`), `OutLoudQuestionTests`, `OutLoudControllerTests` (in `OutLoudTests.swift`), `TeachPlannerTests`, `TeachAppModelTests` (in `TeachTests.swift`).
    - Ask Cap and the AI layer (`AI/`): `Ask*Tests`, `AssistantTests`, `TutorTests`, `GraderTests`, `AITransportTests`,
      `AISSEParserTests`, `AIOnDeviceTests`, `RelayContractTests`.
    - Paywall, sync, Squad: `StoreEntitlementTests`, `StoreReminderAndOfferTests`, `PaywallCopyTests`, `SyncEngineTests`,
      `SyncAccountServiceTests`, `BackendClientTests`, `SquadTests`.
    - Onboarding, routes, settings, widgets: `OnboardingMachineTests`, `OnboardingQuizTests`, `RouterTests`, `DeepLinkTests`,
      `SettingsExportTests`, `NotificationPlannerTests`, `IntentTests`, `Widget*Tests`.
    - Opt-in (skipped unless switched on): `LocalStackTests`, `StorePurchaseFlowTests`, `AssistantWireTests`.
  - The whole suite (`SIM_ID=<udid> scripts/xcq.sh test`), once, only at a gate: before a TestFlight or App Store upload; at the end of a
    build phase (BUILD.md gets its "Verified" line); after a change to a shared base (`Model/`, `Engine/`, `App/AppModel.swift`,
    `Shared/`, `project.yml`, the relay contract, the sync wire format); when asked. Not after each round of fixes, not for wording,
    and a commit or push is not a gate by itself: the commit message says what ran.
- Simulators: other sessions share this Mac. Create your own (`xcrun simctl create "Cramless <You>"
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0`), use only its
  id, shut it down when you stop using it, and never boot, shut down or erase anyone else's.
- `Secrets.xcconfig` is gitignored; blank values mean no relay (the app runs on-device and offline). The helper
  writes a blank one when missing.
- Backend: `cd supabase/functions && deno task test` (see `supabase/README.md`).
- Against real things (each one says what it needs):
  - `scripts/fm_live/run.sh`: the app's AI code on the real Foundation Models model on this Mac. Run it after
    changing an on-device prompt, schema or mapping.
  - `scripts/speech_live/run.sh`: lecture transcription on this Mac's speech models. `run.sh answers`: short spoken answers and commands, one at a time, which is what `SpokenAnswer` has to read.
  - `scripts/local_stack.sh up|env|down`: a local Supabase stack. With it running, the opt-in
    `CramlessTests/LocalStackTests` drive the app's networking against it.
  - `OPENAI_API_KEY=… deno task live` (in `supabase/functions`): every route on OpenAI through the relay's code path
    (`LIVE_ONLY=grade,check` runs some); `deno task live-openai` does the same for Ask Cap's tutor alone.
  - `deno run -A tools/assistant_bakeoff/run.ts [--group cards] [--cases a,b] [--live-research] [--debug]` (in `supabase/functions`): 50 requests
    to Ask Cap's assistant on the real model through the relay's code path, playing the app's part, with checks and costs (about 13¢;
    key from `~/.config/capling/openai_key`, else `OPENAI_API_KEY`: a stale shell key has shadowed the file before).
  - `deno run -A tools/serve_mock_relay.ts` (in `supabase/functions`, port 54990) with
    `TEST_RUNNER_CRAMLESS_ASSISTANT_RELAY_URL=http://127.0.0.1:54990 SIM_ID=… scripts/xcq.sh test -only-testing:CramlessTests/AssistantWireTests`:
    the app's real HTTP client against the relay's code in MOCK mode (opt-in; skipped without the address).
  - `supabase/functions/tools/tutor_bakeoff/run.ts` (flags and the key file in `docs/BUILD.md` ▸ Ask Cap on OpenAI): Ask Cap's
    tutor on OpenAI models, 33 questions and a dozen problems from a photo (`--groups problem,mistake`); `report.ts DIR` scores a run.
  - `scripts/device_isolated.sh <udid>`: installs on a phone with the wildcard profile, no capabilities.
  - `scripts/device_demo.sh <udid>`: opens that build in demo mode on the Ask tab (the seeded world, the mock relay's scripted
    replies, sounds, the phone's real haptics). Needed because the assistant only runs through a relay, and a build with no Supabase
    project hides it when opened from its icon. A phone shown as `unavailable` (off, locked or off the network) is skipped.
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
  - `scripts/journey_film.sh <udid> <out> <journey>` (through `simq run media --`): a film of a person using the app with **real taps and
    typing**, for the tour page a reviewer without an iPhone watches (the `review-tour` skill is the how-to). `scripts/journeys/`:
    `phone.py` (the driver over `mobilecli`: taps by label, steered scrolling, typing in bursts, marks, stall cuts), `j_*.py` (one file
    per journey), `moves.py` (what a student does in a session), `tour.py` (`list`, `try <journey> <udid>` rehearses on a fresh install
    with a screenshot at every mark, `package`), `tour_page.py` + `tour_content.py` (the page, `build/review/anis-tour/`). The app
    draws a ring under each finger when `CRAMLESS_SHOW_TOUCHES=1` (`App/TouchDots.swift`); the hooks for a journey's start are the
    usual ones. film.sh gets `FILM_DRIVER` (run the driver instead of sleeping), `FILM_NO_HALF=1` and writes `<name>.marks.json`.
    The harness shows the welcome on the first launch after an install: journey_film.sh launches once and lets go.
  - `scripts/xcq.sh build|test …`: `scripts/xc.sh`, retried while the Mac's shared build queue (`simq`) has no slot.
    `xc.sh test` sets `SIMQ_NO_CACHE=1`: simq's shared compile cache rewrites source paths to `/^src/…`, and the tests that
    find the source folder or `docs/` through `#filePath` (Localization, PaywallCopy, GameRender, WidgetRender) fail on it.
    Get a simulator with `simq sim --udid` (not `simctl create`, which simq shuts down as idle) and give it back with
    `simq sim release`; run heavy ffmpeg and recordings through `simq run media -- …`.
  - `scripts/sound_audition/run.sh`: renders every cue on every palette to `docs/shots/audition/`.
  - `scripts/make_alt_icons.py`: the four alternate app icons and the picker's previews, drawn from the main icon (Cap cut out of the
    blue, four new skies; free, repeatable). `scripts/contact_sheet.py out.png a.png b.png …` puts screenshots side by side to look at
    them together. `scripts/cap_anim/films_game.sh` and `build_game_page.py` make the game loop's films and review page.
  - `scripts/review_server.py`: serves `build/review/<phase>/` with byte ranges (Safari needs them for video),
    on port 8824, exposed with `tailscale serve`. Its log has each request's Range header, and `GET /__d?<text>` answers 204 and is
    logged: a page on the owner's phone can report to it (the tour page does when its address ends in `?log`; the `review-tour` skill's
    `scripts/video_check.html` is a page that tries the films one at a time). A film that plays in Chromium can still show a black player on the phone: see the
    tour section of docs/BUILD.md.
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
  skipped. `CRAMLESS_SEED=0` empty world; `CRAMLESS_MOCK_AI=0` turns mock off: local AI with a blank `Secrets.xcconfig`, but with a filled
  `Secrets.xcconfig` it calls the live relay.
- `CRAMLESS_ROUTE=<name>[:<arg>]`: one screen; the list is `TestHarness.apply(route:)`.
- `CRAMLESS_ONBOARDING=1`, `CRAMLESS_ROUTE=onboarding:<page>`, `CRAMLESS_NOW=<ISO 8601>`, `CRAMLESS_THEME=dark`,
  `CRAMLESS_DYSLEXIC=1`, `CRAMLESS_PLAN=pro`, `CRAMLESS_CONSENT=0`, `CRAMLESS_QUIET=1` (Quiet mode on).
- Lectures: the harness (or `CRAMLESS_FAKE_LECTURE=1`) records with a demo transcriber that replays Lecture 6;
  `CRAMLESS_LECTURE_PREFILL=<n>` shows its first n lines at once, `CRAMLESS_LECTURE_ELAPSED=<seconds>` starts the
  clock there (`Lecture/LectureDemo.swift`).
- The harness keeps settings in a `cramless.harness` suite wiped at launch, and never touches StoreKit
  (`CRAMLESS_STOREKIT=1` opts in). StoreKit purchase-flow tests are opt-in
  (`TEST_RUNNER_CRAMLESS_STOREKIT_TESTS=1`): they can leave a "Sign in to Apple Account" prompt on a simulator until
  it's erased.
- Screen states (each documented beside its view):
  - Today: `CRAMLESS_TODAY=catchup|partway|split|noExam|examEve|twoEves|eveDone|done|caughtUp|noMaterial|empty` (`split`: the session
    serves no one exam, so no chip; `noExam`: no exams at all; `twoEves`: the first two exams share tomorrow; `done` also fills the done card's exam, +10%);
    `CRAMLESS_TODAY_NOTICES=0|1|2|3` deals that many of Cap's cards (stand-ins); `CRAMLESS_TODAY_WHY=<ms>`, `CRAMLESS_TODAY_QUESTS=<ms>` open
    "Why these?" and the quests sheet, `CRAMLESS_TODAY_LATER=<ms>` presses Cap's "Later", `CRAMLESS_NOTICE_TAP=<ms>` his card's button, each that long after launch;
    `CRAMLESS_TODAY_SCROLL=1` scrolls down to the exams row and back (for a film), `=notice` to Cap's card, where it stays; `CRAMLESS_TODAY_OPEN=<ms>` opens the sky that
    long after launch, as a tap on the band would; `CRAMLESS_CANVAS=375x667` draws Today (also the Ask screen, the Explain sheet, a session, a source page, a lecture's notes, the last look, and at its width "Looks wrong?" and the harder question sheet) at an iPhone SE's size (a drawing, with no status-bar inset; the real thing is
    `simq sim --device "iPhone SE (3rd generation)" --os 27.0 --udid`, released with `simq sim release <udid>`); `CRAMLESS_TODAY_TYPE=xxxl|ax1…ax5` draws Today at that text size without changing
    the simulator's own setting (others may share it). Routes `todayWhy`, `quests` (the sheets) and `skyList` (the sky as a list,
    "Study something else"); `streak` shows the month with exams and eves marked.
  - Cap's cards, from the real engine (`App/AppModel+NoticeHarness.swift`): `CRAMLESS_NOTICES=mixup,lookalike,fading,back,mock,gap,lecturedate|all|none` shapes the demo world so those kinds and no others fire
    (`lookalike`: the Bio midterm 9 days out; `fading`: 4 days out with its questions 20 days overdue, and 60 more own-words ones added so the sessions before it can't reach them all; `back`: 8 days away after a 23-day run; `mock`: the Bio midterm 5 days out); `CRAMLESS_NOTICE_STATE=second|later|done|allLater`
    puts the deck part way through the day (`done`: "Plan updated"). `CRAMLESS_ROUTE=lookAlike` opens the sheet on the best pair, `CRAMLESS_LOOKALIKE=rules|cloud|writing` holds its lesson in that state. With `CRAMLESS_ROUTE=session:fix`, `CRAMLESS_FIX_LESSON=lesson|writing` opens on the fix's first screen (without it a hooked drill starts at once).
    `CRAMLESS_ROUTE=settings:notifications CRAMLESS_NOTICES=fading` shows the ping in the page's planned list.
    `CRAMLESS_MIXUP=coming|slip` (with `mixup`): the last answer came right ("coming along"), or the mix-up is about one question ("Go over it"). `CRAMLESS_ESSAYS=<n>` (with `mock`): the midterm is essays only, with `n` of them.
    `CRAMLESS_NOTICES=busy` (the midterm 9 days out) with `CRAMLESS_BUSY=<offset>[:<hours>]` (`DemoBusyCalendar`, access granted; 3 days ahead and 6 hours by default) deals "Monday looks busy"; `CRAMLESS_BUSY=ask` the card that asks for the calendar (a press grants it, and the busy card follows), `askno` the same with a refusal, `denied` refused long ago. `CRAMLESS_NOTICE_STATE=done` also moves that day.
    `CRAMLESS_NOTICES=tooeasy` (or `CRAMLESS_LADDER=offer`): a Bio midterm question has become too easy (`Ladder`). `CRAMLESS_ROUTE=ladder` opens "Yes, harder" on a question, with `CRAMLESS_LADDER=writing|proposal|added` holding that state (`LadderSheet`).
  - Sessions:
    - `CRAMLESS_LOOKSWRONG=sheet|checking|fixed|stands|retired|queued` with an answered state (`CRAMLESS_SESSION_STATE=mcq-answered CRAMLESS_SESSION_PICK=wrong`) opens "Looks wrong?" over the question, in that state (`LooksWrongSheet`). Wait 9 s or so: the sheet opens 1.6 s after the question.
    - `CRAMLESS_SESSION_STATE=ownwords|graded|mcq(-answered)|cloze(-answered)|diagram(-filled|-answered)|flashcard|flipped|flashcard-rated|last-rated|flashcard-drag|flashcard-swiped|summary|exameve-summary|fix-summary`
    - `CRAMLESS_SESSION_PICK=wrong`, `CRAMLESS_SESSION_ANSWER=<text>`
    - `CRAMLESS_SESSION_AUTOPLAY=rrrrrpwk` answers every question by that pattern (`r` right, `p` partly, `w` wrong,
      `k` "I don't know") and presses Continue `CRAMLESS_AUTOPLAY_BEAT` ms after each panel, through to the summary.
      Film it with `CRAMLESS_MOCK_AI=0` on a build with a blank `Secrets.xcconfig`, so the feedback is the real offline grade of that
      answer (with a filled `Secrets.xcconfig` it calls the live relay).
    - `CRAMLESS_SESSION_MINUTES=<n>` makes the session that long (a 5-minute one reaches its summary inside a film).
    - `CRAMLESS_SESSION_DRAFT=<text>` (with `ownwords`): the first question's editor opens with those words "Kept from before"
      (`AnswerDrafts`). `CRAMLESS_SESSION_RESUME=1` (with `session` or `session:catchUp|examEve`): a session of that kind was cut off
      earlier today after three answers, with words typed on an own-words question; it picks up ("Picked up where you left off.").
    - Undo (`SessionRunner.PendingGrade`): `flashcard-rated` flips and rates the first flashcard (`CRAMLESS_SESSION_RATE=again|hard|good|easy`, Good by default), so the
      next question shows the pill; `last-rated` does it on a session of that one question ("That was the last one."). `CRAMLESS_UNDO_HOLD=1` keeps the
      pill until it is pressed; `CRAMLESS_SESSION_UNDO=<ms>` presses Undo that long after it shows.
    - The flashcard swipe: `flashcard-drag` holds the flipped card 60% of the way right; `flashcard-swiped` swipes it (the next one up, the tally at 1 and 0,
      the pill stays); `CRAMLESS_SESSION_SWIPE=rrlhe` plays a session of flashcards only by that pattern (`r` swipe right, `l` swipe left, `h` the Hard
      tile, `e` the Easy tile, `f` only flips, for a real finger), `CRAMLESS_AUTOPLAY_BEAT` ms on each flipped card. Check the swipe itself with a real drag too
      (`mobilecli io swipe x1,y1,x2,y2 --duration 700`: a fast one is a flick, which counts from anywhere). `CRAMLESS_SESSION_LONG_ANSWER=1` (with a flashcard state) gives the card an answer longer than the screen: a real drag up scrolls it, a real drag sideways swipes it (`FlashcardSwipe.SwipePan`).
    - `CRAMLESS_SESSION_STATE=flashcard-saved|mcq-saved` makes the first flashcard (or multiple-choice question) a
      fading memory and answers it right: a save, with the sky's flare.
    - The last look: `CRAMLESS_ROUTE=lastLook[:<n>]` opens it on the nth upcoming exam (`lastLook:1`: the Bio midterm, whose notes have pages; without a number, the first with ideas to show), `CRAMLESS_LASTLOOK=offline|cloud` with the prepared sentences missing or written (the mock relay). On an eve's summary (`CRAMLESS_ROUTE=session:examEve CRAMLESS_SESSION_STATE=exameve-summary`) it is the card under the words.
    - `CRAMLESS_SUMMARY_SKY=<ms>` opens the memory sky that long after a summary's choreography, as a tap on its
      "See the sky" strip would (films follow a real session into the sky it relit).
  - Onboarding steps: `CRAMLESS_STEP=firstSession|readiness|plan` (with `CRAMLESS_SEED=0`; `CRAMLESS_STEP_NODATE=1` for a person
    who gave no exam date: the readiness step then shows no number);
    `CRAMLESS_FIRSTSET=choose|processing|review` (with `CRAMLESS_ROUTE=scanner`).
  - Capture: `CRAMLESS_CAPTURE_PHASE=reading|ideas|writing|checking|done|review|error:<kind>`,
    `CRAMLESS_CAPTURE_INPUT=photo|text`, `CRAMLESS_REVIEW_EDIT|UNTICK|SCROLL|PEEK|APPROVE|ALLOW` (`SCROLL=leftout` also opens the "Left out" list; `SCROLL=offer` goes to the better-questions offer),
    `CRAMLESS_RECORD_FLAG|PAUSE|STOP`, `CRAMLESS_NOTES_FOCUS`, `CRAMLESS_IMPORT`, `CRAMLESS_PASTE_TEXT` (`sample`, or `long`: about 21 pages),
    `CRAMLESS_CANVAS=375x667` (SE size). A lecture's notes (`CRAMLESS_ROUTE=lectureNotes`): `CRAMLESS_NOTES_FOCUS=<s>` opens cued on that moment
    ("Play from …"), `CRAMLESS_LECTURE_PLAY=<s>` opens playing from it (the seeded lecture has no audio: `DemoLecturePlayback` runs the clock, silently).
  - A source: `CRAMLESS_ROUTE=source[:<n>]` the nth source with pages (one page opens straight on it, `source:1` has two). A source page: `CRAMLESS_ROUTE=sourcePage` zooms to a question's lines and circles them (`PageFocus`), `sourcePage:<n>` is that page of the first
    source, `sourcePage:text` a typed page (it scrolls to the lines, then circles them), `CRAMLESS_PAGE_ANCHORS=p0.l3,p0.l9` names the lines (across
    columns: no zoom, a circle each), `CRAMLESS_PAGE_FOCUS=0` keeps the old look (marks only).
  - Library and exams: `CRAMLESS_SCENARIO=eve|past|graded|missed|repair|thin|calibrated|ontrack|crowded|empty|bright|mocked|fewItems|gap` (each documented in
    `AppModel.applyHarnessScenario`; `calibrated` logs two past grades so the letter shows; `bright`: nothing is fading), `CRAMLESS_SCROLL=<section>`,
    `CRAMLESS_SEARCH=<words>`, `CRAMLESS_GRADE=<n>`. `CRAMLESS_ROUTE=course:<n>` opens the nth course (`course:3` is Spanish II,
    with no exam; one page, no tabs), `CRAMLESS_SCROLL=topics|sources|questions` scrolled to that part, `CRAMLESS_COURSE_TAB=questions` with its questions list open over it (`sources` scrolls to the sources), `CRAMLESS_COURSE_FILTER=attention|suspended|<kind>|topic:<n>` the list filtered; `CRAMLESS_ROUTE=exam:<n>` the nth upcoming exam, and `CRAMLESS_EXAM_SKIP=1` opens it with "What if I skip …?" on.
    The exam page's numbers are pinned with `CRAMLESS_NOW=2026-11-06T14:00:00-05:00` (the Chem quiz on Sunday at 10:00).
  - An exam's scope: `CRAMLESS_ROUTE=syllabus[:new|edit]` opens the exam editor on "Snap the syllabus" (`edit`, the default: the Bio midterm); `CRAMLESS_SYLLABUS=pick|reading|proposal|offline|applied|error:unreadable|nothing|nodate|notopics` holds a state, from a sample syllabus (`SyllabusSample`, the same page as `fixtures/requests/syllabus.json`): `proposal`, what Cloud AI reads (the mock relay); `offline`, this iPhone's rules; `applied`, the editor filled from it (the found page's button adds or saves the exam itself; the filled form is left only when it can't, a new course to name). `CRAMLESS_ROUTE=editItem:<kind>` edits the first question of that format (`editItem:recall`: key ideas with their other ways to say it). `CRAMLESS_ROUTE=newExam` is "Add exam" from the first course (no Course row), `newExam:today` from Today (the course asked); `CRAMLESS_EXAM_FORMAT=1` with it opens "Format and target". The gap: `CRAMLESS_EXAM_THIN=<n>` with any route narrows the nth upcoming exam (0: the soonest) to its smallest topic, for the page's thin-scope note. `CRAMLESS_ROUTE=exam:1 CRAMLESS_SCENARIO=gap` the exam page's card (one topic with drafts waiting), `CRAMLESS_GAP=sheet|research` opens "Fill the gap" over it (`research` also runs the web research: with `CRAMLESS_PLAN=pro`; `CRAMLESS_RESEARCH=pro` is the relay refusing a free account), `CRAMLESS_NOTICES=gap` Cap's card on Today. A date heard in class: `CRAMLESS_ROUTE=lectureNotes CRAMLESS_EXAM_HEARD=new|known|moved|added` makes Lecture 6 say one (`added`: "Add exam" pressed), `CRAMLESS_NOTICES=lecturedate` Cap's card.
  - Study out loud (no microphone or sound, `OutLoudDebug`): `CRAMLESS_ROUTE=outLoud` the intro; `CRAMLESS_OUTLOUD=asking|listening|verdict|summary|blocked|nomodel` starts at once and holds there; `CRAMLESS_OUTLOUD_SCRIPT=rpwk` answers question by question (`r` right, `p` partly, `w` wrong, `k` "I don't know", `s` "skip", `e` "repeat", `x` "stop"; after the last letter, `r`), through the same reading and grading as a real voice. The Live Activity's looks are in `WidgetRenderTests` (`docs/shots/widgets/session-*-outloud*`).
  - Teach Cap (`TeachDebug`): `CRAMLESS_ROUTE=teach[:n]` the nth topic with enough to ask; `CRAMLESS_TEACH_SCRIPT=good|thin` "says" an explanation with every idea, or only the first; `CRAMLESS_TEACH_STATE=prompt|listening|check|followup|added` opens on that state; `CRAMLESS_NOTICES=teachback` Cap's card on Today (the midterm 20 days out, one of its topics well remembered).
  - Ask, Settings and Squad: `CRAMLESS_ASK`, `CRAMLESS_ASK_MODE=open` (Cap's style open in the composer), `CRAMLESS_CHAT`, `CRAMLESS_AGE=teen|under13|adult|notShared` (with any route: `under13` shows `NoPurchaseView` on the paywall, Exam Pass and a Squad code; `notShared` the row that asks again in `settings:aiPrivacy`), `CRAMLESS_TUTOR`, `CRAMLESS_CARDS`,
    `CRAMLESS_SYNC`, `CRAMLESS_NOTIFY`, `CRAMLESS_SQUAD`, `CRAMLESS_ACCOUNT=apple|email`. `CRAMLESS_SQUAD_SHARE=fail` presses the sharing switch and the server turns it down (a build newer than its server); `CRAMLESS_SQUAD_TODAY=two|none|private|sharing` shapes the Squad's day (two friends studied; nobody yet; nobody shares; you share), for the page (`CRAMLESS_ROUTE=squad CRAMLESS_PLAN=squad`) and Today's line in "Your plan".
  - Explain my mistake: `CRAMLESS_ROUTE=explain`, `CRAMLESS_EXPLAIN_STEP=1|2|3` (that step, once the answer has reached it), `CRAMLESS_EXPLAIN=card|added|followup` (step 3 with "Make this a card" drafted, or added, or the follow-up composer open). `CRAMLESS_MOCK_LATENCY` slows the reply, to see the pages unlock.
  - Snap a problem (with `CRAMLESS_ROUTE=ask`): `CRAMLESS_SNAP=confirm|mathlike|unreadable` opens "Check the problem" in that state, `asked` sends a problem (the reply with its citation), `notcovered` one the notes don't hold (the app's own line), `CRAMLESS_SNAP_TEXT=<words>` sets the words.
  - Answered later (with `CRAMLESS_ROUTE=ask`): `CRAMLESS_OFFLINE=1` makes the mock relay's tutor and assistant fail as `URLError.notConnectedToInternet`, `CRAMLESS_OFFLINE_UNTIL=<ms>` only for that long after launch, and then the app acts on the connection coming back (a real press of "Answer it later" before that shows the answer arrive); `CRAMLESS_ASK=later` asks with no connection, `kept` also presses "Answer it later", `answered` shows the late answer in place.
  - Ask Cap's assistant (`docs/assistant.md`): `CRAMLESS_ROUTE=ask CRAMLESS_ASSISTANT=cards|quiz|note|exam|practice|research|multi|answer|limit|error`
    asks Cap in a Bio 101 chat and plays the mock relay's script at its live pace (`AskDemo.assistant`). `CRAMLESS_ASSISTANT_FREEZE=<n>` holds the
    reply after n updates (a card half way through its work), `_AUTO=cards,notes,exams` switches on "Let Cap do it", `_SEND=<text>` asks
    something else, `_APPROVE=<ms>` presses Add and `_UNDO=<ms>` takes it back, `_SEED=1` (with `CRAMLESS_ROUTE=settings:assistant`) fills "Added by
    Cap", `CRAMLESS_RESEARCH=pro` shows a free account's web research. `scripts/cap_anim/films_assistant.sh <udid> <out>` films and shoots them all.
  - Paywall and onboarding: `CRAMLESS_PAYWALL_PLAN`, `CRAMLESS_PAYWALL_STATE=purchasing|pending|cancelled|failed|purchased|restored`,
    `CRAMLESS_PAYWALL_TRIAL=0`, `CRAMLESS_PAYWALL_SCROLL=free|plans|timeline` (`free`: the "Always free" card), `CRAMLESS_ONB_REMINDER=1`.
  - Progress: `CRAMLESS_ROUTE=month` opens the month sheet, `CRAMLESS_ROUTE=streak CRAMLESS_SCROLL=heatmap` the streak page's twelve weeks, `CRAMLESS_SCROLL=week|exams|fading|mixups|more` the tab's sections; `CRAMLESS_SKY=memory` opens "How you remember" over the sky.
  - Mock exam: `CRAMLESS_ROUTE=mock[:<n>]` opens a mock of the nth upcoming exam (without a number, the first with enough questions; `mock:0` is the Chem quiz, multiple choice only, and too short: the too-few state), `CRAMLESS_MOCK=intro|mcq|short|cloze|review|timeup|marking|summary|selfcheck` opens on that state (`selfcheck` with `CRAMLESS_CONSENT=0`: the own-words answers are the person's to mark), `CRAMLESS_MOCK_AUTOPLAY=rrwpk…` answers every question by that pattern (`r` right, `p` partly, `w` wrong, `k` left blank), `CRAMLESS_AUTOPLAY_BEAT` ms apart, then hands in; `CRAMLESS_MOCK_ELAPSED=<s>` starts the clock that far gone. The exam page's card: `CRAMLESS_SCENARIO=mocked` (a mock taken three days ago, "Last mock"), `fewItems` (five questions left in scope, "Write more questions").
  - Money and trust: `CRAMLESS_QUOTA=scans:2,lectures:1,grades:20` sets the free AI uses left on those meters, as if the server said so
    (`scans:0` is the limit reached; the + sheet, the scanner and the recorder say it, `AllowanceCopy`); `CRAMLESS_LECTURE_RECOVERED=2480`
    raises launch's "Cap kept your lecture up to 41:20." toast with Open (`=2480,3100`: two lectures); `CRAMLESS_ROUTE=settings:help`
    opens Help.
- Feel:
  - The harness is silent unless `CRAMLESS_SOUNDS=1`, but logs every cue to `Documents/feel-log.jsonl` for
    `film.sh`. On a simulator no audio engine is built at all without it, harness or not (`CLSoundOutput`): the audio system's first call aborted
    the process on a busy Mac.
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
  - Today's top is a sky band (`HeroWorld`): `CRAMLESS_HERO=12000:x300y160` taps the point (300, 160) 12 s after launch, through
    the same code as a finger (a tap opens the full sky; on the outline sky of the first day it ripples).
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
  - The game loop (`AppModel+GameHarness.swift`), all with no taps: `CRAMLESS_SCENARIO=streak:<n>` makes a streak of n days up to
    yesterday (so a session today makes n + 1: `streak:29` then a session is the 30-day milestone);
    `CRAMLESS_QUESTS=start|partial|done|weekFull` puts today's quests and the week part way through (`weekFull`: one session from
    lighting a sky; it makes the week end today), `CRAMLESS_QUEST_PICKS=finishSession,ownWords,learnNew` names today's quests;
    `CRAMLESS_UNLOCK=all` and `CRAMLESS_SKY_THEME=<night|dusk|aurora|ember|bloom|glacier>` unlock every icon and sky or choose one;
    `CRAMLESS_SKY_TOUR=<ms>` cycles Today through the six skies; `CRAMLESS_TILT=<pitch>,<roll>` (each -1 to 1) holds a badge medal's
    tilt. Routes `badges` and `badge:<id>` (`Badge` raw values, `badge:streak30`). Summaries: `CRAMLESS_SESSION_STATE=milestone-summary|
    badge-summary|quest-summary` answer eight questions and show the summary; then `CRAMLESS_SUMMARY_SCROLL=<ms>` scrolls it to its
    end, and each that long after the one before `CRAMLESS_SUMMARY_USE_SKY` (puts the sky the week lit behind the stars),
    `CRAMLESS_SUMMARY_BADGE` (opens the new badge) and `CRAMLESS_SUMMARY_DONE` (presses Done). Films use `CRAMLESS_NOW` in the
    afternoon: after 22:00 celebrations are calm (no confetti).
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
    SwiftUI's tab delegate and answers "may it be selected?" with no, running the action instead (the + sheet, for the course on screen:
    `AppModel.courseOnScreen`). A selected + swaps the
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
- A sheet raised over a cover is the cover's to present (`Router.rootSheet`): from the root it takes the cover's place, and the cover is built anew when it closes. Test a sheet over a session with a real tap: its question and timer must be the same after it closes.
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
  then the on-device model (off in the shipped build since 2026-11-04: `AIBuild.onDeviceModelEnabled`, docs/BUILD.md),
  then the relay (cloud) only after consent and within quota. Generated sets arrive
  as drafts the person approves. Grading highlights only quotes found verbatim in the answer. Tutor answers cite
  the person's material or say it isn't covered. Failures fall back quietly to the offline path. Cloud requests
  are built from what is true after any wait (consent sheet, network).
- **Consent**: cloud AI is opt-in (`settings.cloudConsentVersion`), sending page photos is a separate switch
  (`settings.sendPhotos`). Copy never says "nothing leaves your device" where a cloud path exists.
- **Under-13**: Cloud AI never runs (`AIAgeGate.child`), so nothing is sold: `settings.canBuyPro` is false, every way to a purchase shows `NoPurchaseView`
  (Restore stays) and no router suggestion points at the paywall. A new way to a purchase checks it.
- **Under-18**: `settings.isMinor` keeps the tutor on hints first and teen-safe; no essay writing or
  "humanizing", for anyone. When iOS gives no age range, a student who said college or grad school keeps the adult rules and everyone else gets these (`AgeRange.fallback`, `AgeBand.notShared`). It also locks every "Let Cap do it" switch on ask-first and removes web research
  (`settings.assistantAuto`, `assistantWeb`; the relay refuses `research` and drops `research_web` for `minor` too).
- **Ask Cap's assistant** (`docs/assistant.md`): the model only *chooses* a tool; the app runs it (`AppModel+Assistant`,
  `AIRouter+Assistant`). A draft tool returns a proposal in the chat (`AssistantStep`, kept in `ChatMessage.actionsData`) that the student
  adds, changes or skips, or, with "Let Cap do it" on for that kind, that is added at once and can be undone. The model's claims are checked
  here before they are shown (`AssistantDrafts`: a quote is evidence only if it is in the notes, else the item says "Cap's own words"; a
  choice question needs its right option; a date must be a real day). Adding goes through `ItemFactory` / `createSource` / `createExam`, undo
  is a soft delete of the ids the step made. The tool result the model reads must say what really happened ("proposed" or "added"). Web text
  is data: the research route has no tools and its result becomes a note only on a tap. Add a tool in `_shared/assistant.ts` (strict
  schema), `AssistantToolName`, `runDraftTool` or the router, a mock script in `_shared/fixtures`, and the live test's cases.
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
  system's Liquid Glass (`.glassEffect`, `.buttonStyle(.glass)`); a toast sits on the solid surface, so it reads over anything.
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
  - Today's top is a short sky band (`TodaySkyHero` over `HeroWorld`, `HeroWorldGeometry.band`: the sky, background stars, hills and
    a strip of lake, Cap on the shore; a tap opens the full sky; its pure parts are `HeroWorldModel.swift`; the welcome's taller
    world is the same geometry with `style: .world`); what each day's card says and offers is one pure value, `TodayHeroContent`
    (copy in `TodayCopy`, "Why these?" in `TodayReasons`, the week in `TodayPlanStrip`; Cap's cards are dealt by `NoticeEngine` (`Engine/Notices.swift`, its head says how to add a kind), said by `NoticeContent` as `CapNotice`). Progress shows pieces of it: an exam's region (`SkyScene.region(of:)`, drawn by
    `SkyRegionStill`) and a topic's glyph (`SkyScene.glyph(of:)`, `SkyGlyphView`).
  - An exam's region records the constellations it covers (`SkyLayout.Region.covers`); use that, never "is it inside the
    circle", to decide what belongs to an exam.
- Celebrations: `CelebrationPolicy` (`Engine/Celebration.swift`) picks one per screen, for learning only (never a
  purchase); `CLConfetti` draws it. Exam eve, quiet hours and Quiet mode stay calm.
- The game loop (`docs/design.md` ▸ The game loop): nothing to lose, no currency.
  - The flame is `StreakFlame(stage:size:lit:bounce:)` over `StreakStage(days:)` (`Shared/`, drawn in code, so widgets use it too);
    use it wherever a streak is shown in colour, not `flame.fill`. Milestones are `StreakStage.milestones` (3, 7, 30, 100, 365).
  - Daily quests are `QuestEngine` (`Engine/Quests.swift`, pure and seeded). A quest's raw value is its bit in `DayRecord.questMask`
    (stored, synced as `quest_mask`, merged by OR): never renumber `QuestKind`. Progress is read from the day's own answers
    (`AppModel.questFacts(forDay:)`); `settleQuests()` writes the bits (summary, rollover). 12 in a calendar week light the next
    `SkyTheme` (`settings.litWeeks`).
  - Badges are `AchievementEngine` over facts read from the whole log (`achievementFacts()`, cached per revision); `settings.badges`
    keeps which the person has been told about. `AppModel.settleGame()` is what the summary calls after a session.
  - A sky is a `SkyPalette` read from the environment (`@Environment(\.skyTheme)`, set at the root): draw with
    `theme.palette.top`/`.farHills`/…, never the night colours. Icons are `AppIconChoice` (unlocked by the best streak); change one
    with `app.setAppIcon(_:)`, which asks the system's switcher (a fake in tests).
  - `ReviewPromptPolicy` decides when to ask for a rating; the summary asks. It never asks in the harness or in tests.
  - Quiet mode (`settings.quietMode`, Settings ▸ Study): every game surface checks it. No flame, quests, badges or run counter, calm celebrations, no streak
    notifications (`NotificationPlanner.Input.quiet`), no sounds, no flame on the Today widget (`WidgetSnapshot.quiet`; a placed Streak widget stays). Quests
    and badges still settle unseen. A new game surface checks it too.
  - Look at anything with layers in a real screenshot: a `.shadow` + `inset(by:)` + blur + blended sheen on one view drew a second
    medal beside the first on screen and not in an `ImageRenderer` (`BadgeMedal`).
- Feel: a moment with a sound plays `CLFeel.play(.right(combo:))`, `.saved`, `.done`, …
  (`DesignSystem/Feel/`), which plays the sound and its paired haptic together.
  - Plain taps, ticks and page turns stay on `CLHaptics` and make no sound.
  - Both are for the person's own actions; demo scenes and loops fire none.
  - Sounds are synthesized (`CLSynth`, no audio files), mix with other audio and obey the Silent switch.
  - Anything that takes the audio session claims `AudioFocus` first.
- A self-given rating (a flashcard, own-words marks, "Counts as") is held for Undo (`SessionRunner.Options.undoWindow`, `PendingGrade`) before it is written. Graded
  answers aren't: Continue was their moment. A review log is append-only once sync has pushed it, so nothing is ever recorded and then reverted.
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
