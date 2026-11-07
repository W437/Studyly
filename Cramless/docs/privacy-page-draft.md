# Loopware's privacy page: Capling's section, as it should appear

A draft for the owner to approve at Launch. Nothing here is published, and the repo below hasn't been touched.

- **Where it lives:** `~/Documents/GitHub/loopware-landing`, `src/components/PrivacyPage.jsx`, the `#capling` section. Netlify publishes a push to main within a minute, and other sessions push there, so work in a separate worktree and fetch right before pushing. Live at https://loopware.app/privacy.
- **Publish it with the release, not before.** It describes the Stage 1 to 4 build; build 1.0 (5) has no calendar, no spoken answers, no Squad mark.
- **Read against the code** at commit 112198e on 2026-11-07; the facts route by route are in `docs/privacy-wording.md`.
- **Changed from the live section:** on the phone (spoken answers, calendar, snapped photos), Cloud AI (syllabus, a date heard in a lecture, "Looks wrong?", harder questions, look-alikes, the last look, spoken grading), Ask Cap (a snapped problem, a question kept for later), web research (the real list of sites; Fill the gap), the server's record (Squad's day), sync (grades, marks), Squad (the mark), permissions (all), age limits (when iOS reports them).

---

## Capling

An exam-prep study app for iPhone. Capling has no ads and no tracking, and it includes no third-party code that collects data. It works on your iPhone first. Our server is used only for Cloud AI, signing in and sync, purchases and Squad.

### On your iPhone

Your courses, scanned pages, notes, questions, answers, review history, exams, Ask Cap chats and settings are stored on your iPhone. Scanning a page and reading its text happen on your iPhone. A lecture you record is turned into text on your iPhone, and the audio stays there. The first time you use a language, iOS may download its speech model; no audio is sent. Capling can also write questions, grade answers and answer Ask Cap from your notes on your iPhone, with its built-in rules. Its widgets read a copy kept on the same iPhone, and its Live Activities and reminders are made by the app on your iPhone.

When you answer questions out loud or explain a topic to Cap, your iPhone turns your voice into words. Your voice isn't recorded or sent, and the words are gone after the answer, unless Cloud AI grades them (below).

When you snap a syllabus or a problem you're stuck on, the photo is read on your iPhone and isn't kept. It is never sent.

If you let Capling read your calendar, it looks only at when you're busy (the times of events marked busy), on your iPhone, to offer to move study off long days. It doesn't read what your events are, it doesn't keep what it reads, and nothing from your calendar leaves your iPhone.

### Cloud AI (optional)

Cloud AI is off until you turn it on, and you can turn it off at any time in Settings → AI and privacy. Without it, Capling still works on your iPhone, in less detail. With it on, your iPhone never talks to an AI company directly: requests go to our server, which passes them to OpenAI. What a request carries depends on what you ask for:

- **Questions from your pages.** The text read from the pages, PDFs or notes you add, with the course name and the source's title. The questions written are then checked against that text.
- **Grading.** The question, its model answer and key ideas, the words of the answer you typed or said and a passage from your notes. What you tell Cap in Teach Cap is graded the same way. Your voice never goes.
- **Lecture notes.** The lecture's transcript and the moments you flagged, with the course name and the lecture's title. The audio is never sent.
- **Your syllabus.** The words read from a syllabus or past paper (up to six pages), with the course's name, the exam's name, today's date and the course's topic names, so Capling can suggest the exam's date, topics and format. The photo is never sent.
- **A date heard in a lecture.** If you tap Add the exam on a date Capling heard, the sentence it was heard in, with the lecture's title and day, the course's name and its topic names.
- **Mistake patterns.** When you ask Cap about something you keep mixing up: the questions you keep missing, with the expected answers and yours. When you ask about two questions that look alike: those two questions and their answers.
- **A question that looks wrong.** If you ask Cap to check one: the question and its answer, the lines of your notes it came from, the source's title and headings, the reason you chose, the answer you gave and anything you wrote. If it can't go at once, it waits on your iPhone and goes when it can.
- **A harder question.** If you ask for one: the question you've outgrown and its answer, with the lines around it.
- **The last look.** In the two days before an exam, when you open Capling, your shakiest questions for that exam (up to eight) go by themselves, with their answers and the lines they came from, so Cap can put each in a plain sentence for the night before. The sentences stay on your iPhone.
- **Cards from a chat.** The messages of that chat.

