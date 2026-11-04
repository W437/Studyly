// What a smaller tutor request saves, on the relay's real code path:
//
//   OPENAI_API_KEY=… deno run -A tools/tutor_cost_ab.ts --requests requests.json [--concurrency 4] [--out cost.json]
//
// `requests.json` is [{ "id": "amara.3.w2000", "group": "w2000", "body": { …the body of a POST to the `tutor` route… } }, …]: the app's own request for a
// question at a word budget (the harness's `bench request` writes them, from `TutorSelection` and `TutorRequest`). Each one is sent through the `tutor` route
// (the relay's prompt, the real OpenAI provider, Terra at low effort, a fresh in-memory account with no cost cap) and the tool records the reply, its citations,
// the token usage and the cost the relay would log. Per group it prints the means: input tokens, how many of them OpenAI's cache served, output tokens, the
// cost as logged (cache reads at their price) and the cost with no cache at all (the worst day, and the fair way to compare two sizes: a cache hit depends on
// what ran a minute before). Nothing is stored anywhere but `--out`, and the key is read from the environment only. `DRY=1` runs it on canned replies, without a
// key, to check the plumbing.

import { costNano, formatUsd, TERRA } from "../_shared/cost.ts";
import { OpenAIProvider } from "../_shared/openai.ts";
import { parseSse } from "../_shared/sse.ts";
import { rig, ScriptedProvider } from "../tests/_harness.ts";

const args = Deno.args;
function option(name: string, fallback: string): string {
  const i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
}
const dry = Deno.env.get("DRY") === "1";
const key = Deno.env.get("OPENAI_API_KEY") ?? "";
const concurrency = Math.max(1, Number(option("--concurrency", "4")));
const outPath = option("--out", "");
const limit = Number(option("--limit", "0"));
if (!dry && !key) {
  console.error("Set OPENAI_API_KEY in the environment (never commit it), or DRY=1 for a dry run. Nothing was sent.");
  Deno.exit(2);
}
if (!args.includes("--requests")) {
  console.error("Give --requests (see the top of this file).");
  Deno.exit(2);
}

interface Job {
  id: string;
  group: string;
  // deno-lint-ignore no-explicit-any
  body: any;
}
interface Result {
  id: string;
  group: string;
  status: number;
  reply: string;
  citations: { sourceId: string; label: string; quote: string }[];
  usage: { input: number; cached: number; output: number } | null;
  /** What the relay logs for it (cache reads at their price), in dollars. */
  costUsd: number | null;
  /** The same tokens with no cache at all, in dollars. */
  coldUsd: number | null;
  seconds: number;
  error?: string;
}

let jobs: Job[] = JSON.parse(await Deno.readTextFile(option("--requests", "")));
if (limit > 0) jobs = jobs.slice(0, limit);

async function once(job: Job): Promise<Result> {
  const scripted = dry ? new ScriptedProvider() : null;
  const t = rig({
    env: { DAILY_COST_CAP_USD: "0", PAID_DAILY_COST_CAP_USD: "0", PAID_WEEKLY_COST_CAP_USD: "0" },
    provider: scripted ?? new OpenAIProvider({ apiKey: key, timeoutMs: 120_000 }),
    tutorModel: Deno.env.get("OPENAI_TUTOR_MODEL") || TERRA,
    tutorEffort: "low",
  });
  t.store.addUser("user-1", "AB", "UTC");
  // A Pro account: the free plan's ten tutor answers a day would end a long run in a 429.
  t.store.entitlements.push({
    userId: "user-1",
    plan: "pro",
    productId: "com.loopware.Capling.pro.yearly",
    originalTransactionId: "otid-user-1-pro",
    transactionId: "t1",
    purchaseDate: "2026-10-01T00:00:00Z",
    expiresAt: "2027-10-29T00:00:00Z",
    revokedAt: null,
    environment: "Production",
  });
  if (scripted) {
    scripted.replyTutor([
      { type: "start", model: TERRA },
      { type: "delta", text: "Canned reply." },
      {
        type: "done",
        model: TERRA,
        usage: { inputTokens: 1000, outputTokens: 50, cacheReadTokens: 500, cacheWriteTokens: 0 },
        stop: "end",
      },
    ]);
  }
  const started = performance.now();
  const res = await t.ai("tutor", { body: job.body });
  const out: Result = {
    id: job.id,
    group: job.group,
    status: res.status,
    reply: "",
    citations: [],
    usage: null,
    costUsd: null,
    coldUsd: null,
    seconds: 0,
  };
  if (res.status !== 200 || !res.body) {
    out.error = `HTTP ${res.status}`;
    out.seconds = (performance.now() - started) / 1000;
    return out;
  }
  for await (const m of parseSse(res.body)) {
    const data = m.data ? JSON.parse(m.data) : {};
    if (m.event === "delta") out.reply += data.text ?? "";
    else if (m.event === "citation") {
      out.citations.push({ sourceId: data.sourceId ?? "", label: data.label ?? "", quote: data.quote ?? "" });
    } else if (m.event === "error" || m.event === "failure") out.error = JSON.stringify(data).slice(0, 200);
  }
  await t.settle();
  out.seconds = (performance.now() - started) / 1000;
  out.reply = out.reply.trim();
  const row = t.store.requests[0];
  if (row) {
    out.usage = { input: row.inputTokens, cached: row.cacheReadTokens, output: row.outputTokens };
    out.costUsd = Number(row.costUsd);
    out.coldUsd = Number(formatUsd(costNano(row.model, {
      inputTokens: row.inputTokens + row.cacheReadTokens + row.cacheWriteTokens,
      outputTokens: row.outputTokens,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
    })));
  }
  return out;
}

