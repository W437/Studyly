// Real OpenAI through the relay's real code path: `OPENAI_API_KEY=… deno task live`.
//
// Runs the `ai` handler in-process (the same handler the deployed function serves; the test rig supplies the auth
// and an in-memory store) with the real OpenAI provider. It asks for questions from the sample page, checks them
// against the page, grades three answers and asks the tutor two questions (streamed with citations), all on GPT 6.1
// Terra, printing what the app would show and a verdict per check. It spends a few cents and stores nothing. The key is
// read from the environment only and never written anywhere. `LIVE_ONLY=generate,check,grade,tutor,mistake,photo,lookalike` runs some of them.
//
// Use it after changing a prompt in _shared/prompts/ (then `deno task bundle`), and once before launch.

import { OpenAIAssistantProvider } from "../_shared/openai_assistant.ts";
import { parseSse } from "../_shared/sse.ts";
import { fixtureJson, logLines, rig } from "../tests/_harness.ts";

const key = Deno.env.get("OPENAI_API_KEY") ?? "";
if (!key) {
  console.error("Set OPENAI_API_KEY in the environment (never commit it). Nothing was sent.");
  Deno.exit(2);
}

// OPENAI_BASE_URL points it at the mock server instead (`deno task mock-openai`), for a dry run of this script.
const baseURL = Deno.env.get("OPENAI_BASE_URL") || undefined;
const only = new Set(
  (Deno.env.get("LIVE_ONLY") ?? "generate,check,grade,tutor,mistake,photo,lookalike").split(",").map((p) => p.trim()),
);
const t = rig({
  env: { OPENAI_API_KEY: key, DAILY_COST_CAP_USD: "0" }, // many requests as one person: no daily cost cap
  provider: new OpenAIAssistantProvider({ apiKey: key, baseURL, maxRetries: 1, timeoutMs: 120_000 }),
});
t.store.addUser("user-1", "Live check", "UTC");
if (baseURL) console.log(`(dry run against ${baseURL}: canned replies, the quality checks don't mean anything)`);
let failures = 0;
function verdict(ok: boolean, what: string): void {
  console.log(`${ok ? "  PASS" : "  FAIL"}  ${what}`);
  if (!ok) failures++;
}

// deno-lint-ignore no-explicit-any
async function post(path: string, body: unknown): Promise<any> {
  const res = await t.ai(path, { body });
  const text = await res.text();
  if (res.status !== 200) {
    console.log(`  ${path}: HTTP ${res.status} ${text.slice(0, 300)}`);
    return null;
  }
  return JSON.parse(text);
}

// 1. Generate from the sample page.
console.log("\n== generate (sample page, p. 87)");
const generateRequest = fixtureJson("requests/generate");
const lineIds = new Set<string>(
  generateRequest.pages.flatMap((p: { lines: { id: string }[] }) => p.lines.map((l) => l.id)),
);
const generated = only.has("generate") ? await post("generate", generateRequest) : null;
if (generated) {
  // deno-lint-ignore no-explicit-any
  const items: any[] = generated.items;
  for (const item of items) {
    const extra = item.kind === "mcq"
      ? ` choices=${
        JSON.stringify(item.choices.map((c: { text: string; correct: boolean }) => (c.correct ? "*" : "") + c.text))
      }`
      : item.kind === "cloze"
      ? ` cloze=${item.cloze?.text}`
      : item.keyIdeas?.length
      ? ` ideas=${JSON.stringify(item.keyIdeas.map((k: { label: string }) => k.label))}`
      : "";
    console.log(`  [${item.kind}] ${item.prompt} → ${item.answer}${extra} lines=${item.anchors.join(",")}`);
  }
  verdict(items.length >= 6, `${items.length} questions (want 6 or more)`);
  verdict(new Set(items.map((i) => i.kind)).size >= 3, "at least three formats");
  verdict(
    items.every((i) => i.anchors.length > 0 && i.anchors.every((a: string) => lineIds.has(a))),
    "every question points at real lines",
  );
  verdict(
    items.filter((i) => i.kind === "mcq").every((i) =>
      i.choices.filter((c: { correct: boolean }) => c.correct).length === 1
    ),
    "each multiple choice has exactly one right answer",
  );

  // 2. The check pass on what was generated.
  console.log("\n== check (against the page)");
  const checked = only.has("check") ? await post("check", { pages: generateRequest.pages, items }) : null;
  if (!only.has("check")) console.log("  (skipped)");
  else if (checked) {
    // deno-lint-ignore no-explicit-any
    for (const v of checked.verdicts as any[]) console.log(`  ${v.id}: ${v.verdict} — ${v.reason}`);
    verdict(checked.verdicts.length === items.length, "a verdict for every question");
  } else verdict(false, "the check answered");
} else if (only.has("generate")) verdict(false, "generate answered");

