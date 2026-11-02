// The system prompts (files in _shared/prompts, bundled into generated.ts) and the user content of every route.
// The person's material goes in as data, in tagged blocks; ids are written exactly as the app sent them so the
// model can only cite real ones.

import type {
  AssistantRequest,
  CardsFromChatRequest,
  ConfusionsRequest,
  GeneratedItem,
  GenerateRequest,
  GradeRequest,
  LectureRequest,
  PageInput,
  ResearchRequest,
  TranscribeImageRequest,
  TutorRequest,
} from "./contract.ts";
import { PROMPTS } from "./generated.ts";
import type { ContentBlock, Message } from "./provider.ts";

export type Task = "generate" | "check" | "grade" | "confusions" | "lecture" | "cards" | "transcribe";

function prompt(name: string): string {
  const text = PROMPTS[name];
  if (text === undefined) throw new Error(`Missing prompt ${name}`);
  return text;
}

/** The shared rules, then the task. */
export function systemFor(task: Task): string {
  return `${prompt("rules")}\n\n${prompt(task)}`;
}

/** The tutor's system prompt: hints first (always for a minor) or explain, plus the teen-safe scope. */
export function tutorSystem(req: TutorRequest): string {
  const parts = [prompt("rules"), prompt("tutor")];
  const hints = req.minor || req.mode === "hints";
  parts.push(prompt(hints ? "tutor-hints" : "tutor-explain"));
  if (req.minor) parts.push(prompt("tutor-minor"));
  if (req.course) parts.push(`The student's course: ${oneLine(req.course)}.`);
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
function oneLine(text: string): string {
  return text.replace(/[\r\n\t`<>]+/g, " ").replace(/\s+/g, " ").trim().slice(0, 120);
}

/** The web research prompt. */
export function researchSystem(): string {
  return `${prompt("rules")}\n\n${prompt("research")}`;
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

export function generateContent(req: GenerateRequest): ContentBlock[] {
  return [
    ...pagesContent(req.pages),
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
        "Write the practice set from these pages.",
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

export function checkContent(pages: PageInput[], items: GeneratedItem[]): ContentBlock[] {
  const anchored = new Set(items.flatMap((i) => i.anchors ?? []));
  return [
    ...pagesContent(pages, anchored),
    {
      type: "text",
      text: `<items>\n${JSON.stringify(items.map(itemForCheck), null, 1)}\n</items>\n\nGive one verdict per item.`,
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
      "Find the mix-ups and write their fixes.",
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

/** The conversation for the tutor: the earlier turns as text, and the last question with the passages (as sources) and, for "Explain my mistake", the question the student got wrong. */
export function tutorMessages(req: TutorRequest): Message[] {
  const turns = [...req.messages];
  while (turns.length > 0 && turns[0].role !== "user") turns.shift();
  const last = turns.pop();
  if (!last || last.role !== "user") return [];
  const out: Message[] = turns.map((m) => ({ role: m.role, content: m.text }));
  const content: ContentBlock[] = req.sources.map((s): ContentBlock => ({
    type: "search_result",
    source: s.id,
    title: s.label ? `${s.title} · ${s.label}` : s.title,
    content: citableBlocks(s.text),
  }));
  if (req.sources.length === 0) {
    content.push({ type: "text", text: "(No passages from the student's material matched this question.)" });
  }
  if (req.context) {
    content.push({
      type: "text",
      text: `The student is asking about a question they got wrong.\n<question>${req.context.itemPrompt}</question>\n` +
        `<expected>${req.context.expected}</expected>\n<their_answer>${req.context.given}</their_answer>`,
    });
  }
  content.push({ type: "text", text: last.text });
  out.push({ role: "user", content });
  return out;
}
