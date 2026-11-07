# Privacy wording for Capling

For the owner to read at Launch and paste into the privacy policy and App Store Connect (App Privacy and the age rating). Everything
below was read from the code at commit 112198e on 2026-11-07, and the file is named. What only a provider or Apple can confirm is in
"Check before you publish" at the end. Nothing here is legal advice. Nothing here is published. After a change,
`python3 scripts/cap_anim/build_privacy_page.py` rebuilds the page version, with a button that copies the policy section
(`build/review/ask-cap-assistant/privacy.html`). The section as it should appear on Loopware's page is `docs/privacy-page-draft.md`.

## 0. What leaves the phone, now

### Cloud AI

Every row goes from the iPhone to Capling's server (the `ai` Edge Function on Supabase) and on to OpenAI's Responses API, with
`store: false`. The phone never talks to OpenAI itself (`AI/HTTPRelayTransport.swift`, `_shared/openai.ts`).

- **Kept, for every row:** our server keeps no content (`_shared/log.ts` is an allow-list). It writes one `ai_requests` record per request (route, model, plan, status, tokens, cost, time taken, when, account ID) until Delete AI data or the account goes, and a count in `usage_counters` until the account goes. OpenAI keeps what its API terms say (see "Check before you publish").
- **Consent, for every row:** the Cloud AI switch, consent version 3 (`AI/AIConsent.swift`): off until the person taps Allow, and read again before each request (`cloudStillAllowed()`, `AIRouting`). Under 13, as iOS reports it: never. The Consent column names only what is extra.

| What | Data sent | When | Route | Consent, beyond Cloud AI |
|---|---|---|---|---|
| Questions from a reading | Course name, source title, level, language, the page text line by line. A page photo only with its switch | After a scan, PDF or paste is read, or "Use Cloud AI" on its drafts; "Write more questions" for a mock; a gap filled from pages | `generate` | "Send page photos", for the photo |
| Checking those questions | The same lines, the questions written, the source's title and headings | Straight after, with no tap of its own | `check` | None |
| Reading a page from its photo | One page photo, made smaller | "Read it with Cloud AI" | `transcribe-image` | "Send page photos" |
| Grading | The question, its model answer and key ideas, the answer's **words** typed or said, a passage of the notes, level | An answer in the student's own words, in a session, a mock or Study out loud; "Grade again"; what they tell Cap in Teach Cap. Never a multiple choice or a fill-in | `grade` | None |
| A question to Cap, tutor | The last 8 messages, course, the notes (next row), hints or explain, `minor` flag. For "Explain my mistake": the question, the expected answer and theirs | On send. A question kept with "Answer it later" goes once there is a connection, by itself, in the background too (`Services/AnswerLaterTask.swift`): at most 3, dropped after 7 days | `tutor` | None |
| The notes that go with it | Up to 100 passages: the notes of the course Cap is answering from (every course, if All courses): the text of pages and lectures, the cards of decks you imported, the names of what you added. Everything up to 4,000 words on the tutor's route and 6,000 on the assistant's, otherwise the sources the question names and the likeliest passages up to that size (`AI/TutorSelection.swift`) | With each question | `tutor`, `assistant` | None |
| A question to Cap, assistant | The last 10 messages, the notes, the study overview (course, topic and exam names, exam dates, readiness, fading topics, due counts), tool results. The passages `search_notes` finds, in any course when none is named (`AI/AIRouter+Assistant.swift`) | On send, up to 4 rounds | `assistant` | None |
| A problem, snapped | The words the student checked on "Check the problem", as an ordinary question, flagged `fromPhoto`. Never the photo (`Capture/SnapReader.swift`) | On send | `tutor` | None |
| Web research | Topic, focus, course name, `minor` flag, to OpenAI's web search on a fixed list of 40 sites (`RESEARCH_DOMAINS`) | When asked in the chat, or "Find it on trusted study sites" in Fill the gap | `research` | Pro, and not under 18 |
| Mix-ups | Course, each missed question: topic, question, expected answer, the answer given, how many misses | Only after "Fix it now" (`AppModel+Session.swift`) | `confusions` | None |
| Look-alikes | Course, two questions and their answers; nothing of the student's | Only after "Show me" | `confusions` | None |
| Lecture notes | Course, title, the transcript with times, the moments flagged. Never audio | When notes are made from a lecture | `lecture` | None |
| Cards from a chat | Course, the chat's messages | "Make cards" | `cards-from-chat` | None |
| A syllabus or past paper | Course, exam title, today's date, up to 60 topic names, the words read from up to 6 pages. Never a photo: `image` is sent as nil, and the relay drops one if it came | As soon as the page has been read in "Snap the syllabus". Cloud AI off: the rules read it on the phone and nothing goes | `syllabus` | None |
| An exam date heard in a lecture | Course, the lecture's title and day, language, up to 30 topic names, the sentence with the date, the days the phone read from it | Only on "Add the exam" | `exam-mention` | None |
| "Looks wrong?" | The question, its answer, explanation, key ideas and choices; only the lines it cites; the source's title and headings; the reason; the answer given (up to 2,000 characters); their own note (up to 280) | "Ask Cap to check". A report that couldn't go waits on the phone and goes by itself on return to the app or after consent. An own-words "my answer should count" goes to the grader instead | `check` with `reports` | None |
| A harder question | The question outgrown and its answer, course, source title, level, language, one page of at most 60 lines | Only on "Yes, harder" | `generate` with `rung`, then `check` | None |
| The last look | Course, exam title, language, up to 8 of the shakiest questions: topic, question, answer, up to 6 lines each | **With no tap.** On launch and on return to the app, from 48 hours before an exam until 18:00 on its eve, once a day per exam (`AppModel+LastLook.swift`). The sentences stay on the phone | `last-look` | None |
| Quota | Only the session token | Settings, and when a limit is checked, once Cloud AI is allowed | `quota` | None |

