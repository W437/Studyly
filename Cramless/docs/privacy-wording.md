# Privacy wording for Ask Cap's assistant

Draft of 2026-10-27, for the owner to paste into the privacy policy and into App Store Connect (App Privacy and the age rating).
Every fact below was read from the code, and the file is named; what only a provider or Apple can confirm is in "Check before you
publish" at the end. Nothing here is legal advice. After a change, `python3 scripts/cap_anim/build_privacy_page.py` rebuilds the page
version, with a button that copies the policy section (`build/review/ask-cap-assistant/privacy.html`).

**Correction, 2026-11-01.** Every age limit below (under 13: no Cloud AI; under 18: no web research, no "Let Cap do it", hints first)
is in the code, but nothing sets the age band yet: `AgeRange.refresh` has no caller and `settings.level` is only set in the demo
data, so in a real build `ageBand` stays unknown and none of those limits applies. Do not publish them as facts until the age check
is wired in. Loopware's privacy page (the Capling section drafted on the `capling-privacy` branch of the loopware-landing repo) says
only "made for students 13 and up", and the age-rating answer `ageAssurance` is false. The same reading of the code found that a
deleted item stays on the server, marked deleted, until the account is deleted, and that signing in makes a new account and leaves
the anonymous one behind.

**Update, 2026-11-03.** Ask Cap's tutor used to send four passages that matched the question; it now sends the notes of the course
(everything when they come to about 6,000 words or fewer, otherwise the sources the question names and the best-matching passages),
the cards of imported decks, and the names of the sources. The paragraph and the table row below, and the three screens' words, were
changed to say so. The owner should read them again before the policy is published.

**Correction, 2026-11-03 (later).** Saying that only the notes of the course being asked about go with a question was half of it. With each question Cap gets the notes
of the course it is answering from (every course when none is chosen), and when Cap is asked to look through the notes (the
`search_notes` tool) the passages it finds go too, from any of the student's courses, because a lookup without a course searches them
all (`AI/AIRouter+Assistant.swift`, `searchNotes`). The policy paragraph, the table row and the three screens' words now say both. The
owner reviews this wording before release.

**Update, 2026-11-06 (for Launch).** "Snap the syllabus" sends the words read from a syllabus or a past paper to OpenAI, with the course's name and its topic names, when Cloud AI is on; the photo is read on the iPhone and deleted, and never leaves it (off, the rules read it on the iPhone and nothing is sent). "Add the exam", on a date heard in a lecture, sends that sentence or two to OpenAI once, on the student's tap, with the lecture's title and the course's topic names. "Find it on trusted study sites" in "Fill the gap" sends a topic's name, as web research in Ask Cap already does. No new data type (all "other user content"). Worth a look at Launch: the camera's purpose string says pages become questions, and a syllabus doesn't. The policy paragraph gets one sentence for each of the first two, which the owner reviews at Launch.

**Update, 2026-11-06 (for Launch).** "Snap a problem" in Ask Cap sends the words of a problem to OpenAI, as any other question; the photo itself is read on the iPhone and deleted, and never leaves it. The camera's purpose string now also says "or a problem you're stuck on". The policy paragraph below gets one sentence, and App Privacy needs no new data type (the words are "other user content", like any question). "Answer it later" sends a question the student kept, once there is a connection, in the same request as any other; it can happen in the background and it adds no data. Consent stays at version 3: a typed question and a snapped one are the same kind of data. The owner reviews this wording at Launch.

**Update, 2026-11-06 (for Launch): Study out loud and Teach Cap.** Exactly what happens to a spoken answer, from the code:

- The voice: the microphone runs only during a session (`Lecture/SpokenAnswerListener.swift`). No audio is written to a file or sent anywhere; between turns the buffers are dropped, and during a turn they go to Apple's speech model on the iPhone and are gone.
- The words stay on the iPhone, with one exception: an answer in the student's own words, and what they say to Teach Cap, go to OpenAI through Capling's server to be graded, as a typed answer does, when Cloud AI is on and within the allowance. So "spoken answers stay on the phone" is only true with Cloud AI off. A letter, a fill-in, a flashcard's "got it" and the commands ("repeat", "skip") are read on the iPhone and never sent.
- Nothing said is kept: the review log gets the rating and the score, with no words in it, so nothing said is synced either. A multiple choice logs the option's own text, which is the question's and not the student's words. (A typed answer's words are stored and do sync, so the two are different on purpose.)
- The screens' words changed to match: the consent sheet and Settings ▸ AI and privacy now say "answers you type or say … (the words, never your voice)", and the microphone and speech purpose strings name spoken answers. Consent stays at version 3: nothing has shipped, and it is the same kind of data as a typed answer.
- App Privacy: no audio data is collected, so no new type; the words are "other user content", like a typed answer.
- For the policy paragraph below, one sentence: "When you answer out loud, your iPhone turns your voice into words. Your voice isn't recorded or sent, and if Cloud AI is on, only the words of an answer in your own words go to it to be graded."

