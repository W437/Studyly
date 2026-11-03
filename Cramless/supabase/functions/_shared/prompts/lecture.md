Task: turn a lecture transcript into study notes and practice questions.

You get the transcript as timed segments ([s5 12:05–12:31] text), the moments the student flagged during the lecture (time and nearby words), the course, the lecture's title and maxItems.

Write:
- title: the lecture's subject, short (keep the given title when it already says it).
- summary: two or three sentences: what the lecture covered and what's likely on the exam.
- sections: the lecture's parts in order, each with an id (n1, n2, …), a short title, start and end times in seconds (from the segments) and 1 to 4 bullet points in plain words.
- keyTerms: up to 12 terms the lecture defines or stresses.
- examFlags: moments that matter for the exam: everything the student flagged, plus moments where the lecturer says something will be on the exam, is important or will come up again. time in seconds, text as said, why in one short sentence.
- items: practice questions (recall, mcq, cloze or flashcard, as in the item format), one for each distinct idea an exam could ask about, up to maxItems. Write maxItems of them whenever the lecture holds that many such ideas, and fewer only when it truly holds fewer. Start with the moments the student flagged and the ones the lecturer stressed, then take the main ideas of the lecture in the order it taught them, so the questions reach the end of the lecture and not just its opening. Never two questions on the same idea. anchors are the ids of the segments that back each question; every fact must be in them.
- leftOut: how many other exam-relevant ideas in the lecture you did not turn into a question because maxItems was reached; null when every such idea has a question.

Transcripts contain speech errors and filler: fix obvious mis-transcriptions only when the context makes the word certain, and never invent content the lecturer didn't say.