async function run(job: Job): Promise<Result> {
  let last: Result | null = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      last = await once(job);
      if (last.status === 200 && !last.error) return last;
    } catch (e) {
      last = {
        id: job.id,
        group: job.group,
        status: 0,
        reply: "",
        citations: [],
        usage: null,
        costUsd: null,
        coldUsd: null,
        seconds: 0,
        error: String(e).slice(0, 200),
      };
    }
    await new Promise((r) => setTimeout(r, 1500 * (attempt + 1)));
  }
  return last!;
}

const results: Result[] = new Array(jobs.length);
let next = 0;
let done = 0;
async function worker() {
  while (next < jobs.length) {
    const n = next++;
    results[n] = await run(jobs[n]);
    done++;
    // A run that fails from the start (a wrong key, a model name the account lacks) should stop, not retry hundreds of requests.
    if (done === 6 && results.filter(Boolean).every((r) => r.status !== 200 || r.error)) {
      console.error("The first six requests all failed; stopping. First error:", results.find(Boolean)?.error);
      Deno.exit(1);
    }
    if (done % 20 === 0 || done === jobs.length) console.log(`  ${done} of ${jobs.length}`);
    if (outPath && done % 20 === 0) await Deno.writeTextFile(outPath, JSON.stringify(results.filter(Boolean), null, 1));
  }
}
await Promise.all(Array.from({ length: Math.min(concurrency, jobs.length) }, worker));

const mean = (xs: number[]) => xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0;
const median = (xs: number[]) => {
  const s = [...xs].sort((a, b) => a - b);
  return s.length ? s[Math.floor(s.length / 2)] : 0;
};
const groups = [...new Set(results.map((r) => r.group))];
console.log("\ngroup      n  failed  input tok (cached)  output tok  logged ¢  no-cache ¢  median s");
for (const g of groups) {
  const rs = results.filter((r) => r.group === g);
  const ok = rs.filter((r) => r.usage && r.costUsd !== null);
  const total = ok.map((r) => r.usage!.input + r.usage!.cached);
  const cached = ok.map((r) => r.usage!.cached);
  console.log(
    `${g.padEnd(9)} ${String(rs.length).padStart(3)}  ${String(rs.length - ok.length).padStart(5)}  ` +
      `${mean(total).toFixed(0).padStart(9)} (${mean(cached).toFixed(0).padStart(6)})  ` +
      `${mean(ok.map((r) => r.usage!.output)).toFixed(0).padStart(9)}  ` +
      `${(mean(ok.map((r) => r.costUsd!)) * 100).toFixed(3).padStart(8)}  ` +
      `${(mean(ok.map((r) => r.coldUsd!)) * 100).toFixed(3).padStart(9)}  ` +
      `${median(rs.map((r) => r.seconds)).toFixed(1).padStart(8)}`,
  );
}
const spent = results.reduce((a, r) => a + (r.costUsd ?? 0), 0);
console.log(`\nspent about $${spent.toFixed(3)} on ${results.length} requests`);
if (outPath) await Deno.writeTextFile(outPath, JSON.stringify(results, null, 1));
Deno.exit(0);
