# Ask Cap as an assistant

Built 2026-10-27. Ask Cap used to answer questions from the student's notes. It can now also **make** things (flashcards,
questions, notes, an exam), **offer** things (a practice session, a screen) and **look things up** (the notes, and, for
Capling Pro, trusted study sites on the web) — with the student in charge of everything it adds, and every step of its work
on screen.

## The idea in one paragraph

The model never touches the library. It *chooses* a tool; the app runs it. A tool that makes something returns a **draft**
that the student adds, changes or skips (or, with "Let Cap do it" on for that kind, that is added at once and can be undone).
What the model claims is checked by the app before it is shown: a quote is evidence only if it is really in the student's
notes, a multiple-choice question must have its right option, a date must be a real day that has not passed. What the model
reads from the web or from a note is data, never an instruction.

## What the student sees

Each tool call is a **card** in the chat. It works, proposes, and settles.

| State | What is on screen |
|---|---|
| Working | The card breathes. Cards and questions appear one at a time **as the model writes them** (real progress, streamed), with a soft note for each. A note is written onto a white page with a pen. An exam flips onto a calendar tile. |
| Checking | When the model has finished writing, each card gets its check against the notes, one at a time, with a rising note: a tick and the page it rests on ("Textbook p. 87"), or "Cap's own words, not from your notes". The first four cards stay on view from the first check to the proposal, so the card keeps its shape. |
| Your call | A tangerine outline. Tick or untick each card, edit its words, **Add 6 flashcards** or **Skip**. A card the course already has is shown unticked, "Already in this course", and the model is told so (it says how many are new). |
| Added | A tick draws itself, the sound of "saved", "Added to Bio 101", **Undo**. With "Let Cap do it" it says so. |
| Skipped / taken back | Dimmed, with "Add after all" / "Add again". |
| Couldn't | Why, in a sentence of plain words (the model gets its own, with the ids and instructions, and its wrap-up says it couldn't); for web research without Pro, a button to Capling Pro. |

Under the working card, **Cap and one line** say what he is doing this second ("Choosing what to put on the cards", "Writing the cards",
"Checking each card against your notes", "Writing your note", "Searching trusted study sites", "Reading 5 pages"). The chat follows the
work down as it grows, and stops following when you scroll away. A new chat shows **Ask Cap to make something** (flashcards, a quiz, a note, an
exam, research) as first words for the composer, when the cloud tier is open and, for research, the web is on for this student.

**Looking up the notes** is a small card: a page that is scanned once, then chips of where it found things.

**Web research** is the showpiece. The search types itself into a search bar (in plain words, not the model's operators).
The pages it found pop up as tiles in the sites' colours (Wikipedia, Britannica, Khan Academy, OpenStax, universities, NIH…),
one after another; a ring of light passes over them while it reads; the summary writes itself with key terms in bold; the
pages it rests on come last as links. Then **Save as note** (or Skip). The tiles are drawn in code: the app never asks a site
for its icon, because that would tell the site what the student is researching.

## Control

- **Ask first** is the default for everything. Settings ▸ What Cap can do has a switch per kind (flashcards and questions,
  notes, exams) for "Let Cap do it". Practice sessions and screens are buttons, never automatic. Anything that changes or
  deletes something that already exists would always ask (v1 has no such tool).
- **Added by Cap** lists everything Cap has added that is still there, with Undo. Undo is a soft delete of exactly what the step
  made.
- **Under 18**: every switch is locked on ask-first, there is no web research, and the tutor stays on hints first.
- **Cloud only**: the assistant needs the relay, the student's consent (version 3 names the new data: course, topic and exam
  names, due counts, and a research topic) and an account over 13. Without those Ask Cap answers as before. A reply that fails
  before anything is shown falls back to the tutor quietly; one that fails part way keeps what arrived and says so.

## Trust rules (each one is a test)

1. **Grounded or flagged.** Every card and question carries `evidence`. The app finds the quote in the notes
   (`AssistantDrafts.contains`, tolerant of case, accents, quote marks and spacing) and links the item to its page and lines;
   no match means the item is marked "Cap's own words" and is not stamped as checked. In the live test, 72 of 72 quotes were
   exact. A student who says "from your own knowledge" gets exactly that, every item unevidenced and marked.
2. **Nothing is added behind the student's back** unless they switched that kind on, and then it says so and can be undone.
3. **The model is told the truth** about what happened ("proposed" or "added"), so its note never claims more.
4. **Web text is data.** The research route is its own model call with no tools, so a page that says "ignore your rules" can at
   worst change the summary the student reads before saving. A research result becomes a note only on a tap, never on its own,
   whatever "Let Cap do it" says. The relay passes on only https pages on the allowed sites (exact hostname or a subdomain), as
   sources and as citations.
5. **Honest numbers.** A model's multiple-choice question is shuffled by the app (the right option was always first or second).
6. **Kids.** No web, no auto-add, hints first. The relay refuses `research` and drops `research_web` when the request says
   `minor`, but it takes the app's word for that flag (it has no birth date; the age gate is on the device, as for the tutor's
   hints-first mode), so a modified app could ask for the web as an under-18. The cost of that is bounded by the Pro-only rule.

## How it works

