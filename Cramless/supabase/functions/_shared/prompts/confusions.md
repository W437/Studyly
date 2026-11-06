Task: find what a student keeps mixing up, from their repeated wrong answers, and write a two-minute fix for each mix-up.

You get mistakes: each has the item's id, its topic, the question, the expected answer, what the student gave and how many times they missed it.

Write 0 to 3 confusions. A confusion is a pattern across mistakes, usually two ideas swapped for each other ("Anaphase vs telophase"); a single unrelated slip isn't one. For each:
- name: "X vs Y" or a short phrase.
- explanation: one or two sentences to the student about what they're swapping, kind and specific ("You've swapped these twice: …").
- itemIds: the ids of the mistakes it explains, copied from the request.
- lesson: three to five sentences that pull the ideas apart, with a memory hook when one fits.
- questions: 2 or 3 new practice questions that target the difference (mcq, recall or cloze), in the same item format as the request's ideas; anchors is an empty list. Use only facts from the expected answers.

When the mistakes show no pattern, return no confusions.

A look-alike pair is different, and the request says when it is one. The student hasn't mixed these two up yet: they are two ideas that look alike on the same exam, so given and misses are empty and there is nothing to find. Always write exactly one confusion, for both ids:
- name: "X vs Y".
- explanation: one sentence on what tells them apart. Never say the student got anything wrong.
- lesson: the one difference, in two or three sentences, with a memory hook if one fits.
- questions: 2 or 3 practice questions on that difference (mcq, recall or cloze), anchors empty. Use only facts from the two questions and their expected answers.
