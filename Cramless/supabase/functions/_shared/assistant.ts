// Ask Cap as an assistant: the tools the model may call, how a request becomes the model's input, and the checks on what
// the app sends back between rounds. The relay never runs a tool. It lets the model choose one, streams the choice to the
// app (which holds the notes and the screens), and takes the result in the next request. Nothing is stored between rounds:
// the model's own output items travel to the app as an opaque `continuation` and come back with the results.
//
// Every write tool only DRAFTS: the app shows the draft in the chat and the student approves, edits or skips it (or has
// switched "Let Cap do it" on for that kind). A draft is checked by the app against the student's material before it is
// shown, so the model's `evidence` quotes are claims the app verifies, not facts.

import type { AssistantRequest, AssistantToolName, AssistantTurn, StudyState, TutorSource } from "./contract.ts";
import { ASSISTANT_TOOLS } from "./contract.ts";
import { badRequest } from "./errors.ts";
import { type Passage, taggedSources } from "./openai.ts";

export type ToolKind = "read" | "draft" | "navigate" | "research";

export interface ToolSpec {
  name: AssistantToolName;
  kind: ToolKind;
  description: string;
  parameters: Record<string, unknown>;
  /** The array property whose elements are streamed to the app as they are finished. */
  arrayKey?: string;
  /** The string property streamed to the app as it is written. */
  textKey?: string;
}

const nullable = (type: string) => ({ type: [type, "null"] });
const str = { type: "string" };

const EVIDENCE = {
  type: ["object", "null"],
  properties: { source_id: str, quote: str },
  required: ["source_id", "quote"],
  additionalProperties: false,
  description:
    "The passage that backs this item: its source id (s1, s2, …) and a short quote copied exactly from it. null only when the student asked for something their material does not cover.",
};

const object = (properties: Record<string, unknown>) => ({
  type: "object",
  properties,
  required: Object.keys(properties),
  additionalProperties: false,
});

