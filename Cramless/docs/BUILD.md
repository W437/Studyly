# Cramless build log

How the app was built, who owns what, and what is left. Started 2026-10-22 from the plan in
`../../docs/rethink/` (the owner asked for the full launch scope).

## Phases

1. **Foundation** (orchestrator): project, design system, models, router and shell, the relay contract and its
   fixtures, the harness and demo world, stubs for every lane. Builds green with one contract test.
2. **Services, in parallel lanes** (each in its own copy of the tree, merged by the orchestrator):
   - **Engine**: FSRS-6, scheduling, sessions, readiness, plans, streaks; `AppModel+Study`, `AppModel+Insights`.
   - **Backend**: `supabase/` (schema, RLS, the `ai` relay with MOCK mode, entitlements, Squad, account) and the
     Swift client in `Sync/` (auth, sync, backend calls); `docs/relay-contract.md`.
   - **Capture**: scanner, text recognition, PDFs, paste, Anki/Quizlet/CSV imports, lecture recording and
     transcription; `AppModel+Capture`.
   - **AI**: transports (HTTP, mock), offline rules, on-device model, `AIRouter`, consent and quota, the consent
     sheet.
   - **Store and onboarding**: StoreKit 2, the paywall, Exam Pass, the welcome and live-demo onboarding, the quiz.
   - **Widgets**: widgets, Live Activities, controls, App Intents, notifications, deep links, read-aloud.
3. **Screens, in parallel lanes**: Study (Today, sessions, summary, fixes, onboarding's first session and
   readiness), Capture UI (capture sheet, processing, draft review, source pages, lectures, onboarding's first
   set), Library/Exams/Progress, Ask/Settings/Squad.
4. **Integration and polish** (orchestrator): merge, full test run, every screen captured light and dark,
   fixes, feel pass, docs.

## Ownership

| Path | Owner |
|---|---|
| `project.yml`, `App/AppModel.swift`, `App/Router.swift`, `App/RootView.swift`, `App/AppConfig.swift`, `App/TestHarness.swift`, `Model/*`, `DesignSystem/*`, `AI/RelayContract.swift`, `AI/RelayTransport.swift`, `Engine/InsightTypes.swift`, fixtures | Orchestrator (lanes propose changes in their reports) |
| `Engine/*`, `App/AppModel+Study.swift`, `App/AppModel+Insights.swift` | Engine |
| `supabase/**`, `Sync/*`, `App/AppModel+Account.swift`, `docs/relay-contract.md` | Backend |
| `Capture/**`, `Lecture/*`, `App/AppModel+Capture.swift` | Capture |
| `AI/*` (except the contract), `Features/Settings/ConsentSheet.swift` | AI |
| `Store/*`, `Features/Paywall/*`, `Features/Onboarding/*`, `Cramless.storekit` | Store and onboarding |
| `CramlessWidgets/*`, `Shared/*` (new files), `Services/*`, `App/DeepLinks.swift`, `App/Intents/*` | Widgets |

Shared rule: notification requests whose identifier starts with `trial.` belong to `PurchaseStore`;
`NotificationScheduler` never removes them.

## Status

**Done (2026-10-22): the whole launch scope is built and merged.**
- Swift tests: `Executed 601 tests, with 6 tests skipped and 0 failures` (the skips are the opt-in StoreKit
  purchase flows).
- Deno tests: 95 passed (11 more run with the local stack).
- Every harness route was captured in light and dark and looked at. No stub screens remain.

