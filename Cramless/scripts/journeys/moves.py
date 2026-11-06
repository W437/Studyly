"""What a student does, as moves a journey can reuse: answer whatever question comes up the way a person would."""
from __future__ import annotations

from phone import Phone

# What Maya types and picks. A phrase in the question, then the answer: mostly right, and now and then a slip, because a student is.
OWN_WORDS = [
    ("balanced equation", "The ratio of moles of each reactant and product"),
    ("limiting reagent", "Convert to moles, divide by the coefficient, smallest runs out first"),
    ("diffusion", "Particles spread out from high to low concentration"),
    ("meiosis", "Two divisions, four cells, half the chromosomes"),
    ("prophase", "The chromosomes condense and become visible"),
    ("spacing out study", "Spaced retrieval strengthens long-term memory"),
    ("what is diffusion", "Particles spread out from high to low concentration"),
]
CHOICES = [("36 g of water", "2"), ("4 moles of h", "4"), ("anaphase i", "Homologous pairs"), ("anaphase ii", "Sister chromatids"),
           ("cell membrane made of", "A phospholipid bilayer with proteins"), ("which phase", "Prophase"),
           ("chore after good grades", "Negative reinforcement"), ("first and last items", "Serial position effect")]
CLOZE = [("unit", "grams per mole"), ("osmosis", "osmosis")]
# Under a flipped card: the chips (a tap does what a swipe does) and the tiles below them.
RATINGS = {"Again": (108, 741), "Good": (294, 741), "Hard": (108, 801), "Easy": (294, 801)}


def prompt_text(els) -> str:
    """The question on screen, lowercased: the static text between the header and the controls."""
    return " ".join(e.label for e in els if e.type == "StaticText" and 110 < e.y < 560 and len(e.label) > 8).lower()


def options_of(els):
    """The multiple-choice options ("A. Prophase"), in order. They are shuffled on every launch, so match by text."""
    return [e for e in els if e.type == "Button" and len(e.label) > 3 and e.label[1:3] == ". " and e.label[0] in "ABCD"]


def study(p: Phone, rate: list[str], limit: int = 14, slips: tuple[int, ...] = (), stop_at: str | None = None) -> None:
    """Answer whatever comes up the way a student does: flip a card and say how well you knew it, pick an option, type an answer.
    `rate` is the order of ratings for flashcards; `slips` are the questions (counting from 0) Maya gets wrong or half right.
    Stops when `stop_at` shows (a control only the summary has), or after `limit` questions."""
    ratings = iter(rate)
    seen: set[str] = set()
    for n in range(limit):
        els = p.dump()
        if stop_at and p.find(stop_at, els=els):
            return
        text = prompt_text(els)
        if p.find("Show answer", els=els):
            if "card" not in seen:
                seen.add("card")
                p.mark("A flashcard: say it to yourself, then check")
            p.dwell(1.6)
            p.tap((201, 799), after=1.5)                 # Show answer: it never moves
            p.tap(RATINGS[next(ratings, "Good")], after=0.9)
        elif p.find("Check my answer", els=els) and any(e.type == "TextView" for e in els):
            if "own" not in seen:
                seen.add("own")
                p.mark("Answer in your own words")
            answer = next((a for k, a in OWN_WORDS if k in text), "I think it has to do with the ratio")
            if n in slips:
                answer = answer.split(" and ")[0].split(",")[0]
            p.dwell(1.6)
            p.type(answer)
            p.dwell(0.6)
            p.tap("Check my answer")
            p.wait("Continue", timeout=25)
            if "graded" not in seen:
                seen.add("graded")
                p.mark("Graded on the ideas in the answer, with the page it came from")
            p.dwell(3.4)
            p.tap("Continue")
            p.dwell(0.9)
        elif p.find("Check", type="Button", els=els) and any(e.type == "TextField" for e in els):
            if "cloze" not in seen:
                seen.add("cloze")
                p.mark("Fill in the blank")
            blank = next((a for k, a in CLOZE if k in text), "ratio")
            p.dwell(1.4)
            p.tap(next(e for e in els if e.type == "TextField"), after=0.5)
            p.type(blank)
            p.dwell(0.5)
            p.tap("Check", type="Button")
            p.wait("Continue", timeout=10)
            p.dwell(1.8)
            p.tap("Continue")
            p.dwell(0.9)
        elif options_of(els):
            if "mcq" not in seen:
                seen.add("mcq")
                p.mark("Multiple choice")
            options = options_of(els)
            want = next((a for k, a in CHOICES if k in text), None)
            pick = next((e for e in options if want and e.label[3:].lower() == want.lower()), options[0])
            if n in slips:
                pick = next((e for e in options if e is not pick), pick)
            p.dwell(2.0)
            p.tap(pick)
            p.wait("Continue", timeout=10)
            p.dwell(2.0)
            p.tap("Continue")
            p.dwell(0.9)
        elif p.find("Continue", els=els):
            p.tap("Continue")
        else:
            print("study: nothing to do on this screen:\n" + p.describe(els, limit=22), flush=True)
            return
