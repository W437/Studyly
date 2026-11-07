"""The words of the tour page (tour_page.py builds it from these and the films). Voice: the owner talking to a friend: plain, short,
no hype. The page says what is filmed and what is not, and never claims more than the app does. HTML is allowed in the strings.
No pronouns for Maya (the student in the demo): the name, or no subject. A word the reader has not met is explained where it first
appears (Cap, the sky, ready, freeze): a cold read found most of the earlier problems in exactly those places."""

TITLE = "Capling tour"
EYEBROW = "Watch the app, start to finish"
HEADLINE = "Try Capling without an iPhone"

# The app as its store page will show it, at the top of the page: the icon, the name, the subtitle (the app's own welcome line), the button
# (the app is not released, so it says so) and the facts the store puts under them. APP_FACTS: (label, value as HTML, sub-label).
ICON = "../../Cramless/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"      # relative to this file
APP_NAME = "Capling"
APP_SUBTITLE = "Ready on exam day"
APP_ACTION = "Coming soon"
APP_ACTION_NOTE = "In-App Purchases"
_EDUCATION = ('<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
              '<path d="M2.5 9.5 12 5l9.5 4.5L12 14 2.5 9.5z"/><path d="M6.5 11.7V16c0 1.4 2.5 3 5.5 3s5.5-1.6 5.5-3v-4.3"/><path d="M21.5 9.5V15"/></svg>')
APP_FACTS = [
    ("Age", "13+", "Years Old"),
    ("Category", _EDUCATION, "Education"),
    ("Language", "EN", "English"),
    ("Price", "Free", "to start"),
]
INTRO = ("Capling is an exam coach for high-school and college students. Photograph your notes and it writes questions that point back to the page; Cap, "
         "its capybara, coaches you through them; and a night sky shows how ready you are for each exam. Maya, a student, uses it below.")

# The brief (the gateway draws it as the first card). {minutes} is an honest estimate for watching what you care about, {total} is the
# length of all the clips.
BRIEF = """    <p>I filmed the real app running in a simulator, with a demo student's data. Each clip is
    Maya doing one thing, with real taps (a ring shows where a finger lands), real typing and the app's own sounds.</p>
    <p>Who it's for: students with exams coming, 13 and up. Most feel busy, not ready: fewer than 1 in 5 feel very confident about
    their progress. Flashcards are free everywhere now, so our bet is what comes after: knowing what you know, and saying honestly if
    you're ready.</p>
    <p>What I need: watch what you care about, in any order (the clips run {total} minutes in all; you won't need them all), and tap
    Comment to pin a note where something feels wrong, missing or confusing. Five questions sit in the sections they're about, and at the very end a few open ones ask what you think, in your own words.</p>
    <p>Ignore: the AI's wording is plainer here, because the clips use the app's built-in offline rules, not Cloud AI; and a recording
    can't show haptics. In the four clips where Cap makes things, Cap's replies are scripted by the
    app's demo server, so they're the same every time: judge how it works, not the wording.</p>"""

# Folded right under the brief: where Capling sits among the other apps, how it differs, its edge. The facts are from the plan in
# docs/rethink/site/plan.html (researched 2026-10-22; its Sources section has them); a company's own figures are called its own claims.
# Keep it to a minute's reading.
WHERE_TITLE = "Where it sits: the other apps, how we differ, our edge"
WHERE = """<p class="fine">Our read, October 2026; company figures are their own claims.</p>
    <ul>
      <li><b>Quizlet</b>: the top-grossing study app on the US App Store; spaced repetition only since August 2026.</li>
      <li><b>Anki</b>: the best scheduler, the hardest to use.</li>
      <li><b>ChatGPT and Gemini</b>: explain well and now have free study tools, but don't remember what you know or plan to your exam date.</li>
      <li><b>Gizmo</b>: 13 million learners and $22 million raised, on Duolingo-style streaks and leagues.</li>
    </ul>
    <p><b>Our position.</b> Ready, not busy: the others hand you more material, Capling tells you whether you're ready for each exam.</p>
    <p><b>How we differ.</b> A readiness score and a daily plan to your exam date. Questions checked against, and linked to, your own page.
    Answers graded on your ideas, not the exact words. Cards, notes and exams that Cap drafts are checked against your own pages, and
    added only when you say so.</p>
    <p><b>Our advantage.</b> Making cards is free everywhere now; knowing what you know is not, and nobody owns it yet. Reviews, plans,
    readiness and mock exams run on the iPhone with no AI, so the free plan costs us little.</p>"""

HOW = [
    ("Tap a title to open it", "Sections start folded. Each has a clip and its moments, and some have a question."),
    ("Tap a clip to play", "Sound on: the app plays its own small notes. The moments under it jump to that point."),
    ("Comment on anything", "Tap Comment, then the clip or a line, and write what you think."),
    ("Mark each section done", "The button at its end keeps track of what you've checked. Answer the five questions, write your overall thoughts at the end, and Done lights up."),
]

