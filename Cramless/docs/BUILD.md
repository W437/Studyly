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
    the `ai` relay (9 routes, quotas with refunds, anchor cleaning, MOCK = fixtures byte for byte, real mode on
    OpenAI's Responses API with strict structured outputs; tested against a mock OpenAI server), `account` (StoreKit JWS verification ported from plainsum, Squad,
    deletes), `appstore-notify`; Swift `Sync/` (GoTrue auth incl. anonymous and Apple, Keychain session, PostgREST
    sync with a ledger, BackendClient). Deno 95 tests (+11 with the local stack), Swift 50.
    Owner must provide: a Supabase project (host + anon key in Secrets.xcconfig), `OPENAI_API_KEY` and
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
- **The relay's own prompts, replayed (before the move to OpenAI).** `supabase/functions/tools/prompt_replay.ts` records the
  relay's exact calls on the sample page (model, system prompt, user content, JSON schema) and replays a model's replies
  through the relay's own validation and cleaning (`replay`; files in `build/prompt_replay/`). The replies then came from a
  different model family, answered as subagents: generate passed validation (12 items, every anchor a real line, one right
  answer per multiple choice), check caught all three planted errors and kept the real items, grade scored three answers
  right with the student's own words as quotes, and the tutor's hints ended on a question with verbatim citations. It
  didn't cover schema enforcement or cost.
- **OpenAI through the relay, over the API.** `OPENAI_API_KEY=… deno task live` (`supabase/functions/tools/live_check.ts`) runs
  the relay's real code path on the sample page through generate, check, grade and the streamed tutor, with verdicts and
  cost (`LIVE_ONLY=grade,check` runs some). A dry run against the mock server (`deno task mock-openai`, `OPENAI_BASE_URL`)
  exercises the plumbing only.

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
**GPT 6.1 Terra at low reasoning** for Ask Cap. At first only the tutor moved; on 2026-11-02 every other cloud route followed (see
"Every route on OpenAI" below). Set `OPENAI_API_KEY` on the relay and all AI routes answer from OpenAI; without it they answer `upstream`.

- **Built:** `_shared/openai.ts` (`OpenAIProvider.tutor`: the Responses API with a strict JSON schema, `store: false`, one retry
  before any text, abort and timeout; `AnswerStream`, which reads the answer out of the JSON as it arrives; quotes checked against
  the passages before they go out as `citation` events; `withTutor`, the tutor on one provider and the rest on another; since replaced by one OpenAI provider for every route).
  `Deps.tutorModel` and `tutorEffort`, the settings `OPENAI_API_KEY`,
  `OPENAI_TUTOR_MODEL`, `OPENAI_TUTOR_EFFORT` and `OPENAI_BASE_URL` (tests), the prices in `cost.ts`. The app's contract is
  unchanged. The server suite is green (119 tests, 24 of them new: `tests/openai.test.ts` against `tests/_mock_openai.ts`), and
  79 app tests on consent, the tutor, routing and the string catalog. A reviewer who hadn't seen the code found that a cut-off answer
  lost its cost and that the retry and early-stop guards were untested; both are fixed and covered.
- **Consent:** `AIConsent.processor` follows the relay's wiring (now "OpenAI"; version 3 has not shipped, so no one was asked
  twice). The privacy policy and the App Store privacy answers have to say the same.
- **First real call (2026-10-27):** `OPENAI_API_KEY=… deno task live-openai` ran the relay's code path against OpenAI with
  Terra at low reasoning. Hints, explain, a question the page can't answer and an under-18 account all passed: quotes on the
  page, hints and explain ending on a question, no outside facts, no source id in the answer. 0.64¢ for the four answers; first
  words after 0.7 to 1.2 s (3 s for the very first, a cold connection).
- **Not done:** a per-user spend cap beyond the daily 10¢ one (proposed: a monthly dollar cap near 15% of what the plan nets, then
  Cap answers on the iPhone; the paid tutor ceiling cut from 300 to about 60 a day), and a check of OpenAI's rules for apps used
  by 13 to 17 year olds.

The test that chose it: `supabase/functions/tools/tutor_bakeoff/` sends 33 Ask Cap questions to the OpenAI Responses API with the
relay's own tutor prompt (`tutorSystem`) and four passages from the demo notes each: explain and hints mode, under-18 accounts,
follow-ups, "Explain my mistake", questions the notes can't answer, an essay request, a detector rewrite, a planted instruction.

- Run: `deno run --no-check --allow-net=api.openai.com --allow-env=HOME,OPENAI_API_KEY --allow-read --allow-write
  tools/tutor_bakeoff/run.ts [--configs sol-medium,terra-low] [--cases ...]`, then `report.ts DIR`. The key comes from
  `~/.config/capling/openai_key` or `OPENAI_API_KEY` and is written nowhere; `store: false` is sent. The runs are in
  `build/bakeoff/run1` to `run4` (gitignored); about 640 calls cost $0.88.
- Citations: OpenAI has no passage type that keeps the notes on our side and makes the model cite them, so the model returns
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
  other providers, real students' wording, the app's own retriever, a stronger hints prompt for Sol.

### Every route on OpenAI (2026-11-02)

The owner decided the app uses OpenAI only. The seven JSON routes (generate, check, grade, confusions, lecture, cards-from-chat,
transcribe-image) moved to the Responses API on GPT 6.1 Terra, so there is no second provider any more.

- **Built:** `OpenAIProvider.json()` (`_shared/openai.ts`): one non-streamed request, the pages and photos as `input_text` and
  `input_image` parts, a strict `json_schema` output, `store: false`, the tutor's timeout, one retry and error mapping, and the
  reply read back through the contract's own schema. Strict mode needs every property required, so `strictSchema()` makes the
  contract's optional properties nullable and `withoutNulls()` drops those nulls from the reply. The neutral call types live in
  `_shared/provider.ts`; the first provider's class, SDK import, env vars and mock server, and `withTutor`, are gone; a missing key is the cold-start fault `openai_key_missing` and the routes answer `upstream`.
- **Models and effort:** Terra on every route; effort medium for generate, check and lecture, low for the rest, and grading is
  medium for `apply` questions and answers over 700 characters, low otherwise. A reply that could not be used (refusal, cut off,
  unreadable, off-contract) still costs what OpenAI billed, and that now counts toward the day's 10¢ cap.
- **Cost:** Terra is $1 / $5 per million tokens against $0.10 / $0.50 for the small model the cheap routes used before, and
  reasoning tokens bill as output, so the free-plan routes cost about ten times what they did. The 10¢ daily cap and the meters still hold; a
  normal day should be re-measured after launch (`ai_requests` has the tokens and cost of every call).
- **Tested:** the relay suite (179 tests; `tests/openai_json.test.ts` is new) against `tests/_mock_openai.ts`, which now also
  answers whole responses and refuses what strict mode refuses. Live, with the real key: a grade, a photo transcription and a
  check (it has optional properties, so it proves the nullable form) all returned 200 with valid replies, 0.48¢ for the three.

### Relay fixes after the 14-day test (2026-11-03)

The relay's share of the fixes after `capling-14-day-user-test`. Every new request field is optional, every new reply field is optional
and nothing is renamed, so build 1.0 (2) keeps working; the relay and the app change together at the next deploy. The prompts are
in `_shared/prompts/` (bundle with `deno task bundle`), the wire format in `docs/relay-contract.md`.

- **Tutor prompt (R1):** the model reads every source before it says anything is missing (paraphrases, formulas, tables, definitions,
  examples, a classmate's card), builds its reply on any definition, rule, formula or holding it finds (a court's disposition and reasoning
  is its holding) and names a missing part only when it is truly absent from every source. When the answer is not there it says "I couldn't
  find that in what you've added." and names the materials, never "doesn't state/cover" and never asking for pages unless the question is
  plainly about another topic. It says so when two sources disagree, ignores and mentions a line in the notes that gives it an order,
  steers off-topic messages back in one sentence, and declines to do an exam or graded work. The assistant uses the same rules. One
  coupling to know: the app recognises the cloud's "not covered" reply by the prefix "Your material doesn't cover" (`ChatEntry.isNotCovered`,
  `ChatPane.swift`) to show the "Add notes on this" chip and the muted bubble; the new line does not match it, so on build 1.0 (2) the chip
  and the tint simply do not appear for those replies (the usual chips do), and the app should match the new line.
