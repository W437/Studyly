# Featuring nomination: a draft for version 1.0's launch

For the owner to approve and submit. Nothing was sent: App Store Connect was neither read nor written. Every claim below was
checked against the code at commit 3105a20 (2026-11-07) and `docs/BUILD.md`, and the file is named where it matters. The
publish date is the owner's.

## What Apple's form asks (read 2026-11-07)

From three Apple pages, read on 2026-11-07: the App Store Connect help article "Nominate your app for featuring", its
reference page "Nominations template" (the CSV import's columns and limits) and "Getting featured on the App Store". None of
them shows a "last updated" date.

- **Where:** App Store Connect ▸ Apps ▸ Capling ▸ Featuring ▸ Nominations ▸ **+** ▸ Create Nomination. A nomination can be
  saved as a draft and edited until it's submitted. After that, its type and related apps can't change.
- **Who:** the Account Holder, Admin, App Manager or Marketing role.
- **The fields, in the form's order:** a name for the nomination (60 characters at most); the type (New Content, App
  Enhancements or **App Launch**: "the launch or pre-order of a new app or game"); a description for the editorial team (1,000
  characters at most in the CSV template; the form gives no limit); the publish date (a day, or a range); then, on the review
  page, related apps (up to 10 from the same account), platforms, relevant countries or regions (pre-filled from where the app
  is sold), localizations (pre-filled from the app's), in-app events, up to 5 URLs of supplemental material (documents, files,
  art, a TestFlight public link) and "Helpful details" (500 characters at most in the template: accessibility, inclusivity,
  priority, what is unique about the app or the team). The CSV adds three yes-or-no questions: launching in some markets
  first, a pre-order, and a new in-app event.
