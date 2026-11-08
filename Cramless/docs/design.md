# Cramless design notes

The tokens live in code (`Shared/BrandPalette.swift`, `DesignSystem/Theme.swift`, `DesignSystem/Motion.swift`,
`DesignSystem/Haptics.swift`); this page records why they are what they are. The visual reference is the web
prototype in `../../docs/rethink/site/app/` and its screenshots in `../../docs/rethink/site/shots/`.

## Colour

Night `#14213D` ink, Sky `#7CC8FF`, Tangerine `#FF7A1A` for action, Mint `#22C38E` for "you know this", Sun
`#FFCF3F` for "almost", Rose `#FF5A78` for "not yet", Capy `#E0884A` for the mascot. Highlighter marks reuse
Mint, Rose, Sun and Sky at low alpha, so grading feedback and readiness speak the same language.

Contrast (WCAG 2 relative luminance), measured when the palette was set:

| Pair | Ratio | Use |
|---|---|---|
| Night on Tangerine | 6.1 : 1 | Primary button label (white on Tangerine is 2.6 : 1, so it's never used) |
| Night on Mint / Sun / Rose / Sky | 7.1 / 10.8 / 5.3 / 8.8 : 1 | Labels on brand fills |
| `mintInk` `#0B7F5A` on white / page | 5.0 / 4.6 : 1 | Coloured text in light mode (dark: `#4FE0AE`, 10 : 1) |
| `roseInk` `#C8213F` | 5.6 / 5.1 : 1 | (dark: `#FF8199`, 7 : 1) |
| `sunInk` `#8A6200` | 5.5 / 5.0 : 1 | (dark: `#FFD866`, 12 : 1) |
| `skyInk` `#1866AE` | 5.9 / 5.4 : 1 | Links, source chips (dark: `#8FD0FF`, 10 : 1) |
| `tangerineInk` `#B84A00` | 5.2 / 4.8 : 1 | (dark: `#FF9A4D`, 7.9 : 1) |
| `ink2` `#56627A` | 6.1 / 5.6 : 1 | Secondary text (dark `#A9B4C8`, 8 : 1) |
| `ink3` `#6B7489` | 4.7 / 4.3 : 1 | Tertiary text, footnote size and up (dark `#8B97AD`, 5.7 : 1) |
| `ink4` `#8E98AB` | 2.9 : 1 | Placeholders and disabled glyphs only |

Readiness colours: 80 %+ Mint, 50–79 % Sun, below 50 % Rose. A colour never carries meaning alone: rings
show the number, pills say the words, grading marks come with labels.

## Type

- Bricolage Grotesque, bundled as three static cuts (Display = ExtraBold at optical size 96, Title = Bold at 36,
  Heading = SemiBold at 24; instanced from the OFL variable font). It's used for the wordmark, the onboarding
  titles, the paywall headline and the big feedback words.
- SF Pro is used for everything else, and SF Pro Rounded for numbers.
- Every style scales with Dynamic Type through `.clFont(_:)`. With the dyslexia-friendly option on, reading text
  switches to OpenDyslexic (OFL, unmodified), with tracking set to zero.

## Motion

Twelve tokens: `pop`, `settle`, `snap`, `calm`, `fill`, `fade`, `exit`, the highlighter sweep, and for answers
`press`, `release`, `sheet` and `bloom`.
- Each token reads Reduce Motion itself. Under Reduce Motion it becomes a short ease, and looping scenes settle on
  their final frame.
- The onboarding demos use the same tokens as the features they show (the scanner's lock-on, the highlighter,
  the ring climbing), so the demo and the product can't drift apart.

## The first minute

- **The welcome is the memory sky in miniature.** A quiet night scene (dusk, two ridges, a lake that mirrors what is lit) with one small
  constellation, Cap's mortarboard in seven dim stars, and Cap on the shore. His bubble says "Hi, I'm Cap. Light a star with me."
  A touch on a star lights it (a note one step up the scale, a haptic, a ring and a glint that fade); the third lights the rest, a soft
  glow and a shooting star cross the sky, and Cap cheers; "capling"'s star lights too. It teaches the idea (a memory is a star; a little
  every day keeps it lit) before a word is read. Minimal on purpose: a waiting star is a small ring, a lit one a point with a halo, lines
  are hairlines that draw themselves, and nothing glows more than it must. It is also built to be smooth (no blend modes, shadows or
  offscreen layers; its sounds are rendered before the first touch).
  - Nothing waits for the gesture. The buttons are there from the start; if nobody touches, a faint ring pulses on the star he
    would light, he says "Go on, tap one." and lights one himself, then the next, so it finishes by itself in about 17 seconds.
  - Reduce Motion: no ripples, no ignition, no clips; the stars simply light and the sky brightens. VoiceOver: the sky is one button,
    "Lights a star", with "n of 3 stars lit" as its value, and Cap's lines are announced. At accessibility text sizes the world
    is a short band above the words.
- **"capling" is set with a star where the i's dot would be** (`CaplingWordmark`): gold, or faint until it is lit on the welcome.
- **The intro shows what people come for, in six pages:** snap a page (the scan makes flashcards and questions, each marked with
  its kind), flashcards that come back in time (flip, rate, and when it returns; Anki and Quizlet decks come too), answer in your own
  words, know how ready you are, a plan that bends, a tutor that knows your notes. The owner noticed the first version never showed
  flashcards, which is what most people search a study app for.

## Answers