- **Tutor request (R2):** `sources` up to 100 passages (was 12; the assistant's was 24), the per-passage text limit unchanged at 20,000
  characters, `materials?` (20 names of at most 120 characters) as a "The student has added:" block. The input order is now the student's
  material, the earlier turns, then the question (the assistant's too; its study state stays with the question), so the material is the
  same bytes from one question to the next and OpenAI's prompt cache can serve it (before, the passages sat in the last message, after the
  history, and could never be a shared prefix). The app has to keep the passages' ids and order stable between questions for that. Cached input is
  billed at the cached price already (`readUsage`, `costNano`); a 100-passage request is about 8,000 tokens, 0.9¢ cold and 0.2¢ warm. The
  tutor's 1 MB body limit holds 100 passages of 60 words many times over (well under 100 KB).
- **Check (R3):** `sourceTitle?`, `headings?` and `lenient?`; the title and headings are part of the source for the check (so "the court
  held…" is supported when the title names the judge), and a lenient check also reads two lines around each cited one and ignores missing
  names. The verdict contract is unchanged.
- **Lecture (R4):** the prompt asks for `maxItems` questions, one per distinct idea (flagged first, then the lecture in order), and the reply
  may carry `leftOut` (1 to 99; left out when none). The notes' prompt is untouched.
- **Generate (R5):** the prompt covers every section (at most two from one until all have one, the last third counts), and the reply's
  token budget grows from 16,000 (16 questions) to 30,000 (40). A live call wrote 14 questions in 46 s and the app waits 75 s.
- **Research (R6):** `_shared/research_sources.ts` holds the sites research never uses (OpenStax, Connexions, Chegg, Course Hero, Quizlet,
  Studocu, Scribd, Brainly, Bartleby, NCBI's PubMed, PMC and Bookshelf, StatPearls). OpenAI's web search takes only an allow-list, so they are taken out of that list (`env.ts`, the
  provider), named to the model, dropped from sources and citations, and a reply that rested only on them is withheld. Open sources are
  preferred and each page relied on is cited. The built-in list (`RESEARCH_DOMAINS`) now holds only sources we can defend, with the licence
  beside each entry (a test checks that): US federal agencies, GOV.UK and UK legislation, EU institutions, Wikimedia, open-access journals
  under CC BY, Project Gutenberg, MDN, the Python docs. Every commercial publisher, encyclopedia, health or education brand, university site
  and non-commercial licence (MIT OCW, Khan Academy, LibreTexts, CK-12, WHO) is out, and so is arXiv (the author picks its licence). NIH is
  listed by institute (NIDDK, NHLBI, NIA, NIAID, NIMH, NINDS, NIGMS, NEI, NICHD, NCCIH, ODS, plus cancer.gov), not as `nih.gov`, which would
  open NCBI's PubMed, PMC and Bookshelf (items under their own licences, StatPearls non-commercial and no-derivatives); NCBI and StatPearls
  are also on the denylist. An entry may be one host (`www.gov.uk`, so not the councils); the page filter now compares the page's own host.
- **Assistant (R7, R9):** notes and cards say what the passages say and never that the material "does not explain" something; when the
  notes support fewer cards than asked for the model drafts those, says how many fewer and why, and never pads (the tool descriptions say
  the same). It is not a limit the relay enforces: a short draft is a draft.
- **Review fixes (R11 to R14):** the passages of one tutor or assistant request hold at most 200,000 characters in all (`bad_request`, 413,
  before anything is metered; a hand-built 100 x 20,000 request used to cost 26 cents on the tutor, 52 on the assistant; the app sends about
  40,000). Research drops every `RESEARCH_DOMAINS` entry that is a denied host, under one or a parent of one (`nih.gov`), and withholds a
  summary unless it cites a page the student may see once a denied page has turned up (pages merely consulted no longer count). The generate
  call may take 115 s in all (the app waits 120 s; every other model call, the tutor and the assistant included, keeps 90 s, and research
  150 s); a JSON call that timed out while its body was being read used to be reported as a cancellation (499) and is now the timeout (504).
  A `502` from generate can be a billed failure: clients must not retry it (contract note).
- **After the second 14-day test (labels, the upstream log):** the check prompt has a "Labels:" rule: a question may point at its passage by a
  label or a place the cited lines do not repeat ("the headnote", "the Kansas case"), and only the statement and the answer have to be on the
  lines (round 2's check wrongly dropped 10 of 62 court-opinion questions that way; not re-measured, the OpenAI balance ran out first). And
  every refused OpenAI call now carries `upstream` ("429 credit_balance_exhausted", status and error code only, 40 word characters at most)
  in the request's log line (`ApiError.upstream`, `Meta.upstream`, allow-listed in `log.ts`): a spent balance, a rate limit and an outage
  all reach the student as "Cap is busy right now" (503), and until this the log could not tell them apart. Alert on
  `credit_balance_exhausted` and turn on auto-recharge before launch.
- **Prompt rules added after round 2's reviewers (not measured live: the OpenAI balance had run out):** a classmate's deck, list or forum post is
  another student's claim, not a source of truth: the tutor checks it against the course's own sources, says which one the course source
  supports and never gives the deck's claim as the answer when a course source says otherwise (the old line told it not to pick, which let
  Marbury's "the Court ordered delivery" card stand); the assistant leaves out a card that a course source contradicts. The quick-check
  question at the end of an explanation is asked only when it adds something. In hints mode the "ask first" rule is stated for follow-ups too
  (8 of 109 replies had given the answer). An outline, plan or list of key points for an essay is study help and is drafted; only the essay
  itself, or an outline the student says they will hand in, is declined (one student's outline request was refused and another's drafted).
- **Prompt cache key (found on the 2026-11-03 rerun):** a tutor question about a long material (19,000 tokens) was billed in full 6 times out of 7 (1.9 cents,
  the day's 10 cent cap at the fifth question), though the passages were the same bytes each time. OpenAI picks the machine by the first lines of the prompt,
  which are the same instructions for everyone, and serves the cached part only from the machine that read it. The tutor and assistant requests now carry
  `prompt_cache_key` = `cap-` + 32 hex of a hash of the passages block (the material's, never an account's or a person's; `cacheKey` in `openai.ts`), none
  when there are no passages. Measured afterwards (the key is on, deployed as version 11): four different questions about the material, 40 seconds apart,
  each read all 19,000 tokens from the cache (0.16 to 0.18 cent each); questions 4 seconds apart still pay in full (the cache entry is not there yet), so a
  harness must pace its questions like a student (`bench tutor --pace 35`), and a person who asks the next question within seconds pays about 2 cents.
  Not measured without the key at human pace, so how much of the gain is the key and how much the spacing is not known.
  **Later the same night (key deployed):** three fresh 12,000 to 16,000 word materials, one student each, questions 15, 25 and 40 seconds apart, read 1,323 of about
  21,000 tokens from the cache (the instructions), never the passages; each question cost 2.0 to 2.4 cents and each student stopped at the cap after five. The
  earlier hits were on a material other requests had just read. So a single student's passages cannot be counted on to come from the cache, and the tutor's request
  is sized for the cold price (see "Which passages the cloud tutor gets").
- **A spent OpenAI balance (round 2's P0):** an OpenAI `429` whose code or type says the balance or budget is spent (`insufficient_quota`,
  `credit_balance_exhausted`, billing) is answered `503` "Cloud AI is unavailable right now. Try again later." with `retryAfter` 600 (also
  the `Retry-After` header), is not asked a second time (the relay's own retry now skips a 503 that names a wait over 60 s) and the meter is
  given back. A plain rate limit is still "busy" and is retried. The app already does not retry a 503 that names a wait over 15 seconds, so
  it falls back at once. The `upstream` field of the request's log line says which it was (see above).
  The tutor also no longer takes back or doubts an earlier answer of its own unless a source contradicts it (round 2: "I shouldn't have stated what a catalyst does in my last reply" after a correct, sourced answer).
- **Tested:** the relay suite is 232 tests (12 more need the local stack), with new ones for each change above and for the order of the
  input. Not testable without the key: whether the model now finds what it used to miss. After deploying run `deno task live-openai` (it
  has probes for a paraphrase, a planted instruction and the named materials) and `deno run -A tools/assistant_bakeoff/run.ts`.

### App fixes after the 14-day tests (2026-11-03)

What the app side changed after the two tests (`capling-14-day-user-test`, `...-round-2`; the numbers are from the harness in
`~/Documents/capling-user-test/round2`, which runs the app's own Swift code against the relay). All of it is in build 1.0 (3) or, for the offline tutor and the iPhone model changes of the evening, build 1.0 (4) (last bullets); none of it is on a phone yet.

- **Which passages the cloud tutor gets (`AI/TutorSelection.swift`, `LocalRetriever+Recall.swift`).** A request carries 4,000 words: every passage, in reading
  order, of a material that size or smaller; above that the likeliest 4,000 (the sources the question names first, the best 12 of the rest, neighbours, what the chat
  stood on); and for a question that shares no word with a long material ("quiz me on this", "what should I focus on", "explain this chapter", a Japanese question) an even
  spread of it (`Mode.overview`; before, nothing was sent and the offline tutor answered). With the old rule (the best 30 passages and 6 neighbours) the answering line was not
  sent for 8 of the 9 false "not covered" replies; with this one it is missing for 1 of 78 turns on the seven students' materials of 5,000 to 16,000 words
  (`bench select`, no model; the whole material: 0). Real Cloud AI answers to the same 91 questions: the answering line shown in 55 of 78 covered turns (53 with the
  whole material, 44 with the old rule), a covered question refused 2 times (1 and 3), no "Quick check" closer, and no turn answered from the notes for want of
  Cloud AI. **Why 4,000 and not the whole material:** the first version of this fix sent the whole material up to 16,000 words. Measured on the relay's own log it
  cost 2.2 cents a question on a 12,000 to 16,000 word reading, because OpenAI's prompt cache did not serve the passages to one student (three fresh
  materials, questions 15, 25 and 40 seconds apart: 1,323 of 21,000 tokens, the instructions, came from the cache; an earlier run on a material other requests had
  just read did hit, 11 of 11), so the relay's 10 cent day cap, which the owner agreed, came at the fifth answer and the free plan's ten were out of reach (all three
  students stopped there). A request of 4,000 words costs 1.06 cents on average (10,200 tokens, 4,300 of them the labels of 100 passages and the instructions; 85
  questions, none above 1.4), so ten answers fit under the cap on any reading; a German one costs a quarter more. 6,000, 4,500 and 4,000 words each held the
  answering line in 77 of 78 turns, 3,500 in 76. On seven more students that the sizes were not tuned on (round 3, 56 gold turns) the line was in the request in 49 turns at 4,000 words (48 before Japanese was cut into words), 50 at 6,000 and 51 at 8,000 or with the whole material; the 5 that nothing finds are lines the extracted text lacks (a PDF table row, an unreadable handwritten page, a diagram label in a photo) or that the word-overlap check cannot score (Japanese). A wider spread (8,000 words) for the questions with nothing to aim at was tried on Aiko's Japanese questions and taken out again: two of the three turns that looked missing were answered correctly anyway, and the third (who wrote the Oath's first draft) stayed unanswered because the retriever did not split Japanese into words and an even sample is not aimed; that is what the Japanese lexicon fix is for. To have the whole material back, if the caps are raised, set
  `TutorSelection.tutor` to `Budget(wholeWords: 16_000)`.
- **The offline tutor (`AI/Local/LocalSentenceSearch.swift`, `OfflineMeaning.swift`, `LocalTutor.swift`).** The unit is a sentence, scored on its words
  (BM25 over sentences, rare words counting most) and on the meaning of its words (`NLEmbedding.wordEmbedding`), and the best few dozen are read
  by Apple's contextual model (`NLContextualEmbedding`, only when its assets are already on the phone: it never asks for a download). Without
  it the words decide. A gate (`OfflineRanking.Gate`) refuses to quote a sentence that neither the question's words nor their meaning
  support and says `LocalTutor.notCovered` instead; a sentence is shown with the line before it when it points back and the items of a list it
  introduces. On the 78 questions the notes answer, the reply shows the answering line 5 times before (6%) and 14 after (18%); it shows another
  passage 52 times before and 32 after; it says "couldn't find" 21 and 32 times; and of the 13 questions the notes do not cover it quoted the notes anyway
  7 times before and 2 after. It is still weak: how well a sentence matches does not say whether it is the answer (the gate is a floor against the
  unrelated, not a test of the right one), and the speed (median half a second with seven runs sharing the Mac) and the contextual model were
  not measured on a phone then (they were later: "On a phone", below: 0.2 s a question, 150 MB).
- **Questions written without Cloud AI (`AI/QuestionQuality.swift`, `AI/Local/SourceHygiene.swift`, `AI/TextArtifacts.swift`, `LocalGenerator`,
  `OnDeviceJobs`).** One filter for the offline rules and the iPhone model: it drops prompts that are cut off, headings, citations, reference
  entries, captions, listings, page headers, questions about a figure the text lost, fill-ins whose blank is a stop word or is given away,
  and repeats. Blind ratings of the questions written for nine texts (290 rated before, 409 with the regenerated sets rated again): a
  zero on one of four scales in 53% of the offline questions before and 16.7% after; the iPhone model's 44.5% before and 28.2% after. The model's wrong answers (Palsgraf's "judgment affirmed") are not something a filter can see. The stricter fill-in floors
  assume a text long enough for a word to recur, so under ten sentences and bullets (`DocumentContext.isSmall`) they are lower; and a tagger that
  answers "other word" for every word (the iOS Simulator, a device without its model) counts as no tagger, so the verb check is skipped.
  Both were found by the full test run: four pasted sentences had got no offline question at all.
- **Formulas lost from PDFs (`Capture/PDFReader.swift`, `PageLayout.swift`).** `PDFInk` walks each text-layer page's drawing operators (no
  rendering) and counts small filled vector outlines (the glyphs of a typeset formula), and `PageLayout` groups them into formulas and adds
  them to the existing "formulas may be missing" score. Of the 19 labelled pages that lost formulas in the 14-day PDFs the flag now catches 18 (8
  before); heavy pages 10 of 10 (7 before). It flags 2 of the 32 pages labelled clean, and by eye each of those is missing one displayed formula.
  Leave-one-printout-out gives the same 18 of 19; seven other PDFs from different producers got no new flags except three pages of one manual
  (block diagrams whose labels are drawn as outlines). The outline read takes 0.7 ms a page on the Mac.
- **Language of short notation pages, and a stray tone mark.** A request's language is what the recogniser reads in the text when it is at least 80% sure
  and has 40 letters to judge from (`LocalGenerator.confidentLanguage`), else the course's other sources', else the device's: Amara's English
  worksheet of symbols was read as Polish at 0.63 and Cloud AI wrote its five questions in Polish. Cloud vision also writes a subscript c as
  U+A700 (a Chinese tone mark; it renders as a stray glyph and nothing can search for it): `String.withPlainSubscriptC` makes it a plain "c".
- **Right numbers marked wrong (`AI/Local/NumericAnswer.swift`, `LocalGrader.gradeOwnWords`, `AIRouter.refinableText`).** A calculation's key ideas describe the
  method ("Use η = 1 − Tc/TH") and its answer is a number, so every grader that looks for the ideas called a right number wrong: in the fourteen persona runs
  (3,774 own-words answers) 94 of the 94 right answers to a question whose model answer is only a quantity were not graded correct (72 wrong, 22 partly right; this
  Mac's model 75, Cloud AI 14, the self-check 5; Tariq's physics and Amara's chemistry). When the model answer is nothing but a quantity and the person's answer states the
  same one (a percent and its fraction are the same quantity, the sign must match, a unit must not contradict it, a long answer counts by its last number), the offline grade is
  correct and no model is asked. It never calls an answer wrong: a different number goes to the grader as before, and a right number in another form ("half") is still the
  grader's. Over the recorded answers it accepts all 94 and none of the wrong ones (`tools/numeric/run.sh` in the harness; the one "wrong" answer it accepted was a copy
  of the model answer in the simulated student's wrong list). Tests: `NumericAnswerTests`.
- **Japanese and Chinese (`AI/Local/Lexicon.swift`).** The tokenizer made a whole Japanese sentence one "word" (letters make words, and there are no spaces), so the retriever found nothing for any
  Japanese or Chinese question: five of five of Aiko's, in round 3, gave no hits at all, and the tutor's request fell back to an even sample (the Oath question stayed unanswered). A run of Han, kana or
  katakana is now cut into words by the system's tokenizer (`NLTokenizer`, Japanese when the text has kana, Chinese otherwise; the particles are stop words; ranges still point into the text; one tokenizer per call,
  0.06 s for an 8,800-character article on this Mac), and Latin text beside it is unchanged. The same five questions now get 2 to 4 hits each, the request is aimed (`best`, not `overview`) and holds the answering line, and Cloud AI answers the Oath question
  ("由利公正"). Aiko's whole fortnight rerun on the final lexicon (`runs10/`): 14 days, 13 of 14 questions by Cloud AI, none refused (1 before), her 9 Japanese questions all by Cloud AI. Tests: `CJKRetrievalTests`.
- **Settings no longer says "unlimited" on a paid plan (`Features/Settings/AIPrivacyPage.swift`).** The header is "Your AI" and a footnote says that a day with a lot of Cloud AI pauses it until midnight; round 3's Pro
  cram night reached that limit. The store text and the listing are yours.
- **Paywall fine print (`Features/Paywall/PaywallCopy.swift`).** "Fair use applies." ends the line under the price on every plan, because "Unlimited scans, PDFs and lectures" means no count, not no ceiling: a day with a lot of Cloud AI pauses it until midnight (the relay's
  cost caps). The store description on App Store Connect is not changed (it is the owner's text and says "unlimited" in the same sense). Tests: `PaywallCopyTests`.
- **Diagrams in photos (`supabase/functions/_shared/prompts/tutor-figures.md`, `AI/TutorSelection.swift`).** Tobias's two diagram photos were read well (27 and 42 lines) apart from one letter ("Plant Uptake" came out "Pant Uptake"), but a reading of text cannot say which
  arrow a label belongs to, and Cap guessed ("transpiration") once and said it could not see the picture once. The labels were in the request each time (the "share 0.00" of the first check was only the spelling), so the failure was the tutor's. Two changes:
  (1) the tutor's prompt now ends with a rule for the labels of a photographed picture: if one label is clearly the name of what the question describes, give it and say you cannot see the picture to check it; if several could fit, name them, say you cannot see which
  sits where and ask what the picture shows next to the part meant; never name a part that is not among the words. Measured on the real model with his photos and the whole material (`OPENAI_API_KEY=… deno task tutor-figure-ab`, 5 and 7 questions, 2 runs, the prompt as it
  was (A) against the prompt with the rule at its end (B)): A never said it could not see the picture (0 of 16 picture replies; it answered "plant uptake" and "Surface Flow" directly and said "I couldn't find" for the sign by the pumps and the arrow on the right), a first
  version of the rule said so in 5 of 6 but hedged the two obvious answers too, and the shipped version said so in 7 of 10 (the others were direct answers with the caveat), gave "Plant Uptake" and "evaporation" with the caveat, named the candidates and asked for the two ambiguous
  ones, and left two ordinary questions as they were (54 and 30 percent); four requests in each arm of the second test hit the test account's free tutor limit (the tool now uses a Pro account), so the sample is small. Cost about 17 cents. **Deployed as relay version 13 (the owner's approval); checked on the live relay with his
  material: "I can't see the picture… the printed labels include 'Pumping wells…' and 'Pumping well'… what else can you see near the sign?" for two picture questions, a direct answer (54 percent) for an ordinary one, and, for the arrow from the roots, "I couldn't find a label for an upward arrow among the diagram words" (the one-letter misread again) instead of a confident wrong answer.** (2) A question that points at a picture ("the picture", "the diagram",
  "an arrow", "a label") now names a source whose title says it is a figure, a diagram, a chart or a graph, so such a source is sent first: in a material of 24,850 words (two readings, a novel, a 534-word diagrams source) it was sent for 1 of 3 picture questions and is for 3 of 3, and a question about TCP
  is unchanged. Not fixed: the reader's one-letter misread, and where an arrow points (that needs the photo to go to Cloud AI, which his persona keeps off). Tests: `TutorSelectionTests` (`testAQuestionAboutAPictureSendsTheSourceThatIsMadeOfDiagrams`), the relay's `prompts.test.ts`.
- **Multiple-choice questions the model writes (`supabase/functions/_shared/prompts/generate.md`, tool `tools/generate_ab.ts`).** The right option is the strictly longest in 40% of round 3's 88 cloud-written questions (51% of round 2's rerun, 84; about 25%
  by chance), a tell that shuffling the options (`ChoiceOrder`, per item and per day) does not hide; fill-ins with a guessable blank (54 "too easy" flags in 346 questions) and facts repeated across sources (23 duplicates) are the other
  flags. The generation prompt had no rule about the length of wrong options or the guessability of a blank. Two rules were measured against the real model with the relay's own code path (`OPENAI_API_KEY=… deno task generate-ab --runs 2 <texts>`,
  three English texts: TCP, the Meiji Restoration, *Pride and Prejudice* chapters 1 to 8; 2 runs each; the prompt as it was (A) against the prompt with the rules at its end (B)): A wrote 96 questions, 18 multiple choice with the right option the longest in 13 (72%)
  and on average 1.37 times as long as the wrong ones, and 11 fill-ins of which 1 had a repeated or stop-word blank; B wrote 96 questions, 20 multiple choice with the right option the longest in 9 (45%), 1.06 times as long as the wrong ones, and 10 fill-ins with none.
  The samples are small (18 and 20 multiple-choice questions: the drop in the share is suggestive, the length ratio clearer) and the blank count is only the repeated or stop-word kind, not "too easy". Cost $0.44 (a first attempt that only the short text passed, then the full run).
  The rules are now the last paragraph of `generate.md` (bundled in `generated.ts`) and were **deployed as relay `ai` version 13 on 2026-11-04 with the owner's approval** (with the tutor's picture rule, below). Checked on the live relay with the harness (`bench gen`, two texts, one run each):
  44 questions, 11 multiple choice with the right option the longest in 7 (64%) and 1.10 times as long as the wrong ones (the test's 1.06; the share needs more questions than 11), 5 fill-ins. Next: ask the blind reviewers about "too easy" and repeats, which a script does not count.
  **Measured again on more questions (4 Nov, evening; six new texts of about 1,900 words each: TCP, the Meiji Restoration, Carnot's cycle, a handout on heart medicines, the Declaration of Independence, Kant; 2 runs each, 12 calls an arm, the relay's own code path).**
  The deployed prompt, twice: the right option is the strictly longest in 11 of 36 (31%) and in 10 of 34 (29%) multiple-choice questions, 21 of 70 (30%) in all, 1.01 times as long as the wrong ones: that is chance (25% with four options),
  and the 45% and 64% above were 20 and 11 questions. Stronger wording does not help: a rule asking for the right option to be the longest in one question in four gave 9 of 40 (23%, ratio 0.99), "no more than one in three" 2 of 36 (6%, 0.89), the first
  "three in four" quota 3 of 38 (8%, 0.89) and "same shape, nearly the same length" 1 of 40 (3%, 0.92): the model overshoots and the right option becomes the short one, which is a tell too. So `generate.md` stays as deployed in v13 and no relay deploy follows.
  Fill-ins with a blank the sentence repeats or a stop word: 4 of 19 and 0 of 15 for the deployed prompt, 1 of 20 to 1 of 24 for the others (too few to tell). Cost $1.64 for the 72 calls. `deno task generate-ab --rules a.txt,b.txt` now tests several rule sets in one run.
- **The offline tutor and the iPhone's model after round 3 (4 Nov, evening).** The tutor without Cloud AI still quoted another passage for about two covered questions in five and said "couldn't find" for as many. Measured on 155 questions with the line that answers
  them written down (round 2's 78 and round 3's 77; the gate was set on round 2's) and on 507 study questions the Cloud AI wrote from known lines (the generator's anchors), with the saved pool of the sentence search for every question (`bench rankdump` in the test harness):
  the first sentence is the answering line for 19% of the 155 (29% in round 2, 9% in round 3) and for 57% of the study questions; it is among the 24 candidates for 59% (69% and 48%) and 91%; the reply shows the line 24 times (15%), another passage 64 (41%), "couldn't find" 67 (43%),
  and it quotes the notes for 5 of the 27 questions they do not cover. Tried on the saved pools, leave-one-student-out, with no gain: nine answer-type signals (a year for "when", a number for "how many", a name for "who", cause words for "why", a definition for "what is"…): the first
  sentence is right for 19% and 56% as before; weighting the existing signals again: 16% and 62%; a learned gate over the gate's own evidence: the same trade-off as the hand-set one (shows 21, wrong 82, refused 52 against 18, 75, 62); 48 candidates instead of 24: the line is among
  them for 71% instead of 59% and first for the same 19%; Apple's whole-sentence vectors: 3% and 29% alone, and added to the score no better (12 to 17%, 50 to 58%). What is left to say for the rules-only tier is that a question put in other words than the notes' is out of reach of word and word-vector matching: showing the
  three closest places instead of one would show the line for 21% instead of 12% of the 155 questions, at the price of two more lines each (not done).
  **Japanese and Chinese (`Lexicon.cjkWords` and `wordCount`, `LocalSentenceSearch`, `LocalRetriever`, `LocalTutor`, `AIRouter+Tutor`).** Every Japanese sentence counted as one word (no spaces), so the search left out each one as too short to say anything, a question in Japanese had no candidate at all (5 of 11 of Aiko's pools were empty),
  and a Japanese passage ran to 60 sentences. A run of Han and kana now counts for about one word per two characters wherever a sentence's length decides something, and the full-width ？ ends a question. The contextual model's similarities run 0.8 to 0.99 for Japanese sentences that are not about
  the question (the floor elsewhere is 0.48), so with the count fixed and the gate unchanged 5 of Aiko's 6 Japanese questions were answered with a wrong passage; a Japanese or Chinese question is now judged on its words (at least half their weight in the best sentence or its passage, `Gate.cjkCoverage`).
  Result: no empty pool, the line among the candidates for 2 of 6 (none before), and "couldn't find" for all six, none wrongly answered; a question that uses the notes' own words is answered (`CJKRetrievalTests`). The notes' words and a question's words rarely match in Japanese (書いた for 起草) and the system has no Japanese word vectors, so
  that stays out of reach without Cloud AI. A shortened word of a question that a word of the notes begins with ("hiper" for "hiperinflación") is no longer "a word the notes never use".
  **What this iPhone's model reads and may quote (`OnDeviceWindow` in `AIRouter+Tutor.swift`, `OnDeviceTutoring.reply`).** It was handed the three passages the keyword search liked best: the answering line was in them for 19% of the 155 questions (56% of the study ones); the passages of the three best sentences hold it for 37%
  (50%), and for 46% (71%) with four keyword passages as well. It answered few questions: with the line in front of it (four students), 10 of 29 replies were accepted, 9 said "not covered", and 10 were thrown out, nearly all by the rule that the quoted passage must carry 40% of the question's words by weight, which a question put in
  other words fails (those I read were right: "the golden rule of Jesus" for "which religious teaching sums up the ethics"). With this Mac's model, the model answered / was right on / was wrong on, of the 155: the keyword passages 20 / 7 / 13; the three best sentences' passages 22 / 12 / 10; those and two keyword ones 22 / 7 / 15;
  five passages of the best sentences 21 / 10 / 11; eight 16 / 8 / 8: a small model reads a few passages well, so it gets the three. A quote it makes is also accepted when it is the sentence the search ranks first, or second within 0.7 of it (`OnDeviceWindow.closest`): 31 / 14 / 17 (32 / 15 / 17 when any of the best eight counted, which let an unrelated sentence through in a two-sentence library: `testAnUnrelatedQuoteSendsTheQuestionToTheOfflineTutorInstead`).
  The whole tier, with the offline tutor behind it, by the automatic check: the answering line shown 23 to 25 of 155, a wrong passage or answer 74 to 67, "couldn't find" 58 to 63. Blind review of the 42 replies that changed (three reviewers, who did not know which was which; the run with the quote rule at the best eight, the same on 171 of 182 turns as the final): accuracy 0.83 to 1.10 of 2,
  better on 21, worse on 13, level on 8; flagged as another passage 21 to 11, as made up 3 to 5 (the model states what the notes do not: a unit, a reversed mechanism), as wrongly refused 2 to 6 (five are Japanese questions, answered with a wrong passage by the run before the Japanese gate and now declined). The model's replies change from run to run. On a phone, see the next bullet.
  Tests: `CJKRetrievalTests`, `OfflineSearchTests` (the window, the search's own answer), `AIOnDeviceTests` (a quote the search ranks closest).
- **On a phone, the question rewrite, and what was left alone (4 Nov, night).** `Cramless/App/OfflineBench.swift` (DEBUG only, absent from Release; started with `CRAMLESS_OFFLINE_BENCH=1`) measures the offline tutor and this iPhone's model on the device it runs on and writes a report
  (a progress line after every question). Built development-signed for the Loopware team: development provisioning profiles made through the API (`Claude Dev com.loopware.Capling` and `... .Widgets`, the certificate "Apple Development: Wael Abed Elal", both registered iPhones, expiring 2027-11-04; they stay in the account),
  installed with `phone-install` on the owner's iPhone 17 Pro "frankWhite" (iOS 27.0 build 24A437, 11.4 GB of memory, Low Power Mode off) with the owner's approval, the test libraries copied into the app's container with `devicectl`, the report copied back, the dev build removed afterwards.
  Two runs: speed and memory on three libraries (5,500 to 13,400 words), and the whole tier (keyword search, sentence search, the model on the passages, the checks on its reply, the offline reply behind it) on the 14 students' libraries (3,700 to 15,100 words, 92 to 317 passages, 168 questions).
  Reports and inputs: `~/Documents/capling-user-test/after-round3/phone/`. **The offline search on the phone:** the first question of a library (the index of every sentence, the word vectors, the contextual model loading) takes a median 0.57 s (at most 0.67); every question after it 0.20 s on average, 0.41 s at worst;
  memory 74 MB at launch, 110 to 150 MB with the models loaded (149 MB at the peak over all fourteen libraries); thermal state nominal, fair after six minutes of model calls without a pause. Speed and memory are not a problem.
  **The model on the phone:** a window of 8,192 tokens; a call takes a median 2.3 s (p90 7.4 s, at most 9.9 s), a whole question 1.8 s (p90 3.3 s). **Its own `covered` flag was false in all 96 replies it gave** (4 calls returned nothing), so with the rule that a reply needs `covered` the model tier answered none of the 168 questions
  on this phone, in builds 1.0 (3) and (4) too: every answer was the offline tutor's. Of the 96: 74 say in words that the notes do not cover the question, 13 answer with a quote from the notes, 9 answer with empty quotes (the notes' own sentence, restated). Counting the flag as advisory when a reply answers and quotes, and standing on the search's best sentence when the
  quotes are empty (a reply that restates it, at least 60% of its words), gave 17 answers of 168 (7 on the line that answers, 10 not); one blind reviewer rated the 16 against the offline quote each replaces: accuracy 1.50 and 1.50 of 2, better on 6, worse on 7, level on 3 (a restated sentence garbled, a hedge, a passage that says the opposite).
  **Not shipped:** the replies are no better than the quotes they replace and cost 2 s or more each, so the tier stays as it is (inert on this OS build; the offline tutor answers); the changes are kept as a patch (`after-round3/model_tier_covered_flag_restated_and_phone_bench_worktree.patch`). The Mac's model sets the flag and its answers were better (above); a phone whose model does too gets them.
  **Question rewrite, tested and not adopted.** The model writes the sentences a textbook would answer the question with (`OnDeviceExpandCall`), and the sentence search reads their words beside the question's, to find and to rank (never to decide whether the notes cover it): it wrote one for 121 of 182 turns (the others it declined or failed; 0.8 to 2.4 s on the phone, 14 s at the median on the loaded Mac).
  On the 108 questions that got one the first sentence was the answering line for 12 before and 13 after (11% to 12%) with the rewrite counted for half, 15 (14%) counted in full, 13 with the words score counted again; over all 155: 30 before, 31, 33 and 27 after; replies showing the line 24 before, 25, 28 and 22. A few points, within the noise, for a model call a question (one in three failed on the Mac, one in twelve on the phone) that only a device with the model can make: not adopted
  (`after-round3/hyde_expansion_and_phone_bench_worktree.patch`).
- **The model chooses the answering sentence; Japanese and Chinese measured (4 Nov, late night).** The sentence search has the line that answers a question among its best eight for 45% of the 155 real questions and puts it first for 18%, so a model that reads the eight can
  lift the right line a long way. This iPhone's model (the Mac's, here) was shown the question and the eight numbered sentences and asked for the number of the one that answers (0 for none), `OnDevicePickCall`: it chose the right one for 46 of the 148 questions it answered (31%; 69% of the 67 where the answer was among the eight; with five sentences, 44),
  the search's first being right for 27; it chose a wrong one 101 times and said "none" once, and it quoted all 25 questions the notes do not cover, so it cannot refuse and whether the notes cover a question stays with the search's gate. Of the 88 covered questions the gate lets through, the first sentence was right for 18 and the model's choice for 28 (wrong 70 to 57);
  when the model chooses another sentence than the search's first, the first is right 2 times in 49 and the model's choice 13 (27%). **Built in:** its answer is a number, so what is shown is always the notes' own sentence (nothing it writes reaches the student) and it needs no "covered" flag (the phone's model never sets it); the router asks once per question,
  when the gate says the notes cover it and the iPhone's model is available (English), before this tier's window is made, and the chosen sentence goes first for the model's window and for the offline tutor's reply (`choosing` in `AIRouter+Tutor.swift`; `OnDeviceWindow.useModelPick`, `pickAmong` 8; 8 s limit; the search's first stays when the model answers 0, 1, a number out of range or nothing).
  **Whole tier on the Mac, 155 questions with a known answering line:** the reply shows the line 25 times (16%) with the window alone, 29 (19%) with the choice; the model's own answers 31 (14 right) to 41 (21 right); another passage 67 to 65, "couldn't find" 63 to 61, not-covered questions quoted 3 and 3.
  Blind review of the 32 replies that changed (two reviewers who did not know which was which): accuracy 0.69 to 1.03 of 2, grounded 1.09 to 1.38, better on 16, worse on 6, level on 10; flagged as another passage 16 to 12, template-like 9 to 5 (round 3's students, whose notes nothing was tuned on: 0.71 to 1.29, better on 11, worse on 1; round 2's: 0.67 to 0.73, better on 5, worse on 5, level on 5). Tests: `TutorTests` (the choice is shown, the search's first stays when the model cannot choose, no question to the model when the gate says no); the other on-device tests switch the choice off to script the model's own answer.
  **Not yet on a phone:** the owner chose to run that later; the phone's model may choose differently, and a bad choice would be worse than the search's first, so the change is in the commit and **not in build 1.0 (4)**; the phone benchmark (`OfflineBench` with `"choose": true`) is ready (`after-round3/phone/choose_in.json`).
  **Japanese and Chinese.** Test sets of 30 questions each, written by agents from the Japanese Wikipedia article on the Meiji Restoration (492 paragraphs) and the Chinese one on the Xinhai Revolution (357 paragraphs), with six questions each the article does not answer (`bench/tutor_cjk_ja.json`, `..._zh.json`; 19 of the 30 Japanese questions share no word with their answering paragraph:
  deliberately hard). The offline search: the answering paragraph is among the eight candidates for 15 (Japanese) and 20 (Chinese) of 30 and first for 8 and 7; the gate lets 9 and 6 through (right 7 and 4, wrong 2 and 2) and refuses 21 and 24; not-covered questions quoted 2 and 0 of 6. Counting pairs of neighbouring characters (the usual remedy when a segmenter cuts a name differently in a question and in its answer:
  BM25 over the pairs in stage 1 and in the final score, pair coverage in the gate) put the right paragraph first for 9 and 10 of 30, but the answers given did not change (right 7 and 4, wrong 3 and 2): the gate, not the ranking, holds the rest back, and at the best threshold each further right answer costs about two wrong ones; not adopted. The model's choice: right for 10 of 12 (Japanese) and 16 of 18 (Chinese)
  where the answer is among the candidates (the search's first: 9 and 10), 12 of 12 not-covered questions quoted. The iPhone's model tier is English-only by design (`OnDeviceLanguageGate`), so it does not apply to them. These two languages stay mostly declined without Cloud AI (patch: `after-round3/cjk_character_pairs_and_model_pick_worktree.patch`).
- **Tested:** the full app suite on the merged tree: 1,478 tests, 27 skipped, 0 failures (the first run failed 3 of 1,477: the short-notes regression
  above, a phase-recall test that depended on which questions a 16-question set keeps, and a medal render that passed on the rerun). After it came the exact-number check, the tutor's 4,000-word request, the even spread, the Japanese and Chinese word splitting and the Settings copy; on that final tree the
  full suite: 1,493 tests, 27 skipped, 0 failures (an earlier run of the same code failed 60 assertions in five selection tests that assumed the 6,000-word request; they now name the budget they test).
  After build 1.0 (3) was uploaded, the offline tutor and the iPhone model changes above (Japanese and Chinese word counts and gate, the shortened-word rule, the model's passages and quote rule) were made and tested: the full suite on that tree, 1,500 tests,
  27 skipped, 0 failures (the one test added afterwards, `testOnlyTheBestSentenceAndACloseSecondCountAsTheSearchsOwnAnswer`, ran with its class: `OfflineSearchTests`, `CJKRetrievalTests` and `AIOnDeviceTests`, 52 tests, 0 failures). Those changes are not in build 1.0 (3); they are in build 1.0 (4), uploaded and attached (last bullet). The model's choice of sentence (the bullet before this one) came after build 1.0 (4) and is **not in it**: the full suite on that tree, 1,504 tests, 27 skipped, 0 failures, and the tutor classes alone 137 tests, 0 failures.
  After that run the Japanese word splitting was made 5 times faster (one tokenizer per call, 0.06 s for an 8,800-character article); the 19 test classes that use the lexicon and the offline rules ran on the final tree:
  331 tests, 3 skipped, 0 failures (`CJKRetrievalTests`, `NumericAnswerTests`, `GraderTests`, `SelfCheckTests`, `GeneratorTests`, `LocalGeneratorQualityTests`, `QuestionQualityTests`, `GenerationPartsTests`,
  `OfflineSearchTests`, `OfflineLanguageTests`, `TutorTests`, `TutorSelectionTests`, `TutorHonestyTests`, `RelayLimitsTests`, `TutorPrivacyCopyTests`, `AIOnDeviceTests`, `RouterTests`, `AssistantDraftsTests`, `AskTextTests`).
  After the owner's decisions of the same afternoon (the paywall sentence, the tutor's picture rule and figure-word match) the full suite ran again on the tree that was then archived: 1,494 tests, 27 skipped, 0 failures (a first run of it failed one assertion of the
  new selection test, which assumed the ordinary fill never sends a small source; the test now checks the selection mode).
  The relay suite: 237 tests, 0 failures (`deno task test`), `deno task check`, lint and format clean.
- **Rerun with Cloud AI (2026-11-03 evening, after the owner added OpenAI credit at 22:48; relay version 11).** Fresh anonymous users, round 2's materials and
  round 1's, `~/Documents/capling-user-test/round2` (the report's "After the retest" has every number). Cloud AI grading: 167 of 168 answers graded by the model
  (67 before, the rest had fallen to the self-check), 156 of 167 matching the labels, none the wrong way. The tutor on the seven students' 12 questions: the "Quick check"
  closer on 0 of 91 replies (45 before), refusals on covered questions 1 of 78 (3 before), the answering line shown in 53 of 78 (44 before); blind side by side on
  all seven students (84 questions): accuracy 1.80 to 2.00, "couldn't find" while the notes cover it 10 to 0 of 76, better on 12 and worse on 2. Jamal's 14 days: the classmate's wrong Marbury card is now corrected against the
  opinion ("Trust the opinion"), the outline request is drafted (it was declined), Brown and Marbury sets keep 62 questions and drop none (10 of 62 wrongly dropped before).
  Jin's 14 days: both planted deck mistakes get a "trust the reading" answer. Amara's worksheet photo: 5 questions in English (Polish before). Tariq's printout: 6 pages
  flagged and read by Cloud AI (3 before); the derivation photo keeps its subscripts. All seven students' 14 days were rerun on fresh accounts (Jin's and Jamal's twice, the first
  attempt having hit the cap); Cloud AI answered all but a few of each student's questions (the others were requests Cap declines on the phone, or days with Cloud AI switched off). The rerun spent $8.97 (1,450 calls); the first attempts of the tutor bench and of two 14-day runs hit the relay's 10 cent day cap and were redone.
  Two differences from round 2 were looked into afterwards. Tariq's Cloud AI gradings fell from 45 to 6: the router and the offline grader's matching are the same (the final router, with every
  tier open, sends 29 of round 2's 193 answers and 6 of the rerun's 118 to the Cloud first, the counts recorded); round 2's questions had key ideas the rules could not find even in
  a copy of the model answer (four questions came back 19 times, each an exact copy scored at zero key ideas), and this Mac's model gave no grade 16 times (seven runs shared the Mac; the cause was not checked) and the Cloud took over. Hannah's free-limit
  day was not reached in the rerun because the harness changes account every few questions to stay under the relay's 10 cent cap; replayed on one account it gives what round 2
  gave: 10 Cloud AI answers, then 2 from her notes (each now starting with "You've used today's free answers. Here's a hint from your notes instead."). Her ten answers cost 9.05 cents (the 10 cent cap sits just above the free limit).
  A Release build of the fixed tree for iPhone (`generic/platform=iOS`, no signing, no archive) compiled: BUILD SUCCEEDED.

- **The seven students' 14 days on the final code (2026-11-04, harness `bin/ut_final6`, `runs8/` in `~/Documents/capling-user-test/round2`).** The same persona scripts as round 2 on fresh
  accounts, after the number check, the 4,000-word tutor request and the even spread: every tutor question Cap does not decline was answered by Cloud AI (none fell back for want of
  budget) except Hannah's two past her free limit (day 4 on one account: 10 Cloud AI answers, then 2 from her notes, as in round 2; she upgrades on day 6 and gets 13 Cloud AI answers on
  the cram night of day 12); no "Quick check" closer anywhere (14 in round 2); Jamal's court-opinion sets keep 59 questions and drop none (52 kept and 10 dropped); 12 of 12 right numeric
  answers graded correct (none of 94 before). The count of Cloud AI gradings depends on the questions each run wrote (Jin 13, 82 and 72; Tariq 4, 6 and 47), not on the router. The
  experiments and these runs cost $6.91 (1,123 calls) on top of the earlier $17.63; their throwaway users and Sandbox Pro rows are deleted.
- **Round 3: seven more new students on the final code (2026-11-04, harness `bin/ut_final7`, `runs9/`).** Noor (organic chemistry, a free account's heavy day), Mateo (Spanish macroeconomics, Pro), Priyanka (TCP and DNS,
  Pro cram night), Oliver (17, *Pride and Prejudice*, no on-device model), Aiko (Japanese and English history), Tobias (hydrology, three missed days), Grace (US founding documents, a lecture and a deck with planted
  errors, Pro from day 6): people and texts that rounds 1 and 2 never used, a fortnight each, **a fresh account for every active simulated day and none within a day** (the cap and the free limits reset at midnight;
  90 accounts), no cost-based swaps. Results: 111 questions to Cap, 100 answered by Cloud AI (the 6 others: Noor's 2 past her free limit, Priyanka's 4 at the day cap), 2 "couldn't find", no "Quick check" closer
  (14 in round 2), 346 questions kept and 3 dropped; the nine gold questions each (62 replies, 56 whose answer is in the notes): all from Cloud AI, 0 refused, the answering line shown in 42 of 56. Seven blind
  reviewers: 346 questions accurate 1.97, clear 1.82, useful 1.66, well formed 1.69 of 2 (round 2's 398: 1.85, 1.65, 1.56, 1.65), safety failures 0 (4 in round 2); the gold replies accurate 1.87, grounded 1.89,
  pedagogy 1.81, a covered question answered "I can't find it" in 4 of 56. Found and done: see the report's "What round 3 found". The round, its reviewers' inputs and the checks of the request size cost $3.93 (778 calls); its 115 throwaway users and 32 Sandbox Pro rows are deleted. The follow-ups after it (Aiko's rerun, the production cap check, the tests) cost $0.69 (109 calls) on the relay, and the prompt A/B $0.44 directly on OpenAI through lockbox; their 26 throwaway users and 1 Sandbox Pro row are deleted.
- **Build 1.0 (3) (2026-11-04).** `CURRENT_PROJECT_VERSION` 3, archived on this Mac from this commit's tree (the notes aside) and exported as an IPA signed
  `Apple Distribution: Loopware LLC (6XH75DGC66)` with the App Store profiles `Claude App Store com.loopware.Capling` and `... .Widgets` (get-task-allow false, no device
  list; the widget extension is 1.0 (3) too). The relay host and the public anon key are compiled in from the gitignored `Secrets.xcconfig` (blank again after the archive).
  The IPA's SHA-256 is 392fea19298cb5eeded078c516c82810e9a8f6db18f969e128de4585faf37b23; files, gitignored: `Cramless/build/archive/Capling-1.0-3/` (`Capling.ipa`, `Capling.xcarchive`).
  **Uploaded to App Store Connect on 2026-11-04 at 17:57 with the owner's approval** (altool with the Loopware API key, delivery 88a0b0f6-b24d-44a9-9692-b37a45c37121), processed to `VALID` in three minutes and **attached to version 1.0 in place of build 2**
  (`capling_asc.mjs build 3`); the version is still `PREPARE_FOR_SUBMISSION` and there are no review submissions: nothing is submitted. Not on a phone (an App Store build reaches one through TestFlight). The Mac rebooted twice during the work and cleared
  `/private/tmp` each time; the archive was made again after the second one from the committed tree.
- **Build 1.0 (4) (2026-11-04, evening).** `CURRENT_PROJECT_VERSION` 4: build 3 plus the offline tutor and iPhone model changes above, archived from the committed tree (the notes aside, and a doc comment) with the real host (32 characters) and anon key (208 characters)
  compiled in (the settings file blank again afterwards), exported with the same profiles (version 1.0 (4), widget 4, `Apple Distribution: Loopware LLC`, get-task-allow false, no device list). SHA-256 2b70b68f00301341740ade3d6d57b4f1c711049cf086e2e60a2ecc3aa3ab5407; files, gitignored:
  `Cramless/build/archive/Capling-1.0-4/`. **Uploaded at 19:50 with the owner's approval** (delivery 6b6f8051-034d-4dc7-9016-14012734af8b), `VALID` at 19:53 and **attached to version 1.0 in place of build 3** (`capling_asc.mjs build 4`); read back: version 1.0 `PREPARE_FOR_SUBMISSION`,
  build 4 `VALID`, no review submissions. Nothing is submitted; not on a phone.
- **Apple's answer tier is off (2026-11-04, night; not in a build yet).** `AIBuild.onDeviceModelEnabled` is now `false`. The AI ladder is Cloud AI (OpenAI, through the relay) first and the offline rules
  below it; the iPhone's Apple Intelligence model sat between them and answered only with no network, no consent or the allowance used up, and was judged too weak for tutoring and grading in this app. The probe now answers
  `.unavailable(.disabledByBuild)` on every iPhone, so the tutor, the grading of answers in the student's own words, question writing, lecture notes and cards that had a model step take their offline path
  (`LocalTutor`, `LocalGrader`, `LocalGenerator`, `LocalLectureNotes`), which is what a phone without Apple Intelligence did already. The code stays: the switch is the one place to turn the tier back on, and the model's choice of
  sentence (`OnDeviceWindow.useModelPick`) and the iPhone-model tests keep running on `FixedOnDeviceProbe`. Copy that promised "your iPhone's own AI" went with it: Settings ▸ AI and privacy shows no "This iPhone's own AI"
  card and its free-limits footnote says "the offline rules", and the onboarding badge "On-device first" is "Works offline". `SystemOnDeviceProbe` takes `buildEnabled:` (default the switch) so a test or the phone lab
  (`OfflineBench`, DEBUG) can still look at the model. Tests: `AIOnDeviceTests`, `RouterTests`, `SelfCheckTests`, `LocalizationTests` and `TutorPrivacyCopyTests` (78, all pass; the others use a fixed probe and do not see the
  switch; the full suite was not run). Build 1.0 (5) is the first build without the model tier.
- **Build 1.0 (5) (2026-11-05, 00:47).** `CURRENT_PROJECT_VERSION` 5: build 4 plus commit 056ae19 (the iPhone model's choice of sentence, dormant now) and 9068eff (the Apple tier off), archived from commit d6d258a with the real host (32 characters)
  and anon key (208 characters) compiled in (the settings file blank again afterwards), exported with the same profiles (version 1.0 (5), widget 5, `Apple Distribution: Loopware LLC`, get-task-allow false, no device list, iPhone only). SHA-256
  b9a3dd17cde15000acc9b97dd2b50d07787412e347636bb6ace55ebf00eca5e5; files, gitignored: `Cramless/build/archive/Capling-1.0-5/`. **Uploaded at 00:48 with the owner's approval** (delivery 10818e3f-0a3c-4e34-8a03-2e3e5e244018), `VALID` at 00:51 and
  **attached to version 1.0 in place of build 4** (`capling_asc.mjs build 5`); read back: version 1.0 `PREPARE_FOR_SUBMISSION`, build 5 `VALID`, no review submissions. Tested before it: the 78 tests of the five affected classes; the owner chose to upload
  without the full suite, which has not been run on this commit. Nothing is submitted; not on a phone.
- **What a smaller cloud-tutor request saves (2026-11-05; the app is unchanged).** `TutorSelection.tutor` sends up to 4,000 words (about 89 passages, 10.5k tokens, a cent at Terra's $1 per million input tokens). The app's own selection was run
  for the 14 test students' 168 questions at four word budgets (harness command `bench request`; 141 questions have a gold line): in how many the gold line is inside the request, at 4,000 words 134 of 141 (95%), 2,000 words 110 (78%),
  1,000 words 89 (63%), 500 words 68 (48%) (a named source and the 12 best passages of the others go whatever the room, so the small budgets send 2,160, 1,317 and 909 words). Then 56 of those questions (4 covered per student) went through the
  relay's `tutor` route with the real key (`supabase/functions/tools/tutor_cost_ab.ts`: the relay's prompt, Terra at low effort, 224 requests, $1.48, and $0.48 for the merge check below), the replies scored against the gold lines with the offline check's scorer:
  tokens in 10,575 / 6,638 / 4,790 / 3,891 (counted beforehand with a stand-in tokenizer, o200k_base: 10,515 / 6,579 / 4,731 / 3,832), about 110 tokens out (0.055 cent); **cost per answer as the relay logs it 1.10 / 0.72 / 0.47 / 0.35 cents**
  (-35%, -57%, -69%; the shorter prompts also read 14% and 28% of their tokens from the cache, with no cache 1.11 / 0.72 / 0.53 / 0.45, -35%, -52%, -60%); **replies that show the gold line 40 / 33 / 26 / 20 of 56** (71%, 59%, 46%, 36%). With the
  line missing from the request the model mostly says it cannot find it (10 of 18 at 2,000 words, 17 of 26 at 1,000, 20 of 34 at 500) and otherwise answers from another passage. So a smaller request costs answers faster than it saves money:
  the 35% cut at 2,000 words loses 7 correct answers in 56. The offline sentence search does not rescue it: its best 12 sentences (570 words) hold the line in 80 of 141 (57%).
  **A cut that keeps every word:** a 4,000-word request is 88.5 passages but only 22 distinct pages, and each passage costs a `<source id=... title=...>` wrapper (about 36 tokens). Sending the neighbouring passages of one page as one block
  (the same words), the same 56 questions: 8,066 tokens in (-24%), **0.85 cent per answer (-23%), 43 replies show the line against 40** (6 gained, 3 lost: noise, not a loss), 1.41 citations an answer against 1.46. `TutorSelection` already joins
  neighbours in its whole-material mode and credits a quote to the member that holds it; doing the same in the other modes is an app change that was not made. Scripts and outputs: `~/Documents/capling-user-test/after-round3/cost/`.

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

### Stage 1: money and trust (2026-11-06, lane `s1-trust`)

- **Paywall** (`PaywallCopy`, `PaywallView`): "With Pro" names only the AI work ("AI scans, PDFs and lecture notes, no weekly limit",
  "Every answer graded by Cloud AI", "Cap's answers and drafts, no daily limit", "Web research from trusted sites", the last hidden under
  18). An "Always free" card (`AlwaysFreeCard`, `PaywallCopy.alwaysFree`; scroll id `free`) sits between them and the plans; Settings ▸
  Subscription and Help show it too. Mock exams join its list when they ship (one row after the plan row). The old free-plan footer line
  is gone; "Fair use applies." stays in the terms. `PaidFeature` lost `practiceTests`, `multipleExamPlans` and `projectedGrade` (nothing
  gated them).
- **Exam Pass** (`ExamPassOffer.isEligible(plan:examDates:now:calendar:)`): offered only while the soonest upcoming exam is 8 to 21 days
  away (`StoreCatalog.examPassQuietDays = 7`): the paywall's "Continue free", onboarding after its paywall, and the exam page
  (`ExamPresentation.offersExamPass(plan:examDate:examDates:now:calendar:)`, which also needs that exam itself in the window). Settings ▸
  Subscription lists it at any time.
- **What's free, said first** (`AllowanceCopy`, from `ai.freeCloudUsesLeft(for:)`, nil on a paid plan, without consent or for a child):
  lines under the + sheet's Scan, PDF and Record rows and its footer, under "Scan pages" in the scanner's fallback (VisionKit's own camera
  has no room for it), and in the recorder's "Making notes" line (read when stop is pressed). In sessions a free limit is a line with no
  button (`SuggestionBanner(inSession:)`), and Explain my mistake shows no "See Pro" (`CapMessageView(allowsUpgrade: false)`); the
  consent offers keep their buttons.
- **Nothing lost mid-answer** (`Features/Session/SessionKeep.swift`, `App/AppModel+SessionKeep.swift`): own-words drafts in
  `capling.session.drafts.v1` (30 at most, 7 days, saved after a 400 ms pause and when the app leaves the screen, restored into an empty
  editor as "Kept from before", cleared when the answer is recorded); `SessionCheckpoint` in `capling.session.checkpoint.v1` (written at
  start, at each question and on leaving the screen, cleared on finish or leave), so a daily, catch-up or eve session iOS closed picks up
  the same day in the same `StudySession`, with the minutes it had left and the drafted question first; `finishSession(_:wallStart:)`
  counts only the time it was on screen. A rebuilt queue, not the exact one: questions answered before the close are scheduled and only
  come back if due again. Launch's lecture recovery returns what it kept and says so: "Cap kept your lecture up to 41:20." with Open (a
  `ToastAction`; toasts can act now), or "Cap kept 2 lectures that were cut off." (recordings under 10 s are not mentioned).
- **Help** (Settings ▸ More ▸ Help, `AppSheet.help`): "Write to a real person" opens `StoreCatalog.supportURL`
  (https://loopware.app/support), with the Always free card, Restore purchases and the version. No reply time is promised. "Questions?
  Ask a real person" (`HelpLink`, its own sheet over whatever shows) sits in the paywall's footer, under Subscription's card, and beside
  the free-limit lines (Ask's suggestion card, the draft review's limit card, the capture problem screen, the tutor's and assistant's
  cost-cap notes), never inside a session.
- **Ask's composer** sits on a solid dock (`AskDock`: the screen colour and a hairline), so the chat no longer shows through behind it.
- **Age check** (`AgeRange.checkIfNeeded`, `AgeCheck`): asked once in onboarding, right after the four questions (before consent and the
  tutor depend on it), and once a moment after launch for someone who finished onboarding before. Never again after an answer, a "Don't
  share" or a system with no answer (`capling.ageRange.v1`); a passing failure (no network) is tried at later launches, three times in all.
  Declined or unanswered, the band stays unknown and the level fallback applies as before (no level: adult rules). Skipped in the harness,
  in tests and on the simulator, which has no answer: **a device check**.

### Stage 1: the new Today, plan first (2026-11-06, lane `s1-today`)

- **The band** (`TodaySkyHero`, `HeroWorld`, `HeroWorldGeometry.band(width:topInset:compact:)`): 188 pt under the status bar on every
  phone, Cap 96 pt on the shore, a strip of lake that mirrors nothing (`reflects`), the dusk's glow and the top scrim shortened
  (`glowReach`, `scrimReach`). The welcome builds its own geometry and keeps `style: .world` (its numbers are tested unchanged).
  Greeting by the hour (`TodayCopy.greeting`), streak pill, avatar, "17 stars dimming" (plural key). A tap anywhere opens the full sky:
  `HeroFocusCard`, `HeroFocusPlacement`, the band's camera moves and constellation hit-testing are gone (the full sky keeps its card and
  Practice). The band draws at the screen's rate while anything moves (it was capped at 30 a second: a tilt or a shooting star stepped
  on a 120 Hz screen) and stops when nothing does.
- **The day card** (`TodayDayCard` from `TodayHeroContent.make(snapshot)`): `TodaySnapshot` gains `focus` (the `SessionFocus` exam with
  its topics and `readinessAfter` over today's built session, never below now), `sessionTopics`, `eveTopics`/`eveOthers`, `doneExam`
  (`AppModel.todayDoneExamID()`: the exam today's last finished session counted toward), `practice` (the topic with the lowest mean
  recall), `strip`, `notices`, `greeting`, `firstDay`; `TodayExam` gains `when`, `itemsInScope`, `deltaToday`. The snapshot reads
  `todayPlan()` once. Every state of the plan's table, with "Study · N min" also on catch-up days and "Practice <topic> · 5 min" when all
  is lit. "Why these?" is `AppSheet.todayReasons` (`TodayReasonsSheet`, pure `TodayReasons.make` over `AppModel.todayReasonsInput()`);
  "Study something else" pushes `Route.skyList` (`SkyScreen(startsAsList: true)`). The projection ring is `ReadinessRing(style:
  .projection)` (dashed; the default `.solid` is unchanged).
- **Your plan** (`TodayPlanCard`, pure `TodayPlanStrip.make` over `examPlans()` and the day records): two days back, today, four ahead;
  never red. Quests are one line opening `AppSheet.quests` (`TodayQuestsSheet`, the same `TodayQuestsCard`). "Calendar" opens the streak
  page, whose month now marks each upcoming exam (mortarboard) and its eve (moon), with a legend, and goes one month ahead.
- **Cap noticed** (`CapNotice` in `Engine/CapNotice.swift`, `App/AppModel+Notices.swift`: `todayNotices()`, `snoozeNotice(_:)`,
  `perform(_:)`): today's open mix-ups, most missed first, at most three, as cards with "1 of N", "Fix it · 2 min" and Later (the old
  snooze store, so Stage 2's ledger can import it). Stage 2's engine replaces the adapter and keeps the type. On the eve the slot is
  `TodayQuietLine`.
- **Exams** (`TodayExamsRow`; `TodayAddExamCard` with material and no exam): "See all" pops Progress to its root and selects it. The exam
  editor asks for a course name when there is no course (`ExamDraft.newCourseName`; `createExam` makes the course).
- **Removed:** `TodayExamCard`, `TodayOtherExams`, `TodayCapNote`, `TodayQuickAdd`, `TodayHeroActions`, the Squad row, `HeroFocusCard`,
  `HeroFocusPlacement` (and its tests), `HeroWorldGeometry.make`/`bandShare`/`bandLimits`, the old hero lines' plural keys.
- **Hooks:** `CRAMLESS_TODAY=partway|split|noExam` (new; `done` fills the done card's exam), `CRAMLESS_TODAY_NOTICES`,
  `CRAMLESS_TODAY_WHY`, `CRAMLESS_TODAY_QUESTS`, `CRAMLESS_TODAY_LATER`, `CRAMLESS_TODAY_TYPE`, routes `todayWhy`, `quests`, `skyList`; `CRAMLESS_HERO` keeps only
  `x…y…` taps; `CRAMLESS_CANVAS=375x667` applies to Today. Scripts: `films_hero.sh` (no constellation taps; a Reduce Motion film),
  `j_game.py` (opens the quests sheet), `j_study.py` (the exams row's tile), `j_sky.py` (the band's pill).

### Stage 2: sessions and a calm chat (2026-11-06, lane `s2-sessions`)

- **Undo: hold, then commit** (`SessionRunner`): a review log is append-only once sync has pushed it (about 2.6 s after a save), so nothing is recorded and reverted.
  `Options.undoWindow` is nil by default (tests, onboarding, the quick check); `SessionView` sets 5 s, 15 s with VoiceOver. `record(…, undo:)` holds a self-given
  rating as a `PendingGrade` (reviewID, rating, time, day key, `queueBefore`, how the question comes back) and moves on from `AppModel.previewReview`, which shares its
  scheduling with `recordReview` (the same due load, deterministic fuzz), so the preview is what recording does. `commitPending()` goes through the idempotent
  `recordReview(…, at:, dayKey:, reviewID:)`: on the timer, the next answer recorded, a question left without an answer, finish or close, the app going to the
  background (not merely inactive), and disappear. `undoPending()` restores the queue (a re-queued copy goes with it). `Phase.wrapping` is "That was the last one."
  (`SessionWrappingView`); the summary starts on commit. Undoable: flashcard ratings and swipes, own-words marks, "Counts as". A question view picks up its state
  with `takeRestore(for:)`: no regrade, no sounds, no read-aloud. A draft goes on commit, not on submit; `hasRecorded` is true for a held rating, so a view leaving
  doesn't write its draft back. The checkpoint follows the question on screen through an Undo. A crash inside the window loses that one rating (its question and
  its draft are still there when the session picks up). `advance(arriving:)` gained a default parameter and `record` a defaulted one; the rest of the API is as it was.
- **`UndoPill`** (`SessionParts.swift`): glass, ⌘Z, an overlay on the question's content (`sessionUndoSlot`), above the footer. Not on the bar: past the safe-area bar's own
  bounds it shows and takes no tap. It waits for the next question to land, and hides once that one is checked. Interval labels refresh when the held rating is
  recorded (it moves the session's due load).
- **The swipe** (`Questions/FlashcardSwipe.swift`): pure `SwipeRule` (35% of the width or 700 pt/s, a flick back is a change of mind, direction lock after 12 pt at
  1.5 times sideways); `FlashcardSwipeState` holds the offset, read only by `FlashcardSwipeLayer`, so a finger's move doesn't re-run the question's body. The gesture is
  simultaneous with the scroll view, and a `GestureState` springs the card back if the system takes the touch away. Fly-out inside the view with an animation
  completion; the next question rises (`Arrival.rise`). Footer: the chips, the tiles; `usesGrid` for accessibility sizes, VoiceOver and Switch Control. ← → and 1 to 4 keys.
  `SessionRunner.flashcardTally` counts ratings, a held one included; the view reads it once as the card comes up.
- **Quiet mode** (`AppSettings.quietMode`, Settings ▸ Study): `applyFeel`, `CelebrationFacts.quietMode`, `NotificationPlanner.Input.quiet`, `WidgetSnapshot.quiet` (optional, so an
  older snapshot reads; `forTodayWidget`), `TodaySnapshot.quiet`, `SessionRunner.liveCombo`/`shownRun`, the summary (clears `GameOutcome` after `settleGame()`, so the
  bits are written and nothing shows), Progress, the Streak page (only the calendar), the rollover's toast, the export. Other lanes' Cap cards need no change unless
  they mention the streak; Welcome back should check it.
- **Ask's calm chat:** `AskTitleMenu` (the title is the course menu), `AskDock` with `FreeAnswersNote`, `AskDockChipRow` over pure `AskDockChips.make` and `AskStarters.chipLabel` (hidden once
  words are typed, height kept until the starters are ready), `TutorModePill` in `ChatComposer` (a popover; locked under 18) and `onCamera`, the slot for Stage 3's camera (nothing passes it yet).
  `AskEmptyState` is Cap, one line, one chat to pick up. Follow-ups "Explain it simpler" and "Make 3 flashcards" (the assistant when ready, else `AppSheet.makeCards(threadID:, maxItems: 3)`).
  `TutorModeControl` and `CourseMaterialChip` are gone.
  At the accessibility text sizes the style takes a line of its own in the composer, and the chips stay one scrolling row (the appendix's two-line flow left no room for the chat).
- **Scripts:** `journeys/moves.py` (the chips and tiles), `journeys/j_ask.py` (Cap's style in the composer, the short chip).
- **Verified (2026-11-06, on main cd6ad9c plus this lane):** the whole suite, 1,657 tests, 27 skipped, no failures. Real drags and taps on the simulator: a slow drag past the line, a short one
  springing back, a flick, a vertical drag and a swipe on an unflipped card doing nothing, Undo by a tap on the pill (flashcard and own-words marks), the app going to the background
  committing the last question. Not checked: haptics, ⌘Z and the arrow keys with a hardware keyboard, a live VoiceOver session.

### Stage 1: fixes after the first review (2026-11-06, lane `s1-polish`)

- **The day card names the nearest exam.** `SessionFocus.make` takes `now` and `calendar`: an exam within 7 days holding at least 20% of
  the session's seconds is the focus (soonest first); otherwise the old rule (at least 40%, the most seconds, ties to the sooner). The
  session itself is unchanged; `trackedExam` follows. `SessionFocus.topicsWeakestFirst(readiness:)` orders the card's title by readiness
  for that exam, the order "Why these?" reads.
- **"Why these?" says only what is true in any order** (`TodayReasons`, `Input.daysLeft`/`focusSeconds`, `Other.seconds`/`due`): "a few"
  only when each other exam has less of today than the focus, "further off, so a smaller share" only when that is true of them all,
  "because they're due" only when none of their questions is new.
- **One number for the eve.** `BuiltSession.tonightMinutes` (the built session's planned minutes, rounded up, at most 10; 0 with nothing to
  review) drives Today's button, its spoken words, its reason and tonight's mark in the strip, and on the exam page the button, its line
  and the plan's "Tonight". An eve ahead in the strip shows `PlanDay.shownMinutes`, what the exam page's stop shows. With nothing to review
  the exam page has no button and its stop says "Tonight · nothing to review". The evening notification still says "10 minutes of weak spots"
  (written ahead of time).
- **A picked-up session** (`SessionRunner`): the clock counts from the time already spent (the checkpoint's wall seconds, or the session's
  active seconds if those are more; the closed time is never in it), and the bar starts with the earlier answers (`earlier`, from the log;
  `segmentCount`, `segmentPosition`). A run of right answers still starts with this runner. The Live Activity still counts this runner's
  questions only.
- **The summary's delta** (`SessionSummary.readinessDelta`) is the difference of the two rounded percentages, so "53% → 67%" sits beside +14%.
- **Layout.** Toasts sit on `CLColor.surface` with a hairline and a shadow (glass let the greeting and the streak show through).
  `ReflowPill` wraps whenever it doesn't fit, not only at accessibility sizes; the exams row uses it, and its tiles are sized so the next
  one peeks (`TodayExamsRow.tileWidth`). The day card's chip row is a `ViewThatFits`. `DotLine` (parts on one line, or one part to a line) is
  used by the exam page's hero, the summary's readiness line, the done card's line and the chip's when-line. `FittingLabel` really picks the
  first title that fits; the all-lit button and the exam page's practice button shorten to "Practice · 5 min", and the all-lit reason names the topic.

## App Store Connect (2026-11-01)

The Capling record on the Loopware team (app 6828649543) is filled in by `scripts/asc/`. Every command is re-runnable and has
`--dry-run`; `capling_asc.mjs --account loopware ready` lists what the version still lacks.

- **Listing** (`capling_asc.mjs listing`): the English words are in `capling_copy.json`, the other 38 languages in
  `capling_copy_locales.json` (machine drafts for a native read; en-AU, en-CA and en-GB reuse the English words). Support URL
  `loopware.app/support`, privacy URL `loopware.app/privacy`, Education and Productivity, age rating 4+, content rights, App Review
  notes, eight iPhone screenshots (en-US only; the other languages fall back to them), the header and Search card in all 39 languages.
- **Preview video** (`scripts/store_video/`, README there): a 25 s portrait motion piece drawn from the app's own pieces, 886 x 1920 at 30 fps
  with a synthesized score from the app's sound palettes; Cap plays his own animation clips from the app (`CapClips/*.mov`, decoded to frames
  by `scripts/capclips.sh`; a clip's last picture dissolves onto his drawing, so two of them stop a few pictures early). It meets Apple's
  preview spec (audio required) but is drawn, not a screen capture (App Review 2.3.4). Uploaded 2026-11-02 to the en-US App Previews (Asset Library,
  `scripts/asc/capling_preview.mjs`, poster frame 00:00:01:20, ACTIVE; not submitted). A review page is on tshare as `capling-app-store-preview-video`.
- **Price** (`capling_asc.mjs price`): Free, 175 territories.
- **Purchases** (`capling_products.mjs`): the group "Capling Pro" with Squad Yearly $99.99, Pro Yearly $49.99 (one-week trial) and Pro
  Monthly $9.99, and the Exam Pass $14.99 (30 days, non-renewing). The ids are the ones in `Cramless.storekit` and `StoreCatalog`.
  Each has its own App Review screenshot, taken from the harness (`paywall` with `CRAMLESS_PAYWALL_PLAN`, `examPass`).
- **App Privacy**: published (nine data types, each for App Functionality, linked to the person, no tracking). It has no API: it was
  done in the browser, see the app-store-connect skill.
- **Signing**: App IDs `com.loopware.Capling` and `.Widgets` with the App Group `group.com.loopware.Capling`, Sign in with Apple and
  Declared Age Range; the App Store profiles come from the skill's `asc-sign.mjs`.
- **Gate**: the full suite, 1,082 tests run, 24 skipped (the opt-in ones), 0 failures (2026-11-01), run again after the
  `project.yml` change below.
- **Backend (2026-11-02)**: Supabase project `capling` (ref `xwzhopcsdqjvgqntatel`, free plan, org Amplified): the five migrations
  applied, `ai`, `account` and `appstore-notify` deployed, `OPENAI_API_KEY` set (lockbox `OPENAI_KEY_CAPLING_APP-PROD`) with
  `APPLE_APP_ID` and `APPLE_BUNDLE_ID`, anonymous and Apple sign-in on (the bundle ID is Apple's authorized client ID; the native
  ID-token flow needs no client secret). Checked live with one anonymous test user, deleted afterwards: every `ai/*` route (generate
  14 items in 46 s for about 2¢, check, grade, confusions, lecture, cards-from-chat, transcribe-image, the tutor and assistant streams,
  research refused on the free plan), `account/entitlements` (free; a fake purchase is refused), the Squad error paths, `delete-ai-data`
  and `delete` (the token is refused afterwards). Not checked live: the Squad happy path, a real purchase, Sign in with Apple on a
  device, and a real Apple notification.
- **Server notifications (2026-11-02)**: App Store Connect has Version 2 with
  `https://xwzhopcsdqjvgqntatel.supabase.co/functions/v1/appstore-notify` for both Production and Sandbox (set with `PATCH /v1/apps/<id>`
  and the four `subscriptionStatusUrl*` attributes; a read straight after the PATCH can show null for a few seconds).
- **Before real users**: the free Supabase plan pauses a project after a week idle, so upgrade it; set a spend limit on the OpenAI
  project; register `capling.app` (Squad invite links point at it); wire the age check.
- **Build 1.0 (5)** (2026-11-05, after midnight): build 4 plus the iPhone model's choice of sentence (dormant) and the Apple model tier switched off; uploaded with the owner's approval, `VALID`, attached to version 1.0 in place of build 4; nothing submitted for review.
- **Build 1.0 (4)** (2026-11-04, evening): build 3 and the offline tutor and iPhone model changes; uploaded with the owner's approval, `VALID`, attached to version 1.0 in place of build 3, replaced by build 5; nothing submitted for review.
- **Build 1.0 (3)** (2026-11-04): the fixes after the 14-day tests, with the real host and anon key compiled in (details under "App fixes after the 14-day tests"). Uploaded the same day with the owner's approval, `VALID`, and attached to version 1.0 in place of
  build 2 (which does not contain the fixes); replaced by build 4 the same evening; nothing submitted for review.
- **Build 1.0 (2)**: the full suite passed on a blank `Secrets.xcconfig` (1,082 run, 24 skipped, 0 failures), then the Release archive
  was made with the real host and anon key compiled in, uploaded and attached to version 1.0 (`VALID`). Build 1 is superseded.
- **Build 1.0 (1)**: a Release archive for iPhone only, signed with the Loopware distribution certificate and the two App Store
  profiles, uploaded with altool and processed to `VALID` in about three minutes; `capling_asc.mjs build` attached it to version 1.0.
  TestFlight's internal state is `READY_FOR_BETA_TESTING`. No relay is compiled in (see below).
- **Found on the way**:
  - `Secrets.xcconfig` is blank, so a store build has no relay: no Cloud AI, Ask Cap's assistant, sync, sign-in or Squad (`AppConfig`
    mode `local`, "On this iPhone only"). The listing describes them, so either the backend is up before submission or the text is trimmed.
  - `AgeRange.refresh` has no caller and `settings.level` is only set in demo data, so `ageBand` stays unknown and nothing that
    depends on it engages: the under-13 and teen limits (hints first, no web research, "Let Cap do it" locked) never apply. The privacy
    policy and the App Review notes make no such claim, and the age-rating answer `ageAssurance` is false until it is wired in.
    (Wired in Stage 1, see "Stage 1: money and trust"; still to be checked on a phone.)
  - XcodeGen gives an app target the device family "1,2" unless the target sets its own, whatever the project-wide value says, and an
    iPhone-only, portrait-only app then fails upload with 90474. `project.yml` now sets "1" on both targets.
  - Loopware's privacy page had no Capling section. It is drafted on the branch `capling-privacy` of the loopware-landing repo
    (commit e92c033), not pushed.

## Left for the owner

- Accounts and keys (see README "Before the App Store"):
  - a Supabase project
  - the OpenAI key every AI route runs on (see "Ask Cap on OpenAI")
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
- The relay's cost caps (`DAILY_COST_CAP_USD` 10 cents for the free plan, `PAID_DAILY_COST_CAP_USD` 40 and `PAID_WEEKLY_COST_CAP_USD` 70 cents for paid plans): **deployed as `ai` version 12 on 2026-11-04, with the owner's approval**
  (`lockbox run SUPABASE_ACCESS_TOKEN -- supabase functions deploy ai --project-ref xwzhopcsdqjvgqntatel --use-api`; the only relay code that changed since version 11). Why: the third user test's Pro student on a cram night (14 Ask Cap
  questions) got 10 answers from Cloud AI and then 4 from her notes with "That's all the cloud AI for today", under a Settings header that said "Your AI, unlimited" (the header is now "Your AI" with a footnote). A yearly Pro nets about
  12 cents a day (`cost.ts`), so the 40 cent day sits inside a 70 cent week (7 x the old 10 cents): the most a paid person can cost in a week is what it was, and a cram night is possible. **Checked in production:** a Pro test
  account asked 13 tutor turns in a row: 12 answered by Cloud AI (11.61 cents on the relay's log; the 12th began past 10 cents, where version 11 stopped a Pro account) and 1 declined offline as an essay request. Version 13 (2026-11-04, the owner's approval) carries the prompt rules above and below on top of these caps. The defaults are in code;
  the secrets `PAID_DAILY_COST_CAP_USD` / `PAID_WEEKLY_COST_CAP_USD` (0 turns each off) tune them without a deploy. The wording "unlimited" in the store text, if it is there, is the owner's.
- Build 1.0 (5) is uploaded and attached to version 1.0 (2026-11-05, replacing build 4); it is processed (`VALID`, installable through TestFlight) and nothing is submitted. Submitting for review is yours. The store description still says "unlimited scans, PDFs and lectures": the owner chose to leave it (4 Nov; the counts of scans, PDFs and lectures are unlimited, only the Cloud AI part pauses on a very heavy day, which the paywall's fine print and Settings say).
- Prompt quality over the real API: the prompts held up on one sample page with the same models answering
  through subagents (above). Once the key is in, run `deno task live`, then tune with more real pages: other
  subjects, handwriting, long PDFs.
- Smaller follow-ups:
  - Sessions, day records and pages have no `updatedAt`. Every change to a session or a day clears its
    `syncedAt`, and a page goes up with its source's stamp, so nothing is missed. The one approximation: when two
    devices study on the same day, that day keeps the larger total, not the sum.
  - Mock mode's tutor replays one canned script whatever the question.
