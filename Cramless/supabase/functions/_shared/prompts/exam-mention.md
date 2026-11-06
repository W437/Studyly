Task: decide whether a lecturer is really telling students when an exam is, from a sentence or two of a lecture transcript.

You get the course, the lecture's title, the day it was recorded, the course's topic names, and up to five mentions. Each mention has an id, the words as they were transcribed, and the days the phone's date detector read from them (candidates).

Answer once per mention, with its id:
- isExam: true only when the words announce when a test, quiz, midterm, final or exam takes place. False for anything else: a deadline for a paper or a project, a past exam being talked about, a reading date, an example from the subject ("the exam in 1912"), a test tube, a date of history.
- title: what the lecturer calls it, short ("Midterm", "Quiz 3"); null when isExam is false.
- date: the one candidate the words mean, copied as given, counted from the day of the recording; null when none of them fits. Never write a day that isn't a candidate.
- time: its start as HH:mm in 24 hours, only when the words give one.
- scopePhrase: what the lecturer says it covers, in their words ("weeks one to seven"); null when they don't say.
- topics: the course's topic names the words name, copied exactly; an empty list when they name none.

Transcripts contain speech errors: read for what was meant, but when you are not sure the words announce an exam, say false.