export const TOOL_SPECS: Record<AssistantToolName, ToolSpec> = {
  search_notes: {
    name: "search_notes",
    kind: "read",
    description:
      "Look up more passages in the student's own notes (their pages and lecture transcripts). Use it when the passages you were given do not cover what the student asked about, or to look in another course. Returns up to 6 passages, each with a source id you can use as evidence.",
    parameters: object({
      query: { ...str, description: "What to look for, in a few plain words." },
      course_id: { ...nullable("string"), description: "A course id from the study state, or null for every course." },
    }),
  },
  create_flashcards: {
    name: "create_flashcards",
    kind: "draft",
    description:
      "Draft flashcards for the student to review. The app shows them in the chat; nothing is added until the student approves. One idea per card: a short front (a term or a question) and a short back. Make 4 to 12 unless they ask for a number.",
    arrayKey: "cards",
    parameters: object({
      course_id: { ...str, description: "The course id from the study state." },
      topic: { ...nullable("string"), description: "The topic name these belong to, or null." },
      cards: {
        type: "array",
        items: object({ front: str, back: str, evidence: EVIDENCE }),
      },
    }),
  },
  create_quiz_questions: {
    name: "create_quiz_questions",
    kind: "draft",
    description:
      "Draft practice questions for the student to review. Types: multiple_choice (3 or 4 options, exactly one right), short_answer (answered in the student's own words; give 2 to 4 key ideas a good answer contains), fill_blank (a sentence from the material with the hidden word or phrase wrapped in {{ }}). Make 3 to 10 unless they ask for a number.",
    arrayKey: "questions",
    parameters: object({
      course_id: { ...str, description: "The course id from the study state." },
      topic: { ...nullable("string"), description: "The topic name these belong to, or null." },
      questions: {
        type: "array",
        items: object({
          type: { type: "string", enum: ["multiple_choice", "short_answer", "fill_blank"] },
          question: { ...str, description: "The question. For fill_blank, the sentence with the blank as {{answer}}." },
          options: { type: ["array", "null"], items: str, description: "multiple_choice only; otherwise null." },
          correct_index: { type: ["integer", "null"], description: "multiple_choice only: the right option, from 0." },
          answer: { ...str, description: "The right answer in words (for multiple_choice, the right option's text)." },
          key_ideas: { type: ["array", "null"], items: str, description: "short_answer only: 2 to 4 short phrases." },
          explanation: { ...str, description: "One sentence on why the answer is right." },
          evidence: EVIDENCE,
        }),
      },
    }),
  },
  create_note: {
    name: "create_note",
    kind: "draft",
    description:
      "Draft a note for the student's library, to review before it is added. Use it when they ask for notes, a summary or a study sheet. Plain text; short headings and bullet lines are fine. Write only what their material says, or what they told you.",
    textKey: "body",
    parameters: object({
      course_id: { ...str, description: "The course id from the study state." },
      title: { ...str, description: "A short title." },
      body: str,
    }),
  },
  create_exam: {
    name: "create_exam",
    kind: "draft",
    description:
      "Draft an exam for the student's calendar, to review before it is added. The date must come from the student; if they gave none, ask once.",
    parameters: object({
      course_id: { ...str, description: "The course id from the study state." },
      title: { ...str, description: "For example “Bio 101 midterm”." },
      date: { ...str, description: "yyyy-MM-dd, resolved from today's date in the study state." },
      time: { ...nullable("string"), description: "HH:mm, or null when they did not say." },
      topic_ids: {
        type: ["array", "null"],
        items: str,
        description: "Topic ids in scope, or null for the whole course.",
      },
    }),
  },
  start_practice: {
    name: "start_practice",
    kind: "navigate",
    description:
      "Offer a practice session. The student sees a button and starts it themselves; nothing opens on its own.",
    parameters: object({
      course_id: { ...nullable("string"), description: "A course id, or null for whatever is due." },
      topic_id: { ...nullable("string"), description: "A topic id, or null." },
      minutes: { type: ["integer", "null"], description: "5 to 30, or null." },
    }),
  },
  open_screen: {
    name: "open_screen",
    kind: "navigate",
    description: "Offer a button that opens a screen of the app. Nothing opens on its own.",
    parameters: object({
      screen: { type: "string", enum: ["today", "library", "progress", "sky", "course", "exam"] },
      id: { ...nullable("string"), description: "The course id or exam id for course and exam; otherwise null." },
    }),
  },
  research_web: {
    name: "research_web",
    kind: "research",
    description:
      "Research a topic on the web, from trusted study sites only, and show the student a short cited summary they can save as a note. Use it only when the student asks you to look something up online, or when their notes do not cover it and they agree. At most once per reply.",
    parameters: object({
      topic: { ...str, description: "The topic, in a few words." },
      focus: { ...nullable("string"), description: "What to focus on, or null." },
    }),
  },
};

/** Tools that draft something the student can add: they count as the student's daily "actions" on the free plan. */
export const DRAFT_TOOLS: ReadonlySet<AssistantToolName> = new Set(
  ASSISTANT_TOOLS.filter((t) => TOOL_SPECS[t].kind === "draft"),
);

export function isToolName(name: unknown): name is AssistantToolName {
  return typeof name === "string" && (ASSISTANT_TOOLS as readonly string[]).includes(name);
}

/** The tools OpenAI is offered: the ones the app allows, minus what this student may not have (the web, under 18). The draft
 * tools stay on offer when the day's drafts are used up: the model's attempt to make something is how the relay learns the
 * student asked for it, and it ends the reply there (see `assistant` in ai/handler.ts). */
export function allowedTools(asked: readonly AssistantToolName[], o: { minor: boolean }): AssistantToolName[] {
  const seen = new Set<AssistantToolName>();
  for (const name of asked) {
    if (!isToolName(name) || seen.has(name)) continue;
    if (o.minor && name === "research_web") continue; // no open web for under-18 accounts
    seen.add(name);
  }
  return [...seen];
}