- **Buttons:** filled buttons stand on a darker edge (4, 3 or 2 pt by size, inside the same height). Pressing sinks
  the face onto it (`press`); letting go springs it back with a small bounce (`release`). Answer options and
  flashcard rating tiles do the same on their own shapes (`.pressable(depth:)`). Text-only and disabled buttons
  are flat.
- **The answer panel:** once a question is checked, the footer gives way to a panel rising from the bottom edge
  (`sheet`, `DesignSystem/Components/FeedbackSheet.swift`). It carries the verdict's colour, Cap, and a Bricolage
  headline:
  - "Nice!", "Almost." and "Not yet."
  - "Here's the answer." when nothing was answered.
  - "Saved it." when a right answer rescued a fading memory.

  Cap reacts beside it (see Cap), in an 82 pt box (about 74 pt of Cap; 60 pt until 2026-10-26, 44 pt at the accessibility
  sizes). He stays left of the headline, and the panel's spacing is tightened by the amount he grew, so the panel is no
  taller. The owner's rule for him anywhere: bigger is fine, but never by lengthening a panel or by overlapping what is
  above it (a Cap peeking over the top edge hid the ✕ of a wrong answer and the start of a line of a long one). Under the
  headline come why, the fix and the source, then Continue in the
  verdict's colour (mint, sun, or tangerine for "Not yet": a red button reads as an alarm). At the accessibility
  sizes the panel keeps the headline and Continue, and the details stay in the card. The panel's colour runs on under
  the home indicator to the bottom edge of the screen.
- **Runs:** consecutive right answers make a run (`ComboRun`); each answer plays the next note up the scale.
  - From three, a "3 in a row" chip sits under the headline, and a glass pill with the run morphs out of the timer
    pill.
  - At 5, 10 and 15 the flourish plays.
  - Flashcard self-ratings neither build nor break a run.
  - Nothing ever says a run was lost.
- **The bar:** the newest result blooms (`bloom`); a run of three or more glows mint, with one shine per step.
  Nothing loops while the person reads.
- **Small touches:** the picked option ripples (a Metal shader, `CLRipple`), and its check draws itself on.

## Cap

Cap is drawn, not built in code. Nineteen poses are drawn: wave, study, celebrate and sleep, then think, point, scan,
plan, mic, relax; nice, almost, notYet; listen, ask; sleepy, proud; stargaze, tuckIn.
- A moment names the pose it means (`CapMoment`, `DesignSystem/Components/Cap.swift`). A pose that arrives before its
  art shows a stand-in (`CapPose.fallback`), so new art lands with no other change.
- The art shares one frame (`scripts/cap_post.sh`): every drawing ends on the same feet line, 21 pt above the bottom
  of the 600 pt square, so a hop or a cross-fade between poses keeps Cap's feet where they were.
- **Cap's character sheet** is `docs/cap/` (the sheet and its panels): the turnaround, ten faces, close-ups of his teeth,
  tongue, eyes, paws and hat, the palette and what he always and never does. Everything that moves him is made from it.
  His open eyes are dark, round and have one small white highlight, never a white ring; a laugh shows two small cream upper
  teeth and a pink tongue; he wears the mortarboard in every frame.
- **Cap moves in clips.** Every pose has one: a short transparent video (HEVC with alpha, 720 px, 24 fps, 3 to 5 seconds,
  about 0.4 to 1.7 MB) made from his drawing with Kling 4.0 (`scripts/cap_anim/produce.py`, prompts in `clips.json`) and
  checked before it ships (it starts on the drawing, is on-model, leaves no stray background, matches the drawing's colours).
  - **A clip draws a new picture on every frame.** The video model sometimes animates "on twos" or "on threes" (a new drawing
    every 2nd or 3rd frame, the same one held between), which moves a 24 fps file only 12 or 8 times a second: choppy on a
    120 Hz screen, and the welcome's wave was (found by the owner on the phone). `produce.py check` counts pictures a second and
    warns; `produce.py smooth` draws the missing ones from the real ones (Apple's frame-rate conversion, before the cut-out).
  - A clip starts and ends on its pose's drawing, eased exactly onto it, so the drawing hands to the clip and back with
    nothing visible and clips chain.
  - A change of pose is a cross-fade between drawings. With a clip on screen, the player holds its frame and it dissolves
    into the new drawing over `CLMotion.fade` while the drawing grows a little from the feet; the new clip starts 290 ms
    later, when the dissolve is over. Never let go of a looping clip's `AVPlayerLooper` before that: it takes the frame
    off the layer at once and Cap blinks out for about 80 ms. `scripts/cap_anim/film_gaps.py` finds such blinks in a film.
  - A clip is an **idle** (a quiet loop of breathing, blinking and small things he does, played while he waits) or a
    **performance** (a reaction that plays once when the moment arrives: a cheer, a nod, a wave).
  - `CapScript` (pure, tested) decides what plays. The clip does the moving, so the code's hop, wiggle and nod stand down
    when a pose has one; the entrance (`arrive`) and the sparkles stay in code because they are about the screen, not
    about Cap. A waiting Cap loops his idle; one that isn't asked to wait comes alive now and then (every 5 to 10 s).
  - Clips are off, and Cap is a drawing, under Reduce Motion and when "Cap moves" (Settings ▸ Accessibility ▸ Feel) is
    off. Low Power Mode keeps reactions and drops the waiting. At most three play at once; the rest of a crowded screen
    stays still. Widgets and the Watch use the drawings.
  - **A clip's colour is stored premultiplied, black where it is transparent.** The file says so (`AlphaChannelMode`), and the
    video layer draws the colour planes as they are, so any colour under a transparent pixel is added to what is behind Cap:
    on Today's dark sky it was a lighter rectangle the size of the clip and a halo round him (the first encode fed straight-alpha
    frames to the encoder, and macOS, which multiplies it away when it reads BGRA, hid it from every check). `produce.py`
    premultiplies before encoding and refuses a clip that isn't black under its transparency (`produce.py audit`;
    `CapClipFileTests.testEveryClipIsBlackUnderItsTransparentPixels` reads the planes). Look at a new clip on a dark
    background, not only a light one.
