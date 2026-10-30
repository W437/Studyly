"""The library: classes, topics and every question with the page it came from."""
from __future__ import annotations

from phone import Phone
from registry import journey


@journey("library", "Your classes",
         "Every class with how ready it is, its topics, and every question with the page it came from. Imports from Quizlet and Anki "
         "keep the sets you already have.")
def library(p: Phone) -> None:
    p.mark("Library: every class, how ready it is, and when its exam is")
    p.dwell(1.0)
    p.tab("Library", after=2.6)
    p.dwell(2.6)
    p.mark("Bring what you already have: Quizlet, Anki, PDFs, pasted text")
    p.scroll_to("Bring your stuff", top=150, bottom=700, points=240)
    p.dwell(2.6)
    p.scroll(-900, after=0.8)
    p.mark("A class: readiness, its exam, and a button to practise it")
    p.tap("Bio 101", type="Button", after=2.8)
    p.dwell(1.4)
    p.mark("Topics, each with how well you know it")
    p.scroll(330)
    p.dwell(3.0)
    p.mark("Every question, and the page it came from")
    p.scroll_to("What is the cell membrane made of?", top=150, bottom=650, points=260)
    p.dwell(2.4)
    p.tap("What is the cell membrane made of?", after=2.6)
    p.dwell(2.6)
