/* Sample content for the Cramless prototype. Everything here is example data. */
window.DATA = {
  brand: { name: 'Cramless', mascot: 'Cap', tagline: 'Never cram again.' },
  user: { first: 'Maya', initials: 'MR' },
  todayLabel: 'Wednesday, Oct 22',

  prices: {
    yearly:  { label: 'Yearly',  price: '$49.99', unit: 'year',  sub: '$0.96 a week', trial: 7, badge: 'Best value' },
    monthly: { label: 'Monthly', price: '$9.99',  unit: 'month', sub: 'Cancel anytime' },
    squad:   { label: 'Squad',   price: '$99.99', unit: 'year',  sub: 'You + 3 friends · $2.08 each a month', trial: 7, badge: 'Study together' }
  },

  exams: [
    { id: 'bio', course: 'Bio 101', name: 'Bio 101 Midterm', date: 'Fri, Nov 14', short: 'Nov 14', days: 23, ready: 64, delta: 5, target: 90,
      projected: 'B+', projectedPct: 87, format: 'Multiple choice + short answer',
      topics: [
        { name: 'Cell cycle', m: 92 }, { name: 'Mitosis', m: 88 }, { name: 'Cytokinesis', m: 80 },
        { name: 'Cell membrane', m: 75 }, { name: 'Meiosis', m: 61 }, { name: 'Mendelian genetics', m: 42 },
        { name: 'DNA replication', m: null }
      ],
      materials: [
        { icon: 'book-open', name: 'Textbook, Unit 3', meta: '12 pages scanned' },
        { icon: 'mic', name: 'Lecture 6: Cell division', meta: '52 min, transcribed on iPhone' },
        { icon: 'presentation', name: 'Week 5 slides', meta: 'PDF, 24 slides' },
        { icon: 'layers', name: 'Imported from Quizlet', meta: 'Unit 3 terms, 40 cards' }
      ],
      plan: [
        { d: 'Wed', n: '22', min: 15, today: true }, { d: 'Thu', n: '23', min: 15 }, { d: 'Fri', n: '24', min: 10 },
        { d: 'Sat', n: '25', min: 0 }, { d: 'Sun', n: '26', min: 20 }, { d: 'Mon', n: '27', min: 15 }, { d: 'Tue', n: '28', min: 15 }
      ] },
    { id: 'chem', course: 'Chem 110', name: 'Chem 110 Quiz', date: 'Fri, Oct 24', short: 'Fri', days: 2, ready: 45, delta: 12, target: 80 },
    { id: 'psych', course: 'AP Psychology', name: 'AP Psych Exam', date: 'Wed, May 6', short: 'May 6', days: 196, ready: 31, delta: 2, target: 90 }
  ],

  courses: [
    { name: 'Bio 101', color: 'sky', exam: 'Midterm Nov 14', sources: 4, cards: 86, m: 64 },
    { name: 'Chem 110', color: 'tang', exam: 'Quiz Friday', sources: 2, cards: 40, m: 45 },
    { name: 'AP Psychology', color: 'mint', exam: 'Exam May 6', sources: 6, cards: 210, m: 31 },
    { name: 'Spanish II', color: 'sun', exam: 'Vocab, no exam set', sources: 1, cards: 150, m: 72 }
  ],

  /* The set generated from the scanned textbook page (p. 87). */
  generated: {
    title: 'Mitosis', source: 'Biology textbook, p. 87',
    concepts: ['Phases of mitosis', 'Cytokinesis', 'Why mitosis matters', 'Chromosome number'],
    items: [
      { t: 'Recall', q: 'In your own words: why do cells divide by mitosis?', a: 'To grow, repair damaged tissue and, in some organisms, reproduce asexually, making two genetically identical cells.', src: 'p. 87 · Why is mitosis important?' },
      { t: 'Recall', q: 'What does "genetically identical daughter cells" mean?', a: 'Both new cells have the same DNA, and the same number of chromosomes, as the parent cell.', src: 'p. 87 · intro' },
      { t: 'Recall', q: 'What happens to the nuclear envelope in prophase?', a: 'It breaks down while chromatin condenses into visible chromosomes and spindle fibres begin to form.', src: 'p. 87 · Prophase' },
      { t: 'Recall', q: 'Describe what happens in anaphase.', a: 'Spindle fibres pull the sister chromatids apart and they move to opposite ends of the cell.', src: 'p. 87 · Anaphase' },
      { t: 'Recall', q: 'How is cytokinesis different from mitosis?', a: 'Mitosis divides the nucleus; cytokinesis divides the cytoplasm, giving two separate cells.', src: 'p. 87 · What happens after mitosis?' },
      { t: 'Multiple choice', q: 'In which phase do chromosomes line up at the cell’s equator?', a: 'Metaphase', src: 'p. 87 · Metaphase' },
      { t: 'Multiple choice', q: 'Which of these is not a job of mitosis?', a: 'Making sex cells', src: 'p. 87 · Why is mitosis important?' },
      { t: 'Multiple choice', q: 'What do spindle fibres attach to in metaphase?', a: 'The centromeres', src: 'p. 87 · Metaphase' },
      { t: 'Multiple choice', q: 'Which phase comes right before cytokinesis?', a: 'Telophase', src: 'p. 87 · Telophase' },
      { t: 'Fill in', q: 'During ____, chromatids reach opposite poles and the nuclear envelopes re-form.', a: 'telophase', src: 'p. 87 · Telophase' },
      { t: 'Fill in', q: 'Mitosis makes two genetically ____ daughter cells.', a: 'identical', src: 'p. 87 · intro' },
      { t: 'Fill in', q: '____ is the division of the cytoplasm.', a: 'Cytokinesis', src: 'p. 87 · Key term' },
      { t: 'Diagram', q: 'Name the phase: chromosomes lined up in the middle.', a: 'Metaphase', src: 'p. 87 · diagram' },
      { t: 'Diagram', q: 'Name the phase: chromatids moving to opposite poles.', a: 'Anaphase', src: 'p. 87 · diagram' }
    ]
  },

  /* A study session mixes question types. Recall answers are graded by key idea. */
  session: [
    { type: 'recall', concept: 'Why mitosis matters',
      q: 'In your own words: why do cells divide by mitosis?',
      example: 'So the body can grow and repair tissue, making two identical cells.',
      ideas: [
        { label: 'Growth and repair', re: '\\b(grow\\w*|growth|repair\\w*(?: (?:damaged )?tissue)?|replac\\w*|heal\\w*)' },
        { label: 'Genetically identical cells', re: '\\b(identical(?: cells)?|same dna|same genes|clones?|exact cop(?:y|ies))' },
        { label: 'Same number of chromosomes', re: '\\b(same (?:number of )?chromosomes?|chromosome number|46 chromosomes|diploid)' }
      ],
      fix: 'Each new cell keeps the same number of chromosomes as the parent: 46 in a human body cell.',
      src: 'Textbook p. 87 · What happens after mitosis?' },
    { type: 'mcq', concept: 'Phases of mitosis',
      q: 'During which phase are sister chromatids pulled apart to opposite ends of the cell?',
      options: ['Prophase', 'Metaphase', 'Anaphase', 'Telophase'], correct: 2,
      why: 'In anaphase the spindle fibres shorten and pull each pair of sister chromatids apart.',
      src: 'Textbook p. 87 · Anaphase' },
    { type: 'diagram', concept: 'Phases of mitosis',
      q: 'Which phase is this cell in?',
      options: ['Prophase', 'Metaphase', 'Anaphase', 'Telophase'], correct: 1,
      why: 'The chromosomes are lined up across the middle of the cell, on the metaphase plate.',
      src: 'Textbook p. 87 · diagram' },
    { type: 'flip', concept: 'Cytokinesis',
      front: 'Cytokinesis', back: 'The division of the cytoplasm into two daughter cells, right after telophase.',
      src: 'Textbook p. 87 · Key term' },
    { type: 'cloze', concept: 'Phases of mitosis',
      before: 'During', after: ', the chromatids reach opposite poles and the nuclear envelopes re-form.',
      answer: 'telophase', accept: ['telophase', 'telophase.'],
      src: 'Textbook p. 87 · Telophase' },
    { type: 'recall', concept: 'Phases of mitosis', apply: true,
      q: 'A drug stops spindle fibres from forming. Which phase can’t happen, and why?',
      example: 'Anaphase, because without spindle fibres the chromatids can’t be pulled apart.',
      ideas: [
        { label: 'Anaphase is blocked', re: '\\b(anaphase|metaphase)' },
        { label: 'Spindle fibres pull the chromatids apart', re: '\\b(pull\\w*(?: apart)?|separat\\w*|apart|attach\\w*|move\\w*)' }
      ],
      fix: 'Without spindle fibres nothing can attach to the centromeres, so the chromatids are never pulled apart.',
      src: 'Textbook p. 87 · Metaphase, Anaphase' }
  ],

  chatSeed: [
    { who: 'me', text: 'What’s the difference between mitosis and meiosis? I keep mixing them up.' },
    { who: 'cap', kind: 'compare' }
  ],

  lecture: [
    { t: '02:58', text: 'OK, so last time we finished interphase. Today: what actually happens when the cell divides.' },
    { t: '03:12', text: 'Prophase first. The chromatin condenses, and you can finally see chromosomes under the microscope.' },
    { t: '05:40', text: 'Then the nuclear envelope breaks down and the spindle starts forming from the centrosomes.' },
    { t: '07:40', text: 'Metaphase is the easy one to spot: everything lines up along the middle, the metaphase plate.' },
    { t: '12:05', text: 'This one will be on the midterm, by the way: anaphase is where the sister chromatids get pulled apart.', flag: true },
    { t: '15:20', text: 'And telophase is basically prophase in reverse. The nuclear envelopes re-form around each set.' }
  ],

  classmates: [
    { n: 'Priya', i: 'PS', c: 'sky', min: 214, now: true },
    { n: 'You', i: 'MR', c: 'tang', min: 188, me: true },
    { n: 'Jordan', i: 'JK', c: 'mint', min: 160, now: true },
    { n: 'Alex', i: 'AM', c: 'sun', min: 131 },
    { n: 'Sam', i: 'ST', c: 'rose', min: 96, now: true },
    { n: 'Nora', i: 'NB', c: 'sky', min: 74 }
  ]
};