- **Cap answers a tap.** Tapping him, wherever he is (a screen that uses a tap for something else says `interactive: false`),
  does three things at once, and none is the same twice:
  - **His reaction.** Each pose has a second clip, its `poke` (3 s; the same format, starting and ending on the drawing, so it
    plays from whatever he was doing and hands back to it). It replaces nothing: he goes back to waiting as he was, without
    repeating his arrival. A run of taps restarts it only once the last one is well under way, so he never snaps back to its start.
  - **A squash on top.** `CapPoke` (pure, seedable) rolls a new one for every tap: one of five styles (squish, boing, wobble,
    squeeze, wriggle), picked by how the pose takes it (sleepers are nudged, cheerers bounce), with its own press, spring,
    damping, lean and hop, so no two feel alike. They are damped springs rooted at his feet, his width follows his height, a
    limiter holds overlapping springs to a natural squash and they ease to exactly rest, so the layer never pops. A quick run
    of taps gets stronger and ends in a shimmy. A soft haptic follows how hard he was pressed.
  - **A few words.** A bubble over his head (`CapBubble`; it slides sideways to stay on screen, its tail still pointing at him)
    with something short from `CapLines`: lines for his pose, lines for any pose, a greeting for the hour, and flustered ones
    for a run of taps; and when Today's sky has been pulled down and refreshed, one of 14 "refreshed" lines (`CapView(refreshed:)`:
    he reacts like a tap, but says one of these; a tap never picks them). `CapLineBag` deals each pool out without repeating
    until it is used up, never starts a round with the last line of the one before, and carries on after the app is closed.
  - **Settings ▸ Accessibility ▸ Feel.** "Cap moves" governs the squash and the clips (always off under Reduce Motion, which
    leaves only the words); "Cap talks" governs the words. Both off: a tap does nothing.
  - **His lines** follow the voice rules: short (under about 40 characters, 46 at most), warm, specific to what he is doing,
    sentence case, no emoji, and never a nudge about what you haven't done. They are localizable like all copy.
    `CapSpeechTests` checks length, emoji, guilt-trip words, duplicates and the dealing.
  - In Today's sky only Cap takes the tap; the rest of the sky answers with a ripple (the pill opens the full sky).
- Without a clip (or with clips off) Cap moves with four tokens (`CapMotion`), plus sparkles. Each is a curve in code, tested like an engine:
  - **hop:** squash, stretch up, land and settle.
  - **wiggle:** a wobble from the feet.
  - **nod:** two small, kind dips.
  - **arrive:** rising from the feet with a little overshoot.
  - **sparkles:** five stars bursting around the head.
- Cap waits in one of two ways: breathing while the AI works (his clip loops; without one the code breathes for him), or
  dozing with z's drifting up.
- Under Reduce Motion Cap doesn't move, and a change of pose is a cross-fade.

| Moment | Cap |
|---|---|
| "Nice!" | nice, hop |
| 5, 10, 15 in a row | celebrate, hop, sparkles |
| "Saved it." | nice, hop, sparkles |
| "Almost." | almost, wiggle |
| "Not yet." | notYet, nod |
| "Here's the answer." | point |
| The AI checking or making something | think, breathing |
| A session's end | celebrate, arrive; then the celebration's hop (and sparkles) |
| A streak milestone | proud, sparkles |
| Exam eve's end | sleep, arrive, dozing |
| Streak at risk | sleepy, dozing |
| Today, the sky | stargaze, breathing |
| Today, nothing due | relax, breathing |
| Today, the day's work done | proud, breathing |
| Today, exam eve with nothing more to do | sleep, dozing |
| Study out loud: Cap is asking | ask, breathing |
| Study out loud and Teach Cap: your turn | listen, breathing (Teach Cap: a nod for each idea he hears) |
| Teach Cap: what you covered, all of it / some / none | nice / almost / ask |

## Memory sky

Every item you've studied is a star, every topic a constellation, every course a patch of the sky, and every upcoming
exam a faint region around what it covers. A star shines while the item is remembered and dims as it fades;
answering relights it. It is the one picture of "how ready am I", and it can't lie: nothing in it is decoration.

`SkyEngine` (`Engine/Sky.swift`) is pure, like the other engines.
- **Layout is stable.** It depends only on ids, order and counts, never on how well things are remembered, so stars
  stay put as days pass.
  - Items group by topic; items with no topic form a field per course, with no lines.
  - Stars sit on a Vogel spiral (radius √(k+½), a golden angle further round each time), nudged up to 0.3 by a hash
    of their id.
  - A constellation reserves room for the next power of two of its stars (at least 4), so nothing moves until a topic
    doubles. Constellations of a course are placed along golden-angle directions at the nearest distance that keeps
    clear; courses are packed in rows to the shape the sky is drawn at.
  - Lines are a minimum spanning tree over a constellation's first 12 stars, plus a closing edge from six stars on. A
    line is as bright as its dimmer star.
  - An exam's region is the smallest circle around the constellations it covers (Welzl's algorithm). It records which
    constellations those are (`Region.covers`), because a circle can have another constellation's corner inside it
    that the exam doesn't cover; what lights with a region, and what Progress shows of it, is what it covers.