### Account, sync, Squad, purchases

| What | Data | When | Where it goes | Kept how long | Who said yes |
|---|---|---|---|---|---|
| Anonymous ID | A random account ID | The first time Cloud AI or a purchase needs the server | Supabase Auth | Until the account is deleted. Signing in starts a new account and leaves the anonymous one behind | Turning on Cloud AI, or buying |
| Profile | First name if given (up to 80 characters), time zone | Whenever there is a session and either has changed (`AccountService.pushProfileIfNeeded`) | `profiles` | Until the account is deleted | The name is typed by the person, or comes from Apple on sign-in. The time zone is not asked |
| Sign-in | Apple's ID token (the email or relay address in it), or an email and its 6-digit code | Sign in with Apple, or the email code | Supabase Auth | Until the account is deleted | Signing in |
| Sync | Courses, topics, sources (titles, file names, the text of pages, lecture transcripts and notes), questions and cards with their schedule, "reported" and "harder version of" marks, typed answers and the option picked (`review_logs.answer`; never a spoken answer's words), review history, study sessions (mocks too, with readiness before and after), daily records with quests, mix-ups, exams with scope, format, and the grades logged (`Sync/SyncRecords.swift`) | While signed in | Supabase tables, row-level security, one account each | Until the account is deleted. A deleted item stays there, marked deleted, until then | Signing in. There is no separate switch, and an anonymous session never syncs |
| Page photos | The photos of scanned pages | While signed in, with "Send page photos" on (`SyncEngine.pushPageImages`) | Private storage folder of the account | Until the account is deleted | Signing in, and the photos switch |
| Purchases | Apple's signed transactions; the account ID as `appAccountToken` when signed in | On launch and after a purchase; Apple also tells the server of renewals, expiries and refunds (`appstore-notify`) | `entitlements`; Apple | Until the account is deleted | Buying |
| Squad membership | Who is in which Squad, when they joined, the invite codes | Invite, redeem, remove, needs sign-in | `squads`, `squad_members`, `squad_invites` | Until they leave or the Squad goes. A code works once and expires in 14 days | Joining or inviting |
| What other members see | First name ("Squad member" or "Squad owner" without one), joined date, who owns it, an account ID their phone holds but never shows; never a time zone (`account/handler.ts`, `membersOf`) | Opening Squad, and for Today's line at most every 15 minutes | The other members' phones | As long as they are in the Squad | Joining |
| The studied-today mark | The person and the day, nothing else: no course, topic, answer or number | 4 seconds after the day's first finished session, once a day. Needs a session, not sync | `squad_activity`; shown to the Squad as "Studied today" | 14 days, pruned when anyone next records. Gone at once on switching it off or leaving the Squad, and when the owner's account goes | "Show when I've studied", off by default, per person |
| Deleting | Nothing new | Settings ▸ Account ▸ Delete account; Settings ▸ AI and privacy ▸ Delete AI data | `cramless_delete_account_data`, the storage folder, the auth user | The rows go. Delete AI data removes the request log and the open scan and keeps the counters | The person |

Apple's own services: Sign in with Apple, StoreKit, Declared Age Range (Apple's sheet; the band stays on the phone in settings, and only a `minor` flag leaves, on tutor, assistant and research requests), and iOS downloading a language's speech model (no audio goes).
A link opens in the browser only when tapped (a research source, Help, Terms, Privacy).

