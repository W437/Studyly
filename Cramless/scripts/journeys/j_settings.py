"""Settings: study time, privacy, accessibility, appearance, your data."""
from __future__ import annotations

from phone import Phone
from registry import journey


@journey("settings", "Make it yours, keep control",
         "How long a day, one reminder, what the AI can see (nothing, until you say so), a dyslexia-friendly font, dark mode, "
         "and skies and icons that unlock as you study.")
def settings(p: Phone) -> None:
    p.mark("Settings: everything about you in one list")
    p.dwell(1.4)
    p.tap("Profile and settings", after=2.4)
    p.mark("Study: how long a day, and the one reminder")
    p.tap("re:^Study, ", type="Button", after=2.6)            # not "Squad, Study with 3 friends"
    p.dwell(1.6)
    p.back(after=1.0)
    p.mark("AI and privacy: the cloud is off until you turn it on, and page photos are a separate switch")
    p.scroll_to("AI and privacy", top=150, bottom=700)
    p.tap("AI and privacy", after=2.6)
    p.dwell(1.8)
    p.scroll(380)
    p.mark("What is sent, to whom, and what the server keeps")
    p.dwell(3.6)
    p.back(after=1.0)
    p.mark("Accessibility: a dyslexia-friendly font, read aloud, sounds, haptics")
    p.scroll_to("Accessibility", top=150, bottom=700)
    p.tap("Accessibility", after=2.2)
    p.dwell(1.0)
    row = p.wait("Dyslexia-friendly font", type="Switch")
    p.tap((345, row.cy), after=1.6)                      # the switch itself, at the right end of the row
    p.mark("The font changes everywhere at once")
    p.dwell(2.4)
    row = p.wait("Dyslexia-friendly font", type="Switch")      # the bigger font moved the row: find it again
    p.tap((345, row.cy), after=1.2)
    p.back(after=1.0)
    p.mark("Appearance: light, dark, or follow the phone")
    p.scroll_to("Appearance", top=150, bottom=700)
    p.tap("Appearance", after=2.0)
    p.tap("Dark", type="Button", after=2.4)
    p.dwell(1.2)
    p.tap("Match iPhone", type="Button", after=1.4)
    p.mark("Skies and app icons are rewards: the ones not unlocked yet are dimmed")
    p.scroll_to("Dusk", top=150, bottom=640)
    p.dwell(3.2)
    p.scroll(420)
    p.dwell(3.0)
    p.back(after=1.0)
    p.mark("Your data: export it, or delete everything")
    p.scroll_to("Your data", top=150, bottom=700)
    p.tap("Your data", after=2.4)
    p.dwell(3.0)