ROUTE_TITLE = "In a hurry? About four minutes"
ROUTE = [                                              # (label, film, seconds into it): each link starts the clip there
    ("The welcome, and lighting a star", "welcome", 0),
    ("A wrong answer, kindly", "quiz", 68),
    ("A dim constellation, relit", "sky", 17),
    ("Cap makes flashcards and checks them", "assist-cards", 14),
    ("The streak page", "game", 11),
    ("What it costs", "plans", 10),
]

# One dict per clip, in the order they appear: id, group, chip (the nav label), film (a package.py film), title, lede (HTML), look.
SECTIONS: list[dict] = [
    dict(id="first-minute", group="Getting started", chip="First minute", film="welcome", title="The first minute",
         lede=("A new student opens Capling for the first time: a welcome sky to touch, six short demos, four one-tap questions "
               "(what they're aiming for, the exam date, minutes a day, where their notes live), a first study set made from one "
               "photographed page, two quick questions, and a plan. This is all of it, in real time."),
         look="where you'd have stopped reading, and whether the six demos earn their place."),
    dict(id="add", group="Getting started", chip="Add a page", film="scan", title="Add a page",
         lede=("Maya photographs a textbook page. The app reads it, finds the ideas, writes questions and checks each one against the "
               "page. Before anything joins the set, every question says where it came from, and tapping the source shows the exact "
               "line on the exact page. (On a phone this is the camera; the simulator has none, so it uses a sample page.)"),
         look="whether you'd trust the questions: each one shows where it came from."),
    dict(id="classes", group="Getting started", chip="Your classes", film="library", title="Your classes",
         lede=("Every class with how ready it is and when its exam is. Inside: the topics, each with how well they're known, and every "
               "question with the page it came from, including ones from a lecture. Anki, Quizlet, PDFs and pasted text come in too."),
         look="whether you can tell at a glance what you're studying and how ready you are."),
    dict(id="lecture", group="Getting started", chip="Lecture", film="lecture", title="Record a lecture",
         lede=("The lecture is transcribed on the phone as it happens (a demo transcript plays here, because the simulator can't hear). "
               "Tap when something sounds important and it is flagged for the exam. When the recording stops: a summary, the flagged "
               "moments, key terms, and questions."),
         look="the “on the exam” flags. Would you use that in a real lecture?"),
    dict(id="quiz", group="Studying", chip="Quiz prep", film="quiz", title="Two days before a quiz",
         lede=("Maya has a Chem quiz on Wednesday, and the app says Maya is 42% ready: its estimate of how much of the quiz material "
               "will still be remembered on the day. The exam page shows where that comes from and what it would take to reach the goal. "
               "Then a practice run uses every kind of question: flashcards, multiple choice, fill in the blank, and answers typed in "
               "Maya's own words, graded on the ideas the answer contains rather than the exact wording. A wrong answer says "
               "“Not yet.” and shows the fix. The summary shows what moved."),
         look="what the app does when an answer is wrong, and whether the summary feels earned."),
    dict(id="ask", group="Studying", chip="Ask Cap", film="ask", title="Ask Cap",
         lede=("A tutor that answers questions only from Maya's own notes and names the page. By default Cap asks before it tells; one "
               "tap and it just explains. Tapping the source opens the page with the line highlighted, and the questions made from it. "
               "(The words come from the app's built-in offline tutor; with Cloud AI, if you allow it, the cloud writes them.) "
               "Cap can also make things for Maya, and on Capling Pro look things up: the next four clips."),
         look="whether “only from your notes” is a strength or a limit. Would you ask this, or use ChatGPT?"),
    dict(id="ask-make", group="Studying", chip="Cap makes", film="assist-cards", title="Ask Cap to make something",
         lede=("New: Cap doesn't only answer, it makes things. Maya taps Make flashcards, types the topic, and Cap writes six cards "
               "as Maya watches, then checks each against Maya's notes and shows the page it came from. One card isn't in the notes, so "
               "Cap marks it as its own words. Nothing is added until Maya says so: leave a card out, add the rest, and Undo takes "
               "them back. Anything Cap makes is a draft, something to look over first; the free plan gets 3 drafts a day, Pro far more. "
               "(Cap's reply is scripted by the app's demo server; the cards' checks, the buttons and what is saved are the app's own.)"),
         look="whether you would trust cards you can watch being checked against your notes, and whether the “Cap's own words” mark is clear."),
    dict(id="ask-more", group="Studying", chip="Quiz, note, exam", film="assist-more", title="A quiz, a note and an exam",
         lede=("The same chat, three more things Cap can make. Questions to practise with (pick one, in your own words, fill in the "
               "blank), a note written onto a page, and an exam put on a calendar tile with its day and what it covers. Each is shown "
               "first, and Maya adds it. Cap can also start a practice session or open a screen when asked (not filmed)."),
         look="whether a quiz, a note and an exam from one chat is useful, or too much."),
    dict(id="ask-research", group="Studying", chip="Research", film="assist-research", title="Research online, on trusted sites",
         lede=("Capling Pro only, 3 a day (Pro is the paid plan: see Free, Pro, Exam Pass and Squad further down; a developer setting "
               "makes Maya a Pro subscriber in this clip). Cap searches trusted study sites only (Wikipedia and its sister sites, "
               "government and science agencies, open-access journals and free reference sites, about 40 in all), writes a short summary, and shows the pages it rests on. "
               "Nothing is saved unless Maya says so. Under 18, Cap does not look things up online. (The sites and the summary are "
               "scripted by the app's demo server.)"),
         look="whether you would pay for research on trusted sites, or ask ChatGPT."),
    dict(id="ask-control", group="Studying", chip="In charge", film="assist-control", title="You stay in charge",
         lede=("Cap asks before it adds anything. In Settings, under What Cap can do, Maya can switch on “Let Cap do it” for flashcards "
               "and questions, notes, or exams. Then the same request adds the cards at once, says why, and Undo is still one tap away. "
               "Settings lists everything Cap added, each with Undo. Anything that changes or deletes something that already exists "
               "always asks. Under 18, Cap always asks first."),
         look="whether “ask first” is the right default, and whether you would switch “Let Cap do it” on."),
    dict(id="sky", group="Where you stand", chip="Memory sky", film="sky", title="The memory sky",
         lede=("Maya opens the sky from Today, looks at what it shows, picks a dim constellation, studies it for a minute, and "
               "comes back to the sky."),
         look="whether you understand the sky without anyone explaining it."),
    dict(id="game", group="Staying with it", chip="Streaks", film="game", title="Streaks, quests and badges",
         lede=("Three small quests a day, a streak that forgives (a freeze covers a missed day, and one is earned after 7 days in a row; "
               "a repair brings back a longer gap) and thirteen badges that stay earned. Twelve quests in a week unlock a new sky "
               "theme. No hearts or lives, no coins, no paid freezes."),
         look="whether it's too much, too little, or calm enough."),
    dict(id="rewards", group="Staying with it", chip="Rewards", film="rewards", title="Rewards a few weeks in",
         lede=("Moments you won't reach in a first week. These three are staged, not played in real time: a developer setting puts the "
               "streak and the week's quests where they need to be. The 30-day milestone takes over the summary; twelve quests in a "
               "week unlock a new sky theme (a new colour for the night sky); a badge arrives as a medal that tilts with the phone."),
         look="whether these moments feel earned, or over the top."),
    dict(id="settings", group="Around it", chip="Settings", film="settings", title="Make it yours, keep control",
         lede=("How long a day and the one reminder. What the AI can see: everything stays on the phone until you turn cloud AI on, "
               "page photos are a separate switch, and a plain list says what is sent and what the server keeps. A dyslexia-friendly "
               "font, dark mode, and skies and icons that unlock as rewards. Export or delete everything."),
         look="anything missing from privacy, accessibility or your data."),
    dict(id="plans", group="Around it", chip="Plans", film="plans", title="Free, Pro, Exam Pass and Squad",
         lede=("Free is unlimited flashcard reviews, 3 scans a week and 20 graded answers a day. Pro adds unlimited scans, PDFs and "
               "lecture notes, answers in your own words graded without the daily limit, and Cap's answers without the daily limit. Plans, readiness and mock exams are free. "
               "Exam Pass is Pro for the 30 days around one exam, paid once. Squad is Pro for you and three friends on one plan."),
         look="whether the free plan feels fair and the prices feel right."),
]

