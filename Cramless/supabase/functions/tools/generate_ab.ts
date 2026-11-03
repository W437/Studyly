// A before/after test of the question writer's prompt on the relay's real code path:
//
//   OPENAI_API_KEY=… deno run -A tools/generate_ab.ts [--runs 2] [--rules rules.txt] [--out ab.json] text1.txt text2.txt …
//
// Each text file is one source (a paragraph per line). For each file and each of `--runs` runs it asks the `generate` route for 16 questions with the
// prompt as it is (A) and once more with each rule set in `--rules` (a file, or several separated by commas) added to the end of it (B, C, ...; with no
// `--rules` the two rules below, which `generate.md` has had since v13: they are only there to measure an older prompt). It prints, per arm: how many questions,
// how many are multiple choice, in how many of those the right option is the strictly longest (about 25% by chance with four options, 40 to 51% in the user
// tests) and the mean length of the right option against the wrong ones, how many fill-ins have a blank that appears again in the same sentence or is a
// stop word, and the cost. Nothing is stored, and the key is read from the environment only. `DRY=1` runs it on canned replies, without a key, to check the plumbing.
//
// It measures one thing a prompt can change and a script can count. Whether a question is worth asking needs a reader.

import { OpenAIProvider } from "../_shared/openai.ts";
import type { JsonCall, JsonResult } from "../_shared/provider.ts";
import { fixtureJson, logLines, rig, ScriptedProvider } from "../tests/_harness.ts";

const DEFAULT_RULES = `
Multiple choice: make every wrong choice as long and as specific as the right one, a real misconception or a neighbouring fact from the same pages, and vary which choice is the longest; the right choice must not stand out by its length or its detail.
Fill-in: blank a term, name, number or phrase that a student has to know and cannot get from the rest of the sentence; never a word the sentence repeats or gives away.`;

const args = Deno.args;
function option(name: string, fallback: string): string {
  const i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : fallback;
}
const files = args.filter((a, i) => !a.startsWith("--") && !(i > 0 && args[i - 1].startsWith("--")));
const runs = Number(option("--runs", "2"));
const ruleFiles = args.includes("--rules") ? option("--rules", "").split(",").filter((f) => f) : [];
const ruleSets: { name: string; text: string }[] = [];
for (const [i, f] of ruleFiles.entries()) {
  ruleSets.push({ name: `${String.fromCharCode(66 + i)} (${f.split("/").pop()})`, text: await Deno.readTextFile(f) });
}
if (ruleSets.length === 0) ruleSets.push({ name: "B (the rules added)", text: DEFAULT_RULES });
const outPath = option("--out", "");
const dry = Deno.env.get("DRY") === "1";
const key = Deno.env.get("OPENAI_API_KEY") ?? "";
if (!dry && !key) {
  console.error("Set OPENAI_API_KEY in the environment (never commit it), or DRY=1 for a dry run. Nothing was sent.");
  Deno.exit(2);
}
if (!dry && files.length === 0) {
  console.error("Name at least one text file (a paragraph per line).");
  Deno.exit(2);
}

/** The provider with the rules added to the system prompt of the `generate` route only (its task line is "Task: turn pages of a student's class material"; the shared rules come first). */
class WithRules extends OpenAIProvider {
  constructor(private extra: string, apiKey: string) {
    super({ apiKey, timeoutMs: 180_000 });
  }
  override json<T>(call: JsonCall): Promise<JsonResult<T>> {
    return super.json<T>(
      this.extra && call.system.includes("Task: turn pages of a student's class material")
        ? { ...call, system: call.system + "\n" + this.extra }
        : call,
    );
  }
}

// deno-lint-ignore no-explicit-any
type Item = any;

function pagesOf(text: string) {
  const lines = text.split("\n").map((l) => l.trim()).filter((l) => l.length > 0);
  const pages = [];
  for (let p = 0; p * 14 < lines.length; p++) {
    pages.push({
      page: p,
      label: String(p + 1),
      lines: lines.slice(p * 14, p * 14 + 14).map((t, n) => ({ id: `p${p}.l${n}`, text: t })),
    });
  }
  return pages.slice(0, 40);
}

function bodyFor(text: string, title: string) {
  return {
    course: "Course",
    sourceTitle: title,
    level: "college",
    language: "en",
    formats: ["recall", "apply", "mcq", "cloze", "flashcard"],
    maxItems: 16,
    pages: pagesOf(text),
  };
}

