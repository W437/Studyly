// The live assistant test: `deno run -A tools/assistant_bakeoff/run.ts [--cases a,b] [--group g] [--live-research]
// [--budget 2] [--out DIR] [--model gpt-6.1-terra] [--effort low] [--debug]`. The key is read from
// ~/.config/capling/openai_key, else from OPENAI_API_KEY, and is never printed or written.
//
// It plays the app. For each request in cases.ts it runs the relay's `ai` handler in-process (the code the deployed function
// serves) with the real OpenAI provider, then does what the app would do with each tool call: a lookup is answered from the
// notes (the bake-off corpus), a draft is "proposed", anything else is "offered", research is "researched" (or really run
// with --live-research). It checks what Cap chose to do and what it said, and totals what it cost. Nothing is stored.

import { ASSISTANT_TOOLS } from "../../_shared/contract.ts";
import { TERRA } from "../../_shared/cost.ts";
import { OpenAIAssistantProvider } from "../../_shared/openai_assistant.ts";
import { parseSse } from "../../_shared/sse.ts";
import { rig } from "../../tests/_harness.ts";
import { CORPUS, type Passage, search } from "../tutor_bakeoff/corpus.ts";
import { type Case, CASES } from "./cases.ts";

// ---- arguments and key

const args = Deno.args;
const flag = (name: string) => {
  const i = args.indexOf(`--${name}`);
  return i >= 0 ? args[i + 1] : undefined;
};
const has = (name: string) => args.includes(`--${name}`);

function readKey(): string {
  // The private file wins: a stale OPENAI_API_KEY left in the shell has shadowed it before.
  try {
    const fromFile = Deno.readTextFileSync(`${Deno.env.get("HOME")}/.config/capling/openai_key`).trim();
    if (fromFile) return fromFile;
  } catch {
    // no file
  }
  return (Deno.env.get("OPENAI_API_KEY") ?? "").trim();
}

const key = readKey();
if (!key) {
  console.error("No OpenAI key: set OPENAI_API_KEY or put it in ~/.config/capling/openai_key. Nothing was sent.");
  Deno.exit(2);
}
const model = flag("model") ?? TERRA;
const effort = (flag("effort") ?? "low") as "low" | "medium" | "high";
const budget = Number(flag("budget") ?? "2");
const out = flag("out") ?? new URL("../../../../build/assistant-bakeoff/run1/", import.meta.url).pathname;
const liveResearch = has("live-research");
// --mode hints runs every case in the app's default tutor mode (hints first) instead of each case's own.
const modeOverride = flag("mode") === "hints"
  ? "hints" as const
  : flag("mode") === "explain"
  ? "explain" as const
  : undefined;

// ---- the student's world

const COURSES = [
  {
    id: "c1",
    name: "Bio 101",
    prefix: ["t", "l", "w"],
    topics: [{ id: "t1", name: "Phases of mitosis", weak: true }, { id: "t2", name: "Meiosis" }, {
      id: "t3",
      name: "Cell membrane",
    }],
  },
  {
    id: "c2",
    name: "Chem 110",
    prefix: ["c"],
    topics: [{ id: "t4", name: "Moles" }, { id: "t5", name: "Stoichiometry" }, { id: "t6", name: "Limiting reagent" }],
  },
  {
    id: "c3",
    name: "AP Psychology",
    prefix: ["p"],
    topics: [{ id: "t7", name: "Memory" }, { id: "t8", name: "Learning" }],
  },
];

/** The app's search also knows a source's name: "Lecture 6" finds the passages of that lecture. */
function lookup(query: string, limit: number): Passage[] {
  const q = fold(query);
  const named = CORPUS.filter((p) => {
    const title = fold(p.title);
    const label = fold(p.label);
    return (q.includes("lecture 6") && title.includes("lecture 6")) ||
      (/\bslides?\b/.test(q) && title.includes("slides")) ||
      (q.includes("textbook") && label.includes("textbook"));
  });
  if (named.length > 0) return named.slice(0, limit);
  return search(query, 40).slice(0, limit);
}