# Five decisions at most, each right after the clip it is about. options: value:Label|value:Label (2 to 4). watch = (film, seconds).
DECISIONS: list[dict] = [
    dict(after="first-minute", id="onboarding-length",
         question="That was about three minutes from opening the app to the first day's plan. How was it?",
         options="right:About right|demos:Too long: cut the six demos to two or three|questions:Too long: ask less up front|paywall:Fine, but show the paywall after the first session",
         context="In those three minutes: a welcome, 6 demos, 4 questions, a reminder prompt, a first set, 2 graded questions, a plan and the paywall.",
         watch=("welcome", 0)),
    dict(after="sky", id="sky-meaning",
         question="Did the sky make sense from the clip alone?",
         options="yes:Yes, straight away|later:After a star lit up|no:No, it needs a short explanation",
         context="The app is built around this idea, so how fast it lands matters.",
         watch=("sky", 0)),
    dict(after="rewards", id="game-amount",
         question="How much game is right for a study app?",
         options="right:About right|more:More: add things like levels or friends' leaderboards|less:Less: strip it back to the streak",
         context="Today: a streak with freezes and repairs, 3 quests a day, 13 badges, skies and icons as rewards. No hearts, no currency.",
         watch=("game", 11)),
    dict(after="plans", id="pricing",
         question="Is the pricing right for a student?",
         options="fair:Fair|high:Too high|simpler:Too many plans: simplify",
         context=("Pro $49.99 a year ($9.99 a month, 7 days free). Exam Pass $14.99 for 30 days. Squad $99.99 a year for four. "
                  "For scale: the median education app charges $44.99 a year; AI-heavy study apps charge about $96 to $155."),
         watch=("plans", 10)),
    dict(after="plans", id="build-next",
         question="To get students coming back every day, which one should I build next?",
         options="widget:Answer a flashcard from the Home Screen|squad:A shared sky for your Squad, and term-end recap cards|watch:Apple Watch cards|scan:A scan that lights each line as it's read",
         context="All four are planned (Watch comes last on the roadmap). Eight more languages are on it too."),
]

