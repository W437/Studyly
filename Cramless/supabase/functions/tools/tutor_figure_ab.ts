// A before/after test of a tutor prompt rule for questions about a picture, on the relay's real code path:
//
//   OPENAI_API_KEY=… deno run -A tools/tutor_figure_ab.ts --material material.json --questions questions.json [--runs 2] [--rule rule.txt] [--out ab.json]
//
// `material.json` is the student's sources as the app sends them: [{ "id": "s1", "title": "…", "label": "…", "text": "…" }, …]; the passages of a photographed diagram hold
// only the words printed on it. `questions.json` is [{ "q": "…", "kind": "figure" }, { "q": "…", "kind": "control", "expect": "regex the reply must match" }, …].
// For each question and run it asks the `tutor` route twice: with the prompt as it is (A) and with the rule in `--rule` added to the end of the system prompt (B, default:
// the rule below). It prints every reply and, per arm: how many figure replies say plainly that the picture cannot be seen (a proxy: it does not tell a good answer
// from a bad one, so read the replies), and how many control replies still carry the fact they must (a rule must not make Cap hedge about what the notes say).
// Nothing is stored, and the key is read from the environment only. `DRY=1` runs it on canned replies, without a key, to check the plumbing.

import { TERRA } from "../_shared/cost.ts";
import { OpenAIProvider } from "../_shared/openai.ts";
import type { TutorCall, TutorStreamEvent } from "../_shared/provider.ts";
import { parseSse } from "../_shared/sse.ts";
import { fixtureJson, logLines, rig, ScriptedProvider } from "../tests/_harness.ts";

const DEFAULT_RULE =
  `- A source made from a photo of a picture, figure or diagram holds only the words printed on it, one per line, in no useful order: you cannot see where they sit. When the question asks which part, arrow or label is where in the picture, answer from the labels only as far as their meaning goes. If one label is clearly the name of what the question describes (an "upward arrow from the roots" is "Plant Uptake"), give it and say you cannot see the picture to check it. If several labels could fit, name them, say you cannot see which one sits where, and ask the student what the picture shows next to the part they mean. Never name a part from what you know if it is not among the words you were given.`;

const args = Deno.args;
function option(name: string, fallback: string): string {
  const i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
}
const dry = Deno.env.get("DRY") === "1";
const key = Deno.env.get("OPENAI_API_KEY") ?? "";
const runs = Number(option("--runs", "2"));
const rule = args.includes("--rule") ? await Deno.readTextFile(option("--rule", "")) : DEFAULT_RULE;
const outPath = option("--out", "");
if (!dry && !key) {
  console.error("Set OPENAI_API_KEY in the environment (never commit it), or DRY=1 for a dry run. Nothing was sent.");
  Deno.exit(2);
}
if (!dry && (!args.includes("--material") || !args.includes("--questions"))) {
  console.error("Give --material and --questions (see the top of this file).");
  Deno.exit(2);
}

interface Question {
  q: string;
  kind: "figure" | "control";
  expect?: string;
}
// deno-lint-ignore no-explicit-any
const material: any[] = dry
  ? fixtureJson("requests/tutor").sources
  : JSON.parse(await Deno.readTextFile(option("--material", "")));
const questions: Question[] = dry
  ? [{ q: "What is the upward arrow called in the picture?", kind: "figure" }, {
    q: "What is mitosis?",
    kind: "control",
    expect: "mitosis",
  }]
  : JSON.parse(await Deno.readTextFile(option("--questions", "")));

/** The provider with the rule added to the tutor's system prompt. */
class WithRule extends OpenAIProvider {
  constructor(private extra: string, apiKey: string) {
    super({ apiKey, timeoutMs: 120_000 });
  }
  override async *tutor(call: TutorCall): AsyncGenerator<TutorStreamEvent> {
    yield* super.tutor(this.extra ? { ...call, system: call.system + "\n\n" + this.extra } : call);
  }
}