- [x] Foundation (2026-10-22)
- [x] Phase 2 lanes
  - [x] Engine (merged 2026-10-22): FSRS-6 matching py-fsrs 6.3.2 on 334 reviews, scheduler, sessions, readiness,
    plans, streaks, confusion candidates; 80 tests. `applyDailyRollover()` runs at launch and on becoming active.
    Notes: for multiple choice, pass the chosen option's text as `answer` to `recordReview` (swap detection);
    `DayRecord`/`StudySession` are marked for sync by clearing `syncedAt`; projections assume the plan is followed
    and are labelled projections.
  - [x] Capture (merged 2026-10-22): `RecognizeTextRequest` (measured against `RecognizeDocumentsRequest`: same lines
    on the sample, but only the text request's confidence separates real text from hallucination), reading order
    and page numbers, confidence gates (`PageRead`: unreadable and math-like pages flagged), PDFs, paste, Anki
    (zip + SQLite, scheduling kept; anki21b-only decks get an export instruction), Quizlet, CSV, lectures (AAC
    stream remuxed to m4a on stop so a crash keeps the audio; SpeechAnalyzer; flags; a demo transcriber for the
    simulator); 93 tests. Anki cards suspended in Anki import suspended.
  - [x] Widgets (merged 2026-10-22): snapshot in the App Group (empty state in unsigned builds), next-exam, today and
    streak widgets on Home and Lock Screen, session and exam-week Live Activities, a Start control, intents
    (How ready am I, scan, record, start) and shortcuts, the notification planner (quiet hours, 2 a day,
    `trial.` untouched), deep links, read-aloud, Declared Age Range (entitlement added); 65 tests.
  - [x] Backend (merged 2026-10-22): schema with RLS and explicit grants (pgTAP 53 checks against a local stack),
    the `ai` relay (9 routes, quotas with refunds, anchor cleaning, MOCK = fixtures byte for byte, real mode via
    `@anthropic-ai/sdk` 1.1.0 with structured outputs and tutor citations over search results; tested against a
    mock Anthropic server, never a real key), `account` (StoreKit JWS verification ported from plainsum, Squad,
    deletes), `appstore-notify`; Swift `Sync/` (GoTrue auth incl. anonymous and Apple, Keychain session, PostgREST
    sync with a ledger, BackendClient). Deno 95 tests (+11 with the local stack), Swift 50.
    Owner must provide: a Supabase project (host + anon key in Secrets.xcconfig), `ANTHROPIC_API_KEY` and
    `APPLE_APP_ID` secrets, the Apple provider's client id, the email code template, the App Store notifications
    URL, the `capling.app/squad/<code>` domain. Follow-up: `StudySession`, `DayRecord`, `SourcePage` have no
    `updatedAt`; sync approximates with the parent's stamp or `syncedAt == nil`.
  - [x] AI (merged 2026-10-22): `AIRouter` (+Generate/+Grade/+Tutor/+Jobs) with a pure routing function tested
    against an oracle (~36,000 combinations), HTTP and mock transports (SSE parser), offline rules (generator,
    grader with negation and typo handling, BM25 retriever, tutor, lecture notes, confusions), Foundation Models
    jobs (never throw; untested on hardware: the simulator has no model), Private Cloud Compute dormant, consent
    (`AIConsent.currentVersion` 1) and quota (rules never metered); `ConsentSheet`; 123 tests.
  - [x] Store and onboarding (merged 2026-10-22): `PurchaseStore` (pure entitlement resolver, Exam Pass 30 days,
    trial reminder `trial.`, server grants for Squad seats, `appAccountToken` from the account), the three-option
    paywall with fallback prices when StoreKit has no products (simctl launches), `PurchasedView`, `ExamPassView`,
    the welcome, five live-demo pages, the quiz and the reminder moment; 58 tests including real `SKTestSession`
    purchases. Terms and Privacy URLs are required before App Review (hidden until set).
- Integration notes: AccountService feeds `purchases.accountToken` and server grants; buttons wrap and rounded
  numbers scale at accessibility sizes.
- [x] Phase 3 screen lanes
  - [x] Library, Exams, Progress (merged 2026-10-22): library with search, course (topic map, sources,
    questions), source and page views (zoom, highlights), course/question/exam editors, exam detail (ring,
    projected grade, path chart, week strip with a missed day absorbed, Exam Pass card), log grade, Progress
    (streak, heatmap, weekly minutes, readiness history, retention, due forecast, topics, confusions), streak
    calendar; `AppModel+Library.swift`; 44 tests.
  - [x] Study (merged 2026-10-22): Today (session card and its states: catch-up, exam eve, done, empty; next exam;
    Cap's confusion note; quick capture), the session cover with all six formats (own words with the
    highlighter and refined grading, multiple choice, fill-in, diagram on the real page, flashcards with interval
    previews), Live Activity and read-aloud, the summary (readiness before/after, streak, a confusion offered),
    exam eve's stop-and-sleep ending, ConfusionView, and onboarding's first session, readiness and plan steps
    (wired into `OnboardingFlow`); `AppModel+Session.swift`; 31 tests. Small buttons now take taps over 44 pt.
  - [x] Ask, Settings, Squad (merged 2026-10-22): Ask Cap (streamed answers with citations that open the page,
    hints first or just explain, locked for minors; quick checks answered inline; starters from your material;
    history; the essay/humanizer refusal mirrored offline), Explain my mistake, Make cards from a chat, Settings
    (account with Sign in with Apple or an email code, subscription, study, notifications, AI and privacy with
    consent, the photos switch, on-device report, quotas and Delete AI data, accessibility, appearance, data
    export as CSV/JSON and delete all, about with font licences, a DEBUG page), Squad (invite, members, redeem);
    `AppModel+Ask.swift`; 40 tests.
  - [x] Capture screens (merged 2026-10-22): the capture sheet, the scanner (VisionKit, or Photos and the sample
    page where the scanner isn't available), the processing screen (real phases, paced, the onboarding scene's
    choreography), problems (unreadable, math, no text) with a cloud read only when photos are allowed, the draft
    review (topics, ticks, edits, source chips, "Left out" with reasons, an honest origin line, course picking),
    paste, deck import with a preview, the lecture recorder (live transcript, "on the exam" flags) and lecture
    notes; `AppModel+Drafts.swift`; onboarding's first set (wired); 19 tests.
- More integration fixes: sheets get the dyslexia-friendly font (they don't inherit it from the presenter); the
  tutor's retrieval widens to the last two questions and Cap's last answer for short follow-ups ("why?");
  onboarding's "I already have an account" opens a real sign-in (then syncs and skips onboarding); a redeemed
  Squad seat counts at once (also in mock mode).
- Integration fixes:
  - **Honest projections.** The plan simulation assumed every first look at new material was recalled and that
    the plan is followed perfectly (Chem showed 42% → A+ 99% in two days). It now uses the person's first-try
    rate on new items (75% until there are 20 first looks) and their adherence (share of recent days studied,
    80% until a week of history): `projected = now + adherence × (plan − now)` (`AppModel.studyHabits()`).
  - The harness keeps its settings in a `cramless.harness` suite wiped at launch (a dark run no longer leaks
    into the next one), and never touches StoreKit (`CRAMLESS_STOREKIT=1` opts in).
  - `StorePurchaseFlowTests` are opt-in (`TEST_RUNNER_CRAMLESS_STOREKIT_TESTS=1`): on iOS 27 simulators they
    can leave a real "Sign in to Apple Account" prompt over every app until the simulator is erased.
- [x] Integration and polish (2026-10-22): merged in order; the build was kept green and every suite run after
  each merge. Onboarding is wired end to end: welcome → five demos → quiz → first set → first session →
  readiness → plan → paywall → Today. Every route was captured in light and dark. Simulators were deleted.

## Verified against real services (2026-10-22, after the build)

Everything above was first tested against mocks. This pass ran the app's own code against the real things this
Mac has.

- **Foundation Models (Apple's on-device model on this Mac, macOS 26.6.2; the iPhone model family).**
  `scripts/fm_live/run.sh` compiles the app's AI sources into a macOS program and runs them on the sample page.
  - The first run found real problems, and each is now fixed:
    - A kept question was false ("Which is NOT a phase… → Telophase"). Negative stems are now dropped, and the
      model's multiple choice is never kept as choices: it becomes a flashcard, and the rules supply multiple choice.
    - Key ideas were empty labels ("Purpose", "Role"). Ideas must now carry the answer's own new facts, and are
      rebuilt from the answer otherwise; list answers get one idea each.
    - A fill-in blanked out the whole sentence. The blank word is now recovered from the sentence, and whole-sentence
      blanks are refused.
    - The model repeated one question several times, and some questions gave their answer away. Both are filtered.
    - Grading feedback leaked internal ids ("got K1 and K2") and praised a wrong answer. Feedback is now always the
      rules' wording, built from the hits.
    - The model and the rules each missed a different idea in a paraphrase. A hit now counts when either can quote
      the student's exact words; the paraphrase is graded correct.
    - Hints mode stated the answer, or claimed the notes didn't cover it. The prompt was reworded, and a hints reply
      without a question falls back to the offline tutor's guiding question, so minors always get hints first.
    - A question with no passages got an answer from the model's own knowledge (the World Cup). The quote check
      dropped it, and the app never sends a question with no passages.
  - On-device generation now yields 2–5 accurate questions per page, topped up by the rules.
  - Tests pin each measured pattern (`AIOnDeviceTests.testModelOutputFiltersFromTheRealModelRuns`).
- **Speech (this Mac's on-device speech models).** `scripts/speech_live/run.sh` runs the app's lecture transcription
  on a spoken mitosis lecture.
  - Setup took 1.4 s and transcription 0.8 s for 21 s of audio, and the "on the midterm" flag fired.
  - Finding: `SpeechTranscriber` ignores contextual strings, while `DictationTranscriber` uses them. With the course's
    vocabulary, "interface / Anna faces / Telo phases" became "interphase / anaphase / telophase".
  - Lectures now prime the engine with the course's own words (`AppModel.lectureVocabulary`), and use the dictation
    engine when there is a vocabulary (`TranscriptionGate.preferringVocabulary`, tested).
- **The owner's iPhone 15 Pro (iOS 26.6.2).** `scripts/device_isolated.sh` built the debug app, signed it with the
  team's wildcard profile (no capabilities requested, the developer account untouched) and installed it.
  - The phone was locked, so the probe couldn't launch. `scripts/device_probe.sh <udid>` runs it after unlocking:
    on-device generation, grading and tutoring through the app's router, a speech round trip (the phone speaks, the
    lecture transcriber reads it back), VisionKit, a Live Activity, haptics hardware and notifications.
    `scripts/device_shots.sh` captures real screenshots.
- **Supabase, the real software on a local stack** (`scripts/local_stack.sh up|env|down`, MOCK relay). The app's own
  Swift classes ran over HTTP to localhost (`CramlessTests/LocalStackTests`, opt-in), and all 12 tests passed:
  - Auth: anonymous sign-up, the token reused, concurrent calls making one sign-up, refresh, email codes, sign-out.
  - The relay: every route decoding equal to the fixtures, the tutor really streaming, and quota reads.
  - Quotas: the 21st grade gets HTTP 429 with the envelope.
  - Sync: two `AppModel`s on one account, all 10 tables, page photos byte-equal, tombstones, edits both ways.
  - Squad: invites, redeem, the plan showing in the backend, `PurchaseStore` and the relay; refusals.
  - Deletion: AI data, then the account, with old tokens refused.
  - Purchases: a StoreKit test purchase posted to `account/entitlements` grants Pro.

  On the same stack, the Deno suite ran 106 tests (the Postgres-backed ones included), and the six StoreKit purchase
  flows passed on a freshly booted simulator.
  - **Bug found and fixed:** someone who bought while anonymous and then signed in was metered as free until the
    next launch (`PurchaseStore.resyncEntitlements()` after sign-in). The same gap after sign-out is closed too.
- **Claude models on the relay's own prompts.** There's no API key on this Mac, so
  `supabase/functions/tools/prompt_replay.ts` recorded the relay's exact calls on the sample page: model, system
  prompt, user content and JSON schema. Claude Haiku 5.5 and Sonnet 5.5 answered them as Claude Code subagents.
  Their replies went back through the relay's own validation and cleaning (`replay`). The files are in
  `build/prompt_replay/`.
  - Generate (Haiku 5.5): all 12 items passed validation (4 recall, 4 multiple choice, 2 flashcards, 1 cloze,
    1 apply). Every anchor was a real line, and every multiple choice question had exactly one right answer.
  - Check (Haiku 5.5): all 12 supported, each with a reason naming what the page says. A second set mixed 4 of
    those items with 3 planted errors. All three were caught, and the 4 real items stayed supported:
    - Anaphase was marked as the phase where chromosomes line up: fixed, with Metaphase marked correct.
    - Mitosis's purpose was given as making sex cells: unsupported.
    - Cytokinesis was defined as dividing the nucleus: fixed to "the division of the cytoplasm".
  - Grade (Haiku 5.5), three answers to one question: partial (2 of 3 ideas), correct (3 of 3) and incorrect (an
    answer about sex cells). Every hit quoted the student's exact words.
  - Tutor (Sonnet 5.5): hints mode gave 46 words pointing to the right lines, ending on a question. Explain mode
    gave 54 words with two citations, both verbatim from the page, and a check question. These were read by
    script, not replayed: the replay tool doesn't stream.
  - What this doesn't cover: the subagents had their own agent context, the API didn't enforce the schema, and
    no tokens or cost were measured.
- **Claude through the relay, over the API.** `ANTHROPIC_API_KEY=… deno task live`
  (`supabase/functions/tools/live_check.ts`) runs the relay's real code path on the sample page, through generate,
  check, grade and the streamed tutor, with verdicts and cost. It hasn't been run, for lack of a key. A dry run
  against the mock server (`ANTHROPIC_BASE_URL`) exercises the plumbing only.

## Featuring plan (approved 2026-10-22)

The plan for making Cramless an app Apple features is `~/.claude/plans/cozy-meandering-flamingo.md`: 14 phases,
each reviewed by the owner as films on `https://macbook-pro.tail9699dc.ts.net:8824/` (`build/review/`).

**Phase 0: groundwork, the sound engine and the review pipeline (done 2026-10-22).**
- **Sound and haptics:**
  - `DesignSystem/Feel/`: `CLSynth` (synthesized cues, Foundation only), `CLSound` (ambient AVAudioEngine, four
    players, quiet hours), `AudioFocus` (read-aloud and the recorder take the session first), and `CLFeel.play(_:)`
    (sound plus haptic, the one call).
  - `CLHapticPatterns` (Core Haptics, one tap per note) is in `Haptics.swift`.
  - `AppSettings.sounds` sits in Settings ▸ Accessibility ▸ Feel, with "Hear an example", the summary line and the
    export.
- **Feel lab:** Settings ▸ Debug ▸ Feel lab (DEBUG) plays every cue on each palette; `CRAMLESS_FEELLAB=sounds` plays
  them all for a film.
- **Groundwork:**
  - "Saved it": `ReviewOutcome.recallBefore` and `isSave`.
  - Answers applied later: `recordReview(at:dayKey:reviewID:)`, idempotent by the review id, credited to the day
    they were given.
  - Stable demo ids (`ModelID`, `StableRandom.uuid`), so the demo world repeats exactly.
  - `Shared/Core/` (Foundation only).
  - `\.clReduceMotion` and `\.clDifferentiateWithoutColor`, with DEBUG overrides.
- **Review pipeline:** `scripts/film.sh` (films scored from the cue log), `scripts/sound_audition/run.sh`,
  `scripts/review_server.py`.
- **Tests:** 636 Swift tests run, 0 fail, 18 skipped (they only run when switched on); 20 are new (`FeelTests.swift`).
- **Decided 2026-10-23:** Marimba, at the rendered loudness.

**Phase 1a: the localization foundation (done 2026-10-22).** Phase 1 was split. The foundation came first; the
sweep of existing copy (1b) moves to just before translation (Phase 11), because Phases 2–10 rebuild many of those
screens, and anything they touch is converted as it goes.
- **String Catalogs:** for the app and the widgets, with `developmentLanguage: en`, `LOCALIZATION_PREFERS_STRING_CATALOGS`
  and `SWIFT_EMIT_LOC_STRINGS`. `scripts/sync_strings.sh` (run by `xc.sh` after every green build or test run) merges
  the extracted strings, the way Xcode's editor does.
  - The app's catalog now holds 953 keys; the widget's holds 43.
- **Plurals:** `docs/l10n/plurals.json` holds English plural forms, applied at sync. Keys with two numbers use catalog
  substitutions. "1 minutes"-style text in 16 existing strings is fixed.
- **Components:**
  - `CLRow`, `CLSectionHeader`, `CLEyebrow`, `CLChip`, `CLPill`, `ReflowPill`, `Toast` and `router.toast`, plus the
    Settings components, take `LocalizedStringResource`.
  - Computed text passes through `.verbatim(_:)` (`Shared/Core/Localization.swift`), unchanged on screen.
- **Screenshots:** `scripts/shots.sh` takes `SHOT_LANG=` and `PSEUDO=bounded|double|rtl`.
  - The bounded sweep on the review page shows what 1b must convert, mostly computed lines.
  - Doubled text shows the tab bar needs room.
- **Tests:** 640 run, 0 fail (`LocalizationTests`).

**Phase 2: the session's feel (done 2026-10-22).**
- **Buttons with depth:** `CLButtonStyle` (an edge per kind, plus `.verdict(tone)` for the panel's Continue) and
  `CLPressableStyle(depth:)`, used by answer options and rating tiles. New tokens: `press`, `release`, `sheet`,
  `bloom`. Edge colours are in BrandPalette.
- **The answer panel:** `DesignSystem/Components/FeedbackSheet.swift` (`FeedbackTone`, `AnswerFeedback`,
  `FeedbackPanel`, `FeedbackDetails`, `ComboChip`).
  - `sessionFooter(feedback:…)` swaps it in for the button bar.
  - All five question views use it; the inline `FeedbackBox` is gone.
  - The headlines come from `SessionCopy.headline` ("Nice!", "Almost.", "Not yet.", "Here's the answer.",
    "Saved it.").
  - Own-words answers show "Checking…" while the highlighter sweeps, and the panel rises as it finishes.
- **Runs:**
  - `Engine/ComboRun.swift` counts the run; flashcard ratings are neutral.
  - `SessionRunner.combo(adding:kind:)`, `liveCombo`, `wouldSave(_:)` and `cues(for:item:answered:)` back it.
  - The run is fixed at the verdict, so the panel never counts an answer twice while it leaves.
  - Each verdict plays its cue through `CLFeel`: the run's note, the flourish at 5/10/15, the save, almost, not yet,
    revealed. A flashcard plays flip and rated.
- **Top and progress bar:** the timer is a glass pill, and a run pill morphs out of it from three in a row
  (`GlassEffectContainer`, `glassEffectID`). `SessionSegments` are 8 pt, with a bloom on the newest result, a mint
  glow for the run and one shine per step.
- **Touches:** a ripple on the picked option (`Shaders/Ripple.metal`, `CLRipple`), and checks that draw on
  (`.symbolEffect(.drawOn)`).
- **Films:**
  - `CRAMLESS_SESSION_AUTOPLAY` and `CRAMLESS_AUTOPLAY_BEAT` play a whole session headlessly.
    `SessionQuestionHost.rightAnswer(to:subject:)` keeps "right" right under the offline grader.
  - Film sync took three fixes:
    - The recorder drops seconds mid-take, so a per-frame timecode strip (`FilmTimecode`) replaced one-point sync.
    - A `CADisplayLink` drives the strip, because a SwiftUI timeline in a second window lagged under load.
    - film.sh trims with a filter, because a fast seek on these variable-rate recordings landed about 1.5 s off.
  - The Feel lab now shows each sound's name at its own frame, within about 10 ms.
- **Tests:** 648 run, 0 fail (`ComboRunTests`, `SessionFeelTests`, headline copy).
- **Owner review, 2026-10-23:** approved, with the tangerine Continue after "Not yet". One fix: the panel's colour
  stopped above the home indicator, leaving a strip of page under it. `SessionQuestionHost` clipped to its frame,
  which ends at the safe area; it no longer clips, so the fill reaches the screen's edge and the buttons stay put.

**Phase 3: Cap in motion and celebrations (done and approved 2026-10-23).** It shipped with no new art, so every new
pose showed a drawn stand-in; the art came after (next entry).
- **Cap** (`DesignSystem/Components/Cap.swift`):
  - `CapPose` gains the 15 planned poses. `CapPose.drawn` lists the four with art, and `fallback` and `shown` pick
    the stand-in.
  - `CapMotion` (hop, wiggle, nod, arrive) is a set of pure curves (`frame(at:)`, `MotionCurve`), with
    `CapSparkles`, plus breathing and dozing (drifting z's).
  - `CapMoment` is the moments table. `CapView(_ moment:)` plays a moment's motion when it appears and whenever it
    changes, and cross-fades poses. Under Reduce Motion it never moves.
- **The answer panel:**
  - `AnswerFeedback.cap` comes from `CapMoment.verdict(...)`: a hop for right, sparkles for a save or a run of five,
    a wiggle for almost, a kind nod for not yet, and pointing for "I don't know".
  - Cap thinks while the AI double-checks.
  - Lecture notes and transcripts show Cap working (think, breathing).
- **Celebrations:**
  - `Engine/Celebration.swift` (`CelebrationPolicy`, pure): the first session, streak milestones (3, 7, 30, 100,
    365), readiness crossing the goal, a mix-up fixed, badges (Phase 6), and a perfect session.
    - Exam eve and quiet hours are calm, and a big celebration plays at most once a day
      (`AppSettings.lastBigCelebrationAt`).
  - `AppModel+Celebration.swift` gathers the facts.
  - `CLConfetti` (`Components/Confetti.swift`) draws a seeded `ConfettiField` in a Canvas and stops when the pieces
    are gone.
  - `CLCountingText` and `CountUp` count the summary's numbers up, with at most 12 ticks.
- **The summary:**
  - It plays in order: Cap arrives, the done sound, the count-ups, the ring, the streak, then the celebration.
  - Its title names the reason ("7 days in a row", "Goal reached", "All right first time", "First session done").
  - `CRAMLESS_CELEBRATION` sets the size.
- **Feel lab:** Sounds, Cap and Celebrations sections; `CRAMLESS_FEELLAB=cap|confetti` plays each through.
- **Films:** `CRAMLESS_SESSION_MINUTES=5` makes the hooked session short enough to reach its summary on film. The
  review page's session film earned its celebration for real: Chem 110 Quiz went from 42% to 83%, past its 80% goal.
- **Tests:** 677 run, 0 fail, 18 skipped (opt-in). 29 are new (`CelebrationTests.swift`): poses and motions, the
  policy and its facts, confetti, count-ups.

**Cap's 15 new poses (2026-10-23).** fal was topped up, so the poses were rendered.
- `../docs/rethink/brand/generate.py --candidates 2 <pose>…` renders two takes of each into `raw/candidates/`; the
  prompt book (`prompts.json`) points every pose at the original reference drawing.
- `scripts/cap_post.sh` frames the art: every drawing ends on one feet line (21 pt above the bottom of the 600 pt
  square), is centred on its weight, and keeps the scale it was drawn at. `ship <pose> <raw.png>` writes the asset set;
  `sheet` makes a contact sheet on Night, light and white, to check edge halos on every surface.
- Claude's picks (think 2, point 1, scan 2, plan 2, mic 1, relax 1, nice 1, almost 1, notYet 1, listen 1, ask 1,
  sleepy 1, proud 1, stargaze 1, tuckIn 1) are shipped and all 19 poses are in `CapPose.drawn`. The owner confirmed
  them ("go with your picks", 2026-10-23). A later change of mind is `scripts/cap_post.sh ship <pose> …` again, from
  `raw/candidates/` (kept).
- Tests: every pose has art and its own VoiceOver words, and every drawing sits on the feet line.

**Phase 4: the memory sky (built 2026-10-23, under review).**
- **Engine** (`Engine/Sky.swift`, pure):
  - `SkyEngine.layout` is stable: Vogel spirals, reserved room that only grows when a topic doubles, constellations
    placed on golden-angle directions, courses packed to the screen's shape, minimum-spanning-tree lines, and exam
    regions as the smallest circle (Welzl) around the stars they cover.
  - `light` gives brightness from recall, hollow rings for unstudied items and flicker from fragility.
  - `relights` says what a session visibly changed: a star that began below about 90% recall, or was new, and ended
    right. Saves are counted as they happened, so they equal the "Saved it." the person saw.
- **Read API** (`App/AppModel+Sky.swift`):
  - `skyScene(aspect:at:)` builds a `SkyScene`. The layout is cached by a hash of what it reads, so reviewing never
    lays out again.
  - `relightRequest` is a practice session for one topic, its dim stars first, sized to how long they take.
  - A finished session hands its relight to `pendingSkyRelight` (`SessionSummary.starsRelit` and `starsSaved` count
    it), which the sky plays once when it is next shown.
- **Views** (`Features/Sky/`):
  - `MemorySkyView` is a Canvas in a TimelineView with a camera (`SkyCamera`: fit, focus, pan, pinch, hit-testing),
    the relight playback, and VoiceOver elements and rotors.
  - `SkyRenderer` batches stars by course colour, brightness step, restlessness and twinkle phase.
  - `SkyScreen` (the route `.sky`) has the header, legend, focus card, the list and the empty state.
  - `SkyFlare` is the save's flare over a session. (`SkyCard`, a first card on Progress, was taken out again in
    Phase 5, which puts the sky on Today instead.)
  - `SkyAccessibility` holds the words.
- **Around it:**
  - The summary has a night strip, "Relit 6 stars · 4 saved", that opens the sky.
  - `NightSky` (the welcome screen and the paywall) draws with the sky's own stars.
  - `SessionRunner.flareSave(of:)` publishes the save's flare, called by the question views where they play the
    verdict's cues (a flashcard when it is rated).
  - `ReviewOutcome.isSave` now needs a Good or Easy answer, so it is exactly the "Saved it." on screen (before, a
    "Hard" counted, so a summary could have said "4 saved" after three "Saved it." moments).
- **Hooks:**
  - `CRAMLESS_ROUTE=sky`.
  - `CRAMLESS_SKY=still|relight[:n]|flare|age:<days>|lapse:<days>|focus:<n>|tour|list|fill:<n>`.
  - `CRAMLESS_SESSION_STATE=flashcard-saved`.
  - `CRAMLESS_SUMMARY_SKY=<ms>`: a film follows a real session into the sky it relit.
  - `CRAMLESS_SKY_PERF=1` logs the CPU time of a frame.
- **Speed**, optimized build, on a Mac:

  | | Plan | Measured |
  |---|---|---|
  | Layout, 10,000 items | under 5 ms | 4.3 ms (0.9 ms for 2,000) |
  | Relighting the sky, 10,000 | | 1 ms |
  | Frame, 2,000 stars | 4 ms | about 2 ms |
  | Frame, 10,000 stars | 8 ms | about 2.5 ms (worst 3.7) |

  That is the CPU side of a frame; the GPU's part comes after. The phone's chip is slower, so Instruments on the phone
  is still on the owner's device list.
- **Tests:** 740 run, 0 fail, 18 skipped (opt-in). 63 are new:
  - the engine (`SkyEngineTests`: layout, stability, overlaps, lines, regions, light, relights)
  - the camera, hit-testing, plan, playback and words (`SkyViewTests`)
  - the images the renderer draws (`SkyImageTests`)
  - a real store and sessions (`SkyAppModelTests`)
  - Cap's poses (`CelebrationTests.swift`)

**Phase 5: a simpler Today, and Progress (built 2026-10-23, under review).**
- **Today** (`Features/Today/`):
  - `TodaySkyHero` is the top of the screen: the memory sky edge to edge behind the status bar, with the date, "Today"
    and the streak on it, Cap at his telescope on the horizon and a "63 stars · 20 dim ›" tag. The whole sky is one
    button that opens it.
  - `TodayHeroContent` (pure) says what each of the eight days offers: the sky's state, Cap's moment, a headline, at
    most one big button and one quiet extra, and a caption. `TodayHeroActions` draws them under the sky. The night,
    rest and empty cards are gone; below the hero the page is as it was (next exam, Cap's note, other exams, ways to
    add material, Squad).
  - `SkyBand` drew the sky as a band behind other things (the same renderer, fitted to the free part). It is gone: the hero
    is now `HeroWorld` (see "Today's hero as a world" below), which keeps its modes: `.live`, `.regionLit(examID)` (exam
    eve) and `.outline` (nothing studied yet: three constellations of unlit rings, `SkyRenderer.drawOutline`).
  - At the accessibility text sizes the sky is a 180 pt band with only the streak and the avatar, the date and title
    sit below it, and Cap steps out. VoiceOver reads the title and streak first, then the sky.
- **Progress:**
  - The Phase 4 card (`SkyCard`) is gone: Today has the sky now.
  - Each exam card has a still of its region (`SkyRegionStill`). "Topics" is "Constellations": a glyph
    (`SkyGlyphView`), bright, dim and not-yet-lit counts, and Practice. Heatmap days are stars
    (`ProgressPresentation.starMark`: a dot that grows, then a sparkle from the third step; `SparkleShape` is in the
    design system), and readiness sparklines end in a star.
  - `SkyScene.region(of:)` and `.glyph(of:)` (`Features/Sky/SkyScene+Derived.swift`, pure) cut these from the sky.
- **Engine:** `SkyLayout.Region` now records the constellations its exam covers (`covers`). Inferring them from where
  things sit would light a topic that merely sits inside the circle; a hand-built test has exactly that case.
- **Renderer:** focus dimming became "what shines" (`SkyRenderer.litConstellations`: a focus, or an exam's region),
  and the frame gained `recede` (how much of the rest shows) and `starScale` (the small pictures' bigger stars).
- **Audio:** `CLSound` builds its engine on first use, not at launch. On a fresh simulator the audio service stalled
  and the app aborted 13 seconds after launch (`Cleanup: RPC timeout. Apparently deadlocked`). I don't know why the
  service stalled; the app no longer touches audio until a sound is first prepared or played, and a test checks that.
- **Copy:** the new counted lines have plural forms (4 keys in `docs/l10n/plurals.json`), and the constant lengths
  ("Tonight · 10 min", "5 more minutes") are plain words. A new plural key acts after a build, the catalog sync and a
  second build.
- **Shared header:** `CLSectionHeader` stacks its action under the title at the accessibility sizes (a long title was
  being broken with hyphens beside it).
- **Hooks:** `CRAMLESS_TODAY_SCROLL=1` (down the page and back, for a film) and `CRAMLESS_TODAY_OPEN=<ms>` (opens the
  sky, as a tap would), besides the existing `CRAMLESS_TODAY=`.
- **Films on the phone:** the first encodes (the recorder's variable 100-120 fps, labelled H.264 level 6.1) would not
  play on the owner's iPhone (Safari showed a crossed-out play icon), though they decode on a Mac. They were
  re-encoded at a constant 60 fps, level 5.1, with an HEVC copy and a smaller H.264 copy in `build/review/phase-5/alt/`;
  `films.html` falls back to those by itself and says which it shows. `scripts/film.sh` now makes level-5.1 films.
  The first encodes are kept in `build/films/phase-5/`. The Phase 2, 3 and 4 films (26 files, all but `session-save`)
  are still the old encoding; Phase 0's `feel-lab` is level 5.1.
- **Not checked:** VoiceOver on a device. The Simulator has no phone smaller than the iPhone 17e for iOS 27, so the
  largest text size is the squeeze test.
- **Tests:** 771 run, 0 fail, 18 skipped (opt-in). 31 are new:
  - what each day says and offers, in the singular and the plural (`TodayHeroTests.swift`)
  - the sky in Today's snapshot
  - regions and glyphs cut from the sky, the heatmap's stars, the sparkle and what the renderer lights
    (`SkyDerivedTests.swift`)
  - the pictures it draws and hides, and the sound engine staying silent until it is used

**Cap animation test (2026-10-24; the owner asked for a small test, up to $10).**
- Question: can video models animate Cap's own pictures, consistently, on transparency, in seamless loops?
- Method (`scripts/cap_anim/`): `cap_anim.py` puts a pose on flat magenta (his art has no magenta at all), runs a fal
  image-to-video model with the still as both the start and the end frame, then keys the magenta out and writes frames,
  numbers, an animated WebP and a 12-frame strip. `build_page.py` makes `build/review/cap-animation-test/`.
- Tried: Kling 4.0, Seedance 2.5, FLUX 3 Max (keyframes), MiniMax H3 Max, Wan 3.0 Prime, Gemini Omni Flash 1.1 and
  Pixelcut Looping Video, on three poses (wave, the telescope idle, celebrate): 15 clips, about $7 by fal's list
  prices (`build/cap-anim/ledger.jsonl` caps spend at an estimated $9; the key can't read billing, so the true charge
  is unknown).
- Found:
  - Kling 4.0 is the most faithful and moves best (about $0.79 a 5 s clip); MiniMax H3 Max is nearly as good for quiet
    idles at about $0.16. Wan, Pixelcut, Seedance, FLUX and Gemini each drifted (mint headphones, extra confetti, 6%
    larger, colour shifts, teeth and motion lines) or barely moved.
  - Every model returned Cap to the starting pose (last frame within 0.1 to 0.6% of the first) and the first frame
    lands on the still within a pixel (Seedance aside), so a clip can replace the still without a pop.
  - The magenta cut-out reproduces a still's real alpha to 0.3% on average. Two keying traps: a pixel far from the
    background colour must be left untouched, or the navy hat drifts teal and the cream headphones mint; and the
    background colour has to be read per frame, because some models let it drift.
  - The models add expressions the stills lack (open eyes on a blink, a laughing mouth, teeth); steer with the prompt.
  - 24 fps to 60 fps with `minterpolate` before keying takes about 20 s a clip and looks silky.
  - This Mac makes HEVC with alpha (`hevc_videotoolbox -alpha_quality`), and Apple's stack reports the alpha channel.
- Trap: with Python 3.14 and NumPy 2.2, an expression like `pm - prev` on a local array can overwrite `pm` in place.
  The first loop numbers were wrong because of it; `measure()` builds every array into its own buffer.
- Not tried: playing a clip in the app, poses with props, the production prompts.

**Cap's character sheet, Kling 4.0 with Cap as a character, and other directions (2026-10-24; the owner asked for all three).**
- The sheet (`build/cap-anim2/cap-character-sheet.png`, made by `scripts/cap_anim/sheet_compose.py`): turnaround (front,
  three-quarter, side, back), ten faces, close-ups of his teeth and tongue, eyes (open and closed), paws and feet and the
  mortarboard and headphones, a palette sampled from the art, and always/never rules. The panels are GPT Image 2.5 on
  fal, reference-guided from the existing poses (`scripts/cap_anim/round2.py img ...`, picks in `picks.json`). The
  rules are my proposal and wait for the owner's OK.
- Kling 4.0 reference-to-video (`kling/v4/reference-to-video`) takes a character as an "element" (a front image plus
  up to three more) and up to nine extra reference images; the start image is optional and there is no end frame.
  `round2.py kling <pose> <take>` defines Cap from the sheet and starts on the still.
- Result: wave, the telescope idle, celebrate and sleep stayed on-model, and the details now follow the sheet (his laugh
  has the two small teeth and the pink tongue; last round's guess had no teeth). The cheer did not start on its still:
  Kling followed the sheet's front view (14% smaller, 11 px off). Reference mode may override the start picture when a
  pose resembles a sheet view, and it ends wherever the motion ends (celebrate lands in a new pose), so pinned loops
  still use image-to-video with the picture as the first and last frame (`round2.py i2v`).
- Kling re-colours a flat background in reference mode (raspberry, dusty rose, pink: it differs per clip) and adds a soft
  ground shadow, so the cut-out no longer assumes magenta. `key_frame` treats as background any colour on the line from
  black to the background colour, leaves solid Cap pixels untouched, and takes edge colours from the nearest solid Cap.
  Video compression bleeds the background into edge pixels about 4 px wide, so the edge band is 4 px.
- Pink leftovers (found by the owner, 2026-10-24: "in some frames I see the pink background near the mascot", the cheer
  first). Where an arm or the tassel moves fast the video smears the background into streaks that a geometric keyer reads
  as Cap: up to 4,500 stray pixels in one frame. Cap's palette has no hue between 262 and 350 degrees, so when the
  background is pink-purple any saturated pixel of that hue is background (`PINK_HUES`, `pinkish` in `cap_anim.py`).
  `pink_audit.py` counts the leftovers per frame and writes the worst frames with them painted green; after the fix the
  worst frame of any Kling clip has under 50. `keyer_check.py` tests the keyer on composites with chroma bleed, noise and
  motion blur: the earlier clean-composite test had passed while real clips still showed the streaks. The animated WebP
  adds no fringe of its own (checked by decoding it and counting pale-pink pixels on white and on night blue). The fix
  also removed pink and purple confetti that Kling had not drawn (smeared background); the confetti is the still's.
- Traps: NumPy 2.2 on Python 3.14 can do `~a`, `a | b` and `a - b` in place on a big array that has one name (alternating
  masks, a cut-out that tints navy teal); use ufunc calls (`np.logical_not`, `np.subtract`) or explicit `out=`. Test a
  keyer against composites with chroma blur and noise, not only clean ones: the clean test passed and real clips still
  showed a pink rim.
- Other directions (`build/cap-anim2/directions/`): ten styles of Cap and eight mascots, two of them animated (a plush
  3D Cap waving; Glim the firefly glowing, left on night blue because a glow wants additive light, not a cut-out).
- Spend: about $9 at fal's list prices for 43 images and 8 Kling clips (my cap for the round was $12, estimated with a 1.2
  margin in `build/cap-anim2/ledger.jsonl`). With the first round, about $16 in all.
- Page: `build/review/cap-character/`. Not tried: playing a clip in the app, the full set of poses.
- Owner decision 2026-10-24: "I like our mascot, let's keep it." The flat illustrated Cap stays the mascot; the other
  styles and mascots (including the plush 3D Cap) are not adopted. Glim the firefly is parked as an optional companion for
  the memory sky, not started.

**Cap alive: the clips in the app (2026-10-24, built, tested and filmed; the owner said "implement it in the app: everything, all animations, all transitions"; under review).**
- **The clips** (`Cramless/Resources/CapClips/`, 19 files and `cap-clips.json`, 12.9 MB): one transparent HEVC clip for every
  pose, made from the character sheet. `scripts/cap_anim/produce.py` reads the prompt book (`clips.json`), makes a clip with
  Kling 4.0, keys it off its flat background, judges it (starts on the still, ends back near it, no stray background, colours
  match, moves), and encodes it. $22.14 of fal credit at list price (the owner approved about $25; $2.86 is left).
  - Two modes. `ref` (reference-to-video, Cap defined by the sheet) has the best identity but ignored the starting picture on
    9 of 19 takes: it zoomed in, faced front, or landed elsewhere. `pin` (image-to-video, the still as first and last frame)
    always starts on the still, and an explicit description of his eyes and teeth in the prompt keeps them on-model. 11 clips
    ship from `pin`, 8 from `ref`.
  - Traps: a clip that opens his eyes for a pose with closed eyes gets googly white-ringed eyes unless the prompt says they
    stay closed; a hop lifts the mortarboard off his head whatever the prompt says, so the cheer uses only his arm and head.
  - Finishing: each clip ends on the frame closest to its still, eases in from the still over 3 frames and onto it over 6, and
    is colour-graded onto the still (the model returns him about 2% darker). HEVC with alpha at quality 65 and alpha quality
    0.75 (below 55 the fur strokes soften).
- **The engine** (`DesignSystem/Components/`): `CapClips.swift` is pure (`CapClip`, `CapClipCatalog`, `CapPlaybackPolicy`,
  `CapScript`); `CapClipPlayer.swift` plays them (an `AVPlayerLayer` on a clear view, `CapStage` per `CapView`, `CapPlayback`
  for the setting, Low Power Mode and the cap of three at once). `CapView` draws the still, puts the clip over it and swaps
  with no visible change; every call site gets clips without changing. Settings ▸ Accessibility ▸ Feel ▸ "Cap moves".
- **Changing pose** (what "all transitions" came to): the drawings are the hand-off, because every clip starts and ends on
  its drawing, so a clip hands to the still and back with nothing visible and clips chain. A change of pose dissolves: the
  old clip's last frame is held and fades out over `CLMotion.fade` (0.28 s) as the new drawing fades in and grows a little
  from the feet, and the new clip starts 290 ms later. Not made: clips that morph from one pose into another (a reaction
  must be instant, and each pair would be its own clip, about $0.47 for 3 s); the code's entrance (`arrive`) stays.
  - **Trap found by filming it:** the first version blinked Cap out for 4 to 6 frames (about 80 ms) at every change out of a
    looping idle clip. Letting an `AVPlayerLooper` go takes its items off the player at once, which empties the layer, so
    the old frame was gone before the dissolve began. The player now keeps the looper (looping off, player paused on the
    frame) until the layer is emptied. `scripts/cap_anim/film_gaps.py <film> --box X Y W H` counts the frames where Cap's
    fur isn't on screen: the old build showed 11 dropouts in the cast film (one at each change out of a looping clip), the
    fixed one none.
  - A clip is shown once the layer is ready and two frames have played: `isReadyForDisplay` alone read true from the clip
    before (first frames "in 9 ms"), which would hide the drawing over an empty layer.
- **Hooks:** `CRAMLESS_CAP_CLIPS=1` turns clips on in the harness (off by default so screenshots repeat);
  `CRAMLESS_FEELLAB=cast` plays every pose's clip in turn.
- **Tests** (`CramlessTests/CapClipTests.swift`): `CapClipFileTests` (every pose has a clip; each file is in the app, has an
  alpha channel, is 720 px and the right length; each starts and ends on its drawing, read with Apple's decoder in the
  simulator, against 0.035 because the simulator's HEVC decode rings at the edges) and `CapScriptTests` (the script rules,
  Low Power Mode, Reduce Motion, every moment has a clip, the setting's default and decoding of old settings). The full
  suite: 784 tests, 0 failures, 18 skipped (the opt-in ones). A first full run ended "test runner hung before establishing
  connection"; a restarted simulator and `XC_NO_BUILD=1` ran it clean.
- **Films** (https://macbook-pro.tail9699dc.ts.net:8824/cap-alive/, `build/review/cap-alive/`): `scripts/cap_anim/films.sh`
  records nine (every pose in the Feel lab, Today's four states, a session, the summary, the welcome, the cast with Reduce
  Motion on), `film_alts.sh` makes the HEVC and small fallbacks with the Mac's hardware encoders, and `build_alive_page.py`
  builds the page. All nine pass `film_gaps.py` (no frame where Cap is missing), and the Reduce Motion one shows no movement.
  A clip's first frame is on screen about 100 ms after it is asked for (the Feel lab lists it per pose).
- **On the phone** (2026-10-25, at the owner's request): `scripts/device_isolated.sh 00008150-001244282287801C` built the
  Debug app for frankWhite (iPhone 17 Pro), signed it with the wildcard profile (no App Group, so widgets get no data, and no
  Sign in with Apple) and installed it over the old copy, so the phone keeps its data. It was not launched. The installed
  bundle was checked: valid signature, 19 clips and `cap-clips.json` inside, built after the last source edit. To see every
  pose on the phone: Settings ▸ More ▸ Debug ▸ Feel lab ▸ Cast; the list shows each clip's first-frame time as measured there.
  Not yet seen on hardware: how the clips look and time on the phone, and Low Power Mode and Reduce Motion behaviour.
- **This Mac:** simulators come from the shared pool (`simq sim --udid`, `simq sim release`); one made with `simctl create`
  is shut down within seconds as idle. Builds and tests wait for a slot: `scripts/xcq.sh` retries.

**Tap Cap: two fixes, and he answers a tap (2026-10-25; the owner installed Cap alive on frankWhite and sent a screen recording).**
The owner didn't like (1) the page flashing and refreshing behind the + button and (2) a rectangle behind Cap in Today's sky, and
asked for (3) a reaction of its own in every pose when he is tapped, seamless, with squash and stretch on top, and (4) Cap
talking: something short and fun on each tap, from lots of lines, a bit different every time.
- **The + flash.** Cause (read off the recording: frames 69 to 72 of 143 were empty, with the + drawn as selected): the + is a
  `Tab`, so a tap made UIKit select it, `TabView` swapped the page for the empty + page, and only then did SwiftUI put the
  selection back (four frames on the phone, 143 ms on the simulator; every `onAppear` on the page ran again). There is no action
  tab in the SDK (only `.search` and `.prominent` roles). `AddTabAction` (`App/AddTabAction.swift`, one in each `TabRoot`)
  puts a forwarding proxy in front of SwiftUI's own tab delegate (`TabViewCoordinator_Phone`, read off the live hierarchy of
  a `UIKitTabBarController`) and answers `shouldSelectTab` with no for the last tab, running the action. It forwards every
  other call, steps back in front if SwiftUI sets its delegate again (KVO), and is tested (`AddTabActionTests`). Checked with a
  real tap through the `mobile` tools and a screen recording: a white flash before, none after; tab switching, and + from the
  Library tab, still work. The simulator and the phone both run iOS 27.0.
- **The rectangle.** Cause: a clip is stored premultiplied (`AlphaChannelMode`), the video layer draws the colour planes as they
  are, and the encode had been given straight-alpha frames, so every transparent pixel carried the keyer's leftover colour (a few
  levels of grey, up to full white beside the outline). On the dark sky that added +5 to +8 levels in the clip's rectangle and a
  halo; macOS multiplies it away when it reads BGRA, so no earlier check saw it. `produce.py` now premultiplies before it
  encodes (`write_premultiplied`, `encode`), and `planes_ok` refuses a clip whose planes aren't black under its transparency;
  `reencode` and `audit` redo and check the finished ones; `hevc_planes.swift` reads the raw planes. All 19 base clips were
  re-encoded from their saved frames (no fal spend): 16 of 19 had Y 17 to 26 under the border (black is 16), now all 16, and the
  set shrank from 12.9 to 8.9 MB. Measured on the hero: the step at the rectangle's old edge went from +5/+8/+6 to the
  sky's own gradient (0 to 3). `CapClipFileTests.testEveryClipIsBlackUnderItsTransparentPixels` reads the planes. Tried and
  useless: asking `AVPlayerLayer.pixelBufferAttributes` for BGRA.
- **Cap answers a tap** (rules in `docs/design.md` ▸ Cap):
  - 19 new clips, one per pose (`<pose>Poke`, role `poke`, 3 s, `gen pin`, 7.3 MB), made from prompts in `clips.json`. One take
    of each cost $8.95; four came back with white-ringed eyes (celebrate, nice, proud, stargaze) and were re-taken with the
    eyes-shut wording, $1.88 more. $10.83 of the $20 the owner approved on 2026-10-25 (ledger $32.97 of $42.14).
  - `CapPoke` (pure, seedable): five styles of damped-spring squash, stretch, rock and shimmy rolled fresh on every tap, by
    mood (sleepers are nudged, cheerers bounce), eased to exactly rest, with a limiter for overlapping springs, and a haptic that
    follows how hard he was pressed (`CLHaptics.poke`). A run of quick taps gets stronger and ends in a shimmy.
  - `CapLines`: 418 lines (18 for each pose, 40 for any pose, 6 for each part of the day, 12 for a run of taps);
    `CapLineBag` deals each pool without repeating until it is used up and carries on across launches; `CapBubble` slides
    sideways to stay on screen with its tail still on his head. `CapSpeechTests` checks length, emoji, guilt-trip words,
    duplicates and the dealing.
  - "Cap talks" (Settings ▸ Accessibility ▸ Feel) next to "Cap moves"; both off, or Reduce Motion with talks off: a tap does nothing.
  - Taps in the Today hero go to Cap alone (the rest of the sky still opens it); `interactive: false` opts a use out.
  - Found filming it: the bubble was handed only Cap's width (three-line wrap) and an alignment guide put it on his head; it
    is now given room and lifted by its measured height.
  - Found auditing the films with `film_gaps.py` (it counts frames where Cap's fur isn't on screen; a blink of 17 to 33 ms
    is invisible in a screenshot and plain in a film): races between the video layer (Core Animation) and the drawing
    under it (SwiftUI), each leaving Cap out for a frame or two where a clip hands over.
    (1) **The end of a clip** (the cause of most): an `AVQueuePlayer` advances at the end of an item and, with nothing after
    it, empties its layer in that very instant, a hop before `AVPlayerItemDidPlayToEndTime` reaches us and a frame before
    SwiftUI brings the drawing back. A one-shot now sets `actionAtItemEnd = .pause`, so its last frame (his drawing) stays up
    until we take it down. (2) A clip that followed another straight away found the layer still "ready" and the player's
    clock at the end of the last clip, and hid the drawing before it had a frame: every clip now gets a fresh player.
    (3) The drawing was hidden in the same frame the video appeared, and sometimes a frame early: it is hidden 60 ms after
    (`CapStage.hidesStill`; both are one picture for that long, since a clip starts on its drawing). (4) Defence for the
    rest: the last frame is held on the layer 80 ms (`layerHeldUntil`) and a following clip waits for that.
    Verified with a stress film (`CRAMLESS_CAP_POKE` 18 times in 70 s on Today's hero: 0 blanks) and the tap films.
    A reaction also plays through to its end (taps during it only squash him and have him talk), because restarting it would
    cut it off mid-gesture.
- **Tests:** 821 (37 more), 0 failures. A first full run ended "test runner hung before establishing connection" again; a
  restarted simulator and `XC_NO_BUILD=1` ran it clean.
- **Hooks:** `CRAMLESS_CAP_POKE=3000,6500` taps every Cap on screen at those times, `CRAMLESS_CAP_SEED=n` makes the rolls and
  the words repeat, `CRAMLESS_FEELLAB=cast CRAMLESS_CAST_POKE=1` taps each pose of the cast; `scripts/cap_anim/films_touch.sh`
  films them and `build_touch_page.py` builds https://macbook-pro.tail9699dc.ts.net:8824/cap-touch/.

**Today's hero as a world (2026-10-25; the owner: "improve the stars or visualization in that hero ... it needs to take
advantage of the space and the hero should be something like a world in the hero, interactive, and not small and next to the
mascot").**
- **What it was:** a 292 pt band (40% of the screen), the sky laid out for a fixed wide strip (aspect 0.4, so the demo world's
  63 stars were a ~70 pt cluster), Cap at 134 pt beside it, one tap target (open the full sky).
- **What it is** (`Features/Today/HeroWorld*.swift`, `HeroTilt.swift`, `HeroFocusCard.swift`; rules in `docs/design.md` ▸ Today):
  - `HeroWorldGeometry` (pure) sizes the hero from the screen: 43% of its height under the status bar, held between 300 and 440
    pt (about half the screen on a 17 Pro, so the day's button stays on the first screen), a low 180 pt band at accessibility
    text sizes. The sky is laid out for the free sky's exact shape (`TodaySnapshot.make(app:skyAspect:)`; `TodayView` passes it
    from the real screen, and a different screen or text size lays it out again).
  - `HeroWorldRenderer` draws, far to near: a dusk, a Milky Way band, 240 background stars at three depths (`HeroDust`, seeded
    so they are the same every launch; a few glint), a cloud per course (`HeroCloud`), the sky itself through the unchanged
    `SkyRenderer`, a shooting star every ~19 s (`HeroShootingStar`, a function of time), far and middle hills with ridge light and
    a mist, a lake with reflections of the brightest stars, and the ground. `SkyRenderer` got `spikes` (a four-point glint
    on the brightest stars), `lineWidth` and `focusLift` (a focused constellation's dim stars are lifted toward full
    brightness; zoomed in, a mostly dim constellation was nearly invisible, which found this) as frame settings, off by default so
    the full sky is unchanged. `SkyCamera.fit(largest:)` lets a small sky start closer than the full screen's.
  - Interactive: `SkyHit.nearestStar` (any star within 40 pt, not a circle round the shape) focuses a constellation; the camera
    glides (`SkyCamera.focus`, keeping the shape above the card) and `HeroFocusCard` (name, `SkyCopy.detail`,
    Practice with its minutes, close) slides up; Cap steps aside. A tap on empty sky ripples or lets go; it no longer opens the
    full sky (a near miss on a small target used to throw the person out of Today: found with a real tap). The pill and
    VoiceOver's one element open it.
  - Depth: `HeroTilt` (CoreMotion, 30 Hz, started only while the hero is on screen and active, off under Reduce Motion and Low
    Power) feeds `HeroTiltFilter` the gravity vector's sideways and forward parts and not roll and pitch (gimbal lock when a
    phone is held upright); where it was held a few seconds ago is the middle. Layers move by 2.5 to 10 pt per full tilt. With no
    sensor (the Simulator) they sway on their own (`HeroTilt.idleSway`). The ground and Cap stay on the screen's plane.
  - `SkyBand` is deleted (nothing used it).
- **Not verified on hardware:** the tilt (the filter and the maths are tested; the sensor path and how strong it feels are
  not). Everything else was filmed and screenshot in the Simulator, and the taps were real taps through the `mobile` tools.
- **Cost:** `HeroPerf` (`CRAMLESS_SKY_PERF=1`) on an optimised build: about 1.0 ms a frame for 63 stars (the sky is 0.6 of
  it), at 30 frames a second, paused when off screen. Not measured with thousands of stars in the hero (the sky renderer
  itself is budgeted at 4 ms for 2,000).
- **Tests:** `HeroWorldTests.swift` (geometry, dust, clouds, card placement, the tilt filter including a steady hand,
  shooting stars, `nearestStar`). Hooks: `CRAMLESS_HERO=3000:c2,9500:close,12000:x300y160`; `scripts/hero_shot.sh`;
  `scripts/cap_anim/films_hero.sh`; page https://macbook-pro.tail9699dc.ts.net:8824/hero-world/.

**Pull down on Today (2026-10-25; the owner, after testing the world on frankWhite: "I don't like how the hero is scrollable
when I drag the screen down. It should remain anchored ... maybe we can make it interactive, as in it refreshes with an
animation").**
- **What was wrong:** the hero is the first thing in the page's scroll view, so a pull past the top dragged it down with the
  page and a white band opened behind the status bar (seen on a real drag in the Simulator, `build/review/hero-pull/`).
- **The pin** (`TodayView`): `.visualEffect { content.offset(y: -max(0, proxy.frame(in: .scrollView).minY)) }` on the hero. It
  runs in the render pass with the real scroll offset, so it can't lag a frame (a `@State` copy of the offset, set from
  `onScrollGeometryChange`, would have jittered). Pulled down the page moves under the hero; scrolled up it goes with the page.
- **Pull to refresh** (`Features/Today/HeroRefresh.swift`): `HeroPull` (pure) turns the scroll view's readings (`distance` past the
  top from `onScrollGeometryChange`, finger down from `onScrollPhaseChange == .interacting`) into armed / disarmed / started;
  `HeroRefreshWave` and `HeroPullLook` are the curves and the amounts; `HeroPullModel` (`@Observable`) runs the work. The line is
  72 pt of overscroll (about 140 pt of drag), with hysteresis (a wobble over it doesn't flicker), a tick at the line, and the
  far ridge lights up as the "ready" cue. A flick counts too: finger up at 24 pt or more and the momentum carries the page past
  the line (found with the Simulator's swipe, which lifts at ~30 pt and coasts to ~200; a page flung up that bounces off its top
  has no finger pulling it down and never counts).
- **What the world does** (`HeroWorldRenderer`): while pulled, layers lean down (nearer further, the ground never), the sky is lit a
  second time, the dusk brightens. On letting go: an arc of light (a radial gradient dome) climbs from behind the hills over 0.95 s,
  the sky drawn once more additively through a soft band so the stars it passes flash, background stars flash and grow, a star
  falls (`HeroShootingStar.burst`). Reduce Motion: no leaning, an even brightening only. The timeline switches to the screen's rate
  while it runs.
- **What refreshing does** (`AppModel.refreshToday`): the daily rollover, then with sync on a pull (waits five seconds at most;
  the pull carries on), then Today recomputes its snapshot as of now. An unreachable account gives a toast, not a lie.
  `HeroWorld` lets go of a focused constellation, Cap reacts (`CapView(refreshed:)`, 14 new "refreshed" lines in their own pool)
  and the pill says "Sky refreshed" for 2 s. VoiceOver gets a "Refresh" action and an announcement.
- **Things learned:** the `mobile` swipe tool ends a drag at the bottom edge as iOS's app switcher (both of my first two long
  swipes did): start inside the hero and end above y = 600. A freshly installed build sometimes shows the Welcome screen on its
  first harness launch; launch it again. `CRAMLESS_PULL_LOG=1` shows what the scroll view tells the model.
- **Tests:** `HeroRefreshTests.swift` (the pull rules including flicks and bounces, the curves, the model's work, minimum time,
  one run at a time), a rollover test for `refreshToday`, Cap's pool. Hooks: `CRAMLESS_HERO_PULL`, `CRAMLESS_PULL_LOG`;
  `scripts/cap_anim/films_hero.sh` films the pull (hero-pull, -calm, -empty, -focus, -eve); the page is
  https://macbook-pro.tail9699dc.ts.net:8824/hero-pull/.
- **Not verified on hardware:** the feel of the line (72 pt) under a real finger, and the tick. The pin and the flick were seen
  on real swipes in the Simulator.

**Renamed to Capling (2026-10-25; the owner: "I checked the domain and it's taken ... should we consider renaming", then "you decide,
you recommend").**
- **Why:** two live student products already used Cramless: cramless.io (board-exam prep for medical students, since January 2026;
  it also holds cramless.app, and its email sits on cramless.com, registered in 2022) and cramless.ai (Google Classroom homework on
  WhatsApp, registered 13 October 2026). The "Cram" stem is crowded in Education (Flashcards with Cram, four Cramly apps, Cram AI,
  Cram Easy ...), so the name was weak anyway. Nothing was registered with Apple yet, so renaming cost almost nothing.
- **Why Capling:** the mascot's name made into the brand, the way Duolingo's owl gave Duolingo its name: warm, short, easy in every
  launch language, with no meaning to avoid. Checked on 2026-10-25 (public sources only; not a trademark search and not legal
  advice): no app has it in its name in 21 App Store countries; no trademark for CAPLING (the only hit is CAPLINGER'S, a seafood
  retailer; the nearest word is CAPLIN, with a law firm's CAPLIN & DRYSDALE for online publications, classes 9 and 41, which a
  trademark attorney should look at); capling.app, .io, .ai, .co, .net, .org and getcapling.com, trycapling.com, caplingapp.com were
  all unregistered; capling.com has been registered since 1997 with an "Under Construction" page. Fallback if the name is blocked:
  Skykeep (clear in 18 countries; SKYKEEP is registered for water flossers in class 21).
- **What changed** (`scripts/rename_brand.py Cramless Capling --apply`, 114 files): the display name and usage descriptions; every
  piece of copy and the String Catalog keys; StoreKit names and product ids (`com.loopware.Capling.pro.monthly` ...); bundle ids; the
  App Group; the `capling://` scheme; Squad links (`capling.app/squad/`); notification, defaults and Keychain key prefixes; the
  backend's default bundle id and invite URL; auth config (`supabase/config.toml`); test fixtures; scripts' bundle id. `CFBundleName`
  is "Capling". **What stayed:** the module, targets, folders, file names and type names (`Cramless*`), `PRODUCT_NAME`, the
  `CRAMLESS_*` DEBUG switches, the backend's `cramless_*` database functions and the local stack's project id: nobody sees them, and
  renaming them would break every script, note and path for no benefit.
- **Verified:** 895 app tests and 95 backend tests pass; the built app's plists and string tables hold no "Cramless" (bar
  `CramlessSupabaseHost`, the Info.plist keys the code reads); the Home Screen says "Capling"; the welcome wordmark, Settings, the
  paywall and the consent sheet say Capling.
- **Consequences:** it installs as a new app (new bundle id), beside any old Cramless build, with no data carried over (nothing real
  yet). Old simulators keep the old app until `simctl uninstall com.loopware.Cramless`.
- **The owner still has to** (nothing was bought or filed): register capling.app (and perhaps getcapling.com), have a trademark search
  done and file (classes 9, 41 and 42 in the US; a few hundred dollars a class), create the App Store Connect record named Capling
  (check the name is free when creating it), and claim the social handles. Squad links point at capling.app until then.

**Cap's missing frames (2026-10-25; the owner, after installing Capling on frankWhite: "In the welcome screen, the mascot wave anim is
not smooth, its like low fps. Why?", then "Fix it.").**
- **Why:** the wave drew a new picture only every 3rd frame, so it moved about 8 times a second inside its 24 fps file (the video model
  "animated it on threes"; its raw video does the same). On a 120 Hz iPhone each drawing stayed up for about an eighth of a second.
  Counting new pictures on every shipped clip found 7 more drawn on twos (about 12 a second) for all or part of their length: almost,
  sleepy, mic, and the taps of sleepy, sleep, scan and tuckIn. The other 30 move on every frame. Nothing caught it: the checks
  looked at blinks, colour fringes and loop seams, never at how many different pictures a clip has.
- **The fix:** `scripts/cap_anim/inbetween.swift` keeps the frames that are really new and draws the others from the two around
  them with Apple's frame-rate conversion (`VTFrameRateConversion`, optical flow; free, on the Mac), on the video model's own frames
  before the cut-out, and the usual keyer then cuts every frame out alike. `produce.py smooth <take>` makes the new take `<take>s`
  (same frames, same length), `finalize` and `install` as for any take. `produce.py check` now counts pictures a second and warns when
  a clip is drawn on twos or threes (`pictures_per_second`, `holds` in qa.json).
- **Two ways that failed, for next time:** ffmpeg's `minterpolate` smears the paw into a ghost; and cutting Cap out first and moving
  his colour and his alpha in two passes left the fast paw pink-speckled and see-through (the two passes disagree where the motion
  is big). One pass on the full-colour frame, then the keyer, is clean.
- **A flaw found on the way:** the old wave had two pink smears on its fast paw (frames 93 and 98, held three frames each: 425 and
  250 red-pink pixels against about 50 on a clean frame). `smooth` now leaves out a key frame that spikes against its neighbours
  (`pink_residue`) and draws that stretch from the clean ones; a pose that is pink all through (a tongue, a blush) is not a smear.
- **All 38 clips scanned for the same flaw** (`scripts/cap_anim/residue_audit.py`: a frame whose red-pink count is over 150 and over
  2.5 times the middle of the six around it). One was real: **scanPoke, frames 46 to 48** (and a trace on 49): the raised paw's fingers
  mauve and a salmon lump on the arm under it, the video model's motion blur with the magenta background (902 pink pixels at 720 px
  against about 50 on a clean frame). The shipped clip had it before any of this work. Drawing frame 46 again from its neighbours
  (`repair`) did not help (the blur is in the neighbours' moving edge too), a cross-dissolve of 45 and 47 ghosts the paw, and a wider
  cut-out band moved nothing. **`produce.py scrub <take> 46-49 100,290,260,500`** keeps every shape and recolours only the smear, from
  the fur and paw solid beside it, as the take `<take>c` (scanPoke ships from `scanPoke-pin-1sc`: 229, 54, 58 and 30 pink pixels
  down to 11 to 14 at 360 px). The audit's two other readings are no smear: celebrate (the confetti is red-pink, frames 96 and 97)
  and tuckIn (93 and 94: the ease onto the still mixes two poses; the take itself is clean).
- **Result:** new pictures a second, counted on the keyed takes: wave 7.4 to 19.8, almost 13 to 20.2, sleepy 9.2 to 20.2, mic 11.8 to
  22.2, sleepyPoke 11 to 18.7, sleepPoke 13 to 20.3, scanPoke 12.3 to 20, tuckInPoke 12.7 to 21.3 (stretches where Cap holds still
  count as no new picture, so none reads 24). In the app, on the Simulator recordings of the welcome (the paw's region, 60 fps): about
  7.5 different pictures a second before, 20.6 now. The eight clips are 0.5 MB bigger in all (2.6 to 3.1 MB; the 38 clips 16.2 to
  16.7 MB); frame counts, fps and lengths are unchanged. The old files are kept in `build/cap-clips/final-before-smooth/` and
  `app-resources-before-smooth/`.
- **Verified:** 51 Cap tests (`CapClipFileTests`, `CapScriptTests`, `CapPokeTests`, `CapSpeechTests`, `CapPoseTests`) pass; every clip
  still starts and ends on its still, with no colour under the transparency (`produce.py finalize` checks both); the welcome film has
  no frame where Cap thins out (`film_gaps.py`); ten in-between frames of each clip looked at on the night blue, clean. Before and
  after films: https://macbook-pro.tail9699dc.ts.net:8824/cap-smooth/ (`build_smooth_page.py`).
- **Not on frankWhite yet.** Not verified on hardware: how it feels at 120 Hz in the hand.
- **Lesson (tooling):** with Python 3.14 and NumPy 2.2 an expression like `a - b` can overwrite `a` in place; my first count of the
  clip's steps measured nonsense for that reason. `picture_steps` uses Pillow only.

**A better welcome, and flashcards in the intro (2026-10-25; the owner: "How can we have a better welcome screen? not just the mascot,
maybe other elements", then "I want to make sure our onboarding shows our most important features, and the ones that users look
for. Especially I notice missing the flashcards", then "GO, all improvements").**
- **The gap:** the five intro pages (snap a page, own words, readiness, plan, Ask Cap) never mentioned flashcards, which the app has
  (flip, rate Again/Hard/Good/Easy, scheduled by FSRS) and which most people search a study app for; the setup quiz even offered
  "Flashcard apps: Import them in one tap" with nothing in the intro to say it. Anki (`.apkg`, text) and Quizlet (pasted export)
  import exist.
- **The intro is six pages** (`IntroPage.all`, `OnboardingMachine.introPages = 6`): snap a page (its demo now ends on three cards of
  three kinds, each with its icon), **flashcards that come back in time** (new: `Scenes/FlashcardScene.swift`: the session's own flip,
  tiles and tones; Good is tapped and a week lights the day it returns, "Back in 5 days"; the words say Anki and Quizlet decks come
  too), own words, readiness, plan, Ask Cap. The harness numbering moved with it (welcome 0, intro 1 to 6, questions 7 to 10, first set
  11 ... paywall 15).
- **The welcome is the memory sky in miniature** (`WelcomeWorld`, `WelcomeStage`; pure parts and Cap's lines in `WelcomeSky`, the numbers
  of its motion in `WelcomeLook`): a quiet night scene with one constellation, Cap's mortarboard in seven dim stars, and Cap on the shore.
  A touch on a star lights it: the next note up the scale (`CLCue.right(combo:)`), its haptic, a ring and a four-point glint that fade, a
  ripple, and the lake mirrors it as a short dash. Lines between lit stars draw themselves, solid, from the star lit last toward the one
  before. The third star lights the rest in a sweep, a soft gold glow and one shooting star cross the sky, `CLCue.flourish` plays, Cap
  changes to his cheer and says "That's the whole idea. Shall we?", the star in "capling" lights and the button takes a small breath.
  - **Nothing waits for the gesture.** The buttons are there from the start. A faint ring pulses on the star Cap would light next
    (`stage.hint`). If nobody touches he says hello (1.9 s), "Go on, tap one." (5 s later), then lights a star himself, and another
    every 4.2 s: the cap is lit about 17 s in.
  - **Cap's bubble is scripted** (`CapView(says: CapScriptedLine)`, announced to VoiceOver like his tap lines). His lines are
    `WelcomeCopy`: "Hi, I'm Cap. Light a star with me." / "There. That's one memory." / "One more." / "That's the whole idea. Shall we?"
    (a test holds them to the voice: short, sentence case, whole sentences, no "!", no emoji).
  - **Reduce Motion:** no ripples or ignition, the clips are off, the arc is the calm brightening; the stars simply light. **VoiceOver:**
    the sky is one button ("A night sky with a constellation shaped like Cap's graduation cap", "n of 3 stars lit", action "Light a
    star"). **Accessibility text sizes:** a 230 pt band of sky above the words, which scroll.
  - **"capling" has a star for the i's dot** (`CaplingWordmark`, a dotless i with a four-point star over it): faint on the welcome
    until the cap is lit, gold everywhere else (the intro's top bar, About).
  - **It goes quiet when it is covered** (`WelcomeView.isFront`): the intro pushed over it, the "I already have an account" sheet, the
    app in the background. Cap says and lights nothing then, and no note plays over another screen (checked with real taps: Get
    started at 3 s, nothing played in the next 18). A harness route to an intro page covers the app's own welcome without stopping
    it (the harness leaves onboarding on), so `films_welcome.sh` gives those films `CRAMLESS_WELCOME=lit3`.
  - **Short phones** (under 740 pt tall): a smaller Cap and more of the height for the sky (checked on an iPhone SE).
  - **DEBUG hooks:** `CRAMLESS_WELCOME=lit1|lit2|lit3` (the sky after that many stars, at once) or `3200:s1,5200:s4,7200:s0` (touches
    on stars 0 to 6 at those milliseconds, through the finger's own code). It is read every time and not consumed: the harness builds
    the welcome more than once while it sets the app up, and the first copy used the hook up.
- **Verified:** 914 app tests passed (19 new, and the onboarding, welcome and Cap ones again after the last changes: `WelcomeSkyTests` for the constellation, the touch rules, the finger's hit test, the stage
  with and without motion, and the voice; the intro tests for the six pages and the flashcards page); screenshots of the welcome at
  rest, finished, with Reduce Motion, at the largest text size and on an iPhone SE; real taps in the Simulator; films of the welcome with touches, with nobody touching and with
  Reduce Motion, and of the two intro pages that changed, with the app's own notes mixed in. Page:
  https://macbook-pro.tail9699dc.ts.net:8824/welcome-v2/ (`scripts/cap_anim/films_welcome.sh`, `build_welcome_page.py`).
- **Left out on purpose:** a time-of-day sky (the brand is the night), a "what are you studying for?" question on the welcome (the quiz
  asks it next).
- **Not on frankWhite yet.** Not verified on hardware: how the touches, the notes and the haptics feel, and the tilt.

**The welcome's stars, lighter and quieter (2026-10-25; the owner: "Love it. But I think we can improve our stars/constellation thing.
Better looking and more minimal, and I noticed slight lag as it animates, so it should be optimized to run smooth").**
- **Look:** the first version borrowed Today's whole world (240 background stars, a Milky Way, nebulae, glow bands, big gold discs and long
  glints as stars ignited). The welcome now draws its own: a smooth dusk gradient, about fifty faint stars (thinner behind the
  constellation so its shape reads), the two ridges and the lake, and the cap as a diagram. A star waiting is a small ring with a point
  in it, breathing (the fragile ones faster); lit, it is a warm white point with a soft halo. Lines wait as fine dashes and draw
  themselves solid when both ends are lit. Nothing is bigger than it needs to be.
- **Why it lagged, measured (a debug build in the Simulator, which is what runs on the phone, only faster):** the first note held the main
  thread **163 ms**, the second 28, the third 31 and the flourish 84, because the first sound of a launch synthesises its samples and
  starts the audio engine at the moment of the first touch, as the first star ignites. Now `CLFeel.prepare(cues:)` renders them off the main
  thread and starts the engines 250 ms after the welcome appears: **5, 9, 3 and 1 ms**. (The first version's sky also drew at a capped 30
  frames a second next to a 120 Hz screen and cost 0.4 to 0.9 ms of CPU a frame; the new one draws at the display's rate while it is
  played with, costs **0.04 to 0.09 ms**, and rests at 20 frames a second once the cap has had its moment.)
- **How it stays cheap:** the scenery (`WelcomeBackdrop`) is plain shapes that never redraw; the sky (`WelcomeSkyDrawing`) is about fifty
  fills and strokes, a radial gradient for each lit star, the faint stars' paths built once per size, and no blend modes, shadows or
  offscreen layers. `CRAMLESS_SKY_PERF=1` logs its frame time ("hero frame: …") and `CRAMLESS_FEEL_PERF=1` logs how long each sound held
  the main thread ("feel: right1 took 5.1 ms").
- **Verified:** 919 app tests pass (0 failures, 18 opt-in ones skipped; the first full run died on "the test runner hung before
  establishing connection", the known infrastructure flake, and passed on the rerun). New tests: the star field is the same every launch,
  every envelope of the look (ignition, line, glow, shooting star, ripple, hint) stays in range, the stage with and without motion, and
  the sounds are rendered before they are wanted. Films of the welcome with touches, with nobody touching and with Reduce Motion, and
  stills at rest, finished, with Reduce Motion and at the largest text size, are retaken: page
  https://macbook-pro.tail9699dc.ts.net:8824/welcome-v2/.
- **Not measured:** the phone itself (the Simulator has no GPU of a phone's kind, no haptics and no motion sensor). Today's world is
  unchanged, and heavier than this; it could take the same treatment if it ever stutters.

**Phase 6: the game loop (built 2026-10-26, under review; the owner said "go" to start it).** Nothing in it is a currency, a shop or a way
to lose something: a quest finished, a badge earned, an icon or a sky unlocked all stay. Design rules: `docs/design.md` ▸ The game loop.
- **The flame** (`Shared/Widgets/StreakFlame.swift`, `Shared/Core/StreakStage.swift`): five stages drawn in code from three SVG-style paths
  (spark 1 to 6 days, the flame 7 to 29, a glow and embers 30 to 99, gold with glints 100 to 364, gold with a star 365+; an outline for
  none or on hold), one optional bounce. It replaces every full-colour `flame.fill` (Today's pill, the streak screen, Progress, the
  badges, two widget pills); the Lock Screen's accessories keep their monochrome symbols. Designed as an SVG sheet in headless Chrome first
  (ImageMagick draws no gradients), then ported.
- **Milestones** are 3, 7, 30, 100 and 365 (`StreakStage.milestones`; `StreakEngine.milestoneCrossed(from:to:)`, which freezes and repairs
  cross like studied days; `CelebrationPolicy.milestone` now asks it). The summary's hero becomes "30 days." with the stage's flame
  popping in beside a proud Cap; the streak screen has a Milestones card (a check for each reached, how far to the next); and the day one
  session makes a milestone the reminder and the 20:30 nudge say "One session today makes it 30 days." (`NotificationPlanner.milestoneNext`).
- **Daily quests** (`Engine/Quests.swift`, pure, seeded; `AppModel+Game.swift`): "Finish today's session" every day plus two of save 3
  fading stars, answer 2 in your own words, study before noon (only if the app is first opened before 10:00), fix a mix-up, meet 5 new
  questions, get 5 right in a row, practise for your exam; none on exam eve or with nothing to study; yesterday's come last. Picks are stored
  for the day (`settings.questDay`). Progress is read from the day's own log (`questFacts(forDay:)`), so Today's card counts them as they come;
  `settleQuests()` writes the bits into `DayRecord.questMask` (summary, and the next launch for a day the app was not opened after).
  **Synced** as `quest_mask` (`SyncRecords`, merged by OR, capped at 3 a day when counted); migration `20261025000000_cramless_quest_mask.sql`
  (moved up from Phase 9's). The card (`TodayQuestsCard`) shows after a first finished session. 12 in a calendar week (Sunday- or
  Monday-first, across the clocks changing) light the next sky, once a week.
  - The golden picks are pinned to an independent Python implementation of the hash. `StableRandom.seed` XORs its salt into the day, so
    small salts only shuffle a day's low bits and a week's picks echoed each other; the quest hash mixes the kind in afterwards.
- **Skies** (`Shared/SkyTheme.swift`): six palettes (Night, the old look exactly; Dusk, Aurora, Ember, Bloom, Glacier), read from the
  environment by Today's world (`HeroWorldRenderer`: the glow, the pale band, the dust, the hills, the lake, the ground, the arc), the full
  sky, the exam stills and the glyphs. Settings ▸ Appearance ▸ Sky (`SkyPicker`, `SkySwatch`). Every sky clears 7:1 for white text.
- **Badges** (`Engine/Achievements.swift`): 13 of them, worked out from the log; `settings.badges` remembers which the person has been told
  about, so a first launch notes what is already earned quietly. `BadgeMedal` (a metal rim, a disc, a glyph or the flame, a sheen), the sheet
  (`BadgeSheet`, `TiltingMedal`: CoreMotion up to 12 degrees, a slow sway where there is no sensor, still under Reduce Motion), Progress's row,
  `Route.badges`. The log scan is incremental (one more answer costs a look at the newest ones): 20,000 answers cost 0.4 s the first
  time, nothing again, and 6 ms for one more answer (`testTheBadgeFactsOfAHugeHistoryAreCheapToKeepUpToDate`).
- **App icons** (`Shared/Core/AppIconChoice.swift`): Night (best streak 7), Ember (30), Gold (100), Aurora (365), made by
  `scripts/make_alt_icons.py` from the main icon (no model, no spend). `project.yml` lists them; the picker previews are image sets.
- **The rating prompt** (`Engine/ReviewPrompt.swift`): only after a perfect session of 8 or more, 2 saves or a milestone; not in the first
  4 days or 5 sessions, never on exam eve, 120 days apart, once a version, never in the harness or tests.
- **Hooks:** see `CLAUDE.md` (`CRAMLESS_SCENARIO=streak:<n>`, `CRAMLESS_QUESTS=start|partial|done|weekFull`, `CRAMLESS_QUEST_PICKS`,
  `CRAMLESS_UNLOCK=all`, `CRAMLESS_SKY_THEME`, `CRAMLESS_SKY_TOUR`, `CRAMLESS_TILT`, the three summaries and `CRAMLESS_SUMMARY_*`).
- **Found on the way:** (1) a medal with a `.shadow`, `inset(by:)`, a blur and a `plusLighter` sheen, in a card that fades in, drew a second
  hard-edged medal beside the first on screen and not in an `ImageRenderer`; every layer now has its own size and no filter. (2) NumPy's
  `~a` flipped the icon matte in place (use ufunc calls). (3) Films recorded after 22:00 had no confetti: quiet hours make a
  celebration calm; the films freeze the clock in the afternoon. (4) The Milestones rows broke at the largest text size; the count goes
  under the name there.
- **Verified:** all 1,023 Swift tests pass (104 new for the game loop; 18 skipped as before) and the 95 Deno tests (11 need the local
  stack). Screenshots in light and dark, at the largest text size and with Reduce Motion; films; real taps were not needed
  (every state is a hook). Page: https://macbook-pro.tail9699dc.ts.net:8824/game-loop/ (`scripts/cap_anim/films_game.sh`,
  `build_game_page.py`).
- **Not verified:** the tilt on a phone (the Simulator has no motion sensor), the system's alert when the icon changes, the rating prompt (the
  Simulator shows it, but it is never asked in the harness), and how the quests feel over a real week.
- **Decided without the owner (reversible):** icons unlock at 7, 30, 100 and 365 (the flame's milestones); skies in a fixed order, one a
  week of 12; quests stay hidden until a first session is done; the rest of the plan's badges (a wrapped term, an event) arrive with those
  features.

### Cap on the answer panel: 82 pt (2026-10-26)

The owner found Cap small on the "Saved it." panel (60 pt box, about 54 pt of Cap) and asked for a bigger one that neither lengthens
the panel nor covers anything. Four layouts were rendered by the real app (a DEBUG switch, since removed) and shown on
`build/review/cap-sheet-size/` (tshare `capling-cap-panel`; the full-size shots are in `build/cap-sheet-size/raw/`), with each panel's
height measured from the screenshots (the screen is 3 px per pt): A the same spot at 82 pt with tighter spacing (the same height as
before in every state: 282, 350 and 422 pt for "Saved it", "Not yet" and a long own-words answer); B Cap on the right at 100 pt with the
message beside the headline (6 to 28 pt shorter); C and D at 128 pt with his head over the panel's top edge (the same height, but they
covered the ✕ of a wrong answer and the start of a checklist line). **The owner chose A.** `FeedbackPanel` now draws Cap at 82 pt (44 pt at
the accessibility sizes, as before), with a -8 pt side padding that takes back the empty sides of his tall, narrow art, and the spacing
10 / 8 / 6 / 6 pt (top, between rows, between Cap and the headline, bottom) in place of 18 / 12 / 12 / 8. At the accessibility sizes
nothing changed.

### Review tour for a reviewer without an iPhone (2026-10-26)

Ten films of Maya using the app with real taps and typing (not hooks), plus one staged clip of the rewards a first week doesn't reach (the
Phase 6 hooks), one page with five decisions: `build/review/anis-tour/`,
registered with tshare as `capling-tour` (shared with nobody until the owner says so). `scripts/journey_film.sh` records a journey
(`scripts/journeys/j_*.py`), `scripts/journeys/tour.py try <journey> <udid>` rehearses it, `tour_page.py` + `tour_content.py` build the page.
The how-to is the `review-tour` skill. Real taps found two bugs that the hook-driven films had hidden:
1. **The "63 stars · 17 dim ›" tag on Today's sky did nothing.** It looked tappable and had `allowsHitTesting(false)`, so a finger could
   not open the full sky (only VoiceOver and the `CRAMLESS_TODAY_OPEN` hook could). It is now a button (`TodaySkyHero.starsTag`).
2. **Adding questions from Today crashed the app** (`SkyRenderer.draw`, `Array index out of range`): the hero's canvas received the
   bigger scene a frame before it received the bigger draw plan. `SkyPlan.fitting(scene)` makes the canvas skip a plan that does not
   fit (`testAPlanFitsOnlyTheSkyItWasMadeFor`).
App-side additions, DEBUG only: `App/TouchDots.swift` (a ring under each finger, `CRAMLESS_SHOW_TOUCHES=1`).

**The page did not play on the owner's iPhone** (2026-10-26, iOS 27 Safari: black players at 00:00, a tap did nothing), although the films
played in Chromium, in real WebKit on the Mac (Playwright's `webkit`) and in the iOS 27 Simulator, through both Tailscale links. Two rounds:
1. The first page had eleven `<video preload="metadata">` with a `<source>` and a captions `<track>`. The review server's log showed the
   phone asking for about 90 byte ranges (the eleven films' headers) in four seconds and then nothing, even after a tap. The page was changed
   to `preload="none"`, with an "Open the file" link and a failure note, and `?log` on the plain link (the clips' events go to `/__d`).
2. Still nothing on a tap (`waiting`, then `networkState 3`), but "Open the file" (the same mp4 in Safari's own player) played. The owner ran
   `build/review/anis-tour-diag/` (deleted since; the skill keeps it as `scripts/video_check.html`) on the phone: every film, in every encoding (no audio, Main
   profile 30 fps, Apple's H.264 encoder, HEVC, the old full-size films), played from a bare `<video src>`, and eleven at once and the
   `preload="none"` + tap case played with a `<source>` and a poster; the one test that failed was the page's exact markup, which also has
   `<track kind="captions">` (no length, `readyState 0`, `networkState 3`; its requests read `0-1`, `0-whole file` dropped early, `0-1445`).
   The element that differs is the `<track>`. Not proven alone (the Simulator and desktop WebKit play every variant, so only the phone shows
   it), so the page now is a plain `src` with no `<source>` and no `<track>`, the caption is drawn by the page from the clip's moments
   (`.cue`, compared with the old `.vtt` at 9 sample times: 0 differences; it first sat over the clip and covered the app's Continue button, so it is a line under the clip, as wide as the clip), and a clip that errors or has no length 14 s after Play is
   fetched and played from memory (a blob), which does not use the browser's media loader; if that fails too, the note and "Open the file"
   are what is left. `scripts/review_server.py` logs Range headers and takes the beacon. The check page has `?auto&bisect` for the next time
   (the markup one piece at a time).
Confirmed on the phone (2026-10-26, the owner): the plain `:8824` link with `?log&v=2` plays. Four clips were tapped (welcome, scan,
lecture, sky); each got its length within 0.3 s of the tap, the fetch fallback was never needed, and the requests read `0-1` then the whole
file, without the `0-1445` of the failing runs. The gateway link (`:4810`) has the same page and was checked with a real tap in the iOS 27
Simulator, not yet on the phone. Chromium, Playwright's WebKit and the Simulator played the failing markup too, so no test off the phone
would have caught it.

**Who it is for and where it sits (2026-10-26, the owner asked).** The page said what the app does but nothing about the audience, the
market or the competition, so a reviewer judging the price, the amount of game and what to build next had no frame. Added, all from the
plan (`../docs/rethink/site/plan.html`, researched 2026-10-22), in `tour_content.py`: the lead says "high-school and college students"; a
paragraph in the brief says who it is for (students with exams coming, 13 and up: the app's own data page says "Made for students 13 and
up"), the problem (fewer than 1 in 5 feel very confident about their progress) and the bet (flashcards are free everywhere now; knowing
what you know, and saying honestly if you are ready, is not); a section "Where it sits" (`WHERE_TITLE`, `WHERE`), first in the list, with
Quizlet, Anki, ChatGPT and Gemini and Gizmo in one line each, then "Our position" (ready, not busy), "How we differ" and "Our advantage"
(company figures are called their own claims, and the block is dated); and the pricing decision's context now carries the benchmark (the
median education app $44.99 a year, AI-heavy study apps about $96 to $155). The brief lost a clause that the "How" cards already say. The
figures age: refresh them from the plan's sources before the page goes out in a later month.

**The page follows the cabinet skill's "Sections fold" (2026-10-26, the owner asked; the skill had been updated).** The gateway folds every
`<section>` that opens with its own heading to that heading and starts them all folded. So now: the hero (the app's store listing, below), the
brief, the how-to cards, the route and the nav stay on show; each clip, "Where it sits" and "For reference" is one `<section>`; the five
decisions moved inside the sections they are about (a closed row says "0 of 1 decided"; they used to sit between sections, always on show);
the two `<details>` blocks (where it sits, what else) became sections, and `<details>` is left only for the moments list inside a clip. Each
section ends with **"Mark section as done"** (`data-tshare-pick="done-<id>"`): the gateway saves it for the reader and draws it
(`aria-pressed`), it is not counted as a decision (a `data-tshare-choice` would be, and 13 of them would have held Done back), and the page
shows a tick on the section's label (still there when it is closed) and on its chip; on the plain `:8824` address, with no gateway, the
buttons keep their state in the browser. **The store listing at the top:** the app icon in the store's rounded shape (the 1024 px
`AppIcon.png`, resized with `sips` to `brand/icon.png` and `brand/touch.png`, which also become the tab and home-screen icon), "Capling",
the subtitle "Ready on exam day" (the app's welcome line), a "Coming soon" that is not a button, "In-App Purchases", and age 13+, Education,
EN, Free to start. Checked through the gateway link in WebKit (iPhone size, light and dark, and 1280 wide): 13 sections, all folded at the
start; the hero and brief on show; no decision outside a section; a title opens its section; a mark shows on the button, the closed row and the
chip and survives a reload (the test put it back: `tshare feedback capling-tour` is empty); a route button opens a closed section and
plays; a chip opens its section; no sideways scroll. On the plain address: the marks work and persist, and `tour_test2.js` is ALL OK in
WebKit and Chromium.

### Ask Cap on OpenAI (2026-10-26)

The owner asked whether the cloud tutor should be OpenAI, leaned to GPT 6.1 Sol at medium reasoning, saw the test below and chose
**GPT 6.1 Terra at low reasoning** for Ask Cap. Only the tutor moved: every other cloud route is still written for Claude and was
not tested on OpenAI. Set `OPENAI_API_KEY` on the relay and the tutor answers from OpenAI; without it, from Claude Sonnet as before.

- **Built:** `_shared/openai.ts` (`OpenAIProvider.tutor`: the Responses API with a strict JSON schema, `store: false`, one retry
  before any text, abort and timeout; `AnswerStream`, which reads the answer out of the JSON as it arrives; quotes checked against
  the passages before they go out as `citation` events; `withTutor`, the tutor on one provider and the rest on another).
  `Deps.tutorModel` and `tutorEffort` (OpenAI's when the key is set, else Sonnet at low), the settings `OPENAI_API_KEY`,
  `OPENAI_TUTOR_MODEL`, `OPENAI_TUTOR_EFFORT` and `OPENAI_BASE_URL` (tests), the prices in `cost.ts`. The app's contract is
  unchanged. The server suite is green (119 tests, 24 of them new: `tests/openai.test.ts` against `tests/_mock_openai.ts`), and
  79 app tests on consent, the tutor, routing and the string catalog. A reviewer who hadn't seen the code found that a cut-off answer
  lost its cost and that the retry and early-stop guards were untested; both are fixed and covered.
- **Consent:** it now names both companies. `AIConsent.processor` is "Anthropic and OpenAI" and `currentVersion` is 2, so everyone
  is asked again, as the rule in `AIConsent` says for a new processor; the harness grants the current version. Change the
  processor line with the relay's wiring if everything moves to OpenAI. The privacy policy and the App Store privacy answers
  still have to say the same.
- **First real call (2026-10-27):** `OPENAI_API_KEY=… deno task live-openai` ran the relay's code path against OpenAI with
  Terra at low reasoning. Hints, explain, a question the page can't answer and an under-18 account all passed: quotes on the
  page, hints and explain ending on a question, no outside facts, no source id in the answer. 0.64¢ for the four answers; first
  words after 0.7 to 1.2 s (3 s for the very first, a cold connection).
- **Not done:** a per-user spend cap (proposed: a monthly dollar cap near 15% of what the plan nets, then Cap answers on the iPhone;
  the paid tutor ceiling cut from 300 to about 60 a day), the other cloud routes on OpenAI, and a check of OpenAI's rules for
  apps used by 13 to 17 year olds.

The test that chose it: `supabase/functions/tools/tutor_bakeoff/` sends 33 Ask Cap questions to the OpenAI Responses API with the
relay's own tutor prompt (`tutorSystem`) and four passages from the demo notes each: explain and hints mode, under-18 accounts,
follow-ups, "Explain my mistake", questions the notes can't answer, an essay request, a detector rewrite, a planted instruction.

- Run: `deno run --no-check --allow-net=api.openai.com --allow-env=HOME,OPENAI_API_KEY --allow-read --allow-write
  tools/tutor_bakeoff/run.ts [--configs sol-medium,terra-low] [--cases ...]`, then `report.ts DIR`. The key comes from
  `~/.config/capling/openai_key` or `OPENAI_API_KEY` and is written nowhere; `store: false` is sent. The runs are in
  `build/bakeoff/run1` to `run4` (gitignored); about 640 calls cost $0.88.
- Citations: OpenAI has nothing like Claude's `search_result` blocks that keeps the notes on our side, so the model returns
  `{answer, citations: [{source_id, quote}]}` in a strict JSON schema, and the app's own rule (`HighlightMark.locate`) judges
  the quotes. 787 of 787 quotes were kept, every one naming the right passage.
- Per answer, at list prices of 2026-10-26 (per million tokens: Sol $2 in / $10 out, Terra $1 / $5, Luna $0.10 / $0.50), about
  940 tokens in and 90 to 180 out: Sol medium 0.32¢, Sol low 0.29¢, Terra medium 0.18¢, Terra low 0.14¢, Luna medium 0.02¢.
  First words, median and slowest tenth: Sol medium 1.9 s and 5.8 s, Terra low 1.1 s and 1.5 s, Luna medium 1.7 s and 2.9 s.
- Held for every setup: a cited quote for every factual answer, "your material doesn't cover that" on all five questions the
  notes can't answer (no outside facts), the essay and the detector rewrite refused, the planted instruction ignored, a
  trusted adult named to the stressed under-18. Without the instruction not to, Sol and Terra sometimes wrote "(s1)" into the
  answer: the format note now says never to write a source id.
- Hints first is where they differ. Two graders who didn't know the models read 150 hints-mode replies. The reply gave the
  answer away in full: Sol medium 43%, Terra medium 10%, Terra low 13%, Luna medium 27%, Luna low 60%. Judged a good hint:
  30%, 67%, 57%, 63%, 30%. Sol also ended on a statement, not a question, in 10% of them. Luna with no reasoning once kept
  writing after its JSON ended.
- Recommended, and chosen: Terra at low reasoning (Luna at medium for the free plan if its cost matters more). Not tested:
  Claude (no key), real students' wording, the app's own retriever, a stronger hints prompt for Sol.

### Ask Cap as an assistant (2026-10-27)

The owner asked for Ask Cap to "fully assist the user": create flashcards, quizzes and notes, plan exams, research online, with the
user in charge of everything and animated feedback for each state, like the top apps' agents. Built the same day; the design, the
trust rules and the screens are in `docs/assistant.md`, the wire format in `docs/relay-contract.md` ▸ `ai/assistant`, `ai/research`.

- **What it is:** the tutor's model, given tools. It only *chooses* a tool; the app runs it. Eight tools: look up the notes, make
  flashcards, make questions (pick one, in your words, fill in the blank), write a note, plan an exam, offer a practice session, offer
  a screen, research on the web. A draft is shown as a card (it works, it proposes, it settles) and added only by the student, or
  by "Let Cap do it" for flashcards and questions, notes or exams (never for an account under 18). Everything added can be undone, and
  Settings ▸ What Cap can do lists it.
- **Relay:** `ai/assistant` and `ai/research` (server-sent events); strict function tools and the trusted-sites list in
  `_shared/assistant.ts`; `OpenAIAssistantProvider` (`_shared/openai_assistant.ts`) on the tutor's provider; `_shared/argstream.ts` reads
  finished cards out of a half-written call, so the app can show each card as it is written; the model's own reasoning travels as an
  opaque `continuation` between rounds (the relay stores nothing). Meters: the first round is a `tutor` message; later rounds are the hidden
  `rounds`, refused when they would pass three for each tutor message that day; a draft (`drafts`, free: 3 a day) is taken atomically before
  the model is asked and given back if the reply drafts nothing; research is Pro only (`research`, 3 a day; 5 until 2026-10-27). The web search is a fee of $0.01
  on top of the tokens. Mock scripts `assistant-*.json` and `research-*.json` (the app's mock transport and the relay's MOCK mode play the same
  files). The server suite is green (170 tests; 51 new: streaming readers fuzzed over random cuts, the OpenAI streams against a mock that checks
  each request's shape, quota and refunds, the minor and Pro gates, the mock scripts against the real tool schemas, and one regression test
  for each defect the review below found).
- **App:** `AI/AssistantContract.swift`, `AssistantDrafts.swift` (pure: quotes are evidence only if the notes hold them, a choice question
  needs its right option and is shuffled, a date must be a real day that hasn't passed), `AIRouter+Assistant.swift` (up to four rounds,
  the lookup and the web here, a staged reveal of the checks), `AppModel+Assistant.swift` (study index with short ids, draft tools,
  add through `ItemFactory` / `createSource` / `createExam`, undo as a soft delete), `Model/AssistantSteps.swift`
  (`ChatMessage.actionsData`), the cards in `Features/Ask/Assistant/` and `Features/Settings/AssistantPage.swift`. `AIConsent.currentVersion`
  is 3 (Cap now also sees course, topic and exam names and due counts, and a research topic goes to trusted sites), so everyone is asked again.
  Ask Cap tries the assistant first when Cloud AI is on and falls back to the tutor if the relay has none or it fails before anything is shown.
- **The test that chose the prompt and tools:** `supabase/functions/tools/assistant_bakeoff/` runs 50 requests (45, and five for a free account that has used its three drafts) through the relay's real code on
  GPT 6.1 Terra at low reasoning, playing the app's part (lookups from a small set of notes; drafts "proposed"). The first run passed 40
  of 45 and showed what to fix in the prompt (draft an exam when the student only mentions one; look up at most once; spread cards across
  the passages; the right option was always first or second; no quick-check question after acting; do what "from your own knowledge" says). The
  last run, with real web research: **50 of 50**; $0.136 for 50 requests (0.27¢ each: a drafting turn about 0.25¢, a web research turn
  1.7¢); the first sign of work after 1.1 s, the first card or line after 2.6 s, a whole reply in 3.5 s (9.8 s for the slowest tenth); 72 of
  72 quotes exact and none made up (4 items had none: the student had said "from your own knowledge", and they are marked as Cap's own
  words); hostile text in a note or in a course name ignored; "not in your notes" said, not guessed. Results:
  `build/assistant-bakeoff/run8/results.json` (50 cases, the final prompt; gitignored). A run after the reviewer's fixes showed one case flaky: "from your own
  knowledge" was refused in 2 of 6 tries (the "not covered" rule came first in the prompt); with the exception first it is 10 of 10.
- **Independent review (same day).** A reviewer who had not seen the work read the relay, the migration and the tests and found defects
  that were all fixed, each with a test:
  - the database's meter check did not know `drafts`, `research` or `rounds`, so every draft and research request would have failed in
    production (migration `20261027000000_cramless_assistant_meters.sql`, and the pgTAP file);
  - a request made up by hand, with forged `turns`, skipped the tutor meter (now: a later round needs `rounds` within three for each tutor
    message of the day), and a call id could be replayed (now each id is used once; at most three turns);
  - the day's drafts were checked after the model was asked, so parallel requests could all pass (now taken first, atomically, and given
    back when unused); the "free drafts used up" notice was sent on every first round, even for a plain question (now: the model reaching for a draft tool is the signal, the relay stops it there and the reply ends with the limit, and the app writes the words; 15 of 15 on the real model);
  - the tag scrubber for pasted notes took quadratic time on a long run of spaces, and the first fix still let nine spaces through (now one
    linear pass, `defangTags`);
  - research sources and citations were passed on whatever their address (now https on an allowed site only), a stream cut after the search
    lost its $0.01, and a billed failure gave the quota back (now kept when the provider billed it or the student left);
  - a call to a tool that was not offered was passed on (now ignored), and a round with one unreadable call acted on the others (now every
    call is read before the app is told of any);
  - web research saved itself when "Let Cap do it" was on for notes (now only on a tap).
- **Looking at the real screens (later the same day)** found what no test did, and it is all fixed: the card said "Checking…" while cards were
  still being written (the step now knows its phase, `AssistantStep.checking`, and Cap's line says "Writing the cards", then "Checking each
  card against your notes"); the chat did not follow a growing reply (it follows now, and stops when the student scrolls away); the empty chat
  hid its "make something" chips under the composer (moved up, hidden when Cap's tools can't be used); a failed card showed the model's
  instructions to the student (the student and the model now get their own words); a stopped reply marked an auto-added step "Skipped" while its
  items were in the library (it stays added, and can be taken back); the mock scripts collided with the demo world's own cards and gave the wrong
  wrap-up (they don't now); at accessibility text sizes the card header squeezed its title (it stacks). The app's wire tests
  (`AssistantWireTests`) run the real HTTP client against the relay in MOCK mode. The real model in the app's default hints-first mode: 49 of 50
  (the miss was one card instead of two, from notes that state one fact; the case accepts one now), and explain mode 50 of 50. A reply stopped at the free limit is logged with no tokens (the connection to the model is closed at
  the first sign of the call); it costs about 0.05¢ at OpenAI and counts as one of the day's tutor messages, so it is bounded.
- **Final numbers (2026-10-27):** the relay's Deno suite 172 passed (11 more need the local stack); `deno fmt`, `deno lint` and
  `deno task check` clean. The app's whole suite: 1,079 tests, 0 failures, 18 skipped (the opt-in LocalStack and StoreKit ones), the six
  `AssistantWireTests` among them. With Reduce Motion on, the cards and the research step show their last state at once (checked by eye on
  both: `cards-calm`, `research-calm` in `scripts/cap_anim/films_assistant.sh`). Not run: pgTAP (its values were checked by hand on a scratch
  Postgres). One trap: simq's `xcodebuild` wrapper now shares a compile cache and rewrites source paths to `/^src/…`, which made 15 tests
  that find the source folder with `#filePath` fail; `scripts/xc.sh test` builds without the cache (`SIMQ_NO_CACHE=1`).
- **Decided with the owner (2026-10-27):** keep 3 free drafts a day; research down to 3 a day on Pro (worst case $1.53 a month against the
  $3.54 a yearly plan nets); no web research for under-18s at launch (Apple's age-rating wording and OpenAI's rules for 13 to 17 are
  unchecked; teens keep everything else, asking first); **a daily cost cap** for every person, 10¢ (`DAILY_COST_CAP_USD`), under the
  meters: Pro's fair-use ceilings alone (300 tutor messages, 150 drafts a day) would cost more than a yearly plan nets, so before each AI
  request the relay reads what the person's calls have cost since their local midnight (`cramless_spent_since`, new migration
  `20261027000100_cramless_daily_spend.sql`) and answers 429 "That's all the cloud AI for today" past the cap (`docs/assistant.md`, "The
  day's cost cap"); in the app the tutor's note says so instead of "couldn't be reached". The privacy wording (policy section, App
  Store answers, the manifest's four added types, consent text with exam dates and readiness) is in `docs/privacy-wording.md`.
  `scripts/device_demo.sh` opens the isolated build in demo mode on a phone; the owner's iPhone was unavailable (off or out of reach),
  so nothing was installed. Both device scripts had a guard that took "unavailable" for "available"; fixed.
- **Not done:** editing or deleting what already exists by chat; making a new course; the assistant on the iPhone's own model; open-web research for adults (Apple's
  age ratings ask about unrestricted web access and the floor for a 13+ app was not confirmed); real site icons (the tiles are drawn in code
  so the app never tells a site what the student is researching); the privacy policy and App Store privacy answers have to name the web
  step and the new data; OpenAI's rules for 13 to 17 year olds are unchecked.

## Left for the owner

- Accounts and keys (see README "Before the App Store"):
  - a Supabase project
  - the Anthropic key, and the OpenAI key for Ask Cap's tutor (see "Ask Cap on OpenAI")
  - App Store Connect products and URLs
  - the Squad link domain
  - a trademark check on the name
- On a device:
  - the scanner and the microphone (live transcription, background recording)
  - Foundation Models answers and timings (the simulator has none)
  - Sign in with Apple
  - Live Activities and the Control
  - Declared Age Range
  - haptics
- Prompt quality over the real API: the prompts held up on one sample page with the same models answering
  through subagents (above). Once the key is in, run `deno task live`, then tune with more real pages: other
  subjects, handwriting, long PDFs.
- Smaller follow-ups:
  - Sessions, day records and pages have no `updatedAt`. Every change to a session or a day clears its
    `syncedAt`, and a page goes up with its source's stamp, so nothing is missed. The one approximation: when two
    devices study on the same day, that day keeps the larger total, not the sum.
  - Mock mode's tutor replays one canned script whatever the question.
