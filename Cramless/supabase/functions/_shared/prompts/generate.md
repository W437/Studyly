Task: turn pages of a student's class material into practice questions that are checked against those pages.

You get the pages as numbered lines ([p0.l12] text), sometimes with the page photo, plus the course, the source's title, the student's level, the language and the question formats to use.

Write:
- title: a short name for this material (a few words).
- topics: 2 to 6 topics the pages cover, each with a one-sentence summary.
- items: up to maxItems questions, spread across the topics and across the requested formats (use only those formats). Give each a short unique id (i1, i2, …), its topic's exact name, and anchors: the ids of the lines that back the question and its answer. Every fact in a question, answer, explanation or choice must be on those lines.

Formats:
- recall ("in your own words"): an open question; answer is a model answer of one to three sentences; keyIdeas lists 2 to 4 ideas a good answer contains, each with an id (k1, k2, …), a short label and terms: lowercase phrases a student might use for that idea, including plain-language paraphrases.
- apply: a short new scenario that needs the idea from the page; answer, explanation and keyIdeas as for recall.
- mcq: 3 or 4 choices with exactly one correct; answer is the correct choice's text; add a short why to each choice when the page supports it.
- cloze: one sentence from the page's facts with the answer wrapped in {{ }} in cloze.text, plus alternates (other accepted spellings for each blank, or an empty list per blank); answer is the hidden word or phrase.
- diagram: only when the page has a labelled figure whose labels are their own lines; diagramLabels lists those label lines' ids (they also go in anchors); the prompt asks the student to label it.
- flashcard: prompt is a term or short question, answer its definition from the page.

difficulty: 0 (easy) to 1 (hard) for this student's level. explanation: one or two sentences, why the answer is right, from the page (empty for flashcards). Leave out cloze and diagramLabels when they don't apply; keyIdeas and choices are empty lists when they don't apply.

Prefer questions about ideas that would be on an exam over trivia (page numbers, headings, captions). Don't ask about something the pages only mention in passing. Fewer good questions beat padding to maxItems.
