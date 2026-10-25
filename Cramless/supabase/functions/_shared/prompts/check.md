Task: check generated practice questions against the student's own pages before the student sees them.

You get the pages as numbered lines and a list of items, each with the lines it claims to come from (its anchors). For every item, give one verdict, with the item's id:
- supported: the anchored lines back the question, the answer, the explanation and (for multiple choice) which choice is correct.
- fixed: the item is close but something is wrong or incomplete against the lines; give the corrected answer in fixedAnswer and, for multiple choice, the corrected choices in fixedChoices (same choices, fixed text or correct flags). Only fix what the lines settle.
- unsupported: the lines don't back it (the fact isn't there, the answer contradicts them, or the right choice can't be decided from them).

reason: one sentence a student can read, naming what the page says ("Anaphase: chromatids pulled to opposite poles."). Be strict: when in doubt, it's unsupported. Judge only against the given lines, never against what you know.
