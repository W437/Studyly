"""The memory sky: reading it, and relighting a dim constellation."""
from __future__ import annotations

from moves import study
from phone import Phone
from registry import journey

PILL = (330, 220)       # "17 to review ›" at the foot of Today's sky band (iPhone 17 Pro: the band ends at y 250)


@journey("sky", "The memory sky",
         "Every star is something Maya has learned and a constellation is a topic. A star dims as it is forgotten and lights when it is "
         "studied: Today's sky, the full sky, and one dim constellation relit in two minutes.")
def sky(p: Phone) -> None:
    p.mark("Today's sky band: every star is something learned, and the pill says how many are to review")
    p.dwell(3.0)
    p.mark("A tap opens the whole sky")
    p.tap(PILL, after=3.2)
    p.mark("Three exams, each its own region: bright stars are fresh, dim ones are fading")
    p.dwell(3.4)
    p.tap("Learning, AP Psychology")
    p.mark("A dim constellation: none of its three stars is bright")
    p.dwell(3.0)
    p.mark("Practice it: a short session on exactly this topic")
    p.tap("Practice Learning")
    p.dwell(1.0)
    study(p, rate=["Good", "Good", "Easy"], stop_at="right first time")
    p.mark("Done: the stars it lit")
    p.dwell(7.0)
    p.tap("Relit")
    p.mark("The same sky, after: Learning is bright again")
    p.dwell(4.5)
    p.tap("Sky as a list")
    p.mark("Or as a list: the same sky, for VoiceOver and large text")
    p.dwell(3.5)