- **Light** is the memory's chance of recall now (FSRS), shown as brightness from a faint glow at 35% to full at 97%.
  - Below 70% a star counts as dim, which is the same line as "saved it".
  - An item never studied is a hollow ring.
  - A fragile memory (low stability) flickers, bright but restless. FSRS counts whole days, so recall alone would make
    a card you just missed look mastered; the flicker says it isn't.
- **Relit** is what a session did: a star that began below about 90% recall (or was new) and ended right. A star
  already at full brightness that is answered right is kept bright, not relit. A new item answered right is lit for
  the first time.
- **Saved** is exactly the "Saved it." the person saw: a right answer (Good or Easy) on a fading item. A "Hard" is
  "Almost.", so it relights the star but isn't a save. The flare, the summary's count and the headline all use
  `ReviewOutcome.isSave`.

| Where | What shows |
|---|---|
| Today, the top | The sky edge to edge, with Cap on the horizon and "63 stars · 20 dim ›" (see Today and Progress) |
| Progress | Each fading topic as a constellation glyph with Practice |
| The sky screen | The sky, full screen: tap a constellation to focus it, drag to look, pinch to zoom |
| A focused constellation | Its name and course, a bar of bright, dim and not-yet-lit stars, "Practice Meiosis · 4 min" (a practice session for that topic, its dim stars first) and "Open course" |
| During a session | When "Saved it." comes up, a gold four-point star blooms over the question with a ring and a few motes, about a second, with no sound of its own (the save's marimba note plays with the verdict). A flashcard flares as you rate it |
| The summary | A night strip under the numbers: "Relit 12 stars · 3 saved", which opens the sky |
| Opening the sky after a session | The relit stars ignite one after another through the constellations, once; a save gets a gold ring and a sparkle |

- **Drawing:** one `Canvas` in a `TimelineView` at 30 fps (`SkyRenderer`). Stars are batched by course colour,
  brightness step, restlessness and twinkle phase, so thousands of stars are a few dozen fills. Bright stars get a glow.
  It pauses off screen, in Low Power Mode and under Reduce Motion.
- **Reduce Motion:** nothing twinkles, the camera cuts instead of gliding, a relight shows its result, and the flare is a
  star that fades in and out. A restless star gets a dashed ring instead of a flutter.
- **Differentiate Without Color:** bright stars carry a cross and restless ones a dashed ring; dim stars are plain dots and
  unlit ones rings. The counts are always in words as well.
- **VoiceOver and large text:** "Sky as a list" shows the same thing as rows by course (and is the default at the
  accessibility text sizes). In the sky, each constellation is an element ("Meiosis, Biology 101. 5 of 8 stars bright,
  2 dim. Recall about 74%") with a Practice action, and rotors for dim constellations and exams.
- **Cap** watches from his telescope when the sky is empty.

## Today and Progress

Today is the plan first: a short band of sky, the day's one card, the week, one of Cap's cards and the exams. Progress is the
same sky, taken apart.

**Today** (direction A, "plan first"; `TodayView`), top to bottom:
- **The band** (`TodaySkyHero` over `HeroWorld`, `HeroWorldGeometry.band`): 188 pt of your memory sky under the status bar on
  every phone (250 on a 17 Pro, 208 on an SE), edge to edge and up behind the status bar. On it: the date and a greeting by the
  hour ("Good afternoon, Maya"; "Welcome, Maya" on the first day), the streak pill and the avatar; Cap (96 pt) on the shore at the
  bottom left; "17 stars dimming ›" (or "63 stars") at the bottom right. A tap anywhere opens the full sky, where the
  constellations, their cards and Practice live; on the first day's outline sky a tap ripples. The welcome keeps the tall world
  (`style: .world`).
- **The day card** (`TodayDayCard`, words in `TodayHeroContent` and `TodayCopy`): a chip naming the exam today's session
  serves (`SessionFocus`: an exam within a week with 20% of its minutes, the soonest first, else the one with 40%) and when it is ("For Chem 110 Quiz" · "Sun · in 2 days"), a title of up to two
  topics, weakest first ("Limiting reagents and Stoichiometry", more counted, never "then"), one reason ("The weakest topics for this exam, plus
  12 questions you're about to forget."), readiness now beside a dashed ring for about where today's session takes it ("42% ready
  now" / "about 52% after today": the ring's own function over today's actual session, `ReadinessEngine.valueAfter`; "Based on
  7 questions so far." under 15 questions), "Study · 15 min" and "Why these?" (a fitted sheet, `TodayReasons`: the exam's scope,
  its weakest topic and how many of today's questions are on it, what is due, what waits and why; "Study something else" opens
  the sky as a list).
- **Your plan** (`TodayPlanCard`, `TodayPlanStrip`): two days back (a check, a snowflake or a hollow circle: never red), today
  (its minutes, ringed, or a check), four days ahead with each exam's eve (a moon, and the minutes its plan gives it: "1m", what the exam page says) and day (a mortarboard, "2" when two
  share it) from the shared exam plans. "Calendar" opens the streak page, whose month marks exams and eves and goes one month
  ahead. Once a first session is done, today's quests fold into one line ("0 of 3 quests today · 5 of 12 this week") that opens
  them in a sheet.
- **Cap noticed** (`TodayNoticeCard`, `CapNotice`, dealt by `NoticeEngine`, said by `NoticeContent`): one card at a time with "2 of 3", its
  action, Later (until tomorrow, with a toast), what the action uses ("No AI", "Uses Cloud AI") and a menu with "Don't show these". At most three
  a day, one per kind; a card acted on stays away for 7 days. Counts and minutes, never a percentage. On an exam's eve (any exam tomorrow) the
  slot is his quiet line instead: "Cap is quiet tonight. Bio 101 and AP Psychology can wait until after Chem 110 Quiz." Two exams on one day share the
  evening: one session, both named, and neither waits.
  - Mix-up: "You keep mixing up anaphase and telophase." / "Missed 3 of the last 4 times. Want a 2-minute fix?" / "Fix it · 2 min" / "No AI".
  - Look-alike: "Metaphase and telophase look alike" / "Both are on Wednesday's Bio 101 Midterm. Learn the one difference now?" / "Show me" /
    "Uses Cloud AI" ("No AI" when Cloud AI won't be asked). The sheet (`LookAlikeView`) sets the two side by side with their sources and the one
    difference: at once by the rules when Cloud AI won't be asked; otherwise "Cap is writing it" until the lesson is ready, shown once, "Written by
    Cap from your two questions". "Try 2 questions" or "Not a look-alike".
  - Fading: "18 questions will be dim by exam day" / "From Lecture 3, for your Bio 101 Midterm. 6 more minutes today and tomorrow keeps them." /
    "Fix my week" / "No AI". After it: "Plan updated" / "6 more minutes today and tomorrow for Lecture 3." / OK, Undo. The minutes show on the day
    card and the plan strip.
  - Welcome back: "Welcome back, Maya" / "Your best streak, 23 days, is still yours. 5 minutes today lights your flame again." / "Start 5 min" /
    "No AI". Never a restored streak: nothing to lose, nothing faked. In Quiet mode the card stays and says "Your stars waited for you. 5 minutes today is a good start."
  - Mock offer: "A mock exam for your Bio 101 Midterm" / "20 questions like the real one · 25 min" / "Take it" / "Free". 2 to 7 days before the exam, never on the eve or the day.
  - Gap: "2 topics on your Bio 101 Midterm have no notes" / "Meiosis and Genetics. Want help filling them in?" / "Fill the gap" / "Free". From 28 to 2 days before the exam. The same card sits under the topics on the exam page, with Later; a topic with drafts waiting says "Questions for Meiosis are waiting for your review." `FillGapSheet`: "Snap the chapter" (the scanner aimed at the topic) or "Find it on trusted study sites" (Pro, never under 18). "Nothing is added until you say so."
  - A date heard in class: "Cap heard an exam date" / "“The second quiz is on November 20.” From Lecture 6." / "See it" / "Free". Never a notification: it may be misheard. It leads to the card at the top of the lecture's notes (`ExamHeardCard`), with the words, "Add the exam" and "Not now"; the exam covers the whole course, then "Exam added, 14 days away" with Undo. A date the plan has on another day: "Your Bio 101 Midterm is set for Nov 29. Cap heard Nov 20." / "Use Nov 20".
  - In the week before an exam a card may also come as one notification instead of that day's reminder and streak nudge: no counts, because they
    would be stale (`NoticeContent.pingBody`). A card's menu has "Don't show these"; the kinds turned off are listed in Settings ▸ Study ▸ Hidden tips (shown only while one is), each with "Show again". Settings ▸ Notifications has the "Cap noticed" switch.
- **Exams** (`TodayExamsRow`): tiles in a row, two and the edge of the next on any phone (a 46 pt ring, the name, when, rose within three days, "+15% this week" with an
  arrow), "See all" to the Progress tab. With material and no exam: "When is your next exam?" and "Add an exam" (the editor asks
  for a course's name when there is none). Hidden on the eve.

| Day | Chip | Title | Button |
|---|---|---|---|
| A plan day | "For Chem 110 Quiz" · "Sun · in 2 days" | its topics | "Study · 15 min", "Why these?" |
| Catch-up | the same | the same; the backlog is the reason | "Study · 15 min" |
| No exam, or none the session serves | none (no rings) | its topics or courses | "Study · 15 min" |
| Exam eve | a moon, the exam · "Tomorrow · 10:00" | "Tonight: weak spots only" | "Tonight · 4 min" (the session's own minutes, at most 10) |
| Eve, nothing weak or done | the same; the sky stops twinkling, Cap sleeps | "Nothing left to review tonight" / "That's enough for tonight" | none |
| Done | "Done for today" · "15 min · 24 answers" | "Bright tonight", with "Chem 110 Quiz: 52% ready" and "+10% today · 2 days to go" | "5 more minutes" (quiet) |
| All lit | none | "All lit" | "Practice Limiting reagents · 5 min", or "Practice · 5 min" when that won't fit (the reason names the topic) |
| No questions yet | none (outline sky) | "Let's make your first set" / "Add your first material" | "Try a sample page", "Scan a page" |

- One big button a day; one word per job ("Study", "Practice", "Tonight"); "questions", never "cards".
- Readiness is the only percentage; the projection ring is dashed, so it reads without colour.
- Large text: the band is low with only the streak and avatar on it and the greeting below; the rings sit above their words; the
  week is five rows in words; the exams are rows, and a pill wraps rather than cutting off.
- A chip and its when-line take two lines when one won't hold them, and a line of parts joined by "·" (`DotLine`) breaks into one part
  to a line, so no line ends on a hanging dot.
- VoiceOver: the greeting, the streak, the avatar, "Your memory sky" (opens the sky; a Refresh action), the card (chip, title,
  reason, "42 percent ready now, about 52 percent after today, projected", the button, "Why these?"), the week as one element read
  day by day, Cap's card ("Cap noticed, 1 of 2"), the exams.
- On an iPhone SE the day card, button included, ends above the tab bar (`TodayRenderTests`).

The band's world (`HeroWorldGeometry` says where everything sits, `HeroWorldRenderer` draws it, `HeroWorldModel.swift` is the pure
parts):
- **Layers, far to near**: a dusk at the horizon, a pale Milky Way band, 240 faint background stars at three depths (a few glint),
  a soft cloud of each course's colour behind its constellations, the sky itself (`SkyRenderer`, the same as the full screen),
  a shooting star now and then, far hills lit along the ridge and a mist, middle hills, a strip of lake (too thin to mirror the
  stars, so it doesn't), and the ground Cap stands on.
- **The sky fills its room**: it is laid out for the band's free sky (`HeroWorldGeometry.skyAspect`, about 0.32), and the camera
  may start closer than the full screen's (`SkyCamera.fit(largest:)`). The exam regions keep their dashed rims.
- **It has depth**: tilt the phone and each layer moves by its own amount (`HeroTiltFilter`). With no motion sensor (the
  Simulator) the layers sway slowly on their own. It draws at the screen's own rate while anything moves, and not at all
  otherwise.
- **It stays put when the page is pulled**, and the pull is pull to refresh (`HeroRefresh.swift`): the layers lean, the ridge
  lights at the line, and letting go sends an arc of light up the sky, a falling star, Cap's "refreshed" line and "Sky refreshed"
  on the pill. Under Reduce Motion nothing leans or moves; the sky brightens evenly for a moment.
- **It rests**: nothing moves under Reduce Motion, nothing ambient in Low Power Mode, nothing while the band is scrolled away or
  the app is in the background, and on exam eve once there is nothing left to do it holds still.

**Progress** has no second sky, and takes about a screen and a third. In order:
- **This week**: the flame and the run ("12-day streak"; on hold, an outline and "On hold"), the minutes against last week and the week's chart. All of it one tap: the month (`StreakMonthSheet`, a fitted sheet with the calendar and today's notes, and a way on to the streak page). A repair offer sits under it, outside that tap.
- **Exams** as rows: a ring, the name, "in 2 days · +15% this week" (rose within three days), a sparkline ending in a star. Readiness is the one percentage; no letter here (the exam page has it once logged grades calibrate it).
- **Fading**: topics with questions under the sky's dim line, for the nearest exam first, as their constellations drawn small (`SkyGlyphView`), "Chem 110 · 2 questions fading" and Practice. "Nothing is fading right now." when so.
- **Mix-ups**, when there are any.
- Two tiles: **Badges** (three medals, "3 of 13 earned") and **Memory sky** ("63 stars · 17 dim").

The streak page has the twelve weeks of studying (the heatmap's days are stars: a dot that grows and brightens with the minutes, a sparkle from the third step, a glow at the top, so size and shape carry the scale as well as colour does). The sky has "How you remember": what's coming due and the brightest topics, counts only, as a fitted sheet over the sky and at the head of its list.

**Library**: "Recent" (questions to review first, then what was opened or added on this iPhone in two weeks; three at most, none under two), then the courses, each with its next exam's ring or "Add a date". The tab bar's + is the way in; "Bring your stuff" is for a person with no courses yet.

**A course**: the ring, a chip for each exam ("Midterm · Nov 29 · 53% ready", "Quiz · log your grade", "Quiz · you got 91%"), "Study Bio 101 · 15 min" (the daily rules limited to the course, at the whole goal) with a round +, and three tabs: Topics (readiness for the next exam, gaps first by their course order, "Not on the Midterm" apart with counts only; a tap shows the topic's questions, Practice is its own button), Sources, and Questions (needs attention, meaning fading or in an open mix-up, weakest first; suspended; format; topic).

**A mock exam** (`Features/Mock/`): free, built from the exam's own questions and shaped like it. No marks until the end: Back, Next and Flag, a countdown nothing has to redraw for, a grid to look over. "Time's up." offers "Finish untimed" before the score. "Cap predicted" is the fair score for these questions, recall now plus a guess on multiple choice, not the exam-day ring: a mock taken early would otherwise beat Cap and teach that the number is wrong. Never on the eve or the day: tonight is for weak spots and sleep.

**The last look** (`LastLookView`, a sheet): the eve's end. "Your last look", then five ideas as one sentence each, each with a chip to the page it came from, then "That's enough for tonight. Sleep is part of studying. Good luck tomorrow." and "Good night". No quiz, no marks, no timer. It is offered in words, on the eve's summary and quietly on Today's done card, never pushed.

**Busy days** are Cap's cards like the rest: the ask ("Cap can plan around your long days") and "Monday looks busy", whose button moves minutes and whose confirmation has Undo. The day stays in the strip with its shorter minutes.

**The Squad on Today** is one line in "Your plan": faces with a check mark for who studied today, and words beside them. It opens the Squad. It isn't a score, there's no count of days, and it goes away on an eve and in Quiet mode.

## Celebrations

Learning earns celebrations; buying never does. The purchase screen stays calm, with no confetti.

`CelebrationPolicy` (`Engine/Celebration.swift`) takes what a session did and picks one celebration per screen: the
biggest reason wins and names the summary's title.

| Reason | Size | Title |
|---|---|---|
| The first session after onboarding | big | First session done |
| A streak of 3, 7, or 30/100/365 days | small, medium, big | 7 days. (the hero becomes the flame) |
| Readiness crossing the exam's goal | medium | Goal reached |
| A mix-up fixed | medium | Mix-up fixed |
| A new badge | medium | the badge's name |
| Every answer right first time, 5 or more | small | All right first time |
| Another day on the streak | nudge | Session done |

- **Sizes:**
  - A nudge is Cap hopping.
  - Small is a puff of confetti from behind Cap.
  - Medium is a burst, with Cap's sparkles.
  - Big is confetti from both bottom corners, across the screen.
  - The confetti (`CLConfetti`) is paper in the course colours, seeded so a film repeats.
- **Limits:**
  - Exam eve and quiet hours are calm: no confetti, and Cap's sparkles if there's a reason.
  - A big celebration plays at most once a day; another that day is medium.
- **The summary's order:**
  - Cap arrives, then the done sound with its haptic.
  - The numbers count up, with at most 12 light ticks (`CLCountingText`).
  - The ring climbs, with ticks again, and the streak rolls over.
  - The sky line says what the session did to the sky, and the day's quests tick off one by one, each with a light tick
    (a sky the week's quests lit comes up under them).
  - Last comes the celebration, and, rarely, the system's rating prompt a beat and a half after it.
  - The confetti is silent: the summary has one sound.
- **Reduce Motion:** everything shows its final state at once, with no confetti.

## Taking a rating back, and swiping one

A rating the student gives themselves is the one answer with no second look, so it can be taken back: a flashcard's rating or swipe, the
marks of an own-words answer, a "Counts as" call. The session moves on at once and a glass pill floats just above the next question's
footer, "Easy · back in 4 weeks" and **Undo** (⌘Z), for 5 seconds (15 with VoiceOver). The pill takes no room, so no button moves under a
finger, and it steps aside once the next question has been checked. Undo brings the question back from the leading edge as it was: the card
flipped, the own-words panel with its ticks, no new grade and no sound. After the last question the same moment is a small screen, Cap and
"That was the last one." with **See how it went**; the summary starts when the rating is recorded. Graded answers keep Continue, which is
already their moment.

A flipped flashcard can be swiped: right is "got it" (Good), left is Again. The card follows the finger with a little tilt (none under
Reduce Motion), a stamp says what letting go does ("Got it · 4 days"), past 35% of its width or on a flick it flies off and the next one
rises in its place; a flick back the other way is a change of mind. The chips "← Again" and "Got it →" do the same, Hard and Easy stay as
tiles (Hard counts as got it in the tally), and the ← → keys work. The four-tile grid stays at the accessibility text sizes and with
VoiceOver or Switch Control, and VoiceOver has the four as actions on the answer.

## The game loop

Nothing here is a currency, a shop or a way to lose something. A quest finished stays finished, a badge earned stays earned,
an icon or a sky unlocked stays unlocked, so a streak that breaks takes nothing away. Each part fits in a sentence and lives on a
screen that was already there.

**The flame** (`StreakFlame` over `StreakStage`, `Shared/`): five looks for how long the streak is, drawn in code from three paths
and no asset, so the widgets draw the same. A spark (1 to 6 days), the flame with a bright heart (7 to 29), the flame with a
warm glow and two embers (30 to 99), gold with glints (100 to 364), and gold with a star over it (365 and more). With no streak,
or one on hold (a missed day a repair can still join back up) it is an outline. It is in Today's pill, the streak screen, Progress's
streak card, the badges and the two full-colour widget pills (the Lock Screen's stay monochrome symbols). It bounces once when
the streak grows (`bounce:`), and never under Reduce Motion.

**Quiet mode** (Settings ▸ Study) turns the whole layer down for someone who wants the plan and nothing else: no flame, quests, badges
or run counter, celebrations calm, no streak notifications, no "a new sky is lit", no sounds, and the Streak page and Progress's month sheet are only the calendar; Progress keeps its week, exams, fading topics, mix-ups and the sky tile.
Their plan, stars and readiness stay. Quests and badges go on settling unseen, so turning it off again loses nothing, and a Streak widget
someone placed stays as it is (they put it there); the Today widget loses its flame.

**Milestones** are 3, 7, 30, 100 and 365 days (`StreakStage.milestones`; the flame changes at the last four). The summary's hero
becomes the milestone: Cap proud, the stage's flame popping in beside him and bouncing once, "30 days." as the title and one
warm line about the memory, never about the number ("A month of showing up. Your sky is brighter for it."). The streak screen
lists all five, a check for each the best streak has reached and how far the streak is along to the next. The day one session
makes a milestone (a streak of 29, today not done; or 29 and done, for tomorrow) the reminder and the 20:30 nudge say so: "One
session today makes it 30 days."

**Daily quests** (`QuestEngine`, pure and seeded, so a day's picks are the same on every device):
- Three a day: "Finish today's session" every day, and two more that the material allows: save 3 fading stars, answer 2 in your own
  words, study before noon (only offered to someone who opens the app before 10:00), fix a mix-up, meet 5 new questions, get 5 right
  in a row, practise for your exam (5 answers on what an exam in the next month covers).
- Picked the first time the app is opened that day and kept all day. Yesterday's two come last in the order, so they rarely repeat. None
  on exam eve and none with nothing to study. They show on Today after the first session is done, never before.
- Read from the day's own answers: Today's card counts "2 of 3" as they come in, and a quest's bit goes into `DayRecord.questMask`
  when the session is settled (the summary does it; a day the app was not opened after is settled at the next launch). The mask syncs as
  `quest_mask` and merges by OR, so two devices' quests add up and a bit never goes back; at most 3 count for a day.
- No reward in points. 12 quests in a calendar week light the next sky; each week lights one at most.

**Skies** (`SkyTheme`, six, drawn in code): Night is the look Capling has always had and is always there. Dusk, Aurora, Ember, Bloom
and Glacier are lit one at a time, in that order, by weeks of 12 quests. A sky is a palette (`SkyPalette`): the sky's own gradient, the
dusk at the horizon, the pale band, the faint stars, the hills, the lake and the ground. The stars keep their course colours in every
sky. Settings ▸ Appearance ▸ Sky picks one (an unlit one is a dim silhouette with what lights it). Every white thing drawn over a sky
(the date, the pills) clears 7:1 on all six (`SkyThemeTests`). Today's world, the full sky, the exam stills and the constellation
glyphs all read the palette from the environment (`\.skyTheme`, set at the root).

**Badges** (13, `Badge`, `AchievementEngine`): first session, 10 stars saved, 25 answers in your own words, a mix-up fixed and five,
best streaks of 7, 30, 100 and 365 (each wears its flame), 80% ready on an exam morning, a grade called within 5 points, 1,000
answers, a repaired day. Worked out again from the log each time (a fact only grows) and kept in `settings.badges` once the
person has been told, so nothing is lost if the history is trimmed and nothing syncs. The first launch with badges notes what is
already earned without a fuss. A badge is a metal medal (`BadgeMedal`): a rim, a disc (a night disc for the flames, which would
vanish on orange or gold), the glyph and a sheen that slides as the phone tilts. In its sheet (`TiltingMedal`) it turns up to 12
degrees with the sensor, sways slowly where there is none, and stands still under Reduce Motion. One not earned yet is a silhouette
with how far along it is. Progress has a row of four and "See all".
- **Trap:** a `.shadow` on the whole medal, `inset(by:)`, a blur and a `plusLighter` sheen together, in a card that fades in, drew
  a second hard-edged medal beside the first on screen (not in an `ImageRenderer`). Each layer now has its own size, and the
  shadow is a gradient disc. Look at anything with layers in a real screenshot, not only in a render test.

**App icons** (`AppIconChoice`): Cap on blue, and four more a best streak unlocks at the flame's milestones: Night (7 days),
Ember (30), Gold (100) and Aurora (365). They are drawn from the main icon by `scripts/make_alt_icons.py` (Cap cut out of the blue
and set on four new skies; the gold one is his fur regraded), not generated, so they cost nothing and can be redrawn. Settings ▸
Appearance ▸ App icon. The system shows its own alert when the icon changes.

**The rating prompt** (`ReviewPromptPolicy`): only after a good moment (a session of 8 or more answered right first time, 2 saves,
or a milestone), never in the first 4 days or 5 sessions, never on exam eve, 120 days apart at least, once a version, and never in
the harness or in tests. It asks 1.5 seconds after the summary's celebration.

## Studying out loud, and teaching Cap

Two ways of studying with the voice (`docs/BUILD.md` ▸ Stage 4 has how they work).

- **Study out loud** is for a walk: nobody has to look. Cap asks, the person answers, Cap says how it went, in the session's own words. The screen shows who is talking, the question, the words as they're heard and how it went, with Repeat, Skip and Pause for when a hand is free; the Live Activity carries the same line, with Repeat and Skip, on a locked phone. It enters from a quiet link beside "Why these?", not a second button: the day still has one job.
- **Teach Cap** is for a topic that's going well: "Explain \(topic) to me like I missed the class." His notes fill in as he hears each idea and never show what hasn't been said, which would be the answer. Then "What you covered" as a count of ideas, never a percentage, one follow-up, and the missing idea as a question.
- **Sounds:** none while the microphone is on (`AudioFocus`): the voice is the feedback, and the phone must not hear itself.

## Haptics

Haptics belong to the person's own actions. Each action has one haptic:
- a page turn ticks
- an answer submission commits
- a key idea landing ticks
- a session finishing plays the done cue's swell

Demo loops and timers fire none. `CLHaptics.isEnabled` is the one switch.

A moment that also has a sound (a verdict, a run of right answers, a save, the finish) plays both through
`CLFeel.play(_:)`. Its haptic is one tap under each note, at the note's time, so touch and sound land together. A
run's taps get firmer and crisper as its notes climb, and a misstep is soft and dull, never a buzz.

## Sound

Sounds are synthesized (`DesignSystem/Feel/CLSynth.swift`): a palette is the partials of a struck bar and how fast
they fade, and every cue is a few notes on it.
- **The scale:** a run of right answers climbs C major pentatonic, so every run is in tune and a good session plays
  a little phrase. "Almost" steps down softly; "Not yet" is a muted low pair, never a buzzer.
- **Restraint:**
  - Sounds mix with other audio and go silent with the Silent switch.
  - They play 6 dB softer in quiet hours, and never while read-aloud or the microphone holds the session
    (`AudioFocus`).
  - Taps, page turns and selection make no sound.
- **Switches:** Settings ▸ Accessibility ▸ Sounds (with "Hear an example") turns them off; Haptics is its own
  switch.
- **Palettes:** Marimba, Kalimba and Glass were rendered for the owner to choose from
  (`scripts/sound_audition/run.sh`, review page Phase 0). The owner picked Marimba on 2026-10-23, at the rendered
  loudness. Kalimba and Glass stay in the Feel lab and the audition script for comparison.

## Voice

Cap is calm, warm and specific: "22 minutes tonight and you're done." The app never guilt-trips, never uses
emoji in the chrome, writes in sentence case, and labels a projection as a projection.

Buttons name the action in plain words: Study, Practice, Catch up. The sky's words (lit, relit, dim, fading) say what
happened or how a topic is doing, and are never the thing to tap: a button once said "Relight" and nobody could tell
what it would do.
