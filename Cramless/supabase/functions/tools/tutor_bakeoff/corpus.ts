// The notes Ask Cap searches in this test, and a small search over them.
//
// Bio 101 is what the demo world holds: the bundled sample page (textbook p. 87), Lecture 6 and the Week 5 slides, cut
// into passages the way `LocalRetriever` cuts them (about sixty words, between sentences, a heading glued to its first
// sentence; one lecture segment a passage, because each is longer than 45 seconds). The demo has only flashcards for
// Chem 110 and AP Psychology, so their notes are written here in the same shape. Nothing in this file is real student data.

export interface Passage {
  id: string;
  title: string;
  label: string;
  text: string;
}

const BOOK = "Biology textbook";
const LECTURE = "Lecture 6: Cell division";
const SLIDES = "Week 5 slides";
const CHEM = "Chapter 3 notes";
const PSYCH = "Myers, chapter 7";

export const CORPUS: Passage[] = [
  {
    id: "t1",
    title: BOOK,
    label: "Textbook p. 87",
    text:
      "Mitosis: How Cells Divide. Mitosis is the process by which a single eukaryotic cell divides to produce two identical daughter cells. It allows organisms to grow, replace damaged cells and maintain healthy tissues. During mitosis, the genetic material (DNA) is copied and equally separated into two new nuclei.",
  },
  {
    id: "t2",
    title: BOOK,
    label: "Textbook p. 87",
    text: "Mitosis occurs in four main phases: Prophase, Metaphase, Anaphase, Telophase.",
  },
  {
    id: "t3",
    title: BOOK,
    label: "Textbook p. 87",
    text: "Prophase: Chromosomes condense and become visible. The nuclear envelope breaks down.",
  },
  {
    id: "t4",
    title: BOOK,
    label: "Textbook p. 87",
    text: "Metaphase: Chromosomes line up at the equator of the cell. Spindle fibres attach to the centromeres.",
  },
  {
    id: "t5",
    title: BOOK,
    label: "Textbook p. 87",
    text:
      "Anaphase: Sister chromatids are pulled to opposite poles of the cell. Each chromatid becomes a separate chromosome.",
  },
  {
    id: "t6",
    title: BOOK,
    label: "Textbook p. 87",
    text:
      "Telophase: New nuclear envelopes form around each set of chromosomes. Chromosomes unwind and the cells begin to separate.",
  },
  {
    id: "t7",
    title: BOOK,
    label: "Textbook p. 87",
    text:
      "What happens after mitosis? After mitosis, cytokinesis takes place. This is the division of the cytoplasm, producing two separate daughter cells. Each daughter cell is genetically identical to the parent cell, with the same number of chromosomes.",
  },
  {
    id: "t8",
    title: BOOK,
    label: "Textbook p. 87",
    text:
      "Why is mitosis important? Mitosis is essential for growth and development, allowing multicellular organisms to increase their number of cells. It also replaces old or damaged cells, such as skin cells, and helps with healing after injury. In unicellular organisms, mitosis is a form of asexual reproduction.",
  },
  { id: "t9", title: BOOK, label: "Textbook p. 87", text: "Key term: Cytokinesis - the division of the cytoplasm." },

  {
    id: "l1",
    title: LECTURE,
    label: "Lecture 6 · 2:58",
    text: "OK, so last time we finished interphase. Today: what actually happens when the cell divides.",
  },
  {
    id: "l2",
    title: LECTURE,
    label: "Lecture 6 · 3:12",
    text: "Prophase first. The chromatin condenses, and you can finally see chromosomes under the microscope.",
  },
  {
    id: "l3",
    title: LECTURE,
    label: "Lecture 6 · 5:40",
    text: "Then the nuclear envelope breaks down and the spindle starts forming from the centrosomes.",
  },
  {
    id: "l4",
    title: LECTURE,
    label: "Lecture 6 · 7:40",
    text: "Metaphase is the easy one to spot: everything lines up along the middle, the metaphase plate.",
  },
  {
    id: "l5",
    title: LECTURE,
    label: "Lecture 6 · 12:05",
    text: "This one will be on the midterm, by the way: anaphase is where the sister chromatids get pulled apart.",
  },
  {
    id: "l6",
    title: LECTURE,
    label: "Lecture 6 · 15:20",
    text: "And telophase is basically prophase in reverse. The nuclear envelopes re-form around each set.",
  },

  {
    id: "w1",
    title: SLIDES,
    label: "Slides p. 11",
    text:
      "The cell membrane. A phospholipid bilayer with proteins embedded in it. It is selectively permeable: it controls what enters and leaves the cell.",
  },
  {
    id: "w2",
    title: SLIDES,
    label: "Slides p. 11",
    text:
      "Diffusion: particles move from high to low concentration. Osmosis: water moves across a membrane from dilute to concentrated solution.",
  },
  {
    id: "w3",
    title: SLIDES,
    label: "Slides p. 12",
    text:
      "Meiosis. Two divisions make four cells, each with half the chromosomes of the parent. Crossing over in prophase I swaps pieces between homologous chromosomes.",
  },
  {
    id: "w4",
    title: SLIDES,
    label: "Slides p. 12",
    text:
      "Anaphase I separates homologous pairs; anaphase II separates sister chromatids. Meiosis makes gametes: eggs and sperm.",
  },

  {
    id: "c1",
    title: CHEM,
    label: "Notes p. 1",
    text:
      "Moles. One mole is 6.022 × 10²³ particles (Avogadro's number). Molar mass is the mass of one mole of a substance, in grams per mole.",
  },
  {
    id: "c2",
    title: CHEM,
    label: "Notes p. 1",
    text:
      "To convert grams to moles, divide the mass by the molar mass. Example: water has a molar mass of 18 g/mol, so 36 g of water is 2 moles.",
  },
  {
    id: "c3",
    title: CHEM,
    label: "Notes p. 2",
    text:
      "Stoichiometry. A balanced equation gives the mole ratio of reactants and products. In 2H₂ + O₂ → 2H₂O, 2 moles of hydrogen react with 1 mole of oxygen to make 2 moles of water.",
  },
  {
    id: "c4",
    title: CHEM,
    label: "Notes p. 3",
    text:
      "Limiting reagent. The limiting reagent is the reactant that runs out first, so it limits how much product forms. To find it, convert each reactant to moles, divide by its coefficient, and the smallest result is the limiting reagent.",
  },

  {
    id: "p1",
    title: PSYCH,
    label: "Myers p. 3",
    text:
      "Memory. Encoding is getting information into memory, storage is keeping it there, and retrieval is getting it back out.",
  },
  {
    id: "p2",
    title: PSYCH,
    label: "Myers p. 4",
    text:
      "Serial position effect: we remember the first items on a list (primacy) and the last items (recency) best, and the middle items worst.",
  },
  {
    id: "p3",
    title: PSYCH,
    label: "Myers p. 5",
    text:
      "Spacing effect: studying spread out over time produces better long-term retention than studying all at once, or cramming. Testing effect: retrieving information from memory strengthens it more than rereading it.",
  },
  {
    id: "p4",
    title: PSYCH,
    label: "Myers p. 6",
    text:
      "Operant conditioning is learning from the consequences of behavior. Reinforcement makes a behavior more likely and punishment makes it less likely. Negative reinforcement removes something unpleasant, which strengthens the behavior.",
  },
];