- **When:** the help article asks for at least **three weeks** before the publish date ("Getting featured" says at least two
  weeks' notice), and up to three months ahead for wider consideration.
- **What the editors weigh** ("Getting featured"): user experience, UI design, innovation, uniqueness, accessibility,
  localization, and the product page (screenshots, previews, description, ratings). If Capling is being considered, Apple may
  email the Admin, App Manager and Marketing people for promotional art (the App Store's promotional artwork guidelines).

## The fields, drafted

Paste each block as it stands. The counts were checked when this was written.

**Name** (36 of 60):

```text
Capling 1.0: an exam-readiness coach
```

**Type:** App Launch.

**Description** (948 of 1,000):

```text
Capling is a study coach for iPhone, for high school and college students with an exam coming. A student adds what their class gave them: scanned pages, a PDF, pasted notes, a recorded lecture, or a Quizlet or Anki deck. Capling writes questions that link back to the lines they came from, brings each one back just before it would be forgotten, grades answers written in the student's own words by the ideas they cover, and shows how ready they are for every exam, with a plan to the date and free mock exams. Each question is a star in the student's memory sky: it dims as recall fades and lights up again on review. Cap, an illustrated capybara, reacts to each answer with sound and haptics. Lectures are transcribed on the iPhone, and Study out loud quizzes the student by voice with the screen off. Cloud AI is optional and off until the student allows it; without it, questions and grading run on the iPhone, more simply. No ads, no tracking.
```

**Publish date:** the owner's. It must be at least three weeks after the day the nomination is submitted, and version 1.0
should be set to "Manually release this version" so it goes live that day (`docs/release-1.0.md`, step 26).

**Related apps:** none.

**Platforms:** iOS (iPhone). The app is iPhone only (`TARGETED_DEVICE_FAMILY` "1" in `project.yml`).

**Relevant countries or regions:** the form pre-fills the 175 where Capling is sold. Its screens are English only, so I would
name the English-speaking storefronts: United States, United Kingdom, Canada, Australia, Ireland and New Zealand. The owner's
call (open question 2).

**Do you plan to launch in certain markets first?** No.

**Localizations:** the form pre-fills the 39 languages of the listing. Its 35 translations are machine drafts and the app's
screens are English, so I would keep English (U.S.), English (U.K.), English (Canada) and English (Australia). The owner's
call (open question 2).

**In-app events:** none. **A new in-app event for this nomination?** No. **Pre-order?** No.

**Supplemental materials** (up to 5 URLs): none is ready. Everything we have lives on the tailnet or on the Mac, and Apple's
editors can't open those (open question 3):

| What we have | Where it is | Usable as is? |
|---|---|---|
| The store page: the new screenshots, the description, the preview video | tshare `capling-store-page-for-launch`; `build/review/launch-finish/final/en-US/` | No: tailnet only |
| The 25-second preview video (drawn, not a screen capture) | `build/review/launch-store/video/capling-app-preview.mp4`; tshare `capling-app-store-preview-video` | No: a local file |
| The tour: fifteen films of the app used with real taps | tshare `capling-tour` (shared with Anis only) | No: Cabinet gateway, and it predates Stages 1 to 4 |
| The stage review pages (films and screenshots of every screen) | tshare `capling-stage-1-review` to `-4-review` | No: tailnet only, and written for the owner |
| Cap's character sheet | `docs/cap/cap-character-sheet.png` | As art, yes, once hosted |

What I'd send, once it exists: a TestFlight public link (it needs an external testing group, whose first build goes through
Beta App Review), the preview video and the screenshots on a public page at loopware.app, and Cap's character sheet.

**Helpful details** (472 of 500):

```text
Accessibility: Dynamic Type up to the largest sizes with the main action kept in reach, VoiceOver labels on custom controls and rotors in the memory sky, a dyslexia-friendly font, questions read aloud, and Reduce Motion and Differentiate Without Color respected. Declared Age Range: under 13, no cloud AI and nothing sold; under 18, Ask Cap gives hints first. Screens are in English. Spoken choices are understood in English and eight other languages. No third-party SDKs.
```

## Apple's technology in 1.0, as the code has it

For the owner, and for the editors' follow-up if one comes. "On a phone" says whether a phone has shown it: most of this was
built and tested on the simulator, and the TestFlight pass (`docs/release-1.0.md`, step 19) is the first real look. Cut any
line from the nomination that the phone doesn't confirm.

| Technology | What Capling does with it | Where | On a phone |
|---|---|---|---|
| Liquid Glass | The system tab bar, which shrinks on scroll; the + is a tab with iOS 27's prominent role (the search role on iOS 26); floating controls on `.glassEffect` and `.buttonStyle(.glass)`: a session's top bar, the sky, Ask's title, the mock exam, onboarding, the paywall | `App/RootView.swift` (`MainTabView`), 14 files under `Features/` | Not yet |
| Live Activities | Two. A study session on the Lock Screen and in the Dynamic Island (progress, the topic; in Study out loud the question, with Repeat and Skip buttons that work without opening the app). Exam week: readiness and days left, from 7 days out | `CramlessWidgets/LiveActivityWidgets.swift`, `Services/LiveActivityController.swift`, `Shared/OutLoudIntents.swift` | Not yet |
| Widgets and a Control | Next exam (small, circular, rectangular), Today's session (medium, large, rectangular), Streak (inline, circular); the Control "Start today's session" for Control Center and the Lock Screen | `CramlessWidgets/` | Not yet |
| App Intents and Siri | Five App Shortcuts with Siri phrases: start today's session, how ready am I, scan pages, record a lecture, study out loud. "How ready am I?" answers out loud with a ring, without opening the app | `App/Intents/` | Not yet |
| VisionKit and Vision | The document camera (edges, auto-capture, deskew, many pages) for notes, a syllabus and a problem in Ask; text read on the iPhone with `RecognizeTextRequest` | `Capture/DocumentScanner.swift`, `Capture/TextRecognizer.swift` | Not yet |
| Speech (SpeechAnalyzer) | Lectures transcribed on the iPhone (`SpeechTranscriber`, or `DictationTranscriber` with the course's words); spoken answers in Study out loud and Teach Cap. No audio leaves the phone | `Lecture/LectureTranscription.swift`, `Lecture/SpokenAnswerListener.swift` | Not yet (this Mac's speech models only) |
| AVSpeechSynthesizer | Questions read aloud (an accessibility setting) and Cap's voice in Study out loud | `Services/ReadAloud.swift` | Not yet |
| Declared Age Range | Asked once, in onboarding. Under 13: no Cloud AI and nothing sold. Under 18: hints first, no web research, Cap asks before adding. With no answer, only a student who said college or grad school gets the adult rules | `Services/AgeRange.swift`, entitlement in `Resources/Cramless.entitlements` | **Not yet**: the simulator has no answer to give |
| Accessibility | Dynamic Type everywhere, with primary actions pinned at accessibility sizes; VoiceOver labels and values on custom controls and two rotors in the sky ("Dim constellations", "Exams"); Undo waits 15 s instead of 5 with VoiceOver; OpenDyslexic as a setting; Reduce Motion settles to the final frame; Differentiate Without Color; 44 pt targets | `DesignSystem/`, `Features/Sky/MemorySkyView.swift`, `Features/Settings/DisplayPages.swift` | Not yet: no VoiceOver pass on a phone |
| Sound and haptics | Sounds synthesized in code (no audio files), each paired with a Core Haptics pattern; they follow the Silent switch | `DesignSystem/Feel/` | In October's builds on frankWhite, not checked one by one; the swipe's haptic not yet |
| Core Motion | Today's sky band tilts with the phone | `Features/Today/HeroTilt.swift` | Not yet |
| StoreKit 2, Sign in with Apple | Pro, Squad and the Exam Pass, with App Store Server Notifications v2 to the server; sign-in for sync and Squad | `Store/`, `Sync/`, `supabase/functions/appstore-notify` | Not yet (a sandbox purchase is a TestFlight check) |
| Also | SwiftData; Swift Charts on the exam page; EventKit, reading only busy times on the phone; BackgroundTasks for a question kept for later; lecture playback with lock-screen controls; four alternate icons unlocked by streak milestones; the PhotosUI picker (no photo permission) | | Not yet |

**Off in 1.0, so not claimed:** Foundation Models. The on-device tier for questions, grading and the tutor is coded and was
measured on a phone, then switched off (`AIBuild.onDeviceModelEnabled = false` in `AI/OnDevice/OnDeviceCapability.swift`, since
build 1.0 (5)): the cloud and the offline rules answer instead. Private Cloud Compute is coded and off (it needs an
entitlement Apple grants on request). **Not in 1.0:** the app's screens in other languages, iPad, Apple Watch, widgets you can
review from, Accessibility Nutrition Labels, iPhone Duo screenshots. The featuring plan puts the VoiceOver audit, translation
and the Watch after launch.

**How it reads against Apple's list:** experience and design (one button a day, the sky, Cap, the sounds), innovation and
uniqueness (questions that cite their lines, grading by ideas, a projection labelled as one, studying out loud with the
screen off), accessibility (above). Localization is the weak one: English screens, and translated store text that no native
speaker has read.

## Open questions for the owner

1. **The publish date**, and the release option to match (manual release holds an approved build until that day).
2. **Countries and languages:** all 175 storefronts and 39 languages as the form pre-fills, or the English-speaking six and
   English only, as I'd do.
3. **Supplemental material:** a TestFlight public link (Beta App Review first), a public page at loopware.app with the video
   and screenshots, Cap's sheet. Which, and may I build the page?
4. **When to nominate:** before the build is submitted (as soon as a date is chosen, three weeks ahead) or after App Review
   approves it. Apple asks for launch nominations ahead; nothing in the form needs an approved build.
5. **Helpful details:** add a line about you or the team, if you want one. I didn't know what to say.
6. **The phone pass first:** every technology above is in the code, but few have been seen on a phone. I'd submit the
   nomination after TestFlight, without any line the phone didn't confirm.

## Sources

Read 2026-11-07:

- https://developer.apple.com/help/app-store-connect/manage-featuring-nominations/nominate-your-app-for-featuring
- https://developer.apple.com/help/app-store-connect/reference/nominations/nominations-template
- https://developer.apple.com/app-store/getting-featured/