// 3. Grading three answers to "why do cells divide by mitosis?".
console.log("\n== grade");
const gradeBase = fixtureJson("requests/grade");
const answers: [string, string][] = [
  ["So the body can grow and repair tissue, making two identical cells.", "partial"],
  [
    "To grow and fix damaged tissue; each new cell is an exact genetic copy with the same number of chromosomes.",
    "correct",
  ],
  ["To make sex cells with half the chromosomes.", "incorrect"],
];
for (const [response, expected] of only.has("grade") ? answers : []) {
  const graded = await post("grade", { ...gradeBase, response });
  if (!graded) {
    verdict(false, `graded "${response}"`);
    continue;
  }
  console.log(`  "${response}" → ${graded.verdict} ${graded.score} (confidence ${graded.confidence})`);
  console.log(`     hits ${JSON.stringify(graded.hits)} · missing ${JSON.stringify(graded.missing)}`);
  console.log(`     feedback: ${graded.feedback}`);
  if (graded.fix) console.log(`     fix: ${graded.fix}`);
  verdict(graded.verdict === expected, `verdict ${graded.verdict} (expected ${expected})`);
  verdict(
    (graded.hits as { quote: string }[]).every((h) => response.toLowerCase().includes(h.quote.toLowerCase())),
    "every quote is the student's own words",
  );
}

// 4. The tutor, streamed with citations.
for (const mode of only.has("tutor") ? ["hints", "explain"] : []) {
  console.log(`\n== tutor (${mode})`);
  const body = { ...fixtureJson("requests/tutor"), mode };
  const res = await t.ai("tutor", { body });
  if (res.status !== 200 || !res.body) {
    verdict(false, `tutor ${mode} answered (HTTP ${res.status})`);
    continue;
  }
  let text = "";
  const citations: string[] = [];
  for await (const m of parseSse(res.body)) {
    const data = m.data ? JSON.parse(m.data) : {};
    if (m.event === "delta") text += data.text ?? "";
    if (m.event === "citation") citations.push(`${data.label}: “${data.quote}”`);
    if (m.event === "error") console.log(`  error: ${data.code} ${data.message}`);
  }
  console.log(`  ${text}`);
  for (const c of citations) console.log(`  cites ${c}`);
  verdict(citations.length > 0, "cites the page");
  if (mode === "hints") verdict(text.includes("?"), "hints first asks a question back");
}

/** One tutor reply through the relay's real code path: its words and what it cites. */
async function tutorReply(body: unknown): Promise<{ text: string; citations: string[] } | null> {
  const res = await t.ai("tutor", { body });
  if (res.status !== 200 || !res.body) {
    verdict(false, `tutor answered (HTTP ${res.status})`);
    return null;
  }
  let text = "";
  const citations: string[] = [];
  for await (const m of parseSse(res.body)) {
    const data = m.data ? JSON.parse(m.data) : {};
    if (m.event === "delta") text += data.text ?? "";
    if (m.event === "citation") citations.push(`${data.label}: “${data.quote}”`);
    if (m.event === "error") console.log(`  error: ${data.code} ${data.message}`);
  }
  console.log(`  ${text}`);
  for (const c of citations) console.log(`  cites ${c}`);
  return { text, citations };
}