Page photos have their own switch, "Send page photos", which is off until you turn it on and goes off when you turn Cloud AI off. With it on, photos of the pages you scan go along with their text, made smaller first, so Cloud AI can read handwriting, math and diagrams. If you're signed in, the same switch also uploads your page photos to a private folder that only your account can read, so your other devices can show them. A photo of a syllabus or a problem is never sent, whatever this switch says.

All of Cloud AI runs on OpenAI. OpenAI handles the requests under its API terms, as described under Service Providers.

### Ask Cap

With Cloud AI on, a request to Ask Cap carries your message, the recent messages of the chat and the notes of the course Cap is answering from (of every course, if you chose All courses): the text of your pages and lectures, the cards of decks you imported and the names of what you added. It all goes when it's short, and otherwise the parts that fit your question. When you ask Cap to look through your notes, the passages it finds in any of your courses go too. If you ask about a question you got wrong, that question, its expected answer and yours go too. So that Cap can make things for the right course, it also sees an overview of your study: the names of your courses, topics and exams, your exam dates, how ready you are, which topics are fading and how many questions are due.

If you snap a problem, you check the words read from the photo, and only those words go to Cap. If you keep a question for later because Cap couldn't be reached, it goes once there is a connection, even with Capling in the background. At most three wait at a time, and each is dropped after seven days.

Cap can draft flashcards, questions, a note or an exam. What it makes is shown to you first, and nothing is added to your library until you approve it, unless you switch on "Let Cap do it" for that kind of thing in Settings → What Cap can do. You can undo what Cap added.

### Web research (Capling Pro)

When you ask Cap to research a topic online, or to find a missing topic on trusted study sites, our server sends the topic, anything you asked it to focus on and your course's name to OpenAI's web search. It reads pages on a fixed list of about 40 sites: Wikipedia and its sister sites, government and science agencies, open-access journals and free reference sites. It returns a summary with links to the pages it used. Those sites receive nothing from your iPhone. A link opens in your browser only when you tap it, and that site then sees your visit. A summary becomes a note in your library only when you tap Save. You can turn web research off in Settings → What Cap can do.

### What our server keeps about AI requests

Our server doesn't store the content of your requests or of Cap's replies, and we never use your notes or answers to train AI models. For each request it keeps a short record: the feature, the AI model, the number of tokens, what the request cost us, the time and your account ID. It also counts your requests for the day or week. We use the record and the counts to apply your plan's limits and to keep each person's daily AI cost under a cap. You can delete the record at any time in Settings → AI and privacy → Delete AI data. The counts stay, so the limits keep working, and both are deleted with your account.

### Your account

You don't need an account to use Capling. When Cloud AI or a purchase first needs our server, Capling creates an anonymous account ID: a random ID with no name or email. If you give Capling your first name in Settings → Account, which is optional, our server keeps it with your account ID, along with your time zone, which sets when your daily and weekly limits reset and which day counts as today for your Squad.

Signing in is optional. You can sign in with Apple, or with a 6-digit code we email you. It turns on sync and is needed for Squad. Sign in with Apple gives us an ID from Apple and your email address, or Apple's private relay address if you choose to hide yours. If you haven't given Capling a first name, it uses the one Apple shares. With an email code, we receive your email address. Signing in starts a new account; the anonymous ID you used before isn't merged into it. You can sign out at any time, and everything you studied stays on your iPhone.

### Sync (when you're signed in)

While you're signed in, Capling keeps a copy of your study in your account, so a new iPhone picks up where you left off. The copy holds your courses and topics; your sources, with their titles, file names, the text read from their pages, and lecture transcripts and notes; your questions and cards, and which ones you've reported; the answers you typed when they were graded and the options you picked; mistake patterns; your review history, study sessions and daily records; and your exams, with the grades you log. Ask Cap chats, what you said out loud and anything from your calendar never sync. Page photos are copied only with "Send page photos" on, to a private folder that only your account can read, and lecture audio is never uploaded. Each account can read only its own data. Until you sign in, nothing syncs.

If you delete something in Capling, it's removed from your devices, but our server keeps it, marked as deleted, so your other devices can remove it too. That copy, and any page photos you uploaded, stay until you delete your account.

### Purchases