const SAYS_NO_PICTURE =
  /(can(?:'|’)?t|cannot|can not|unable to|not able to|don(?:'|’)?t|do not)\s+(?:actually\s+)?(?:see|view|look at)\b[^.?!]{0,40}\b(?:picture|image|diagram|figure|photo|drawing)|(?:picture|image|diagram|figure|photo)[^.?!]{0,40}\b(?:can(?:'|’)?t|cannot)\s+(?:be\s+)?seen/i;

async function ask(t: ReturnType<typeof rig>, q: string): Promise<string> {
  const res = await t.ai("tutor", {
    body: { mode: "explain", minor: false, course: "Course", messages: [{ role: "user", text: q }], sources: material },
  });
  if (res.status !== 200 || !res.body) return `(HTTP ${res.status})`;
  let text = "";
  for await (const m of parseSse(res.body)) {
    const data = m.data ? JSON.parse(m.data) : {};
    if (m.event === "delta") text += data.text ?? "";
  }
  return text.trim();
}

interface Arm {
  figure: number;
  figureSaysNoPicture: number;
  control: number;
  controlKept: number;
  cost: number;
  replies: { q: string; kind: string; reply: string }[];
}

async function runArm(extra: string): Promise<Arm> {
  const arm: Arm = { figure: 0, figureSaysNoPicture: 0, control: 0, controlKept: 0, cost: 0, replies: [] };
  const scripted = dry ? new ScriptedProvider() : null;
  const t = rig({
    env: { DAILY_COST_CAP_USD: "0", PAID_DAILY_COST_CAP_USD: "0", PAID_WEEKLY_COST_CAP_USD: "0" },
    provider: scripted ?? new WithRule(extra, key),
    tutorModel: Deno.env.get("OPENAI_TUTOR_MODEL") || TERRA,
    tutorEffort: "low",
  });
  t.store.addUser("user-1", "AB", "UTC");
  // A Pro account: the free plan's 10 tutor answers a day would end a run of 14 questions in a 429.
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
  for (let run = 0; run < runs; run++) {
    for (const q of questions) {
      if (scripted) {
        scripted.replyTutor([
          { type: "start", model: TERRA },
          {
            type: "delta",
            text: q.kind === "figure"
              ? "I can read the labels but I can't see the picture."
              : "Mitosis is how a cell divides.",
          },
          {
            type: "done",
            model: TERRA,
            usage: { inputTokens: 1000, outputTokens: 50, cacheReadTokens: 0, cacheWriteTokens: 0 },
            stop: "end",
          },
        ]);
      }
      const reply = await ask(t, q.q);
      arm.replies.push({ q: q.q, kind: q.kind, reply });
      if (q.kind === "figure") {
        arm.figure++;
        arm.figureSaysNoPicture += SAYS_NO_PICTURE.test(reply) ? 1 : 0;
      } else {
        arm.control++;
        arm.controlKept += new RegExp(q.expect ?? ".", "i").test(reply) ? 1 : 0;
      }
    }
  }
  await t.settle();
  for (const line of logLines.splice(0)) {
    const m = /"cost_usd":"?([0-9.]+)/.exec(line);
    if (m) arm.cost += Number(m[1]);
  }
  return arm;
}

const report: Record<string, Arm> = {};
for (const [name, extra] of [["A (the prompt as it is)", ""], ["B (the rule added)", rule]] as const) {
  console.log(`\n== ${name}`);
  const arm = await runArm(extra);
  report[name] = arm;
  for (const r of arm.replies) {
    console.log(`  [${r.kind}] ${r.q}\n      → ${r.reply.replace(/\s+/g, " ").slice(0, 420)}`);
  }
  console.log(`  figure questions: ${arm.figureSaysNoPicture} of ${arm.figure} replies say the picture cannot be seen`);
  console.log(`  control questions: ${arm.controlKept} of ${arm.control} replies still carry the fact`);
  console.log(`  cost about $${arm.cost.toFixed(4)}`);
}
if (outPath) await Deno.writeTextFile(outPath, JSON.stringify({ rule, runs, report }, null, 1));
Deno.exit(0);