const inCourse = (p: Passage, courseId: string | null | undefined) => {
  if (!courseId) return true;
  const course = COURSES.find((c) => c.id === courseId);
  return course ? course.prefix.some((x) => p.id.startsWith(x)) : false;
};

const fold = (s: string) => s.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase().replace(/\s+/g, " ").trim();

function studyFor(c: Case) {
  const current = c.course === undefined ? "c1" : c.course;
  return {
    today: "2026-10-22",
    ...(current ? { currentCourseId: current } : {}),
    courses: COURSES.map((course) => ({
      id: course.id,
      name: c.inject?.courseName?.id === course.id ? c.inject.courseName.name : course.name,
      sources: 3,
      questions: 40,
      due: 9,
      topics: course.topics,
    })),
    exams: [
      { id: "e1", courseId: "c1", title: "Bio 101 midterm", date: "2026-11-03", readiness: 62 },
    ],
  };
}

// ---- one case

interface Call {
  callId: string;
  name: string;
  // deno-lint-ignore no-explicit-any
  args: any;
  result: string;
  error?: string;
}

interface Result {
  id: string;
  group: string;
  say: string;
  rounds: number;
  calls: Call[];
  text: string;
  citations: { sourceId: string; quote: string }[];
  firstVisibleMs: number | null;
  firstItemMs: number | null;
  totalMs: number;
  costUsd: number;
  tokens: { input: number; cached: number; output: number };
  evidence: { exact: number; elsewhere: number; fabricated: number; none: number };
  checks: Record<string, boolean>;
  failed: string[];
  error?: string;
  /** The `limit` the last reply ended with. */
  limit?: string;
}

// --debug prints the API's reason when it refuses a request (the relay itself says only that Cap could not answer).
const debugFetch: typeof fetch = async (input, init) => {
  const res = await fetch(input, init);
  if (!res.ok) console.log(`      OpenAI said ${res.status}: ${(await res.clone().text()).slice(0, 600)}`);
  return res;
};
// The daily cost cap is off here: one run sends dozens of requests as the same few people and would pass 10¢.
const t = rig({
  env: { DAILY_COST_CAP_USD: "0" },
  provider: new OpenAIAssistantProvider({
    apiKey: key,
    timeoutMs: 120_000,
    ...(has("debug") ? { fetch: debugFetch } : {}),
  }),
  tutorModel: model,
  tutorEffort: effort,
});
t.store.addUser("user-1", "Live check", "UTC");
t.store.entitlements.push({
  userId: "user-1",
  plan: "pro",
  productId: "com.loopware.Capling.pro.yearly",
  originalTransactionId: "otid-live",
  transactionId: "t1",
  purchaseDate: "2026-10-01T00:00:00Z",
  expiresAt: "2027-10-29T00:00:00Z",
  revokedAt: null,
  environment: "Production",
});

// A free account that has used its three drafts today.
t.store.addUser("free-1", "Free check", "UTC");
t.store.counters.set("free-1|drafts|2026-10-22", 3);

