"""Adding material: a photographed page becomes questions that point back to it."""
from __future__ import annotations

from phone import Phone
from registry import journey


@journey("scan", "Add a page",
         "Maya photographs a page of the textbook: the app reads it, finds the ideas, writes questions, checks each against the "
         "page, and shows where every one came from before it joins the set.")
def scan(p: Phone) -> None:
    p.mark("Add: scan, record a lecture, PDF or slides, Quizlet or Anki, paste, or type your own")
    p.dwell(1.4)
    p.tab("Add", after=2.6)
    p.mark("Scan pages: on a phone this is the camera; here, a sample page")
    p.tap("Scan pages", after=2.2)
    p.dwell(1.4)
    p.tap("Use our sample page")
    p.mark("The page is read, the ideas found, the questions written, each one checked against the page")
    p.wait("re:^Add \\d+ questions", timeout=70)
    p.mark("Review before anything joins your set: every question says where it came from")
    p.dwell(2.0)
    p.tap("re:^Adding to", after=1.4)             # the class it joins: a menu
    p.tap("Bio 101", type="Button", after=1.4)
    p.tap("Source: p. 87", after=2.4)
    p.mark("Tap the source: the exact lines on the exact page")
    p.dwell(3.0)
    p.dismiss()
    p.dwell(0.8)
    p.tap("re:^Add \\d+ questions")
    p.mark("Added: they join the class, and are studied from tomorrow")
    p.dwell(3.0)


@journey("lecture", "Record a lecture",
         "A lecture, transcribed on the phone as it happens. Maya flags what the lecturer says will be on the exam, and gets notes, "
         "key terms and questions at the end.")
def lecture(p: Phone) -> None:
    p.mark("Add ▸ Record a lecture: transcribed on the iPhone, never uploaded")
    p.dwell(1.2)
    p.tab("Add", after=2.4)
    p.tap("re:^For ", type="Button", after=1.2)       # the class it is for: a menu (the demo lecture is about biology)
    p.tap("Bio 101", type="Button", after=1.2)
    p.tap("Record a lecture", after=3.0)
    p.mark("The transcript fills in as the lecturer talks (a demo transcript here: the simulator can't hear)")
    p.dwell(13.0)
    p.mark("Tap when something sounds important: it's flagged for the exam")
    p.tap("Mark this moment", after=2.0)
    p.dwell(5.0)
    p.mark("Stop and save")
    p.tap("Stop and save", after=4.2)
    p.mark("Notes: a summary, the moments flagged for the exam, key terms")
    p.dwell(3.6)
    p.scroll(330)
    p.dwell(2.6)
    p.mark("Three questions, ready to study")
    p.tap("re:^Review", type="Button", after=3.0)
    p.dwell(3.2)
