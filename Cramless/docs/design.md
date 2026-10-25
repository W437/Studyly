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

  Cap reacts beside it (see Cap). Under the headline come why, the fix and the source, then Continue in the
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
| Progress | Each exam's region as a small still; each topic as a constellation glyph with Relight |
| The sky screen | The sky, full screen: tap a constellation to focus it, drag to look, pinch to zoom |
| A focused constellation | Its name and course, a bar of bright, dim and not-yet-lit stars, "Relight Meiosis · 4 min" (a practice session for that topic, its dim stars first) and "Open course" |
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
  2 dim. Recall about 74%") with a Relight action, and rotors for dim constellations and exams.
- **Cap** watches from his telescope when the sky is empty.

## Today and Progress

Today is the sky and one button. Progress is the same sky, taken apart.

**Today** (`TodaySkyHero`, `HeroWorld`, `TodayHeroContent`): the hero is a world, about half the screen: your memory sky
edge to edge behind the status bar with the date, "Today" and the streak on it, and Cap standing in it, large, on the shore
of a lake, not small beside the stars. Under it come the day's button and one caption, then the next exam, Cap's note on a
mix-up, the other exams, ways to add material and the Squad. What each day says and offers is one value
(`TodayHeroContent`), so every state is tested.

The world (`HeroWorldGeometry` says where everything sits, `HeroWorldRenderer` draws it, `HeroWorldModel.swift` is the pure
parts):
- **Layers, far to near**: a dusk at the horizon (violet to rose to peach), a pale Milky Way band, 240 faint background
  stars at three depths (a few glint), a soft cloud of each course's colour behind its constellations, the sky itself
  (`SkyRenderer`, the same as the full screen: stars bigger and glowier here, the brightest with a four-point glint, lines
  a little heavier), a shooting star now and then, far hills lit along the ridge and a mist, middle hills, a lake that
  mirrors the brightest stars as broken ripples, and the ground Cap stands on.
- **The sky fills its room**: it is laid out for the free sky's own shape (`HeroWorldGeometry.skyAspect`), not a fixed
  wide strip, and the camera may start closer than the full screen's (`SkyCamera.fit(largest:)`). Constellations are not
  named in the hero (the card names the one you pick); the exam regions keep their dashed rims.
- **Interactive**: tap a star and the camera glides to its constellation, Cap steps aside, and one glass card slides up:
  its name, how it is doing, "Relight · 4 min" (or "Practice") and a close button. Taps aim at stars (any within 40 pt),
  not at circles, so a near miss still finds the shape; a tap on empty sky ripples, or lets go of what was focused; it does
  not open the full sky (a near miss mustn't throw you out of Today). The "63 stars · 17 dim" pill opens the full sky, and so
  does VoiceOver's one element. Tapping Cap makes him answer (see Cap).
- **It has depth**: tilt the phone and each layer moves by its own amount (`HeroTiltFilter`: where the phone was held a few
  seconds ago is the middle, so holding it at an angle is the new middle). With no motion sensor (the Simulator) the layers
  sway slowly on their own. The ground in front, and Cap on it, stay on the screen's plane.
- **It stays put when the page is pulled**: pull Today down past its top and the page moves under the hero, which doesn't
  (`TodayView` pins it with a visual effect that cancels the overscroll, in the same frame, so it can't lag). Before, the
  full-bleed picture came loose from the top of the screen and showed a white page behind the status bar. Scrolled up it goes
  with the page, as ever.
- **Pulling is pull to refresh, and the world answers it** (`HeroRefresh.swift`, pure and tested; `HeroPullModel` reads the
  scroll view): while you pull, the layers lean down by different amounts (the nearer, the further: background stars 4 to 13 pt,
  the sky 16 pt; the ground never moves), the sky's own stars glow and the dusk brightens. At the line (72 pt of overscroll,
  about 140 pt of drag) there is a tick under the finger and the far ridge catches the light, so you can see it is ready. Let
  go and an arc of light climbs from behind the hills, flashing every star it passes, a star falls, and a beat later Cap reacts
  and says one of his "refreshed" lines (14 of them, dealt like his others) while the pill says "Sky refreshed". A hard flick
  that lifts short of the line but carries the page past it counts too (it began under the finger); a page flung up that
  bounces off its top doesn't. What refreshing does: rolls the day over, pulls what other devices changed (waiting five seconds
  at most), and looks at the sky again as of now (`AppModel.refreshToday`). If the account can't be reached a toast says the
  sky is current on this iPhone. The flourish is 1.3 seconds at least, however quick the work. A focused constellation lets go.
  Under Reduce Motion nothing leans or moves: the ridge still lights, and the sky brightens evenly for a moment. VoiceOver:
  a "Refresh" action on the sky, and "Sky refreshed" is announced (by Cap, when he talks).