interface Tally {
  questions: number;
  mcq: number;
  longest: number;
  ratioSum: number;
  cloze: number;
  clozeWeak: number;
  cost: number;
}
const blank = (): Tally => ({ questions: 0, mcq: 0, longest: 0, ratioSum: 0, cloze: 0, clozeWeak: 0, cost: 0 });
const fold = (s: string) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "");

function count(t: Tally, items: Item[]) {
  for (const it of items) {
    t.questions++;
    if (it.kind === "mcq" && Array.isArray(it.choices) && it.choices.length >= 3) {
      const right = it.choices.filter((c: Item) => c.correct);
      if (right.length !== 1) continue;
      const wrong = it.choices.filter((c: Item) => !c.correct).map((c: Item) => String(c.text).length);
      const mean = wrong.reduce((a: number, b: number) => a + b, 0) / wrong.length;
      t.mcq++;
      t.longest += right[0].text.length > Math.max(...wrong) ? 1 : 0;
      t.ratioSum += right[0].text.length / Math.max(1, mean);
    }
    if (it.kind === "cloze" && it.cloze?.text) {
      t.cloze++;
      const m = /\{\{(.+?)\}\}/.exec(it.cloze.text);
      if (m) {
        const answer = fold(m[1]);
        const rest = fold(it.cloze.text.replace(/\{\{.+?\}\}/, " "));
        const words = answer.split(/\W+/).filter((w) => w.length > 2);
        if (words.length > 0 && words.every((w) => rest.includes(w))) t.clozeWeak++;
        if (answer.length <= 3 || /^(the|and|that|this|with|from|are|was|for|its|his|her)$/.test(answer)) t.clozeWeak++;
      }
    }
  }
}

async function runArm(extra: string, texts: { title: string; text: string }[]): Promise<Tally> {
  const t = blank();
  const scripted = dry ? new ScriptedProvider() : null;
  const r = rig({
    env: { DAILY_COST_CAP_USD: "0", PAID_DAILY_COST_CAP_USD: "0", PAID_WEEKLY_COST_CAP_USD: "0" },
    provider: scripted ?? new WithRules(extra, key),
  });
  r.store.addUser("user-1", "AB", "UTC");
  r.store.entitlements.push({
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
    for (
      const { title, text } of dry
        ? [{
          title: "Dry",
          text: "A line.\n" + fixtureJson("requests/generate").pages[0].lines.map((l: Item) => l.text).join("\n"),
        }]
        : texts
    ) {
      scripted?.replyJson(fixtureJson("generate"));
      const res = await r.ai("generate", { body: dry ? fixtureJson("requests/generate") : bodyFor(text, title) });
      if (res.status !== 200) {
        console.log(`  generate answered HTTP ${res.status} for ${title}`);
        continue;
      }
      count(t, (await res.json()).items ?? []);
    }
  }
  await r.settle();
  for (const line of logLines.splice(0)) {
    const m = /"cost_usd":"?([0-9.]+)/.exec(line);
    if (m) t.cost += Number(m[1]);
  }
  return t;
}

const texts = [];
for (const f of files) {
  texts.push({ title: f.split("/").pop()!.replace(/\.[^.]+$/, ""), text: await Deno.readTextFile(f) });
}

const report: Record<string, Tally> = {};
const arms: [string, string][] = [
  ["A (the prompt as it is)", ""],
  ...ruleSets.map((r) => [r.name, r.text] as [string, string]),
];
for (const [name, extra] of arms) {
  console.log(`\n== ${name}`);
  const t = await runArm(extra, texts);
  report[name] = t;
  const pct = (a: number, b: number) => (b ? `${Math.round((100 * a) / b)}%` : "–");
  console.log(
    `  ${t.questions} questions, ${t.mcq} multiple choice: the right option is the longest in ${t.longest} (${
      pct(t.longest, t.mcq)
    }), its length against the wrong ones x${(t.ratioSum / Math.max(1, t.mcq)).toFixed(2)}`,
  );
  console.log(
    `  ${t.cloze} fill-ins, ${t.clozeWeak} with a blank the sentence repeats or a stop word (${
      pct(t.clozeWeak, t.cloze)
    })`,
  );
  console.log(`  cost about $${t.cost.toFixed(4)}`);
}
if (outPath) await Deno.writeTextFile(outPath, JSON.stringify({ rules: ruleSets, runs, files, report }, null, 1));
Deno.exit(0);
