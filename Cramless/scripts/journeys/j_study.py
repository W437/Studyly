"""Studying: the exam page, a practice run in every kind of question, the summary."""
from __future__ import annotations

from moves import study
from phone import Phone
from registry import journey

@journey("quiz", "Two days before a quiz",
         "Maya has a Chem quiz in two days. Today's card names it; the exam page says how ready Maya is and why; a seven-question practice "
         "run uses every kind of question; the summary shows what moved.")
def quiz(p: Phone) -> None:
    p.mark("Today: the day's card, for a quiz on Tuesday")
    p.dwell(2.6)
    # The day card's chip ("Chem 110 Quiz · Tue ›") opens the exam.
    p.scroll_to("Chem 110 Quiz,", type="Button", top=120, bottom=700, points=300)
    p.dwell(0.8)
    p.tap("Chem 110 Quiz,", type="Button")
    p.mark("The ring: how ready Maya is for this exam, 42%, and how it moved this week")
    p.dwell(2.6)
    p.scroll(380)
    p.mark("A projection, labelled as one, and what it would take to reach the goal")
    p.dwell(3.0)
    p.scroll_to("Practice", type="Button")
    p.mark("Topic by topic: where the weak spots are")
    p.dwell(2.2)
    p.mark("Practice: the questions of this course, in every format")
    p.tap("Practice", type="Button")
    p.dwell(1.0)
    study(p, rate=["Good", "Hard", "Good", "Easy"], slips=(3,), stop_at="right first time")
    p.mark("Done: readiness, streak, and the stars it lit")
    p.dwell(8.5)
    p.scroll(300)
    p.mark("The day's quests tick off")
    p.dwell(2.6)
    p.tap("Relit")
    p.mark("The sky Maya just relit")
    p.dwell(4.0)