ALSO_TITLE = "What else is in the app, and what's planned"
ALSO: list[tuple[str, str]] = [                          # ("built" | "pending" | "next", text)
    ("built", "How the sky works: every star is one thing learned, a constellation is a topic, and each exam gets a region. A star dims as it is forgotten and lights when it is studied."),
    ("built", "Home Screen and Lock Screen widgets (next exam, today, streak), an exam-week Live Activity, a Start control, Siri shortcuts such as “How ready am I?”"),
    ("built", "Ask Cap can also start a practice session or open a screen when asked, and look through your notes before it makes a set"),
    ("built", "Import from Anki, Quizlet, CSV, PDFs and pasted text; read-aloud for questions"),
    ("built", "One reminder a day, never in quiet hours, with exam countdowns"),
    ("built", "Dynamic Type, VoiceOver labels, Reduce Motion, a dyslexia-friendly font"),
    ("built", "Sign in with Apple or an email code, sync across devices, Squad invites by link or code"),
    ("built", "Teach Cap: explain a topic out loud, Cap asks one follow-up"),
    ("built", "Study out loud with the screen off: Cap asks, you answer, nothing you say is recorded"),
    ("built", "Free mock exams, Cap's cards, snap the syllabus, the last look on an exam's eve"),
    ("next", "A scan that lights each line as it's read, and an exam-eve goodnight"),
    ("next", "Widgets you can answer from the Home Screen"),
    ("next", "A shared Squad sky and a term-end Wrapped"),
    ("next", "VoiceOver gestures for studying by voice, then eight more languages, then Apple Watch"),
]

# Open questions at the very end, after the reference list: a labelled text box each. The gateway saves what is typed as it is typed, and one with
# required=True counts as a question for Done. In the owner's voice, plain and short; a student's view, not a developer's.
FEEDBACK_GROUP = "Your turn"
FEEDBACK_LABEL = "A few minutes to write"
FEEDBACK_TITLE = "What do you think?"
FEEDBACK_CHIP = "Your thoughts"
FEEDBACK_INTRO = ("You've seen what it does. Now I'd like your own take, in your own words. A few lines are plenty, rough is fine, and any "
                  "language you like. It saves as you type. Think of a student you know, and what they would want from an app like this.")
FEEDBACK_PLACEHOLDER = "Write here"
FEEDBACK: list[dict] = [
    dict(id="fb-overall", question="What do you think of Capling, honestly?", required=True,
         hint="Your first reaction: what you liked and what you didn't. Would you open it every day if you were a student?"),
    dict(id="fb-add", question="What would you add?",
         hint="A feature, a screen, a small detail, or an app you've seen do it better."),
    dict(id="fb-useful", question="What would be most useful to students?",
         hint="What would make a student reach for it before an exam, or every day?"),
    dict(id="fb-change", question="What would you change or take out?",
         hint="Too much, too little, confusing, annoying, or just not needed."),
    dict(id="fb-cap", question="Cap can now make cards, a quiz, a note or an exam for the student. Useful, or too much?",
         hint="See the four Ask Cap clips above."),
    dict(id="fb-else", question="Anything else?",
         hint="Ideas, worries, apps I should look at, questions for me."),
]

FOOT = ("Recorded on an iPhone 17 Pro simulator (iOS 27) with demo data and the app's offline AI, sounds from the app itself; "
        "the four Ask Cap clips that make things use the app's scripted demo server instead. "
        "Capling is a working name; the app is not on the App Store yet.")
