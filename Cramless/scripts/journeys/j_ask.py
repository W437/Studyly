"""Ask Cap: a tutor that answers from your own notes, and says where."""
from __future__ import annotations

from phone import Phone
from registry import journey


@journey("ask", "Ask Cap",
         "Questions about the material, answered only from Maya's own notes, with the page each answer came from. By default Cap asks "
         "before it tells; one tap and it just explains.")
def ask(p: Phone) -> None:
    p.mark("Ask: Cap answers from your own notes and shows where")
    p.tab("Ask", after=2.6)
    p.dwell(2.2)
    p.mark("Starters from your material. By default Cap asks before it tells")
    p.tap("Anaphase vs", after=7.5)
    p.dwell(3.0)
    p.mark("Prefer a straight answer? Cap's style is in the box you type in")
    p.tap("Cap's style", type="Button", after=1.0)
    p.tap("Just explain", type="Button", after=1.2)
    p.tap(next(e for e in p.dump() if e.type == "TextField" and e.y > 600), after=0.8)
    p.type("What is cytokinesis?")
    p.tap("Send", type="Button", after=7.5)
    p.mark("Every answer names the page it came from")
    p.dwell(2.6)
    p.tap("Source: Textbook", after=2.8)
    p.mark("Tap it: the page, the exact line highlighted, and the questions made from it")
    p.dwell(3.6)
    p.dismiss()