// 5. "Explain my mistake": three parts, for an adult and for an under-18 account.
for (const minor of only.has("mistake") ? [false, true] : []) {
  console.log(`\n== tutor, explain my mistake${minor ? " (under 18)" : ""}`);
  const reply = await tutorReply({
    ...fixtureJson("requests/tutor"),
    mode: minor ? "hints" : "explain",
    minor,
    messages: [{ role: "user", text: "I answered “To make sex cells”. What did I miss?" }],
    context: { itemPrompt: "Why is mitosis important?", expected: "Growth and repair", given: "To make sex cells" },
  });
  if (reply) {
    const parts = reply.text.trim().split(/\n\s*\n/);
    verdict(parts.length === 3, `three parts (got ${parts.length})`);
    verdict(parts[parts.length - 1].trim().endsWith("?"), "the last part is a question");
    verdict(reply.citations.length > 0, "cites the page");
  }
}

// 6. A problem from a photo: hints first, cited, never the final answer; and the sentence the app turns into its own when the notes
// don't hold it. `tools/tutor_bakeoff` runs a dozen of these; this is the check on the deployed code path.
if (only.has("photo")) {
  const request = { ...fixtureJson("requests/tutor"), mode: "explain", fromPhoto: true };
  console.log("\n== tutor, a problem from a photo the notes cover");
  const covered = await tutorReply({
    ...request,
    messages: [{
      role: "user",
      text:
        "Homework 3. A cell with 46 chromosomes goes through mitosis. How many chromosomes does each daughter cell have?",
    }],
  });
  if (covered) {
    verdict(covered.citations.length > 0, "cites the method");
    verdict(covered.text.includes("?"), "asks a question back");
    verdict(
      !/\b(each|daughter)\b[^.?!]*\b46\b|\b46\b[^.?!]*\b(each|daughter)\b/i.test(covered.text),
      "does not state the answer (46)",
    );
  }
  console.log("\n== tutor, a problem from a photo the notes don't hold");
  const beyond = await tutorReply({
    ...request,
    messages: [{ role: "user", text: "Find the integral of x^2 from 0 to 3." }],
  });
  if (beyond) {
    verdict(/couldn['’]?t find this topic/i.test(beyond.text), "says it couldn't find the topic");
    verdict(!/\b9\b|power rule|antiderivative/i.test(beyond.text), "uses nothing from outside the notes");
  }
}

// 7. A look-alike pair: two questions from the sample page the student hasn't mixed up yet.
if (only.has("lookalike")) {
  console.log("\n== confusions (look-alike pair)");
  const reply = await post("confusions", {
    course: "Bio 101",
    lookAlike: true,
    mistakes: [
      {
        itemId: "i7",
        topic: "Phases of mitosis",
        prompt: "In which phase do chromosomes line up at the equator of the cell?",
        expected: "Metaphase",
        given: "",
        misses: 0,
      },
      {
        itemId: "i10",
        topic: "Cytokinesis",
        prompt: "Which phase comes right before cytokinesis?",
        expected: "Telophase",
        given: "",
        misses: 0,
      },
    ],
  });
  const lesson = reply?.confusions?.[0];
  if (lesson) {
    console.log(`  ${lesson.name}\n  ${lesson.lesson}`);
    // deno-lint-ignore no-explicit-any
    for (const q of lesson.questions as any[]) console.log(`  [${q.kind}] ${q.prompt} → ${q.answer}`);
  }
  verdict(reply?.confusions?.length === 1, "one confusion for the pair");
  verdict(new Set(lesson?.itemIds ?? []).size === 2, "it covers both questions");
  verdict((lesson?.questions?.length ?? 0) >= 2, "two or more questions");
  verdict(
    !/you (got|missed|swapped|mixed)/i.test(`${lesson?.explanation} ${lesson?.lesson}`),
    "never says the student got it wrong",
  );
}

// Cost, from the relay's own log lines.
let cost = 0;
for (const line of logLines) {
  const m = /"cost_usd":"?([0-9.]+)/.exec(line);
  if (m) cost += Number(m[1]);
}
console.log(`\nCost of this run: about $${cost.toFixed(4)}`);
console.log(failures === 0 ? "All checks passed." : `${failures} check(s) failed.`);
Deno.exit(failures === 0 ? 0 : 1);