The owner reviews this wording at Launch.

## 1. The privacy policy: a section for Ask Cap

> ### Ask Cap, our study assistant
>
> Ask Cap answers questions about your notes and, when you ask, makes things for you: flashcards, quiz questions, a note, an exam on
> your calendar or a practice session. It only works with Cloud AI, which is off until you turn it on, and you can turn it off at any
> time in Settings.
>
> When you use it, Capling's server sends your request to an AI provider to be answered. That includes your message and the recent
> messages in the chat, the notes of the course Cap is answering from (of every course, if you chose All courses): the text of your pages
> and lectures, the cards of decks you imported and the names of what you added, all of it when it is short and otherwise the parts
> that fit your question; when you ask Cap to look through your notes, the passages it finds in any of your courses; and an overview of
> your study, so that Cap can pick the right course: the names of your courses, topics and
> exams, your exam dates, how ready you are, which topics are fading and how many cards are due. If you turn on "Also send page photos", photos of the pages you scan go too. Capling uses OpenAI for all of it: Ask Cap's
> answers, its tools, web research, questions made from scans, grading and lecture notes. Your phone never talks to an AI company
> directly: requests go through our own server.
>
> When you snap a problem you're stuck on, the photo is read on your iPhone and then deleted: only the words, which you check first, go to Cap.
>
> What Cap makes is shown to you first. Nothing is added to your library until you approve it, unless you switch on "Let Cap do it"
> for that kind of thing (accounts under 18 can't), and you can undo what Cap added.
>
> Web research is part of Capling Pro and is not available to accounts under 18. When you ask Cap to research a topic, the topic you
> named, and the name of your course, is sent to OpenAI's web search, which reads pages on a fixed list of trusted study sites
> (encyclopedias, open textbooks, universities, public science and health bodies) and returns a summary with links to the pages it
> used. The sites receive nothing from your device; a link opens in your browser only when you tap it. A summary is saved to your
> library, as a note, only when you tap Save.
>
> We don't store the content of your requests or of Cap's replies on our server, and we never use your notes or answers to train AI
> models. For each request we keep a short record: which feature, which AI model, how many tokens, what it cost us, when, and your
> account ID. We use it to apply daily limits and to keep costs under control. You can delete this record at any time in Settings,
> AI and privacy (your daily counters stay until they reset, so the limits still work), and it is deleted with your account. The AI
> providers process requests under their own API terms and may keep them for a limited time to detect abuse.
>
> Accounts under 13 can't use Cloud AI.

Where each fact comes from:

| Fact | Where |
|---|---|
| Cloud AI is off until allowed; under 13 never; photos are a second switch | `AI/AIConsent.swift`, `AI/AIRouting.swift`, `Features/Settings/ConsentSheet.swift` |
| What the model is sent with each question to Cap: the messages; the notes of the course Cap answers from (every course when none is chosen) as passages: all of them up to about 6,000 words, otherwise the sources the question names and the best-matching passages, at most 100 passages; the cards of imported decks (one passage a card); the names of the sources (`materials`, at most 20); when Cap is asked to look through the notes, the passages the lookup finds in any of the courses (`search_notes`, `AI/AIRouter+Assistant.swift`: a lookup with no course named searches every course); and, for the assistant, the study overview (course, topic and exam names, exam dates, readiness, fading topics, due counts) | `AI/TutorSelection.swift`, `AI/AIRouter+Tutor.swift`, `App/AppModel+AI.swift` (`tutorMaterial`), `AI/TutorDeck.swift` (`TutorMaterial.listing`), `supabase/functions/_shared/assistant.ts` (`studyBlock`), `_shared/contract.ts` (`TutorRequest`, `AssistantRequest`) |
| OpenAI for every AI route (the tutor, the assistant, web research, questions from scans, grading, lecture notes) | `_shared/deps.ts`, `_shared/openai.ts`, `AI/AIConsent.swift` (`processor`), `docs/BUILD.md` "Every route on OpenAI". Change the sentence if the wiring changes |
| Drafts are shown first; "Let Cap do it" per kind; never for under 18; undo | `Features/Settings/AssistantPage.swift`, `App/AppModel+Assistant.swift` |
| Web research: Pro only, never under 18, about 50 trusted sites, summary with links, saved only on a tap, no site learns anything | `_shared/assistant.ts` (`RESEARCH_DOMAINS`), `_shared/plans.ts`, `AI/AIRouter+Assistant.swift`, `Features/Ask/Assistant/WebSourceTile.swift` (logos drawn in code) |
| Content is never stored or logged on our server; OpenAI is called with `store: false` | `_shared/log.ts` (an allow-list of fields), `_shared/openai.ts` |
| The request record: route, model, tokens, cost, time, account ID; "Delete my AI log" keeps the counters | `supabase/migrations/20261022000000_cramless_schema.sql` (`ai_requests`), `cramless_delete_ai_data` |

## 2. The rest of the policy (already true; here so the section above sits in a complete policy)

- **Account:** Sign in with Apple or an email code, or an anonymous session. We keep the email (or Apple's relay address), the account ID
  and a time zone, which decides when daily limits reset. An optional display name, up to 80 characters, is what a Squad's members see.
- **Sync:** when you sign in with an account (an anonymous session doesn't sync). Your courses, topics, pages' text, cards and questions,
  review history, study sessions, daily records and exams are stored in our database; page photos only with "Send page photos" on, in a
  private folder that only your account can read. Chats never sync. Row-level security means an account reads only its own rows
  (`Sync/SyncEngine.swift`).
- **Squad:** members see each other's display names. Nothing else of yours.
- **Purchases:** Apple's subscription transactions are verified by our server and kept so your plan follows you across devices.
- **Deleting your account** deletes all of the above.
- **No tracking, no ads, no analytics SDK.** The app uses no third-party code that collects data (no packages in `project.yml`).

## 3. App Store Connect: App Privacy

"Do you or your third-party partners collect data from this app?" **Yes.** "Used to track you?" **No**, for every row. Every row is
**linked to the person's identity** and its purpose is **App Functionality** (the AI providers behind our server count as partners
that process the same rows; they are not extra data types).

| Data type | Collected | What it is here |
|---|---|---|
| Contact Info ▸ Email Address | Yes | Sign-in by email code, or Apple's relay address |
| Contact Info ▸ Name | Yes | The display name Squad members see |
| Identifiers ▸ User ID | Yes | The account ID |
| Purchases ▸ Purchase History | Yes | Subscription transactions |
| User Content ▸ Photos or Videos | Yes | Page photos, only with "Send page photos": read by AI, and stored with sync |
| User Content ▸ Other User Content | Yes | Notes text, cards (imported decks too), questions, answers, Ask Cap messages, course, source, topic and exam names |
| Search History | Yes | The topics a student asks Cap to research online |
| Usage Data ▸ Product Interaction | Yes | Review history, study sessions and daily records that sync |
| Usage Data ▸ Other Usage Data | Yes | The AI request record (feature, model, tokens, cost, time) and the daily counters |

Not collected: Health and Fitness, Financial Info, Location, Sensitive Info, Contacts, Browsing History, Audio Data (lectures are
transcribed on the iPhone and the audio stays there; only text is sent, and only with Cloud AI), Diagnostics, Advertising Data,
Device ID. The privacy manifest `Cramless/Resources/PrivacyInfo.xcprivacy` now declares the same nine types.

The last four rows (Name, Search History and the two Usage Data ones) are judgment calls under Apple's definitions; they err on the side
of declaring. Before 2026-10-27 the manifest declared five types (Email, User ID, Purchase History, Photos, Other User Content).

## 4. The age rating

Facts for the questionnaire, which changes from year to year (the questions could not be read from here):

- Ask Cap is an AI assistant a student chats with. It never talks to other people, and shows nothing another user wrote.
- It has no browser. Web research is the server reading a fixed list of about 50 study sites and returning a summary; links open in
  the user's own browser only when tapped. Under-18 accounts don't get it, and under-13 accounts get no cloud AI at all.
- Squad shows only its members' display names.

My reading is "no unrestricted web access", but Apple's wording for a 13+ app was not confirmed (`docs/BUILD.md`); answer it when the
questionnaire is in front of you, and tell me what it asks.

## 5. The words inside the app

Kept in step with this page on 2026-10-27: the consent sheet (`ConsentSheet.swift`), Settings ▸ AI and privacy (`AIPrivacyPage.swift`),
and `AIConsent.swift`'s version note. They now say Cap also sees exam dates, readiness and fading topics, and that OpenAI is the only processor (2026-11-02), and that with
each question to Cap the notes of the course it answers from go along (the text of pages and lectures, the cards of imported decks, the names of what was added: all of it when short,
otherwise the parts that fit the question; 2026-11-03), and that when Cap is asked to look through the notes the passages it finds in any of the courses go too (2026-11-03, later). Consent version 3 has not shipped, so it didn't need a fourth; once it has, a change in what is sent is version 4.

## Check before you publish

1. **OpenAI terms.** The app promises "never used to train AI models" and the section above repeats it. OpenAI's API terms say API
   data isn't used for training by default, and it keeps requests for a limited time to detect abuse; read the current terms and,
   if you want the stronger sentence ("not kept"), ask for zero data retention.
2. **OpenAI web search.** Read what its terms say about the queries it makes on a student's behalf.
3. **13 to 17.** OpenAI's rules for these ages are unchecked (web research is off for them; the rest is on, asking first).
4. **If the wiring changes** (another provider, or Private Cloud Compute), change the processors sentence, `AIConsent.processor`,
   and bump the consent version.
5. **The URLs.** App Review needs the Privacy Policy and Terms URLs reachable (`AppLinks`; the paywall hides the links until set).
