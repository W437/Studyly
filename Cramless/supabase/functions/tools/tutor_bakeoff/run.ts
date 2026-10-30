// Ask Cap's tutor on OpenAI models, with the relay's own system prompt and the app's own kind of request.
//
//   deno run --no-check --allow-net=api.openai.com --allow-env=HOME,OPENAI_API_KEY \
//     --allow-read --allow-write tools/tutor_bakeoff/run.ts [--configs sol-medium,luna-low] [--cases x-anaphase,...] \
//     [--out DIR] [--concurrency 6] [--budget 4]
//
// What is the same as production: `tutorSystem()` (the rules, the tutor, hints or explain, the under-18 part), the
// student's passages in the last user turn, the earlier turns as text, "Explain my mistake" context, four passages a
// question. What has to differ: Claude cites through search_result blocks; OpenAI has nothing like it that keeps the
// notes on our side, so the model is asked for {answer, citations: [{source_id, quote}]} in a strict JSON schema and the
// app's own rule decides which quotes count (see report.ts). Nothing is stored at OpenAI (`store: false`).
//
// The key is read from ~/.config/capling/openai_key, or OPENAI_API_KEY; it is never printed or written anywhere.
// It spends a few dollars at most; `--budget` stops the run when the total passes it.

import type { TutorRequest } from "../../_shared/contract.ts";
import { type Case, CASES } from "./cases.ts";
import { type Config, CONFIGS, costUsd, type Usage } from "./config.ts";
import { inputFor, instructionsFor, requestFor, retrieve, SCHEMA } from "./request.ts";

const args = new Map<string, string>();
for (let i = 0; i < Deno.args.length; i += 2) args.set(Deno.args[i].replace(/^--/, ""), Deno.args[i + 1] ?? "");
const only = (name: string) => args.get(name)?.split(",").filter(Boolean);
const concurrency = Number(args.get("concurrency") ?? 6);
const budget = Number(args.get("budget") ?? 4);

function readKey(): string {
  const file = `${Deno.env.get("HOME")}/.config/capling/openai_key`;
  try {
    const key = Deno.readTextFileSync(file).trim();
    if (key) return key;
  } catch { /* no file: try the environment */ }
  const key = (Deno.env.get("OPENAI_API_KEY") ?? "").trim();
  if (!key) {
    console.error(`No OpenAI key: put it in ${file} (never in the repo). Nothing was sent.`);
    Deno.exit(2);
  }
  return key;
}
const key = readKey();

export interface Rec {
  config: string;
  model: string;
  effort: string;
  caseId: string;
  group: string;
  sources: { id: string; label: string; text: string }[];
  raw: string;
  ok: boolean;
  error?: string;
  status?: string;
  refusal?: string;
  ms: { ttfb: number; firstText: number | null; firstAnswer: number | null; total: number };
  usage: Usage;
  cost: number;
  retries: number;
}

class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

/** How much of the "answer" string has arrived in a half-arrived JSON text: the first words the student would see. */
function answerChars(partial: string): number {
  const m = /"answer"\s*:\s*"/.exec(partial);
  return m ? Math.max(0, partial.length - (m.index + m[0].length)) : 0;
}

type Outcome = Pick<Rec, "raw" | "ok" | "error" | "status" | "refusal" | "ms" | "usage">;