- **It rests**: nothing moves under Reduce Motion (the camera cuts and there are no ripples), nothing ambient in Low Power
  Mode, nothing while the hero is scrolled away or the app is in the background, and on exam eve once there is nothing
  left to do it holds still (a tilt still moves it). Cost: about 1 ms a frame for 63 stars, optimised, at 30 frames a second;
  a pull or a refresh draws at the screen's rate and costs about 1.3 ms a frame, 3 ms at worst (the sky is drawn twice).

| Day | The sky | Under it |
|---|---|---|
| A session | Yours | "Relight · 15 min", and "18 reviews · 6 new · 2 weak spots" |
| Catch-up | Yours | "Catch up · 15 min", how much has piled up and how long it takes |
| Exam eve | The exam's region glows, the rest recedes | "Tonight · 10 min", and "10 minutes on your weak spots, then sleep" |
| Exam eve, nothing weak or already done | The same, and it stops twinkling | "That's enough for tonight", no button; Cap sleeps |
| Done | Yours | "Bright tonight", with "5 more minutes" as a quiet extra |
| Nothing due | Yours | "All lit", with "Practice 5 minutes" as a quiet extra |
| No questions yet | Three constellations of unlit rings | "Try a sample page", then "Scan a page" |

- One big button a day. On a day with none, the headline says what the day is.
- At accessibility text sizes the world is a low 180 pt band with only the streak and the avatar on it, the sky laid out
  wide for it, the date and "Today" below it, and Cap steps out so the words have the whole width.
- VoiceOver gets one element for the sky ("Your memory sky, 63 stars, 20 dim. Opens the sky") and the words below it;
  the constellations are listed on the full sky.

**Progress** has no second sky. Each part is a piece of the first:
- Each exam's card has a small still of its region (`SkyRegionStill`): the stars it covers, lit or fading, beside the
  readiness number.
- "Topics" is "Constellations": each topic's shape drawn small (`SkyGlyphView`), how many of its stars are bright, dim
  and not yet lit, and Relight on the ones that need it. "See the sky" opens the full one.
- The study heatmap's days are stars: a dot that grows and brightens with the minutes, a sparkle from the third step,
  a glow at the top. Size and shape carry the scale as well as colour does, so it holds without colour.
- A readiness sparkline ends in a star.

## Celebrations

Learning earns celebrations; buying never does. The purchase screen stays calm, with no confetti.

`CelebrationPolicy` (`Engine/Celebration.swift`) takes what a session did and picks one celebration per screen: the
biggest reason wins and names the summary's title.

| Reason | Size | Title |
|---|---|---|
| The first session after onboarding | big | First session done |
| A streak of 3, 7, or 30/100/365 days | small, medium, big | 7 days in a row |
| Readiness crossing the exam's goal | medium | Goal reached |
| A mix-up fixed | medium | Mix-up fixed |
| A badge (Phase 6) | medium | |
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
  - Last comes the celebration.
  - The confetti is silent: the summary has one sound.
- **Reduce Motion:** everything shows its final state at once, with no confetti.

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
