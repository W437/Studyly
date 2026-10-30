// How a case becomes a request: the four passages its question finds, the tutor request the app would send, and the
// conversation as OpenAI gets it. Shared by the run and by the check that prints what each question retrieves.

import { tutorSystem } from "../../_shared/prompts.ts";
import type { TutorRequest, TutorSource } from "../../_shared/contract.ts";
import type { Case } from "./cases.ts";
import { type Passage, search } from "./corpus.ts";

export const SCHEMA = {
  type: "object",
  properties: {
    answer: { type: "string" },
    citations: {
      type: "array",
      items: {
        type: "object",
        properties: { source_id: { type: "string" }, quote: { type: "string" } },
        required: ["source_id", "quote"],
        additionalProperties: false,
      },
    },
  },
  required: ["answer", "citations"],
  additionalProperties: false,
};

// Claude cites through search_result blocks; here the model is asked for the quotes and the app's own rule judges them.
const FORMAT = `Reply as JSON with two fields and nothing else:
- "answer": your reply to the student, following all the rules above.
- "citations": the quotes that support what you said. Each has "source_id" (the id of the source) and "quote": a stretch of that source's text copied exactly, character for character, 6 to 30 words long. Give one or two. Use an empty list when the sources don't cover the question or you are only steering the student back to their studies.
Never write a source id (like s1) in the answer. If you point to a source, use its page label (for example "your textbook, p. 87") or say your notes, slides or lecture.`;

const attr = (value: string) => value.replace(/["<>]/g, "");

/** The four passages a question finds; a follow-up that is a few words long searches with the turns before it too. */
export function retrieve(c: Case): Passage[] {
  const users = c.messages.filter((m) => m.role === "user").map((m) => m.text);
  const question = users[users.length - 1];
  const asked = c.context ? `${c.context.itemPrompt} ${c.context.expected} ${question}` : question;
  let hits = search(asked);
  if (users.length > 1 && (hits.length === 0 || question.split(/\s+/).filter(Boolean).length <= 4)) {
    const earlier = users.slice(0, -1).slice(-2).join(" ");
    const lastAnswer = [...c.messages].reverse().find((m) => m.role === "assistant")?.text.slice(0, 400) ?? "";
    const widened = search([asked, earlier, lastAnswer].filter(Boolean).join(" "));
    if (widened.length > 0) hits = widened;
  }
  const plant = c.plant ?? [];
  return [...hits.slice(0, 4 - plant.length), ...plant];
}

export function requestFor(c: Case, hits: Passage[]): TutorRequest {
  const sources: TutorSource[] = hits.map((p, i) => ({
    id: `s${i + 1}`,
    title: p.title,
    label: p.label,
    text: p.text,
  }));
  return { mode: c.mode, minor: c.minor ?? false, course: c.course, messages: c.messages, sources, context: c.context };
}

/** The relay's tutor system prompt, plus the output format OpenAI needs. */
export function instructionsFor(req: TutorRequest): string {
  return `${tutorSystem(req)}\n\n${FORMAT}`;
}

/** The conversation as the relay sends it to Claude, with the passages as tagged text instead of search results. */
export function inputFor(req: TutorRequest) {
  const turns = [...req.messages];
  const last = turns.pop()!;
  const out: { role: "user" | "assistant"; content: string }[] = turns.map((m) => ({ role: m.role, content: m.text }));
  const sources = req.sources.length > 0
    ? "<sources>\n" + req.sources.map((s) =>
      `<source id="${s.id}" title="${attr(s.label ? `${s.title} · ${s.label}` : s.title)}">\n${s.text}\n</source>`
    ).join("\n") + "\n</sources>"
    : "(No passages from the student's material matched this question.)";
  const context = req.context
    ? `\nThe student is asking about a question they got wrong.\n<question>${req.context.itemPrompt}</question>\n` +
      `<expected>${req.context.expected}</expected>\n<their_answer>${req.context.given}</their_answer>`
    : "";
  out.push({ role: "user", content: `${sources}${context}\n\n${last.text}` });
  return out;
}