async function runCase(c: Case): Promise<Result> {
  const course = c.course === undefined ? "c1" : c.course;
  const notes = CORPUS.map((p) => {
    const hostile = c.inject?.passage;
    return hostile && hostile.id === p.id ? { ...p, text: p.text + hostile.suffix } : p;
  });
  const byId = new Map(notes.map((p) => [p.id, p]));
  // The passages the app would send with the question: the best four in the chat's course (or in every course).
  const first = search(c.say, 40).filter((p) => inCourse(p, course)).slice(0, 4).map((p) => byId.get(p.id)!);
  const sent = new Map<string, Passage>();
  const sources = first.map((p, n) => {
    sent.set(`s${n + 1}`, p);
    return { id: `s${n + 1}`, title: p.title, label: p.label, text: p.text };
  });

  const result: Result = {
    id: c.id,
    group: c.group,
    say: c.say,
    rounds: 0,
    calls: [],
    text: "",
    citations: [],
    firstVisibleMs: null,
    firstItemMs: null,
    totalMs: 0,
    costUsd: 0,
    tokens: { input: 0, cached: 0, output: 0 },
    evidence: { exact: 0, elsewhere: 0, fabricated: 0, none: 0 },
    checks: {},
    failed: [],
  };
  const rowsBefore = t.store.requests.length;
  const started = performance.now();
  // deno-lint-ignore no-explicit-any
  const turns: any[] = [];
  let questions = 0;

  for (let round = 0; round < 5; round++) {
    result.rounds = round + 1;
    const body = {
      mode: modeOverride ?? c.mode ?? "explain",
      minor: c.minor ?? false,
      course: COURSES.find((x) => x.id === course)?.name,
      messages: [{ role: "user", text: c.say }],
      sources,
      study: studyFor(c),
      tools: [...ASSISTANT_TOOLS],
      turns,
    };
    const res = await t.ai("assistant", { body, ...(c.free ? { user: "free-1" } : {}) });
    if (res.status !== 200 || !res.body) {
      result.error = `HTTP ${res.status}: ${(await res.text()).slice(0, 200)}`;
      break;
    }
    const roundCalls: Call[] = [];
    let continuation: unknown[] = [];
    let stop = "";
    let text = "";
    for await (const m of parseSse(res.body)) {
      const data = m.data ? JSON.parse(m.data) : {};
      const at = performance.now() - started;
      if (m.event === "tool_start" || m.event === "delta") result.firstVisibleMs ??= at;
      if (m.event === "tool_item" || m.event === "tool_text") result.firstItemMs ??= at;
      if (m.event === "delta") text += data.text;
      if (m.event === "citation") result.citations.push({ sourceId: data.sourceId, quote: data.quote });
      if (m.event === "tool_call") {
        roundCalls.push({ callId: data.callId, name: data.name, args: data.arguments, result: "" });
      }
      if (m.event === "done") {
        stop = data.stop;
        continuation = data.continuation ?? [];
        if (data.limit) result.limit = data.limit;
      }
      if (m.event === "error") result.error = `${data.code}: ${data.message}`;
    }
    result.text += (result.text && text ? "\n" : "") + text;
    await t.settle();
    if (result.error || stop !== "tool_calls") break;

    // Do what the app does with each call.
    for (const call of roundCalls) {
      const a = call.args;
      switch (call.name) {
        case "search_notes": {
          const wanted = a.course_id as string | null;
          if (wanted && !COURSES.some((x) => x.id === wanted)) {
            call.error = `no course ${wanted}`;
            call.result = JSON.stringify({ error: "That course doesn't exist." });
            break;
          }
          const hits = lookup(a.query, 40).filter((p) => inCourse(p, wanted)).slice(0, 6).map((p) => byId.get(p.id)!);
          const passages = hits.map((p) => {
            const id = `s${sent.size + 1}`;
            sent.set(id, p);
            return { id, label: p.label, text: p.text };
          });
          call.result = JSON.stringify({ passages });
          break;
        }
        case "create_flashcards":
        case "create_quiz_questions":
        case "create_note":
        case "create_exam": {
          if (!COURSES.some((x) => x.id === a.course_id)) {
            call.error = `no course ${a.course_id}`;
            call.result = JSON.stringify({ error: "That course doesn't exist." });
          } else {
            const items = a.cards?.length ?? a.questions?.length ?? 1;
            call.result = JSON.stringify({ status: "proposed", items });
          }
          break;
        }
        case "research_web":
          if (liveResearch) {
            call.result = await research(a.topic, a.focus, c.minor ?? false);
          } else {
            call.result = JSON.stringify({ status: "researched", sources: 3, summary: "shown to the student" });
          }
          break;
        default:
          call.result = JSON.stringify({ status: "offered", note: "the student sees a button" });
      }
      if (call.name === "create_flashcards" || call.name === "create_quiz_questions") {
        const list = call.args.cards ?? call.args.questions ?? [];
        for (const item of list) {
          const ev = item.evidence;
          if (!ev) {
            result.evidence.none++;
            continue;
          }
          const q = fold(ev.quote);
          const named = sent.get(ev.source_id);
          if (named && fold(named.text).includes(q)) result.evidence.exact++;
          else if (notes.some((p) => inCourse(p, a.course_id) && fold(p.text).includes(q))) result.evidence.elsewhere++;
          else result.evidence.fabricated++;
        }
      }
    }
    result.calls.push(...roundCalls);
    turns.push({
      continuation,
      results: roundCalls.map((x) => ({ callId: x.callId, output: x.result })),
    });
    questions++;
  }
  void questions;

  result.totalMs = performance.now() - started;
  const rows = t.store.requests.slice(rowsBefore);
  for (const row of rows) {
    result.costUsd += Number(row.costUsd);
    result.tokens.input += row.inputTokens;
    result.tokens.cached += row.cacheReadTokens;
    result.tokens.output += row.outputTokens;
  }
  check(c, result, sent);
  return result;
}

