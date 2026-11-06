"""The game around studying: the day's quests, the streak, badges, and the skies and icons they unlock."""
from __future__ import annotations

from phone import Phone
from registry import journey


@journey("game", "Streaks, quests and badges",
         "Nothing to lose and nothing to buy: three small quests a day, a streak that forgives a missed day, badges that stay earned, "
         "and skies and icons that unlock as a reward.")
def game(p: Phone) -> None:
    p.mark("Today: three small quests, and twelve in a week light a new sky")
    p.dwell(1.2)
    p.scroll_to("Today's quests", top=100, bottom=560, points=300)
    p.dwell(1.2)
    p.tap("Today's quests", type="Button", after=1.0)
    p.dwell(3.2)
    p.dismiss()
    p.dwell(0.8)
    p.scroll(-600, after=0.8)
    p.mark("The streak: 12 days, a freeze saved")
    p.tap("-day streak")
    p.dwell(3.0)
    p.scroll_to("Milestones", top=150, bottom=700, points=300)
    p.mark("Milestones at 3, 7, 30, 100 and 365 days")
    p.dwell(3.0)
    p.scroll(200)
    p.dwell(1.0)
    p.scroll(200)
    p.mark("A freeze covers one missed day; a repair brings back a longer gap. Never a penalty")
    p.dwell(4.0)
    p.back(after=1.0)
    p.tab("Progress")
    p.dwell(1.2)
    p.scroll_to("Badges", top=120, bottom=700, points=300)
    p.mark("Badges you keep: medals that catch the light")
    p.dwell(2.4)
    p.tap("Badges")
    p.dwell(2.8)
    p.mark("Thirteen in all; the ones not earned yet say how far along you are")
    p.dwell(2.4)
    p.tap("First light")
    p.mark("A badge up close: the medal tilts with the phone (here it sways on its own)")
    p.dwell(3.6)
    p.dismiss()
    p.dwell(0.8)
    p.back(after=1.0)
    p.dwell(1.2)
