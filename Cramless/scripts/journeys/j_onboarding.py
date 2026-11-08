"""The first minute: the welcome, a page made into questions, two of them answered, the plan."""
from __future__ import annotations

from phone import Phone
from registry import journey

STARS = [(195, 157), (87, 167), (303, 155)]     # the welcome sky's stars, in points (iPhone 17 Pro)


@journey("welcome", "The first minute",
         "A new student opens Capling: a welcome you can play with, a first set made from one page, two quick questions from it, "
         "and a plan.",
         env={"CRAMLESS_SEED": "0", "CRAMLESS_ONBOARDING": "1"})
def welcome(p: Phone) -> None:
    p.mark("The welcome: a night sky, and Cap")
    p.dwell(2.4)
    for x, y in STARS:
        p.tap((x, y), after=1.1)
    p.mark("Tap a star and Cap lights the constellation")
    p.dwell(1.0)
    p.tap("Get started")
    p.mark("Snap a page. Get questions.")
    p.dwell(1.6)
    p.tap("Use our sample page")
    p.mark("The page is read, the ideas found, the questions written and checked against the page")
    p.wait("re:^Add \\d+ questions", timeout=60)
    p.mark("Review the questions before they join your set")
    p.dwell(2.0)
    p.tap("Source: p. 87")
    p.mark("Every question says where it came from")
    p.dwell(2.4)
    p.dismiss()
    p.dwell(0.8)
    p.tap("re:^Add \\d+ questions")
    p.mark("Two quick questions, from your page")
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
    # The sample page makes no exam, so its date isn't asked: the plan has no percentage until a real exam is added.
    p.mark("Your plan: minutes a day and a reminder")
    p.dwell(2.6)
    p.tap("Continue")
    p.dwell(1.2)
    p.tap("Allow")
    p.mark("Free to start; the paid plans are one tap away")
    p.dwell(3.0)
    p.tap("Continue free")
    p.mark("Today, with the first set ready")
    p.dwell(3.0)