```
student ─ message ─▶ AskStreams.ask ─▶ AIRouter.assistant ─ request (notes found by the app, study state with short ids) ─▶ relay ai/assistant ─▶ OpenAI (Terra)
                                              ▲                                                                                  │ stream: tool_start, tool_item…, tool_call, done(continuation)
                                              └── runs each call here: AppModel.runDraftTool / searchNotes / research ◀──────────────┘
                                                  results ("proposed", passages…) go back with the continuation; up to 4 rounds; the last is Cap's note
```

- **Relay** (`supabase/functions`): `ai/assistant` and `ai/research` in `ai/handler.ts`; the tools, their strict schemas and the
  trusted-sites list in `_shared/assistant.ts`; the OpenAI streams in `_shared/openai_assistant.ts`; readers that pull finished
  cards out of half-written JSON in `_shared/argstream.ts`; prompts `assistant.md` and `research.md`; contract in
  `docs/relay-contract.md`.
- **App**: contract `AI/AssistantContract.swift`; reading the model's arguments `AI/AssistantDrafts.swift` (pure);
  the reply loop `AI/AIRouter+Assistant.swift`; the library side `App/AppModel+Assistant.swift` (study index, draft tools,
  add, undo, steps in the chat); values `Model/AssistantSteps.swift` (kept in `ChatMessage.actionsData`; chats never sync);
  screens `Features/Ask/Assistant/*`; settings `Features/Settings/AssistantPage.swift`.
- **Costs** (live test, 50 requests): 0.27¢ a request on average; a drafting turn about 0.25¢; a web research turn 1.7¢
  (tokens plus the search). Meters, all per day:
  - `tutor`: a reply's first round is a tutor message (10 on the free plan), as before.
  - `drafts`: 3 on the free plan, 150 fair use on Pro. One is taken, atomically, **before** the model is asked (so parallel
    requests cannot all pass), and given back if the reply drafts nothing. At 0 the draft tools stay on offer: when the model reaches for one, the relay stops it there and the reply ends with a limit, so Cap says "I can't make anything new today" (the app's own words) with a card that offers Pro. A plain question never meets the limit.
  - `research`: Pro only, 3 a day (at 1.7¢ a turn that is at most about 5¢ a day, $1.53 a month, against the $3.54 a month a yearly
    subscriber nets; it was 5 until 2026-10-27).
  - `rounds` (hidden): the rounds after a reply's first. The relay refuses one when `rounds` would pass three for each tutor
    message that day, so a request made up by hand (a replayed or forged continuation, no first round behind it) costs what an
    honest reply does.
  - A failure that OpenAI billed (an unreadable reply, a cut-off stream) keeps the message counted; one that cost nothing, before
    anything was shown, gives it back.
- **The day's cost cap** (all plans, under every meter): the meters count requests, not money, and Pro's fair-use ceilings alone (300
  tutor messages, 150 drafts a day) would cost more than a yearly plan nets (about 12¢ a day). So before each AI request the relay
  asks the request log what the person's calls have cost since their local midnight (`Store.spentSince`, the database function
  `cramless_spent_since`) and, once that reaches the cap, answers 429 `quota_exceeded` ("That's all the cloud AI for today. It starts
  again at midnight.", no meter named, `retryAfter` to midnight) until the day turns. **10¢**, a starting guess to tune from real use:
  the function secret `DAILY_COST_CAP_USD` (`0` turns it off; an unreadable value falls back to 10¢ and is logged at start-up). A normal
  day costs a few cents. The log is written after each response, so requests still running are not in the sum and a burst can pass
  the cap by what is in flight (one request is about 0.3¢, research 1.7¢). MOCK replies cost nothing and skip the check; if the sum
  can't be read the request goes ahead (the meters still hold) and `daily_cost_check_failed` is logged. In the app the tutor's note
  says "That's all the cloud AI for today, so Cap answered from your notes on this iPhone. It starts again at midnight." (not "couldn't
  be reached"), and an assistant reply a later round of which is refused says it stopped for that reason. The live test tools set the
  cap to 0, since one run sends dozens of requests as the same few people.

## Try it without a key

DEBUG launch hooks (see `CLAUDE.md`): `CRAMLESS_ASSISTANT=cards|quiz|note|exam|practice|research|multi|answer|limit|error`
asks Cap in a Bio 101 chat and plays the mock relay's script; `…_FREEZE=<n>` holds it part way; `…_AUTO=cards,notes,exams`
switches on "Let Cap do it"; `…_APPROVE=<ms>` and `…_UNDO=<ms>` press the buttons; `CRAMLESS_RESEARCH=pro` shows what a free
account sees; `CRAMLESS_ROUTE=settings:assistant` opens the settings page.

Against the real model: `cd supabase/functions && deno run -A tools/assistant_bakeoff/run.ts [--group cards] [--live-research]`
(key from `~/.config/capling/openai_key`, else `OPENAI_API_KEY`; 50 requests, about 13¢; `--mode hints` runs them in the app's default
tutor mode).

## Not in this version

Editing or deleting what already exists by chat (renaming a course, deleting cards, moving an exam); making a new course; a
per-student dollar cap on top of the daily meters; the assistant on the iPhone's own model; open-web research for adults
(deliberately not done: Apple's age ratings ask about unrestricted web access and the floor for a 13+ app was not confirmed);
real site icons.
