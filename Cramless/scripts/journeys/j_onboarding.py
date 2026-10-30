"""The first minute: the welcome, the demos, the questions, the first set, the plan."""
from __future__ import annotations

from phone import Phone
from registry import journey

INTRO = ["Snap a page. Get a study set.", "Flashcards that come back in time.", "Answer in your own words.",
         "Know how ready you are.", "A plan that bends with your week.", "A tutor that knows your notes."]
STARS = [(195, 157), (87, 167), (303, 155)]     # the welcome sky's stars, in points (iPhone 17 Pro)


@journey("welcome", "The first minute",
         "A new student opens Capling: a welcome you can play with, six short demos, four questions, a first set made from one page, "
         "two quick questions, a plan.",
         env={"CRAMLESS_SEED": "0", "CRAMLESS_ONBOARDING": "1"})
def welcome(p: Phone) -> None:
    p.mark("The welcome: a night sky, and Cap")
    p.dwell(2.4)
    for x, y in STARS:
        p.tap((x, y), after=1.1)
    p.mark("Tap a star and Cap lights the constellation")
    p.dwell(1.0)
    p.tap("Get started")
    # Six short demos of what Capling does, each a live miniature. A person reads one and moves on. Continue is at a fixed place,
    # found without asking the screen: the demos loop animations, and the driver waits for an app like that to go idle.
    for title in INTRO:
        p.dwell(0.6)
        p.mark(title)
        p.dwell(3.0)
        p.tap((201, 805), after=1.0)
    p.mark("Four questions, one tap each: what you're aiming for")
    p.dwell(1.2)
    p.tap("Ace my exams")
    p.mark("When your exam is: Capling plans backwards from that date")
    p.dwell(1.2)
    p.tap("Next Month")
    p.tap("Wednesday, 18 November")
    p.tap("Continue")
    p.mark("How long you can give it a day")
    p.dwell(1.2)
    p.tap("15 minutes")
    p.mark("One reminder a day, asked for politely")
    p.dwell(2.0)
    p.tap("Turn on reminders")
    p.dwell(1.2)
    p.tap("Allow")
    p.mark("Where your notes live")
    p.dwell(1.0)
    p.tap("Paper and textbooks")
    p.tap("Slides and PDFs")
    p.tap("Continue")
    p.mark("Your first set: from a page")
    p.dwell(1.6)
    p.tap("Use our sample page")
    p.mark("The page is read, the ideas found, the questions written and checked against the page")
    p.wait("Which class is this for?", timeout=60)
    p.mark("Review the questions before they join your set")
    p.dwell(2.0)
    p.tap("Bio 101")
    p.dwell(1.6)
    p.tap("Source: p. 87")
    p.mark("Every question says where it came from")
    p.dwell(2.4)
    p.dismiss()
    p.dwell(0.8)
    p.tap("Add 16 questions")
    p.mark("Two quick questions to start")
    p.dwell(1.6)
    p.tap("re:\\. Prophase$", type="Button")      # the options are shuffled on every launch
    p.dwell(1.8)
    p.tap("Continue")
    p.mark("In your own words")
    p.dwell(1.4)
    p.type("The chromosomes condense and become visible")
    p.tap("Check my answer")
    p.wait("Explain my mistake", timeout=20)
    p.mark("Graded on the ideas in your answer, not the exact words")
    p.dwell(3.2)
    p.tap("Continue")
    p.mark("Where you stand")
    p.dwell(3.0)
    p.tap("See my plan")
    p.mark("Your plan: a little every day until the exam")
    p.dwell(2.6)
    p.scroll(300)
    p.dwell(1.4)
    p.tap("Start my plan")
    p.mark("Free to start; the paid plans are one tap away")
    p.dwell(3.0)
    p.tap("Continue free")
    p.mark("Today, with the first set ready")
    p.dwell(3.0)
