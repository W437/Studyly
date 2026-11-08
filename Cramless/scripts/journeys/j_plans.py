"""What is free, what Pro adds, Exam Pass, and Squad."""
from __future__ import annotations

from phone import Phone
from registry import journey


@journey("plans", "Free, Pro, Exam Pass and Squad",
         "What a free student gets, what a paid one adds, a one-off Exam Pass for the weeks around a single exam, and a plan for four.")
def plans(p: Phone) -> None:
    p.mark("Settings ▸ Subscription: Maya is on the free plan")
    p.dwell(1.2)
    p.tap("Profile and settings", after=2.2)
    p.tap("Subscription", type="Button", after=2.4)
    p.dwell(2.6)
    p.mark("Pro, with 7 days free")
    p.tap("See Pro", after=2.8)
    p.dwell(2.4)
    p.scroll(300)
    p.mark("Yearly, monthly, or Squad: you and three friends on one plan")
    p.dwell(3.2)
    p.tap("Continue free" if p.has("Continue free") else "Close", after=1.4)
    p.mark("Exam Pass: one payment for the 30 days around an exam, nothing to cancel")
    p.tap("Exam Pass", type="Button", after=2.0)
    p.dwell(1.0)                      # leave before the sheet says the App Store is unreachable: the simulator has no store
    p.dismiss()
    p.mark("Squad: four people, one plan; a friend joins with a link or a code")
    p.tap("Squad", type="Button", after=2.6)
    p.dwell(3.4)
