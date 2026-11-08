# App Review notes: a draft for version 1.0

For the owner to approve at Launch. Nothing is uploaded. The notes on the version today are `reviewNotes` in `scripts/asc/capling_copy.json`, written for an older build: they say the microphone is only for lectures and don't mention the calendar, Squad or mocks. At Launch this text goes there and `capling_asc.mjs` sends it, with the owner's approval. (That file is the store lane's, so this lane left it alone.)

The first run, the sample page, the paste and the mock card below were walked with real taps on the simulator on 2026-11-07, on the offline rules, with Cloud AI off. The sample page gives 8 questions, and an exam of multiple choice and short answers then says "A mock needs 8 of those, and you have 6". With the passage below added, the card offers 9 questions and "Take it". Not walked, because a simulator can't: the camera, a real microphone, the real calendar, a sandbox purchase, Sign in with Apple. The first run was shortened on 2026-11-08 (the clarity pass) and walked again with real taps from the welcome to Today; adding the exam from Today's card was not walked.

## The notes (3,876 characters; the limit is 4,000)

```text
Capling needs no account or demo login. All of this works on a fresh install with Cloud AI off, unless it says otherwise.

FIRST RUN
Tap "Get started", then "Use our sample page", add the questions and answer the two it asks. iOS may show its age range sheet, and on "Your plan" its notification prompt. Then "Continue", "Continue free". The sample makes no exam, so add one about a week away: Today > "When is your next exam?" > Add exam. Settings is your initial at the top of Today.

MICROPHONE AND SPEECH (audio background mode)
Asked for only on first use. No spoken audio is stored or sent.
- Today > Study out loud > Start: Cap reads questions aloud and hears your answers, also with the screen locked. With Cloud AI on, the words of an own-words answer go to be graded; never the voice.
- + > Record a lecture: records, also with the screen locked, and writes it out on the iPhone. Capling never uploads the recording.
- Library > a course > touch and hold a topic > Teach Cap > Say it.

CALENDAR
Asked for only on "Check my calendar" on Cap's card "Cap can plan around your long days". The card needs an exam within 14 days and two days of study, so a fresh install won't show it: see the attached screenshot. The app reads only the times of events marked busy, on the iPhone. Nothing from the calendar leaves it.

CAMERA AND PHOTOS
Asked for only on first use: + > Scan pages; Progress > an exam > ... > Edit exam > Snap the syllabus; the camera in Ask, for a problem. A syllabus or problem photo is read on the iPhone and isn't kept. Photos come through Apple's picker.

FREE MOCK EXAM
Free, no purchase. A mock needs 8 questions of the exam's kinds, and the sample page gives 6. So: + > Paste text, paste the passage below, Make questions, Add. Then Progress > your exam > Mock exam > Take it.

SQUAD
One plan for up to four people. Needs a sandbox purchase and a sign-in: Settings > Subscription > See Pro and Squad; Settings > Account; Settings > Squad > Invite a friend gives a code. Members see only first names, join dates and, for those who turn on "Show when I've studied" (off by default), a mark on days they finished a session. No messages, no shared notes. Joining takes a code from the owner, who can remove anyone.

CLOUD AI
Off until allowed. Settings > AI and privacy > Use Cloud AI shows the consent sheet: what is sent, and that OpenAI processes it through our server. Off, rules on the iPhone answer. Cap's work is a draft the student approves, unless they turn on "Let Cap do it". Web research is Pro only, off under 18, on a fixed list of sites. With Cloud AI on, the app prepares a last look by itself in the two days before an exam, and answers a question kept for later once online (fetch background mode).

PURCHASES
Pro, Squad and the Exam Pass. "Continue free" and Restore are on the paywall. Plans, readiness and mock exams are free.

ACCOUNT AND AGE
Settings > Account > Delete account. Declared Age Range: under 13, Cloud AI stays off and nothing is sold; under 18, hints first and no web research.

PASSAGE
Meiosis is the cell division that makes eggs and sperm. It produces four daughter cells, each with half the chromosomes of the parent cell. Crossing over happens in prophase I, when homologous chromosomes swap segments of DNA. This creates genetic variation. Mitosis, by contrast, produces two identical daughter cells. Enzymes are proteins that speed up chemical reactions by lowering the activation energy. The active site is the part of an enzyme where the substrate binds. Temperature and pH both change how fast an enzyme works, and too much heat denatures it. Photosynthesis is the process by which plants turn light energy into glucose. It takes place in the chloroplast, and chlorophyll is the pigment that absorbs the light. Cellular respiration releases energy from glucose and takes place mainly in the mitochondria.
```

## What to attach

In App Review Information ▸ Attachment (screenshots from `build/review/launch-words/` in the main checkout, which are demo data):

- `busy-ask-card.png`: Cap's calendar card, which a reviewer can't reach on a fresh install. A short film of the card, the iOS prompt and "Monday looks busy" on the phone would be better. It needs the owner's phone.
- `squad-switch.png`: the Squad page with the marks and the switch, since one reviewer can't be two people.
- `mock-card-after-sample-and-paste.png`: the mock card, reached by the path above.

## Before these go in

1. **Check on the phone:** the age range sheet, the microphone and speech prompts, the camera, the calendar prompt and a sandbox Squad. Cut whatever doesn't happen as written.
2. **The speech prompt.** `SpeechAnalyzer`, `SpeechTranscriber` and `DictationTranscriber` have no authorization call in the 26.0 to 27.2 SDKs; Apple documents the prompt and its purpose string only for `SFSpeechRecognizer`. So the code asks only for the microphone, when the student starts, and the notes don't promise a speech prompt. The purpose string stays until a phone proves it's unused: `scripts/device_probe.sh` now reports the authorization status before and after a transcription.
3. **Teach Cap on a fresh install** needs a topic with at least two usable ideas (`TeachPlanner.minIdeas`), and the menu hides it otherwise. The sample page should have one ("Phases of mitosis" has three questions); check it.
4. **The camera in Ask** shows only with notes and a build with the relay, so a fresh install after the sample page should have it. The simulator has no document camera, so this is unchecked.
5. **Age rating.** See `docs/privacy-wording.md` section 4: `ageAssurance` is false and the rating 4+, and the last section of the notes describes an age check. Settle both together.
6. **Contact details** stay as they are on the record (`capling_asc.mjs` keeps them).