Capling Pro, Squad and the Exam Pass are bought through the App Store. Apple processes the payment, so we never see your card details. Capling sends Apple's signed purchase records to our server, which verifies that Apple signed them. It keeps what you bought, when, when it ends, its App Store transaction IDs and whether it's still active, with your account ID. Apple also tells it when a subscription renews, expires or is refunded. If you're signed in when you buy, Capling gives Apple your account ID with the purchase, and Apple keeps it in its purchase records.

### Squad

A Squad is one plan shared by up to four people. Inviting friends or joining a Squad needs you to sign in. Squad members see each other's first names and when they joined; they don't see your notes, questions, exams or answers. Our server keeps who is in a Squad and the invite codes its owner makes, each of which works once and expires after 14 days. The owner shares an invite through the iPhone share sheet, so they choose the app and the person.

"Show when I've studied" is off until you turn it on. With it on, the other members of your Squad see a mark on days you finish a study session. All that's kept for it is your account and the day: nothing about what you studied or how it went. We keep it for 14 days, and delete it at once when you turn the switch off or leave the Squad, or when the Squad's owner deletes their account.

### Permissions

Capling asks for each of these only when you first use what needs it:

- **Camera,** to scan pages, a syllabus or a problem.
- **Microphone,** to record the lectures you choose to record and to hear your answers when you study out loud or teach Cap. Recognition runs on your iPhone.
- **Speech Recognition,** if iOS asks for it, to turn those recordings and answers into words on your iPhone.
- **Calendar,** only if you tap Check my calendar on Cap's card, as described above. iOS offers only full access to read events; Capling looks only at when you're busy.
- **Notifications,** for study, exam, streak, Cap's notes and free-trial reminders, which Capling creates on your iPhone; it has no push server.

To add photos, Capling uses Apple's photo picker, so it sees only the photos you pick.

### Younger students

Capling is made for students 13 and up. If iOS tells Capling an account is under 13, Cloud AI stays off and nothing goes to it. If iOS says an account is under 18, or you told Capling you're in high school, Cap starts with hints, Cap asks before adding anything, and web research is off. iOS shares your age range only if you allow it, and Capling keeps the answer on your iPhone.

### Deleting your data

Settings → AI and privacy → Delete AI data deletes the AI request record that our server keeps and leaves your courses, questions and progress as they are.

Settings → Account → Delete account deletes your account and sign-in on our server, with everything synced to it, the page photos you sent, your purchase records, the AI request record and counts, your Squad seat and what you shared with it (and the Squad, if you own it). It then deletes everything on your iPhone. It also works for an anonymous account. It doesn't cancel a subscription: Apple bills it, and your purchases stay with Apple.

Settings → Your data → Delete all data on this iPhone deletes what's on your iPhone and signs you out there. It doesn't delete your account or its synced copy, and signing in again brings that copy back. The same page exports your cards as a CSV file, or everything as JSON, made on your iPhone and shared only where you send them.

---

## Elsewhere on the same page

Three other sections name Capling. Change these lines too.

**Service Providers ▸ OpenAI.** "…and all of Capling's AI: Ask Cap's answers and tools, web research, writing and checking questions, grading, lecture notes, reading a syllabus, checking a date heard in a lecture, mistake patterns, the last look, cards from a chat and reading page photos."

**How Long We Keep Data.** Add: "**Capling's Squad mark:** 14 days, or until you turn it off, leave the Squad or the owner deletes their account."

**Children's Privacy.** "Capling is made for students 13 and up, and keeps Cloud AI off when iOS indicates that the person using it is under 13." The rest stands.

The page's "last updated" date moves to the day it's published.

## Before publishing

1. Declared Age Range has never run on a phone. "Younger students" says what the code does; check it on the phone first.
2. "Never use your notes or answers to train AI models" and "under its API terms" rest on OpenAI's current API terms: read them once more (`docs/privacy-wording.md`, "Check before you publish").
3. "The audio stays there" and "lecture audio is never uploaded" are about Capling. An iCloud backup of the iPhone, which is iOS's and the person's own, can hold the files, since the app sets no backup exclusion. Add a line if you want that said.
4. "Speech Recognition, if iOS asks for it": the code never asks for that permission itself (`SpeechAnalyzer` needs the microphone), but the string is in `Info.plist` in case iOS does. See what the phone does and cut the "if" or the line.
