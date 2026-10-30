// Ask Cap's tutor on OpenAI through the relay's real code path: `OPENAI_API_KEY=… deno task live-openai`.
//
// Runs the `ai` handler in-process (the same handler the deployed function serves; the test rig supplies the auth and an
// in-memory store) with the real OpenAI provider, Terra at low reasoning unless OPENAI_TUTOR_MODEL and OPENAI_TUTOR_EFFORT
// say otherwise. It asks the tutor four questions about the sample page, prints what the app would show and a verdict per
// check: a quote that is really on the page, hints that end on a question, no source id in the answer, a question the
// notes cannot answer, an under-18 account kept on hints. It spends a fraction of a cent and stores nothing. The key is
// read from the environment only and never written anywhere.
//
// Use it once before the tutor goes live on OpenAI, and after changing the tutor's prompts (then `deno task bundle`).

import { TERRA } from "../_shared/cost.ts";
import { OpenAIProvider } from "../_shared/openai.ts";
import { parseSse } from "../_shared/sse.ts";
import { fixtureJson, logLines, rig } from "../tests/_harness.ts";

const key = Deno.env.get("OPENAI_API_KEY") ?? "";
if (!key) {
  console.error("Set OPENAI_API_KEY in the environment (never commit it). Nothing was sent.");
  Deno.exit(2);
}

const asked = Deno.env.get("OPENAI_TUTOR_EFFORT");
const effort = asked === "medium" || asked === "high" ? asked : "low";
const model = Deno.env.get("OPENAI_TUTOR_MODEL") || TERRA;
// OPENAI_BASE_URL points it at the mock server instead, for a dry run of this script.
const baseURL = Deno.env.get("OPENAI_BASE_URL") || undefined;
const t = rig({
  env: { DAILY_COST_CAP_USD: "0" }, // a live run sends many requests as one person: no daily cost cap
  provider: new OpenAIProvider({ apiKey: key, baseURL, timeoutMs: 120_000 }),
  tutorModel: model,
  tutorEffort: effort,
});
t.store.addUser("user-1", "Live check", "UTC");
if (baseURL) console.log(`(dry run against ${baseURL}: canned replies, the quality checks don't mean anything)`);
console.log(`model ${model}, reasoning ${effort}`);

let failures = 0;
function verdict(ok: boolean, what: string): void {
  console.log(`${ok ? "  PASS" : "  FAIL"}  ${what}`);
  if (!ok) failures++;
}

const page = fixtureJson("requests/tutor").sources[0].text as string;
const fold = (s: string) => s.toLowerCase().replace(/\s+/g, " ").trim();

async function ask(title: string, body: unknown) {
  console.log(`\n== ${title}`);
  const started = performance.now();
  const res = await t.ai("tutor", { body });
  if (res.status !== 200 || !res.body) {
    verdict(false, `the tutor answered (HTTP ${res.status})`);
    return null;
  }
  let text = "";
  let first = 0;
  let served = "";
  const quotes: string[] = [];
  let error = "";
  for await (const m of parseSse(res.body)) {
    const data = m.data ? JSON.parse(m.data) : {};
    if (m.event === "delta") {
      if (!first) first = performance.now() - started;
      text += data.text ?? "";
    }
    if (m.event === "citation") quotes.push(`${data.label}: “${data.quote}”`);
    if (m.event === "done") served = data.model;
    if (m.event === "error") error = `${data.code} ${data.message}`;
  }
  console.log(`  ${text}`);
  for (const q of quotes) console.log(`  cites ${q}`);
  if (error) console.log(`  error: ${error}`);
  console.log(`  first words after ${(first / 1000).toFixed(1)} s, answered by ${served || "?"}`);
  verdict(error === "", "no error");
  verdict(!/\bs[1-9]\b/.test(text), "no source id in the answer");
  return { text, quotes, first };
}

const base = fixtureJson("requests/tutor");

const hints = await ask("hints", { ...base, mode: "hints" });
if (hints) {
  verdict(hints.quotes.length > 0, "cites the page");
  verdict(
    hints.quotes.every((q) => fold(page).includes(fold(q.split("“")[1]?.replace(/”$/, "") ?? ""))),
    "every quote is on the page",
  );
  verdict(hints.text.includes("?"), "hints first asks a question back");
}

const explain = await ask("explain", { ...base, mode: "explain" });
if (explain) {
  verdict(explain.quotes.length > 0, "cites the page");
  verdict(/\?\s*$/.test(explain.text.trim()), "ends with a check question");
}

const beyond = await ask("a question the page cannot answer", {
  ...base,
  mode: "explain",
  messages: [{ role: "user", text: "How many chromosomes do humans have?" }],
});
if (beyond) {
  verdict(!/\b(46|forty-six|23 pairs)\b/i.test(beyond.text), "does not answer from outside knowledge");
  verdict(
    /(doesn['’]?t|does not|don['’]?t|isn['’]?t)[^.?!]{0,60}(cover|say|mention|include|give)/i.test(beyond.text),
    "says the notes don't cover it",
  );
}

const minor = await ask("under 18, explain asked for", { ...base, mode: "explain", minor: true });
if (minor) verdict(minor.text.includes("?"), "stays on hints for an under-18 account");

// Cost, from the relay's own log lines.
let cost = 0;
for (const line of logLines) {
  const m = /"cost_usd":"?([0-9.]+)/.exec(line);
  if (m) cost += Number(m[1]);
}
console.log(`\nCost of this run: about $${cost.toFixed(5)}`);
console.log(failures === 0 ? "All checks passed." : `${failures} check(s) failed.`);
Deno.exit(failures === 0 ? 0 : 1);
