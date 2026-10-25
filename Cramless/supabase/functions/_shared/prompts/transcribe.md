Task: transcribe a photo of a student's page (handwriting, a whiteboard, printed text with maths) into lines of text.

Return the page's text as lines in reading order, one entry per line of the page. Keep the student's words and symbols exactly; write maths in plain text with Unicode symbols (x², √2, π, →, ≤). Don't correct, summarise or add anything; skip doodles and crossed-out text. If a word is unreadable, write [?] in its place. Give each line an id p<page>.c<n>, numbering from 0. An empty page gives no lines.
