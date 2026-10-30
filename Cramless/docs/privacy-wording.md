# Privacy wording for Ask Cap's assistant

Draft of 2026-10-27, for the owner to paste into the privacy policy and into App Store Connect (App Privacy and the age rating).
Every fact below was read from the code, and the file is named; what only a provider or Apple can confirm is in "Check before you
publish" at the end. Nothing here is legal advice. After a change, `python3 scripts/cap_anim/build_privacy_page.py` rebuilds the page
version, with a button that copies the policy section (`build/review/ask-cap-assistant/privacy.html`).

## 1. The privacy policy: a section for Ask Cap

> ### Ask Cap, our study assistant
>
> Ask Cap answers questions about your notes and, when you ask, makes things for you: flashcards, quiz questions, a note, an exam on
> your calendar or a practice session. It only works with Cloud AI, which is off until you turn it on, and you can turn it off at any
> time in Settings.
>
> When you use it, Capling's server sends your request to an AI provider to be answered. That includes your message and the recent
> messages in the chat, a few passages from your notes that match your question, and an overview of your study, so that Cap can pick
> the right course: the names of your courses, topics and exams, your exam dates, how ready you are, which topics are fading and how
> many cards are due. If you turn on "Also send page photos", photos of the pages you scan go too. Ask Cap's answers, its tools and
> web research use OpenAI; making questions from scans, grading and lecture notes use Anthropic. Your phone never talks to an AI company
> directly: requests go through our own server.
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
| What the model is sent: the messages, up to 24 passages, and the study overview (course, topic and exam names, exam dates, readiness, fading topics, due counts) | `supabase/functions/_shared/assistant.ts` (`studyBlock`), `_shared/contract.ts` (`AssistantRequest`) |
| OpenAI for the tutor, the assistant and web research; Anthropic for the rest | `_shared/deps.ts`, `_shared/openai.ts` (`withTutor`), `docs/BUILD.md` "Ask Cap on OpenAI". Change the sentence if the wiring changes |
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
| User Content ▸ Other User Content | Yes | Notes text, cards, questions, answers, Ask Cap messages, course, topic and exam names |
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
and `AIConsent.swift`'s version note. They now say Cap also sees exam dates, readiness and fading topics. Consent version 3 has not
shipped, so it didn't need a fourth; once it has, a change in what is sent is version 4.

## Check before you publish

1. **OpenAI and Anthropic terms.** The app promises "never used to train AI models" and the section above repeats it. Both companies'
   API terms say API data isn't used for training by default, and both keep requests for a limited time to detect abuse; read the
   current terms and, if you want the stronger sentence ("not kept"), ask each for zero data retention.
2. **OpenAI web search.** Read what its terms say about the queries it makes on a student's behalf.
3. **13 to 17.** OpenAI's rules for these ages are unchecked (web research is off for them; the rest is on, asking first).
4. **If the wiring changes** (everything on OpenAI, or Private Cloud Compute), change the processors sentence, `AIConsent.processor`,
   and bump the consent version.
5. **The URLs.** App Review needs the Privacy Policy and Terms URLs reachable (`AppLinks`; the paywall hides the links until set).
