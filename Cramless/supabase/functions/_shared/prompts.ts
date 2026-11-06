// The system prompts (files in _shared/prompts, bundled into generated.ts) and the user content of every route.
// The person's material goes in as data, in tagged blocks; ids are written exactly as the app sent them so the
// model can only cite real ones.

import type {
  AssistantRequest,
  CardsFromChatRequest,
  CheckReport,
  ConfusionsRequest,
  ExamMentionRequest,
  GeneratedItem,
  GenerateRequest,
  GradeRequest,
  LastLookRequest,
  LectureRequest,
  PageInput,
  ResearchRequest,
  SyllabusRequest,
  TranscribeImageRequest,
  TutorRequest,
} from "./contract.ts";
import { PROMPTS } from "./generated.ts";
import type { ContentBlock, Message } from "./provider.ts";
import { DENIED_SOURCES } from "./research_sources.ts";

export type Task =
  | "generate"
  | "check"
  | "grade"
  | "confusions"
  | "lecture"
  | "cards"
  | "transcribe"
  | "syllabus"
  | "exam-mention"
  | "last-look";

function prompt(name: string): string {
  const text = PROMPTS[name];
  if (text === undefined) throw new Error(`Missing prompt ${name}`);
  return text;
}

/** The shared rules, then the task. */
export function systemFor(task: Task): string {
  return `${prompt("rules")}\n\n${prompt(task)}`;
}

/** The tutor's system prompt: hints first (always for a minor and for a problem from a photo) or explain, plus the teen-safe
 * scope and what a problem from a photo adds. */
export function tutorSystem(req: TutorRequest): string {
  const parts = [prompt("rules"), prompt("tutor")];
  const hints = req.minor || req.mode === "hints" || req.fromPhoto === true;
  parts.push(prompt(hints ? "tutor-hints" : "tutor-explain"));
  if (req.minor) parts.push(prompt("tutor-minor"));
  if (req.fromPhoto) parts.push(prompt("tutor-problem"));
  if (req.course) parts.push(`The student's course: ${oneLine(req.course)}.`);
  // Last, as it was when it was measured (tools/tutor_figure_ab.ts): what to do with the labels of a photographed picture.
  parts.push(prompt("tutor-figures"));
  return parts.join("\n\n");
}

/** The assistant's system prompt: the tutor's, plus what the tools add. The quick-check ending of "explain" mode is for
 * answers; after an action Cap's note is short, and the assistant prompt says so. */
export function assistantSystem(req: AssistantRequest): string {
  const parts = [prompt("rules"), prompt("tutor"), prompt("assistant")];
  const hints = req.minor || req.mode === "hints";
  parts.push(prompt(hints ? "tutor-hints" : "tutor-explain"));
  if (req.minor) parts.push(prompt("tutor-minor"));
  if (req.course) parts.push(`The student's course: ${oneLine(req.course)}.`);
  return parts.join("\n\n");
}

