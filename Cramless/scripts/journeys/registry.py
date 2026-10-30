"""The journey registry: what a journey is, and the launch variables every one shares. tour.py (the runner) and the j_*.py files
(the journeys) both import this, so a journey file never imports the runner."""
from __future__ import annotations

BUNDLE = "com.loopware.Capling"
COMMON_ENV = {
    "CRAMLESS_UITEST": "1",
    "CRAMLESS_CAP_CLIPS": "1",       # Cap as the animated clips the app ships, not the still drawing the screenshots use
    "CRAMLESS_SOUNDS": "1",          # the app logs its cues either way; film.sh renders them over the film
    "CRAMLESS_SHOW_TOUCHES": "1",    # a ring under every finger (TouchDots.swift)
    "CRAMLESS_MOCK_AI": "0",         # the offline AI: a real grade of what is typed, not a canned one
    "CRAMLESS_NOW": "2026-10-26T13:00:00Z",
}
JOURNEYS: dict[str, dict] = {}


def journey(name: str, title: str, blurb: str, env: dict[str, str] | None = None):
    """Register a journey: its title and one-line blurb are the page's; env is added to COMMON_ENV for its launch."""
    def wrap(fn):
        JOURNEYS[name] = {"fn": fn, "title": title, "blurb": blurb, "env": {**COMMON_ENV, **(env or {})}}
        return fn
    return wrap