### What stays on the iPhone

| What | What happens to it | Where in the code |
|---|---|---|
| Lecture audio | Recorded to a file, transcribed here, played back here. Capling never uploads it | `Lecture/LectureRecorder.swift`, `Sync/SyncRecords.swift` (no audio field), `SyncEngine.pushPageImages` (page photos only) |
| The voice, in Study out loud and Teach Cap | No file. Between turns buffers are dropped; during a turn they go to Apple's speech model on the phone | `Lecture/SpokenAnswerListener.swift` |
| Spoken words | Read here and gone after the answer, with one exception: an own-words answer, and what they tell Teach Cap, go to `grade` with Cloud AI on. A letter, a fill-in, "got it" and commands never leave. The review log holds no spoken words; a multiple choice logs the option's own text | `Features/Session/OutLoud/OutLoudController.swift`, `App/AppModel+Teach.swift` |
| The calendar | Busy blocks (start, end, marked busy or away), in memory, never a title, place, note or attendee | `Services/BusyCalendar.swift`. The minutes moved stay in the notice ledger. A session's planned length syncs as it always did, and carries no event or time from the calendar |
| A snapped problem's photo | Read here, deleted either way | `Capture/SnapReader.swift` (`discardStaged`) |
| A syllabus photo | Read here, never kept | `Features/Exam/SyllabusFlowView.swift` (`PageImageStore.discard`) |
| Page photos | Kept here, unless both switches above are on | `Sync/SyncEngine.swift` |
| Chats, and questions kept for later | Never sync | `Sync/SyncRecords.swift` (no chat table) |
| Cap's cards, a report's words until it is checked, last-look sentences, half-typed answers, session checkpoints | UserDefaults or local files, never synced | `Engine/Notices.swift`, `Engine/Reports.swift`, `App/AppModel+LastLook.swift`, `App/AppModel+SessionKeep.swift` |
| Settings (age band, level, reminders) | Never synced | `Model/AppSettings.swift` |
| Widgets, Live Activities, notifications | Made on the phone. No push server | `App/AppModel+Widgets.swift`, `Services/NotificationPlanner.swift` |
| Exports | Made here, sent only where the person sends them | `Features/Settings/DataExport.swift` |

### What goes without a tap

Each is under a switch the person set, and none carries a new kind of data. Worth knowing when someone asks "when does it send?":

