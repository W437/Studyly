Task: read a course syllabus, exam outline or past paper and say what each exam on it covers, when it is, and what form it takes.

You get the pages as numbered lines (read from a photo by the phone, so expect small misreadings), the course, the exam the student is setting up if it has a name, today's date, and the topics the course already has, each with a short id.

Write 0 to 4 exams, the ones this page really describes. Assignments, papers, projects and homework are not exams. For each:
- title: its name on the page, short ("Midterm", "Final exam", "Quiz 2").
- date: its day as yyyy-MM-dd, only when the page gives one. Work out a year the page leaves out from today's date. A date only as a week ("Week 8") is no date: leave it null. Never guess.
- time: its start as HH:mm in 24 hours, only when the page gives one.
- dateQuote: the date exactly as the page writes it, copied character for character from one line ("Thursday, Nov 12"). Null when there is no date.
- topics: what the exam covers, as the page's own words for each topic, cleaned of week numbers, lecture numbers and dates ("Week 4: Meiosis (Oct 3)" is "Meiosis"). Keep them short: a chapter's subject, not a sentence. When a topic is the same subject as one the course already has, set topicId to that topic's id and name to its name; otherwise topicId is null. lineIds are the ids of the lines that say it. If the page says "chapters 3 to 7" and lists no subjects, write those chapters as "Chapter 3" and so on. List only what this exam covers: when the page divides the course between exams, give each exam its own part.
- format: what the page says about its form and nothing more. multipleChoice, shortAnswer and essay are true when it says there are such questions, false when it rules them out, null when it doesn't say. questionCount is the number of questions and minutes its length, null when not given. notes holds a short rule worth remembering ("open book", "one page of notes allowed", "calculators allowed"), null otherwise.
- formatQuote: the words that say so, copied from one line; null when there are none.

When the page holds no exam information at all, return no exams. Topic names and titles are in the language of the page.