/** Text from the student's own device as one short line, so a course name cannot add instructions of its own. */
function oneLine(text: string, max = 120): string {
  return text.replace(/[\r\n\t`<>]+/g, " ").replace(/\s+/g, " ").trim().slice(0, max);
}

/** What the student has added (a source's name with its size, "Cardiac cycle (6 pages)"), as a short block for the model
 * to name when it cannot find an answer. The names are the student's own words (a classmate's deck can be called anything),
 * so each is one plain line. Nothing when the app sent none. */
export function materialsBlock(materials: readonly string[] | undefined): string {
  const names = (materials ?? []).map((m) => oneLine(m)).filter((m) => m.length > 0).slice(0, 20);
  return names.length > 0 ? `The student has added:\n${names.map((m) => `- ${m}`).join("\n")}` : "";
}

/** The web research prompt, ending with the sites it must never use (research_sources.ts). */
export function researchSystem(): string {
  const denied =
    `Never read, use or cite a page from these sites, even if a search shows it, because their terms or licences do ` +
    `not allow AI services to use their pages: ${
      DENIED_SOURCES.join(", ")
    }. If the only pages you can find are on them, ` +
    `say that you could not find a source you may use.`;
  return `${prompt("rules")}\n\n${prompt("research")}\n\n${denied}`;
}

/** What the research is asked, from the student's topic and focus. */
export function researchInput(req: ResearchRequest): string {
  const parts = [`Topic: ${req.topic.trim()}`];
  if (req.focus?.trim()) parts.push(`Focus: ${req.focus.trim()}`);
  if (req.course?.trim()) parts.push(`Course: ${req.course.trim()}`);
  parts.push("Research it and write the study summary.");
  return parts.join("\n");
}

/** The media type of a base64 image, from its first bytes (the contract sends JPEG; PNG and others are read). */
export function imageMediaType(base64: string): "image/jpeg" | "image/png" | "image/gif" | "image/webp" {
  if (base64.startsWith("iVBORw0KGgo")) return "image/png";
  if (base64.startsWith("R0lGOD")) return "image/gif";
  if (base64.startsWith("UklGR")) return "image/webp";
  return "image/jpeg";
}

function imageBlock(base64: string): ContentBlock {
  return { type: "image", mediaType: imageMediaType(base64), data: base64 };
}

const attr = (value: string) => value.replace(/["<>]/g, "");

/** The pages as numbered lines, each page after its photo when there is one. */
export function pagesContent(pages: PageInput[], onlyLines?: ReadonlySet<string>): ContentBlock[] {
  const out: ContentBlock[] = [];
  for (const page of pages) {
    const lines = onlyLines ? page.lines.filter((l) => onlyLines.has(l.id)) : page.lines;
    if (onlyLines && lines.length === 0) continue;
    if (page.image && !onlyLines) out.push(imageBlock(page.image));
    const body = lines.map((l) => `[${l.id}] ${l.text}`).join("\n");
    out.push({ type: "text", text: `<page index="${page.page}" label="${attr(page.label)}">\n${body}\n</page>` });
  }
  return out;
}

/** The generate system prompt; a harder question adds its own rule (generate-rung.md). */
export function generateSystem(rung = false): string {
  return rung ? `${systemFor("generate")}\n\n${prompt("generate-rung")}` : systemFor("generate");
}

export function generateContent(req: GenerateRequest): ContentBlock[] {
  return [
    ...pagesContent(req.pages),
    ...(req.rung
      ? [{
        type: "text" as const,
        text: `<easier_question>\n${
          JSON.stringify({ format: req.rung.kind, prompt: req.rung.prompt, answer: req.rung.answer }, null, 1)
        }\n</easier_question>`,
      }]
      : []),
    {
      type: "text",
      text: [
        `Course: ${req.course}`,
        `Source: ${req.sourceTitle}`,
        `Level: ${req.level ?? "not given"}`,
        `Language: ${req.language}`,
        `Formats: ${[...new Set(req.formats)].join(", ")}`,
        `maxItems: ${req.maxItems}`,
        "",
        req.rung ? "Write the harder question from these lines." : "Write the practice set from these pages.",
      ].join("\n"),
    },
  ];
}

/** An item as the check sees it: what it claims and where from. */
function itemForCheck(item: GeneratedItem): Record<string, unknown> {
  return {
    id: item.id,
    kind: item.kind,
    prompt: item.prompt,
    answer: item.answer,
    explanation: item.explanation ?? "",
    ...(item.choices?.length ? { choices: item.choices } : {}),
    ...(item.cloze ? { cloze: item.cloze.text } : {}),
    anchors: item.anchors ?? [],
  };
}

/** The check's system prompt; a lenient check adds its own rule (check-lenient.md), and so does a check with reports
 * (check-reports.md). A check with neither is what it always was. */
export function checkSystem(lenient = false, reported = false): string {
  const parts = [systemFor("check")];
  if (lenient) parts.push(prompt("check-lenient"));
  if (reported) parts.push(prompt("check-reports"));
  return parts.join("\n\n");
}

/** What else a check request may carry: the source's title and section headings, which are part of the source, and the
 * lenient switch. */
export interface CheckExtras {
  sourceTitle?: string;
  headings?: string[];
  lenient?: boolean;
  /** What the student says looks wrong, for the items being checked. */
  reports?: CheckReport[];
}

/** The reports that are about these items, as data: one JSON block the model reads as a claim, never as instructions (the
 * prompt says so; the note has no line breaks or tags to pass for one, and its length is capped by the request schema). */
function reportsBlock(reports: readonly CheckReport[] | undefined, items: readonly GeneratedItem[]): string {
  const ids = new Set(items.map((i) => i.id));
  const about = (reports ?? []).filter((r) => ids.has(r.id));
  if (about.length === 0) return "";
  const rows = about.map((r) => ({
    id: r.id,
    reason: r.reason,
    ...(r.given?.trim() ? { given: oneLine(r.given, 2000) } : {}),
    ...(r.note?.trim() ? { note: oneLine(r.note, 280) } : {}),
  }));
  return `<student_reports>\n${JSON.stringify(rows, null, 1)}\n</student_reports>`;
}

/** The source's title and headings as plain lines (the student's own text, each one line); nothing when there are none. */
function sourceBlock(title: string | undefined, headings: readonly string[] | undefined): string {
  const lines: string[] = [];
  const name = oneLine(title ?? "", 200);
  if (name) lines.push(`Source title: ${name}`);
  const parts = (headings ?? []).map((h) => oneLine(h)).filter((h) => h.length > 0).slice(0, 60);
  if (parts.length > 0) lines.push("Section headings:", ...parts.map((h) => `- ${h}`));
  return lines.join("\n");
}

/** The anchored lines and the `radius` lines on either side of each, within their page: the context a lenient check reads
 * them in. */
function withContext(pages: PageInput[], anchored: ReadonlySet<string>, radius: number): Set<string> {
  const out = new Set(anchored);
  for (const page of pages) {
    page.lines.forEach((line, i) => {
      if (!anchored.has(line.id)) return;
      const to = Math.min(page.lines.length - 1, i + radius);
      for (let j = Math.max(0, i - radius); j <= to; j++) out.add(page.lines[j].id);
    });
  }
  return out;
}

export function checkContent(pages: PageInput[], items: GeneratedItem[], extras: CheckExtras = {}): ContentBlock[] {
  const anchored = new Set(items.flatMap((i) => i.anchors ?? []));
  const about = sourceBlock(extras.sourceTitle, extras.headings);
  const reports = reportsBlock(extras.reports, items);
  return [
    ...(about ? [{ type: "text" as const, text: about }] : []),
    ...pagesContent(pages, extras.lenient ? withContext(pages, anchored, 2) : anchored),
    {
      type: "text",
      text: `<items>\n${JSON.stringify(items.map(itemForCheck), null, 1)}\n</items>\n\n${
        reports ? `${reports}\n\n` : ""
      }Give one verdict per item.`,
    },
  ];
}

export function gradeContent(req: GradeRequest): ContentBlock[] {
  const parts = [
    `<question kind="${req.kind}">${req.prompt}</question>`,
    `<model_answer>${req.modelAnswer}</model_answer>`,
    `<key_ideas>\n${JSON.stringify(req.keyIdeas, null, 1)}\n</key_ideas>`,
  ];
  if (req.sourceExcerpt) parts.push(`<source_excerpt>${req.sourceExcerpt}</source_excerpt>`);
  if (req.level) parts.push(`Student level: ${req.level}`);
  parts.push(`<student_answer>${req.response}</student_answer>`, "Grade the student's answer.");
  return [{ type: "text", text: parts.join("\n\n") }];
}

export function confusionsContent(req: ConfusionsRequest): ContentBlock[] {
  return [{
    type: "text",
    text: `Course: ${req.course}\n\n<mistakes>\n${JSON.stringify(req.mistakes, null, 1)}\n</mistakes>\n\n` +
      (req.lookAlike
        ? "This is a look-alike pair, as described in your instructions: write its one difference."
        : "Find the mix-ups and write their fixes."),
  }];
}

export function clock(seconds: number): string {
  const s = Math.max(0, Math.round(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const ss = String(s % 60).padStart(2, "0");
  return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`;
}

export function lectureContent(req: LectureRequest): ContentBlock[] {
  const transcript = req.segments.map((s) => `[${s.id} ${clock(s.start)}–${clock(s.end)}] ${s.text}`).join("\n");
  const flags = req.flags.length > 0
    ? req.flags.map((f) => `[${clock(f.time)} = ${Math.round(f.time)} s] ${f.text}`).join("\n")
    : "(none)";
  return [{
    type: "text",
    text: `Course: ${req.course}\nTitle: ${req.title}\nmaxItems: ${req.maxItems}\n\n` +
      `<transcript>\n${transcript}\n</transcript>\n\n<flagged_moments>\n${flags}\n</flagged_moments>\n\n` +
      "Write the notes and the practice questions. Times in the reply are in seconds.",
  }];
}

export function cardsContent(req: CardsFromChatRequest): ContentBlock[] {
  const chat = req.messages.map((m) => `${m.role === "user" ? "Student" : "Cap"}: ${m.text}`).join("\n\n");
  return [{
    type: "text",
    text: `${req.course ? `Course: ${req.course}\n` : ""}maxItems: ${req.maxItems}\n\n<chat>\n${chat}\n</chat>\n\n` +
      "Make the items.",
  }];
}

export function transcribeContent(req: TranscribeImageRequest): ContentBlock[] {
  return [
    imageBlock(req.image),
    { type: "text", text: `Page index ${req.page}, labelled "${attr(req.label)}". Transcribe it.` },
  ];
}

/** A syllabus as numbered lines, then what the reader needs to know about the course. Topic names are the student's own, so each is one
 * plain line. */
export function syllabusContent(req: SyllabusRequest): ContentBlock[] {
  const topics = req.topics.map((t) => `${t.id}: ${oneLine(t.name)}`).join("\n");
  return [
    ...pagesContent(req.pages),
    {
      type: "text",
      text: [
        `Course: ${oneLine(req.course, 200)}`,
        ...(req.examTitle?.trim() ? [`The exam being set up: ${oneLine(req.examTitle, 200)}`] : []),
        `Today: ${req.today}`,
        "",
        `<course_topics>\n${topics}\n</course_topics>`,
        "",
        "Read what this page says about the exams.",
      ].join("\n"),
    },
  ];
}

/** The sentences a date was heard in, each with the days the phone read from it. */
export function examMentionContent(req: ExamMentionRequest): ContentBlock[] {
  const mentions = req.mentions.map((m) =>
    `<mention id="${attr(m.id)}" candidates="${m.candidates.map(attr).join(", ")}">${m.text}</mention>`
  ).join("\n");
  return [{
    type: "text",
    text: [
      `Course: ${oneLine(req.course, 200)}`,
      `Lecture: ${oneLine(req.title, 200)}`,
      `Recorded on: ${req.recordedDay}`,
      ...(req.language?.trim() ? [`Language: ${oneLine(req.language, 20)}`] : []),
      `Course topics: ${req.topics.map((t) => oneLine(t)).filter((t) => t).join("; ") || "(none)"}`,
      "",
      mentions,
      "",
      "Answer once per mention.",
    ].join("\n"),
  }];
}

/** The ideas of a last look, each with the question it comes from and the lines behind it. */
export function lastLookContent(req: LastLookRequest): ContentBlock[] {
  const ideas = req.ideas.map((idea) =>
    [
      `<idea id="${attr(idea.id)}">`,
      ...(idea.topic?.trim() ? [`Topic: ${oneLine(idea.topic, 120)}`] : []),
      `Question: ${idea.prompt}`,
      `Answer: ${idea.answer}`,
      ...idea.lines.map((line) => `Line: ${line}`),
      "</idea>",
    ].join("\n")
  ).join("\n");
  return [{
    type: "text",
    text: [
      `Course: ${oneLine(req.course, 200)}`,
      `Exam: ${oneLine(req.examTitle, 200)}`,
      ...(req.language?.trim() ? [`Language: ${oneLine(req.language, 20)}`] : []),
      "",
      ideas,
      "",
      "One plain sentence per idea.",
    ].join("\n"),
  }];
}

/** A source's text in sentence-sized blocks, so a quote can be located in the passage. */
export function citableBlocks(text: string, maxBlocks = 80): { type: "text"; text: string }[] {
  const pieces = text
    .replace(/\r\n?/g, "\n")
    .split(/(?<=[.!?])\s+|\n+/)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
  const merged: string[] = [];
  for (const piece of pieces) {
    const last = merged.length - 1;
    if (last >= 0 && (merged[last].length < 24 || piece.length < 12)) merged[last] = `${merged[last]} ${piece}`;
    else merged.push(piece);
  }
  const blocks: string[] = [];
  for (const piece of merged) {
    for (let i = 0; i < piece.length; i += 1200) blocks.push(piece.slice(i, i + 1200));
  }
  if (blocks.length > maxBlocks) {
    const tail = blocks.splice(maxBlocks - 1).join(" ");
    blocks.push(tail);
  }
  return (blocks.length > 0 ? blocks : [text]).map((t) => ({ type: "text", text: t }));
}

/** How "Explain my mistake" wants its reply: three short parts the app shows one page at a time (`MistakeSteps` in the app). It goes
 * with the question they got wrong, in the last turn, so the instructions and the material before it stay the same bytes for the
 * prompt cache. The app shows the right answer beside theirs, so a part may say it; on hints first, the second part still points
 * instead of telling. */
export function mistakeInstruction(hints: boolean): string {
  const why = hints
    ? "2. A nudge toward why: point to the passage that holds the reason, with its citation, without spelling the reason out. One or two sentences."
    : "2. Why, from the sources, with the citation. Two or three sentences.";
  return [
    "Write this reply as three short parts, separated by one blank line, with no labels, headings or numbers:",
    "1. What their answer got right, then the one thing that's off. One or two sentences.",
    why,
    '3. One quick check question on the same idea, starting "Quick check:". Not a question this reply already answered.',
    "If the sources don't hold the idea, say only that you couldn't find it, as one part.",
  ].join("\n");
}

/** The conversation for the tutor, in the order that lets OpenAI's prompt cache serve the biggest part of each request
 * again: the student's material first (the passages, then what they have added), then the earlier turns, then the last
 * question with what belongs to it alone (a note that no passage matched, or the question they got wrong for "Explain my
 * mistake"). The cache matches from the start of the input, so while the app sends the same passages in the same order the
 * material is the same bytes for every question; the instructions before it are the same for the whole chat. */
export function tutorMessages(req: TutorRequest): Message[] {
  const turns = [...req.messages];
  while (turns.length > 0 && turns[0].role !== "user") turns.shift();
  const last = turns.pop();
  if (!last || last.role !== "user") return [];
  const out: Message[] = [];
  const material: ContentBlock[] = req.sources.map((s): ContentBlock => ({
    type: "search_result",
    source: s.id,
    title: s.label ? `${s.title} · ${s.label}` : s.title,
    content: citableBlocks(s.text),
  }));
  const added = materialsBlock(req.materials);
  if (added) material.push({ type: "text", text: added });
  if (material.length > 0) out.push({ role: "user", content: material });
  for (const m of turns) out.push({ role: m.role, content: m.text });
  const content: ContentBlock[] = [];
  if (req.sources.length === 0) {
    content.push({ type: "text", text: "(No passages from the student's material matched this question.)" });
  }
  if (req.context) {
    content.push({
      type: "text",
      text: `The student is asking about a question they got wrong.\n<question>${req.context.itemPrompt}</question>\n` +
        `<expected>${req.context.expected}</expected>\n<their_answer>${req.context.given}</their_answer>`,
    });
    content.push({ type: "text", text: mistakeInstruction(req.minor || req.mode === "hints") });
  }
  content.push({ type: "text", text: last.text });
  out.push({ role: "user", content });
  return out;
}