- The last look: the only Cloud AI request nobody asked for at that moment. The consent sheet says so.
- A waiting "Looks wrong?" report, and a question kept with "Answer it later" (the person asked, earlier).
- Checking written questions, straight after writing them.
- Sync while signed in; the profile; the studied-today mark for someone who shares.

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
> exams, your exam dates, how ready you are, which topics are fading and how many questions are due. If you turn on "Send page photos", photos of the pages you scan go too. Capling uses OpenAI for all of it: Ask Cap's
> answers, its tools, web research, questions made from scans, grading and lecture notes. Your phone never talks to an AI company
> directly: requests go through our own server.
>
> When you snap a problem you're stuck on, the photo is read on your iPhone and then deleted: only the words, which you check first, go to Cap. A question you keep for later goes once you're back online, even if Capling is in the background.
>
> What Cap makes is shown to you first. Nothing is added to your library until you approve it, unless you switch on "Let Cap do it"
> for that kind of thing (accounts under 18 can't), and you can undo what Cap added.
>
> Web research is part of Capling Pro and is not available to accounts under 18. When you ask Cap to research a topic, the topic you
> named, anything you asked it to focus on and the name of your course are sent to OpenAI's web search, which reads pages on a fixed list of trusted study sites
> (Wikipedia and its sister sites, government and science agencies, open-access journals and free reference sites) and returns a summary with links to the pages it
> used. The sites receive nothing from your device; a link opens in your browser only when you tap it. A summary is saved to your
> library, as a note, only when you tap Save.
>
> We don't store the content of your requests or of Cap's replies on our server, and we never use your notes or answers to train AI
> models. For each request we keep a short record: which feature, which AI model, how many tokens, what it cost us, when, and your
> account ID. We use it to apply daily limits and to keep costs under control. You can delete this record at any time in Settings,
> AI and privacy (your daily counters stay until they reset, so the limits still work), and it is deleted with your account. The AI
> providers process requests under their own API terms and may keep them for a limited time to detect abuse.
>
> If iOS tells Capling an account is under 13, Cloud AI stays off.

Where each fact comes from:

| Fact | Where |
|---|---|
| Cloud AI is off until allowed; under 13 never; photos are a second switch | `AI/AIConsent.swift`, `AI/AIRouting.swift`, `Features/Settings/ConsentSheet.swift` |
| What the model is sent with each question to Cap | Section 0's rows; `AI/TutorSelection.swift`, `AI/AIRouter+Tutor.swift`, `AI/AIRouter+Assistant.swift` (`searchNotes`), `App/AppModel+AI.swift` (`tutorMaterial`), `AI/TutorDeck.swift` (`TutorMaterial.listing`), `supabase/functions/_shared/assistant.ts` (`studyBlock`), `_shared/contract.ts` (`TutorRequest`, `AssistantRequest`) |
| OpenAI for every AI route | `_shared/deps.ts`, `_shared/openai.ts`, `AI/AIConsent.swift` (`processor`), `docs/BUILD.md` "Every route on OpenAI". Change the sentence if the wiring changes |
| Drafts are shown first; "Let Cap do it" per kind; never for under 18; undo | `Features/Settings/AssistantPage.swift`, `App/AppModel+Assistant.swift` |
| Web research: Pro only, never under 18, 40 listed sites, summary with links, saved only on a tap, no site learns anything | `_shared/assistant.ts` (`RESEARCH_DOMAINS`), `_shared/research_sources.ts`, `_shared/plans.ts`, `AI/AIRouter+Assistant.swift`, `Features/Ask/Assistant/WebSourceTile.swift` (logos drawn in code) |
| Content is never stored or logged on our server; OpenAI is called with `store: false` | `_shared/log.ts` (an allow-list of fields), `_shared/openai.ts` |
| The request record: route, model, tokens, cost, time, account ID; "Delete AI data" keeps the counters | `supabase/migrations/20261022000000_cramless_schema.sql` (`ai_requests`), `cramless_delete_ai_data` |

## 2. The rest of the policy, as of release 1.0

True of the build that goes in at Launch, the one with Stages 1 to 4. It is **not** true of build 1.0 (5), attached to the version today: that one has no Squad mark, no calendar, no syllabus, no spoken answers. So these lines go live with the release, not before. Loopware's page says less than this until then (`docs/privacy-page-draft.md` is the update).

- **Account:** Sign in with Apple or an email code, or an anonymous session. We keep the email (or Apple's relay address), the account ID
  and a time zone, which decides when daily limits reset and which day counts as today for your Squad. An optional first name, up to 80 characters, is what a Squad's members see.
- **Sync:** when you sign in with an account (an anonymous session doesn't sync). Your courses, topics, pages' text, lecture transcripts and notes, cards and questions,
  typed answers, review history, study sessions, daily records, mix-ups, exams and the grades you log are stored in our database; page photos only with "Send page photos" on, in a
  private folder that only your account can read. Chats never sync. Row-level security means an account reads only its own rows
  (`Sync/SyncEngine.swift`). A deleted item stays on the server, marked deleted, until the account is deleted.
- **Squad:** members see each other's first names and when they joined. If you turn on "Show when I've studied" (off by default), your Squad also sees whether you studied today: we keep your account and the day, for 14 days, and delete them when you turn it off, leave the Squad, or the owner's account goes.
- **Spoken answers:** when you answer out loud, your iPhone turns your voice into words. Your voice isn't recorded or sent, and if Cloud AI is on, only the words of an answer in your own words go to it to be graded.
- **Calendar:** if you allow it, Capling reads when you're busy, on your iPhone, to offer to move study off long days. It reads only times, not what your events are, and nothing from your calendar leaves your iPhone.
- **Purchases:** Apple's subscription transactions are verified by our server and kept so your plan follows you across devices.
- **Deleting your account** deletes all of the above.
- **No tracking, no ads, no analytics SDK.** The app uses no third-party code that collects data (no packages in `project.yml`).

## 3. App Store Connect: App Privacy

Set by 2026-11-05, as `docs/BUILD.md` and the notes record them. There is no API, so this re-check is against those records and the manifest, not a read of the site: compare them on the website when changing anything. "Do you or your third-party partners collect data from this app?" **Yes.**
"Used to track you?" **No**, for every row. Every row is **linked to the person's identity** and its purpose is **App Functionality**.
The privacy manifest `Cramless/Resources/PrivacyInfo.xcprivacy` declares the same nine.

Re-checked 2026-11-07 against section 0 and Apple's definitions (developer.apple.com/app-store/app-privacy-details, read that day):

| Data type | What it is now | Change |
|---|---|---|
| Contact Info ▸ Email Address | Sign-in by email code, or Apple's relay address | None |
| Contact Info ▸ Name | The first name Squad members see | None |
| Identifiers ▸ User ID | The account ID | None |
| Purchases ▸ Purchase History | Subscription transactions | None |
| User Content ▸ Photos or Videos | Page photos, only with "Send page photos": read by AI, and stored with sync. A syllabus or problem photo is never sent | None |
| User Content ▸ Other User Content | Notes text, cards (imported decks too), questions, answers, Ask Cap messages, course, source, topic and exam names, grades logged. **New in the same row:** syllabus text, a problem's words, a sentence with an exam date, "Looks wrong?" reports and notes, last-look questions and lines, the words of a spoken answer | None to the answer. The row's meaning grows |
| Search History | The topics a student asks Cap to research online, in the chat or from Fill the gap | None |
| Usage Data ▸ Product Interaction | Review history, study sessions (mocks too) and daily records that sync. **New in the same row:** the studied-today mark | None to the answer: purpose App Functionality ("enable features"), linked, not tracking |
| Usage Data ▸ Other Usage Data | The AI request record and the daily counters | None |
| Other Data ▸ Other Data Types | **Not declared today.** The time zone in `profiles`, kept with the account since the backend went live. Not new, and the Squad mark now leans on it. Apple's definition is "any other data types not mentioned", and a zone isn't "coarse location" | **Owner's call. I'd add it:** App Functionality, linked, not tracking, and `NSPrivacyCollectedDataTypeOtherDataTypes` in the manifest, by the same err-on-declaring rule as the last four rows |

Not collected, and still right: Audio Data (no recording or spoken audio leaves the phone: section 0), Health and Fitness, Financial Info, Location, Sensitive Info, Contacts, Browsing History, Diagnostics, Advertising Data, Device ID. Calendar has no row of its own in Apple's list, and busy blocks stay on the phone ("data that is processed only on device is not collected").

**The Squad mark, which other people see.** Apple's form has no question about data shown to other users, and its definitions page says nothing about it, so no answer changes. What the mark is, who sees it and how long it's kept is the privacy page's job.

The judgement calls (Name, Search History, the two Usage Data rows) err on the side of declaring; before 2026-10-27 the manifest declared five types.

**The required-reason list in the manifest** (not App Privacy, read by Apple at upload): UserDefaults, and since 2026-11-07 file timestamps (`NSPrivacyAccessedAPICategoryFileTimestamp`, C617.1): `PageImageStore.removeStaleStaging` reads a staging folder's modification date inside the app's own container.

## 4. The age rating

Facts for the questionnaire, which changes from year to year (the questions could not be read from here):

- Ask Cap is an AI assistant a student chats with. It never talks to other people, and shows nothing another user wrote.
- It has no browser. Web research is the server reading a fixed list of 40 sites and returning a summary; links open in
  the user's own browser only when tapped. Under-18 accounts don't get it, and under-13 accounts get no cloud AI at all.
- Squad shows its members' first names and, for those who turn it on, whether they studied today. Nothing written by another user, and no way to reach a stranger: a Squad is joined only by a code its owner shares.

Two answers to look at again:

- **`ageAssurance` is false** in `scripts/asc/capling_asc.mjs`, chosen because nothing called the age check. Stage 1 wired it (`AgeRange.checkIfNeeded`, in onboarding and once for existing users), but it has never run on a phone, and the simulator has no answer. Check it on the phone, then set it.
- **The rating is 4+** with those answers, while the app, the policy and the tour say "13 and up". Both can stand (a rating is about content, not audience), but a student under 13 can then download it, and the under-13 rule rests only on what iOS reports. If "made for students 13 and up" should be firm, ask for 13+ when the questionnaire is in front of you. The owner's call.

My reading is "no unrestricted web access", but Apple's wording for a 13+ app was not confirmed (`docs/BUILD.md`); answer it when the
questionnaire is in front of you, and tell me what it asks.

## 5. The words inside the app

The consent sheet (`ConsentSheet.swift`) and Settings ▸ AI and privacy (`AIPrivacyPage.swift`) now show the same three paragraphs, `AIConsent.Words` (What you add, What you ask Cap, What you answer), so they can't say different things. `TutorPrivacyCopyTests` holds them to this page. Consent version 3 has not shipped, so it stays 3; once it has, a change in what is sent is version 4.

The rest, as they stand: Study out loud's and Teach Cap's intro (`OutLoudCopy.privacy`, `TeachCopy.privacy`), "The photo stays on this iPhone. Only the words go to Cap." on the snap and syllabus screens, Cap's calendar card, the Squad switch (`SquadCopy.switchNote`), and the purpose strings in `Resources/Info.plist`.

## Check before you publish

1. **OpenAI terms.** The app promises "never used to train AI models" and the section above repeats it. OpenAI's API terms say API
   data isn't used for training by default, and it keeps requests for a limited time to detect abuse; read the current terms and,
   if you want the stronger sentence ("not kept"), ask for zero data retention.
2. **OpenAI web search.** Read what its terms say about the queries it makes on a student's behalf.
3. **13 to 17.** OpenAI's rules for these ages are unchecked (web research is off for them; the rest is on, asking first).
4. **The age limits.** Every "under 13" and "under 18" line depends on Declared Age Range, or on "high school" for under 18. Under 13 engages only when iOS says so. If iOS gives no range, a student who said college or grad school keeps the adult rules, and everyone else gets the under-18 rules (`AgeRange.fallback`; Settings ▸ AI and privacy can ask again). Cloud AI still asks for consent there: no answer from iOS doesn't block it. All of this is unproven on a phone.
5. **Supabase's own logs.** Our functions log no IP or user ID (`_shared/log.ts`), but the platform's gateway logs requests by its own rules. Read Supabase's retention before saying anything stronger than the page does.
6. **If the wiring changes** (another provider, or Private Cloud Compute), change the processors sentence, `AIConsent.processor`,
   and bump the consent version.
7. **iPhone backups.** Capling sets no backup exclusion (`Model/FileStore`), so an iCloud backup of the iPhone, which is iOS's and the person's own, can hold lecture audio and page photos. So the words say Capling never uploads them, not that they can never leave the phone.
8. **The URLs.** App Review needs the Privacy Policy and Terms URLs reachable (`StoreCatalog.termsURL`, `privacyURL`: Apple's standard terms and loopware.app/privacy, both set).

## History

- 2026-10-27: first draft, for Ask Cap's assistant. Nine types in the manifest.
- 2026-11-01: found that a deleted item stays on the server, marked deleted, until the account goes, and that signing in makes a new account. The age limits weren't wired in (they were in Stage 1; see section 4 and check 4 above).
- 2026-11-02: OpenAI became the only processor.
- 2026-11-03: the tutor stopped sending four matching passages and began sending the course's notes. The size it first sent was later cut to 4,000 words (`TutorSelection.tutor`); the assistant's stayed at 6,000 (`TutorSelection.assistant`). Passages `search_notes` finds, from any course, were added to the wording the same day.
- 2026-11-06: syllabus text, a date heard in a lecture, a snapped problem's words, spoken answers and Teach Cap added, each as "other user content".
- 2026-11-07: this page rewritten from the code for Launch: section 0's tables, section 2's heading, the App Privacy re-check, and the research sites, which the words had described as encyclopedias, open textbooks and universities and which are the 40 sites in `RESEARCH_DOMAINS`.
