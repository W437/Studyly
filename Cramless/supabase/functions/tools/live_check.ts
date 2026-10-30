// Real Claude through the relay's real code path: `ANTHROPIC_API_KEY=… deno task live`.
//
// Runs the `ai` handler in-process (the same handler the deployed function serves; the test rig supplies the auth
// and an in-memory store) with the real Anthropic provider. It asks for questions from the sample page (Haiku 5.5),
// checks them against the page (Haiku 5.5), grades three answers (Haiku 5.5) and asks the tutor two questions
// (Sonnet 5.5, streamed with citations), printing what the app would show and a verdict per check. It spends a few
// cents and stores nothing. The key is read from the environment only and never written anywhere.
//
// Use it after changing a prompt in _shared/prompts/ (then `deno task bundle`), and once before launch.

import { AnthropicProvider } from "../_shared/anthropic.ts";
import { parseSse } from "../_shared/sse.ts";
import { fixtureJson, logLines, rig } from "../tests/_harness.ts";

const key = Deno.env.get("ANTHROPIC_API_KEY") ?? "";
if (!key) {
  console.error("Set ANTHROPIC_API_KEY in the environment (never commit it). Nothing was sent.");
  Deno.exit(2);
}

// ANTHROPIC_BASE_URL points it at the mock server instead (`deno task mock-anthropic`), for a dry run of this script.
const baseURL = Deno.env.get("ANTHROPIC_BASE_URL") ?? undefined;
const t = rig({
  env: { ANTHROPIC_API_KEY: key, DAILY_COST_CAP_USD: "0" }, // many requests as one person: no daily cost cap
  provider: new AnthropicProvider({ apiKey: key, baseURL, maxRetries: 1, timeoutMs: 120_000 }),
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
const generated = await post("generate", generateRequest);
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
  const checked = await post("check", { pages: generateRequest.pages, items });
  if (checked) {
    // deno-lint-ignore no-explicit-any
    for (const v of checked.verdicts as any[]) console.log(`  ${v.id}: ${v.verdict} — ${v.reason}`);
    verdict(checked.verdicts.length === items.length, "a verdict for every question");
  } else verdict(false, "the check answered");
} else verdict(false, "generate answered");

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
for (const [response, expected] of answers) {
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
for (const mode of ["hints", "explain"]) {
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

// Cost, from the relay's own log lines.
let cost = 0;
for (const line of logLines) {
  const m = /"cost_usd":"?([0-9.]+)/.exec(line);
  if (m) cost += Number(m[1]);
}
console.log(`\nCost of this run: about $${cost.toFixed(4)}`);
console.log(failures === 0 ? "All checks passed." : `${failures} check(s) failed.`);
Deno.exit(failures === 0 ? 0 : 1);