async function research(topic: string, focus: string | null, minor: boolean): Promise<string> {
  const res = await t.ai("research", { body: { minor, topic, ...(focus ? { focus } : {}) } });
  if (res.status !== 200 || !res.body) return JSON.stringify({ error: `research failed (HTTP ${res.status})` });
  let sources = 0;
  let words = 0;
  for await (const m of parseSse(res.body)) {
    const data = m.data ? JSON.parse(m.data) : {};
    if (m.event === "search" && data.phase === "done") sources += data.sources?.length ?? 0;
    if (m.event === "delta") words += String(data.text).split(/\s+/).length;
    if (m.event === "error") return JSON.stringify({ error: data.message });
  }
  await t.settle();
  return JSON.stringify({ status: "researched", sources, words, summary: "shown to the student" });
}

// ---- the checks

const ID_WORDS = /\b(c[1-3]|t[1-9]|s[1-9]|e[1-2])\b/;
const MACHINE_WORDS = /\b(json|study_state|function call|tool call|the tool|api)\b/i;
const CLAIMS_ADDED =
  /\b(have been added|has been added|i added|i've added|i have added|was added|were added|is now in|are now in|added to your)\b/i;

function check(c: Case, r: Result, sent: Map<string, Passage>): void {
  const e = c.expect;
  const names = r.calls.map((x) => x.name);
  const ok = (name: string, pass: boolean) => {
    r.checks[name] = pass;
    if (!pass) r.failed.push(name);
  };
  ok("noError", r.error === undefined);
  if (e.tools) { for (const tool of e.tools) ok(`calls ${tool}`, names.includes(tool)); }
  if (e.forbid) ok("forbidden tools not called", !e.forbid.some((f) => names.includes(f)));
  ok("rounds <= 3", r.rounds <= 3);
  const draft = r.calls.find((x) =>
    ["create_flashcards", "create_quiz_questions", "create_note", "create_exam", "start_practice", "open_screen"]
      .includes(x.name)
  );
  if (e.course && draft) ok(`course ${e.course}`, draft.args.course_id === e.course || draft.args.id === e.course);
  const list = draft?.args.cards ?? draft?.args.questions;
  if (e.count) {
    ok(`count ${e.count.join("–")}`, Array.isArray(list) && list.length >= e.count[0] && list.length <= e.count[1]);
  }
  if (e.types && Array.isArray(list)) {
    ok(
      `types ${e.types.join("/")}`,
      list.every((q: { type: string }) => e.types!.includes(q.type)),
    );
  }
  if (list && c.group !== "uncovered") {
    ok("no quote made up", r.evidence.fabricated === 0);
    ok("evidence mostly present", r.evidence.none <= Math.ceil(list.length * 0.2));
  }
  if (e.general && Array.isArray(list)) ok("general knowledge marked as such", r.evidence.none === list.length);
  if (e.dates) {
    ok(
      `date ${e.dates.join(" or ")}`,
      !!r.calls.find((x) => x.name === "create_exam" && e.dates!.includes(x.args.date)),
    );
  }
  if (e.minutes) {
    ok(
      `minutes ${e.minutes}`,
      !!r.calls.find((x) => x.name === "start_practice" && x.args.minutes === e.minutes),
    );
  }
  if (e.mentions) {
    const all = JSON.stringify(draft?.args ?? "").toLowerCase();
    ok(`mentions ${e.mentions.join(", ")}`, e.mentions.every((w) => all.includes(w)));
  }
  if (Array.isArray(list) && c.group === "quiz") {
    ok(
      "multiple choice well formed",
      list.every((q: { type: string; options: string[] | null; correct_index: number | null; answer: string }) =>
        q.type !== "multiple_choice" ||
        (Array.isArray(q.options) && q.options.length >= 3 && q.options.length <= 4 && q.correct_index !== null &&
          q.options[q.correct_index] === q.answer)
      ),
    );
  }
  if (Array.isArray(list)) {
    const fronts = list.map((x: { front?: string; question?: string }) => fold(x.front ?? x.question ?? ""));
    ok("no duplicate cards", new Set(fronts).size === fronts.length);
  }
  if (e.answers) {
    ok("no tool", names.length === 0);
    const verified = r.citations.filter((q) => [...sent.values()].some((p) => fold(p.text).includes(fold(q.quote))));
    ok("cites the notes", verified.length > 0 && verified.length === r.citations.length);
  }
  if (e.limit !== undefined) {
    ok(
      e.limit ? "ends with the limit" : "never meets the limit",
      e.limit ? r.limit === "drafts" : r.limit === undefined,
    );
    if (e.limit) ok("nothing was drafted", !r.calls.some((x) => x.name.startsWith("create_")));
  }
  if (e.asks) ok("hints end on a question", r.text.trim().endsWith("?") || /\?\s*$/.test(r.text.trim()));
  if (e.notCovered) {
    ok(
      "says the notes do not cover it",
      /(doesn['’]?t|does not|don['’]?t|do not|isn['’]?t|aren['’]?t|not)[^.?!]{0,60}(cover|include|mention|have|contain|in your)/i
        .test(r.text) || /(couldn['’]?t|could not|can['’]?t|cannot)\s+find/i.test(r.text),
    );
  }
  if (e.clarifyOrValid) {
    const asked = (r.text.match(/\?/g) ?? []).length;
    const valid = r.calls.length > 0 && r.calls.every((x) => !x.error);
    ok("asks once or drafts for a real course", (names.length === 0 && asked >= 1 && asked <= 1) || valid);
  }
  if (e.never) {
    ok(
      `never says ${e.never.join(", ")}`,
      !e.never.some((w) =>
        (r.text + JSON.stringify(r.calls.map((x) => x.args))).toLowerCase().includes(w.toLowerCase())
      ),
    );
  }
  if (r.calls.length > 0) {
    // (A reply that ends with the limit has no words of the model's: the app writes them.)
    if (!e.limit) ok("says something after acting", r.text.trim().length > 0);
    ok("no ids or machine words", !ID_WORDS.test(r.text) && !MACHINE_WORDS.test(r.text));
    ok("does not claim it added anything", !CLAIMS_ADDED.test(r.text));
    ok("short", r.text.length <= 460);
  } else {
    ok("no ids or machine words", !ID_WORDS.test(r.text) && !MACHINE_WORDS.test(r.text));
  }
}

// ---- run

const wanted = flag("cases")?.split(",");
const group = flag("group");
const todo = CASES.filter((c) => (!wanted || wanted.includes(c.id)) && (!group || c.group === group));
console.log(
  `${todo.length} requests, ${model} at ${effort} reasoning${
    liveResearch ? ", web research live" : ""
  }, budget $${budget}`,
);

const results: Result[] = [];
let spent = 0;
for (const c of todo) {
  if (spent >= budget) {
    console.log(`budget reached ($${spent.toFixed(3)}), stopping`);
    break;
  }
  const r = await runCase(c);
  spent += r.costUsd;
  results.push(r);
  const mark = r.failed.length === 0 ? "PASS" : "FAIL";
  const tools = r.calls.map((x) => x.name.replace("create_", "")).join("+") || "—";
  console.log(
    `${mark} ${c.id.padEnd(18)} ${String(r.rounds).padStart(1)} rounds  ${tools.padEnd(34)} ${
      (r.costUsd * 100).toFixed(2)
    }¢  ` +
      `${((r.firstVisibleMs ?? r.totalMs) / 1000).toFixed(1)}s to first sign, ${(r.totalMs / 1000).toFixed(1)}s total` +
      (r.failed.length ? `\n      failed: ${r.failed.join("; ")}` : "") +
      (r.error ? `\n      error: ${r.error}` : ""),
  );
}

// ---- totals

const pct = (xs: number[], p: number) => {
  if (xs.length === 0) return 0;
  const sorted = [...xs].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor(p * sorted.length))];
};
const cost = results.reduce((n, r) => n + r.costUsd, 0);
const passed = results.filter((r) => r.failed.length === 0).length;
console.log(
  `\n${passed} of ${results.length} requests passed every check. Cost $${cost.toFixed(4)} (${
    ((cost / Math.max(1, results.length)) * 100).toFixed(2)
  }¢ a request).`,
);
const groups = [...new Set(results.map((r) => r.group))];
for (const g of groups) {
  const rs = results.filter((r) => r.group === g);
  const c2 = rs.reduce((n, r) => n + r.costUsd, 0);
  console.log(
    `  ${g.padEnd(10)} ${rs.filter((r) => r.failed.length === 0).length}/${rs.length} passed, ${
      ((c2 / rs.length) * 100).toFixed(2)
    }¢ each, ` +
      `${(pct(rs.map((r) => r.totalMs), 0.5) / 1000).toFixed(1)}s median`,
  );
}
const drafts = results.filter((r) => r.calls.some((x) => x.name.startsWith("create_")));
console.log(
  `first sign (median/p90): ${(pct(results.map((r) => r.firstVisibleMs ?? r.totalMs), 0.5) / 1000).toFixed(1)}s / ${
    (pct(results.map((r) => r.firstVisibleMs ?? r.totalMs), 0.9) / 1000).toFixed(1)
  }s; ` +
    `first card or line: ${(pct(drafts.map((r) => r.firstItemMs ?? r.totalMs), 0.5) / 1000).toFixed(1)}s; ` +
    `total (median/p90): ${(pct(results.map((r) => r.totalMs), 0.5) / 1000).toFixed(1)}s / ${
      (pct(results.map((r) => r.totalMs), 0.9) / 1000).toFixed(1)
    }s`,
);
const ev = results.reduce(
  (a, r) => ({
    exact: a.exact + r.evidence.exact,
    elsewhere: a.elsewhere + r.evidence.elsewhere,
    fabricated: a.fabricated + r.evidence.fabricated,
    none: a.none + r.evidence.none,
  }),
  { exact: 0, elsewhere: 0, fabricated: 0, none: 0 },
);
console.log(
  `evidence quotes: ${ev.exact} exact, ${ev.elsewhere} in another passage of the course, ${ev.fabricated} not in the notes, ${ev.none} without evidence`,
);

Deno.mkdirSync(out, { recursive: true });
Deno.writeTextFileSync(`${out}/results.json`, JSON.stringify(results, null, 2));
console.log(`transcripts: ${out}results.json`);