/** OpenAI function tools (strict) for these names. */
export function toolDefinitions(names: readonly AssistantToolName[]): Record<string, unknown>[] {
  return names.map((name) => {
    const spec = TOOL_SPECS[name];
    return { type: "function", name, description: spec.description, parameters: spec.parameters, strict: true };
  });
}

// ---- The conversation ----

const clean = (text: string) => text.replace(/["<>]/g, "");

/** The study state as a compact block of text the model reads; the student's own words in it cannot open a tag. */
export function studyBlock(state: StudyState): string {
  const lines = [
    `<study_state today="${clean(state.today)}"${
      state.currentCourseId ? ` current_course="${clean(state.currentCourseId)}"` : ""
    }>`,
  ];
  for (const c of state.courses) {
    const topics = c.topics.map((t) => `${clean(t.id)} “${clean(t.name)}”${t.weak ? " (fading)" : ""}`).join(", ");
    lines.push(
      `${clean(c.id)} “${clean(c.name)}” · ${c.sources} sources · ${c.questions} questions · ${c.due} due` +
        (topics ? ` · topics: ${topics}` : ""),
    );
  }
  if (state.courses.length === 0) lines.push("(no courses yet)");
  if (state.exams.length > 0) {
    lines.push("exams:");
    for (const e of state.exams) {
      lines.push(
        `${clean(e.id)} “${clean(e.title)}” · course ${clean(e.courseId)} · ${clean(e.date)} · ${e.readiness}% ready`,
      );
    }
  }
  lines.push("</study_state>");
  return lines.join("\n");
}

export interface AssistantInput {
  /** OpenAI input items: the chat, the last turn with its passages, then each round's output items and results. */
  input: Record<string, unknown>[];
  passages: Passage[];
}

/** The model's input for a request. The study state and the passages go in the last student message, after the stable
 * part of the prompt (instructions, tools, earlier turns), so the cached prefix stays the same from round to round. */
export function assistantInput(req: AssistantRequest): AssistantInput {
  const turns = [...req.messages];
  while (turns.length > 0 && turns[0].role !== "user") turns.shift();
  const last = turns.pop();
  if (!last || last.role !== "user") throw badRequest("The last message must be the student's.");
  const input: Record<string, unknown>[] = turns.map((m) => ({ role: m.role, content: m.text }));
  const tagged = taggedSources(
    req.sources.map((s: TutorSource) => ({
      id: s.id,
      title: s.label ? `${s.title} · ${s.label}` : s.title,
      text: s.text,
    })),
  );
  const parts = [studyBlock(req.study)];
  if (req.sources.length > 0) parts.push(tagged.text);
  else parts.push("(No passages from the student's material matched this message.)");
  if (req.context) {
    parts.push(
      `The student is asking about a question they got wrong.\n<question>${req.context.itemPrompt}</question>\n` +
        `<expected>${req.context.expected}</expected>\n<their_answer>${req.context.given}</their_answer>`,
    );
  }
  parts.push(last.text);
  input.push({ role: "user", content: parts.join("\n\n") });
  for (const turn of req.turns) {
    input.push(...turn.continuation);
    for (const r of turn.results) input.push({ type: "function_call_output", call_id: r.callId, output: r.output });
  }
  return { input, passages: tagged.passages };
}

// ---- Rounds ----

/** Requests in one reply: the student's message, rounds of tool calls, and the final answer (so at most three rounds of
 * results are sent back). */
export const MAX_ROUNDS = 4;
/** Calls the model may make in one round. */
export const MAX_CALLS_PER_ROUND = 4;

const MAX_OUTPUT_CHARS = 12_000;
const MAX_ARGUMENT_CHARS = 40_000;
const MAX_ENCRYPTED_CHARS = 80_000;

/** The items the relay itself sends as `continuation`: reasoning (encrypted, so the model can pick up its thread
 * without anything stored at OpenAI) and the function calls. Anything else the app sends back is refused. */
export function cleanContinuation(items: unknown, label = "turns"): Record<string, unknown>[] {
  if (!Array.isArray(items) || items.length === 0 || items.length > 2 * MAX_CALLS_PER_ROUND) {
    throw badRequest(`The request isn't valid: ${label} holds an unexpected number of items.`);
  }
  const out: Record<string, unknown>[] = [];
  for (const raw of items) {
    const item = raw as Record<string, unknown> | null;
    if (item?.type === "reasoning" && typeof item.encrypted_content === "string") {
      if (item.encrypted_content.length > MAX_ENCRYPTED_CHARS) throw badRequest("A reasoning item is too large.", 413);
      out.push({ type: "reasoning", encrypted_content: item.encrypted_content, summary: [] });
    } else if (
      item?.type === "function_call" && isToolName(item.name) && typeof item.call_id === "string" &&
      item.call_id.length > 0 && item.call_id.length <= 80 && typeof item.arguments === "string" &&
      item.arguments.length <= MAX_ARGUMENT_CHARS
    ) {
      out.push({ type: "function_call", call_id: item.call_id, name: item.name, arguments: item.arguments });
    } else {
      throw badRequest(`The request isn't valid: ${label} holds an item the relay did not send.`);
    }
  }
  return out;
}

/** The rounds the app sends back, checked: the items are the relay's own kind, every call has exactly one result and no call
 * id is used twice. */
export function checkTurns(turns: AssistantTurn[]): AssistantTurn[] {
  if (turns.length > MAX_ROUNDS - 1) throw badRequest("Cap has made as many changes as one reply can hold.");
  const seen = new Set<string>();
  return turns.map((turn, n) => {
    const continuation = cleanContinuation(turn.continuation, `turns[${n}]`);
    const calls = continuation.filter((i) => i.type === "function_call").map((i) => i.call_id as string);
    const ids = turn.results.map((r) => r.callId);
    const sameSet = calls.length > 0 && calls.length === ids.length && new Set(calls).size === calls.length &&
      new Set(ids).size === ids.length && calls.every((id) => ids.includes(id));
    if (!sameSet || calls.some((id) => seen.has(id))) {
      throw badRequest(`The request isn't valid: turns[${n}] needs one result for each call.`);
    }
    for (const id of calls) seen.add(id);
    for (const r of turn.results) {
      if (r.output.length > MAX_OUTPUT_CHARS) throw badRequest("A tool result is too large.", 413);
    }
    return { continuation, results: turn.results };
  });
}

// ---- Web research ----

/** The sites web research may read: reference works, open textbooks, courses, universities, science and government
 * bodies. A server setting (RESEARCH_DOMAINS) replaces it. Domains include their subdomains. OpenAI accepts at most 100,
 * and not a bare top-level domain, so schools are named. */
export const RESEARCH_DOMAINS: readonly string[] = [
  "wikipedia.org",
  "wikibooks.org",
  "wikiversity.org",
  "britannica.com",
  "khanacademy.org",
  "openstax.org",
  "libretexts.org",
  "ck12.org",
  "ocw.mit.edu",
  "mit.edu",
  "stanford.edu",
  "harvard.edu",
  "yale.edu",
  "princeton.edu",
  "cornell.edu",
  "berkeley.edu",
  "ox.ac.uk",
  "cam.ac.uk",
  "plato.stanford.edu",
  "iep.utm.edu",
  "nih.gov",
  "medlineplus.gov",
  "cdc.gov",
  "who.int",
  "nasa.gov",
  "noaa.gov",
  "nist.gov",
  "usgs.gov",
  "energy.gov",
  "epa.gov",
  "loc.gov",
  "archives.gov",
  "si.edu",
  "nature.com",
  "mayoclinic.org",
  "clevelandclinic.org",
  "law.cornell.edu",
  "worldbank.org",
  "imf.org",
  "oecd.org",
  "un.org",
  "investopedia.com",
  "merriam-webster.com",
  "dictionary.cambridge.org",
  "developer.mozilla.org",
  "docs.python.org",
  "mathworld.wolfram.com",
  "hyperphysics.phy-astr.gsu.edu",
  "chemguide.co.uk",
];