export function passage(id: string): Passage {
  const found = CORPUS.find((p) => p.id === id);
  if (!found) throw new Error(`No passage ${id}`);
  return found;
}

// A plain BM25 over the passages, with a crude stemmer and the words a question is made of left out. The app's own
// retriever weighs headings and more; this only has to hand every model the same four passages a student's question finds.

const STOP = new Set(
  ("a an and are as at be but by can do does did for from has have how i if in is it its me my of on or so than that the " +
    "their them then there these they this to was we what when where which who why will with you your about into just not " +
    "tell say explain describe difference between please help get got happen happens work works example define " +
    "definition compare versus vs mean meaning understand confused mistake matter use own").split(" "),
);

function stem(word: string): string {
  let w = word;
  for (const suffix of ["ing", "es", "ed", "s"]) {
    if (w.length > suffix.length + 3 && w.endsWith(suffix)) {
      w = w.slice(0, -suffix.length);
      break;
    }
  }
  return w;
}

function terms(text: string): string[] {
  return (text.toLowerCase().normalize("NFD").replace(/\p{M}/gu, "").match(/[a-z0-9]+/g) ?? [])
    .filter((w) => w.length > 1 && !STOP.has(w))
    .map(stem);
}

/** "Prophase: …", "Why is mitosis important? …": the words a passage is headed by. */
function heading(text: string): Set<string> {
  const m = /^(.{1,60}?)[:.?]\s/.exec(text);
  return new Set(m ? terms(m[1]) : []);
}

const DOCS = CORPUS.map((p) => ({ p, t: terms(p.text), head: heading(p.text) }));
const AVG = DOCS.reduce((n, d) => n + d.t.length, 0) / DOCS.length;
const DF = new Map<string, number>();
for (const d of DOCS) for (const w of new Set(d.t)) DF.set(w, (DF.get(w) ?? 0) + 1);

export function search(query: string, limit = 4): Passage[] {
  const q = [...new Set(terms(query))];
  const scored = DOCS.map((d) => {
    let score = 0;
    for (const w of q) {
      const f = d.t.filter((x) => x === w).length;
      if (f === 0) continue;
      const idf = Math.log(1 + (DOCS.length - (DF.get(w) ?? 0) + 0.5) / ((DF.get(w) ?? 0) + 0.5));
      score += idf * (f * 2.2) / (f + 1.2 * (0.25 + 0.75 * d.t.length / AVG));
      if (d.head.has(w)) score += idf;
    }
    return { p: d.p, score };
  }).filter((s) => s.score > 0);
  scored.sort((a, b) => b.score - a.score || a.p.id.localeCompare(b.p.id));
  return scored.slice(0, limit).map((s) => s.p);
}