async function once(cfg: Config, req: TutorRequest): Promise<Outcome> {
  const body = {
    model: cfg.model,
    instructions: instructionsFor(req),
    input: inputFor(req),
    reasoning: { effort: cfg.effort },
    text: { format: { type: "json_schema", name: "cap_reply", strict: true, schema: SCHEMA } },
    max_output_tokens: 8000,
    stream: true,
    store: false,
  };
  const t0 = performance.now();
  const res = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { "Authorization": `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(120_000),
  });
  if (!res.ok) throw new ApiError(res.status, (await res.text()).slice(0, 500));
  const ttfb = performance.now() - t0;
  let raw = "";
  let firstText: number | null = null;
  let firstAnswer: number | null = null;
  let usage: Usage = { input: 0, cached: 0, output: 0, reasoning: 0 };
  let status: string | undefined;
  let refusal = "";
  let error: string | undefined;
  const handle = (block: string) => {
    for (const line of block.split("\n")) {
      if (!line.startsWith("data:")) continue;
      const data = line.slice(5).trim();
      if (!data || data === "[DONE]") continue;
      // deno-lint-ignore no-explicit-any
      const e: any = JSON.parse(data);
      if (e.type === "response.output_text.delta") {
        raw += e.delta ?? "";
        const now = performance.now() - t0;
        if (firstText === null) firstText = now;
        if (firstAnswer === null && answerChars(raw) >= 1) firstAnswer = now;
      } else if (e.type === "response.refusal.delta") {
        refusal += e.delta ?? "";
      } else if (e.type === "response.completed" || e.type === "response.incomplete") {
        const r = e.response ?? {};
        status = r.status ?? (e.type === "response.incomplete" ? "incomplete" : "completed");
        if (r.incomplete_details?.reason) status += `:${r.incomplete_details.reason}`;
        const u = r.usage ?? {};
        usage = {
          input: u.input_tokens ?? 0,
          cached: u.input_tokens_details?.cached_tokens ?? 0,
          output: u.output_tokens ?? 0,
          reasoning: u.output_tokens_details?.reasoning_tokens ?? 0,
        };
      } else if (e.type === "response.failed") {
        error = e.response?.error?.message ?? "response.failed";
      } else if (e.type === "error") {
        error = e.message ?? "error";
      }
    }
  };
  const reader = res.body!.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    let at: number;
    while ((at = buffer.indexOf("\n\n")) >= 0) {
      handle(buffer.slice(0, at));
      buffer = buffer.slice(at + 2);
    }
  }
  if (buffer.trim()) handle(buffer);
  const total = performance.now() - t0;
  const ok = !error && !refusal && status === "completed" && raw.length > 0;
  return {
    raw,
    ok,
    error: error ?? (ok ? undefined : `status ${status ?? "none"}${refusal ? ", refusal" : ""}`),
    status,
    refusal: refusal || undefined,
    ms: { ttfb, firstText, firstAnswer, total },
    usage,
  };
}

async function run(cfg: Config, c: Case): Promise<Rec> {
  const req = requestFor(c, retrieve(c));
  const sources = req.sources.map((s) => ({ id: s.id, label: s.label, text: s.text }));
  const head = { config: cfg.id, model: cfg.model, effort: cfg.effort, caseId: c.id, group: c.group, sources };
  let retries = 0;
  for (;;) {
    try {
      const r = await once(cfg, req);
      return { ...head, retries, ...r, cost: costUsd(cfg.model, r.usage) };
    } catch (e) {
      const status = e instanceof ApiError ? e.status : 0;
      if ((status === 0 || status === 429 || status >= 500) && retries < 2) {
        retries++;
        await new Promise((resolve) => setTimeout(resolve, 1500 * retries));
        continue;
      }
      return {
        ...head,
        retries,
        raw: "",
        ok: false,
        error: e instanceof Error ? e.message : String(e),
        ms: { ttfb: 0, firstText: null, firstAnswer: null, total: 0 },
        usage: { input: 0, cached: 0, output: 0, reasoning: 0 },
        cost: 0,
      };
    }
  }
}

async function pool<T>(items: T[], n: number, fn: (item: T) => Promise<void>): Promise<void> {
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => {
    while (next < items.length) await fn(items[next++]);
  }));
}

const stamp = new Date().toISOString().slice(0, 16).replace(/[-:T]/g, "");
const out = args.get("out") ?? new URL(`../../../../build/bakeoff/${stamp}/`, import.meta.url).pathname;
Deno.mkdirSync(out, { recursive: true });

const wantConfigs = only("configs");
const wantCases = only("cases");
const configs = CONFIGS.filter((c) => !wantConfigs || wantConfigs.includes(c.id));
const cases = CASES.filter((c) => !wantCases || wantCases.includes(c.id));
console.log(`${configs.length} config(s) x ${cases.length} case(s) -> ${out}`);

let spent = 0;
let stopped = false;
for (const cfg of configs) {
  const recs: Rec[] = [];
  const started = performance.now();
  await pool(cases, concurrency, async (c) => {
    if (stopped) return;
    const rec = await run(cfg, c);
    recs.push(rec);
    spent += rec.cost;
    if (spent > budget) stopped = true;
  });
  recs.sort((a, b) => CASES.findIndex((c) => c.id === a.caseId) - CASES.findIndex((c) => c.id === b.caseId));
  Deno.writeTextFileSync(`${out}/${cfg.id}.jsonl`, recs.map((r) => JSON.stringify(r)).join("\n") + "\n");
  const failed = recs.filter((r) => !r.ok);
  const cost = recs.reduce((n, r) => n + r.cost, 0);
  console.log(
    `${cfg.id.padEnd(13)} ${recs.length - failed.length}/${recs.length} ok  $${cost.toFixed(4)}  ` +
      `${((performance.now() - started) / 1000).toFixed(0)}s` +
      (failed.length ? `  FAILED: ${failed.slice(0, 2).map((r) => `${r.caseId}: ${r.error}`).join(" | ")}` : ""),
  );
  if (stopped) {
    console.log(`Stopped: spent $${spent.toFixed(2)}, over the $${budget} budget.`);
    break;
  }
}
console.log(`Total $${spent.toFixed(4)}. Results in ${out}`);
