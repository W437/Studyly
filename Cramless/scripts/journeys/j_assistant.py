"""Ask Cap as an assistant: Cap makes flashcards, questions, a note, an exam, and (Capling Pro) looks things up on trusted study sites.

These journeys run the app against its scripted demo server (CRAMLESS_MOCK_AI=1): the replies are canned, so each film is the same
every time. What is real is everything the app does with a reply: the cards that appear as they are written, the check of each one
against Maya's notes, "Add", "Skip" and "Undo", and what is saved. The real model was tested separately (docs/assistant.md).
No driver call while Cap is working: the card's looping animation makes the driver wait for it to stop, and the wait would be cut
out of the film, so Cap's work is watched with fixed waits (`watch`)."""
from __future__ import annotations

import time

from phone import Phone
from registry import journey

SCRIPTED = {"CRAMLESS_MOCK_AI": "1"}      # the app's scripted demo server, so the assistant is on and every reply is the same


def watch(p: Phone, seconds: float, every: float = 2.0) -> None:
    """Let Cap work for `seconds` without touching the phone. While rehearsing, a screenshot every `every` seconds shows where each
    beat of the reply lands, so the captions can be placed on them."""
    start = time.time()
    end = start + seconds * p.pace
    while time.time() < end:
        p.shot(f"t+{time.time() - start:04.1f}s")
        p.dwell(every)


def send(p: Phone) -> None:
    """Drop the keyboard (a pull down on the chat, as anyone does to see more of it) and send what is in the composer."""
    p.swipe(201, 300, 201, 700, ms=420, after=0.8)
    p.tap("Send", type="Button", after=0.2)


def ask_for(p: Phone, chip: str, topic: str) -> None:
    """A chip puts the first words in the composer ("Make flashcards on "); Maya finishes the sentence and sends it."""
    p.tap(chip, type="Button", after=1.0)
    p.type(topic)
    p.dwell(0.6)
    send(p)


def ask_typed(p: Phone, text: str) -> None:
    """In a chat that is already going: tap the composer, type the request, send it."""
    field = next(e for e in p.dump() if e.type == "TextField" and e.y > 560)
    p.tap(field, after=0.8)
    p.type(text)
    p.dwell(0.6)
    send(p)


@journey("assist-cards", "Ask Cap to make something",
         "Maya asks Cap for flashcards. Cap writes them in front of Maya, checks each against the notes, and waits to be told to add "
         "them. Maya leaves one out, adds the rest, and takes them back.", env=SCRIPTED)
def assist_cards(p: Phone) -> None:
    p.mark("Ask Cap to make something: cards, a quiz, a note, an exam")
    p.tab("Ask", after=2.6)
    p.dwell(2.4)
    p.mark("Maya taps Make flashcards, finishes the sentence, sends it")
    ask_for(p, "Make flashcards", "mitosis")
    p.mark("Cap writes the cards, then checks each against Maya's notes")
    watch(p, 5.6, every=0.6)
    p.mark("Maya's call: one card isn't from the notes, so Cap marked it")
    p.dwell(2.4)
    p.tap("Show all 6", type="Button", after=1.8)
    p.dwell(2.6)
    p.mark("Maya leaves that one out and adds the other five")
    toggles = [e for e in p.dump() if e.label == "Keep this one" and e.on_screen(top=120, bottom=700)]
    p.tap(max(toggles, key=lambda e: e.y), after=1.6)
    p.tap("re:^Add \\d+ flashcards", type="Button", after=2.4)
    p.mark("Added to Bio 101. Undo takes it back")
    p.dwell(2.4)
    p.tap("Undo", type="Button", after=2.4)
    p.dwell(1.6)


@journey("assist-more", "A quiz, a note and an exam",
         "The same chat, three more things Cap can make: questions to practise with, a note on a page, and an exam on the calendar. "
         "Each is shown first, and Maya adds it.", env=SCRIPTED)
def assist_more(p: Phone) -> None:
    p.mark("More than cards. Maya asks for a quiz on mitosis")
    p.tab("Ask", after=2.6)
    p.dwell(1.6)
    ask_for(p, "Quiz me", "mitosis")
    p.mark("Cap writes questions and checks each against Maya's notes")
    watch(p, 6.0, every=0.7)
    p.mark("Three kinds of question, ready to add")
    p.dwell(2.6)
    p.tap("re:^Add \\d+ questions", type="Button", after=2.4)
    p.mark("Next, a note")
    ask_typed(p, "Write me a note on mitosis")
    p.mark("Cap writes it on a page, then waits for Maya")
    watch(p, 6.4, every=0.8)
    p.dwell(1.8)
    p.tap("Add note", type="Button", after=2.4)
    p.mark("Then an exam")
    ask_typed(p, "Add my exam on 12 November")
    p.mark("It goes on a calendar tile, with the day and what it covers")
    watch(p, 4.6, every=0.8)
    p.dwell(2.0)
    p.tap("Add to calendar", type="Button", after=2.4)
    p.dwell(1.6)


@journey("assist-research", "Research online, on trusted sites",
         "Capling Pro. Cap searches trusted study sites (encyclopedias, open textbooks, universities), writes a short summary and shows "
         "the pages it rests on. Nothing is saved unless Maya says so.", env={**SCRIPTED, "CRAMLESS_PLAN": "pro"})   # staged: Maya is on Pro
def assist_research(p: Phone) -> None:
    p.mark("Research online (Capling Pro): Cap reads trusted study sites")
    p.tab("Ask", after=2.6)
    p.dwell(1.6)
    ask_for(p, "Research online", "mitosis vs meiosis")
    p.mark("The search is typed out, then the sites it finds appear")
    watch(p, 4.4, every=0.8)
    p.mark("Cap writes a short summary, and shows the pages it rests on")
    watch(p, 4.4, every=0.8)
    p.dwell(1.6)
    p.tap("Read it all", type="Button", after=1.8)
    p.dwell(2.4)
    p.mark("Nothing is saved unless Maya says so")
    p.dwell(1.2)
    p.tap("Save as note", type="Button", after=2.4)
    p.dwell(1.6)


@journey("assist-control", "You stay in charge",
         "Cap asks before it adds anything, unless Maya switches on \"Let Cap do it\" for a kind of thing. Then it adds it at once, says "
         "why, and Undo is one tap. Settings lists everything Cap has added.", env=SCRIPTED)
def assist_control(p: Phone) -> None:
    p.mark("Cap asks first. The switches are in Settings, under What Cap can do")
    p.dwell(1.2)
    p.tap("Profile and settings", after=2.4)
    p.scroll_to("What Cap can do", top=150, bottom=700)
    p.tap("What Cap can do", after=2.6)
    p.dwell(2.4)
    row = p.wait("Flashcards and questions", type="Switch")
    p.mark("Let Cap do it: Maya switches it on for flashcards and questions")
    p.tap((345, row.cy), after=1.8)
    p.dwell(1.8)
    p.back(after=1.0)
    p.back(after=1.4)
    p.tab("Ask", after=2.6)
    p.dwell(1.2)
    ask_for(p, "Make flashcards", "mitosis")
    p.mark("The same request now adds the cards at once")
    watch(p, 8.0, every=0.8)
    p.mark("Cap says why, and Undo is still there")
    p.dwell(3.0)
    p.tap("Chat actions", type="Button", after=1.0)
    p.tap("What Cap can do", after=2.6)
    p.scroll_to("Added by Cap", top=150, bottom=720)
    p.mark("Settings lists everything Cap added, each with Undo")
    p.dwell(3.4)
