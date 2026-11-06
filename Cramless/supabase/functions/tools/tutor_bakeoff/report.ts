// Scores a run of run.ts and prints the tables: `deno run --no-check --allow-read --allow-write tools/tutor_bakeoff/report.ts DIR`.
//
// The checks are the ones the app itself enforces or the prompt demands, so a pass means something to a student:
//   json       the reply parsed as {answer, citations}
//   cite       a factual reply has at least one quote that is really in the passages (the app's rule: a quote is kept
//              only if it appears, case- and accent-insensitively, in a passage it was sent; otherwise it is dropped)
//   quotes     every quote it gave is kept (a dropped quote is a citation chip that silently vanishes)
//   question   the reply ends by asking the student something (the prompt's hints and explain modes both ask for it)
//   leak       in hints mode, the answer was not handed over (a rule of thumb per case, read by eye afterwards)
//   notCovered when the notes cannot answer, it says so, and uses no outside knowledge (a rule of thumb, read by eye)
//   forbid / must / decline   per-case: no outside knowledge, no followed injection, no essay; the thing it had to say
//   short      at most six sentences ("two to five", plus the check question)
//   format     no headings, bullet lists, bold or emoji
//   noIds      no source id ("s1") written into the reply, where the student would read it
//   parts      "explain my mistake": three parts separated by a blank line, the last a question (the app pages through them)
// It also writes answers-<config>.md next to the results, every reply with its quotes marked, to be read.

import { type Case, CASES } from "./cases.ts";
import { CONFIGS } from "./config.ts";
import type { Rec } from "./run.ts";

const dir = (Deno.args[0] ?? "").replace(/\/$/, "");
if (!dir) {
  console.error("Usage: report.ts DIR");
  Deno.exit(2);
}

const fold = (s: string) => s.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase();
const loose = (s: string) =>
  fold(s).replace(/[‘’‛′`]/g, "'").replace(/[“”„″]/g, '"').replace(/[–—−]/g, "-").replace(/…/g, "...").replace(
    /\s+/g,
    " ",
  )
    .replace(/[\s.,;:!?"')\]]+$/g, "").trim();
const located = (quote: string, text: string) => {
  const q = fold(quote.trim());
  return q.length >= 4 && fold(text).includes(q);
};

const NOT_COVERED =
  /(doesn['’]?t|does not|don['’]?t|do not|isn['’]?t|is not|aren['’]?t|are not|never|nothing|no (mention|information|details?|number|explanation))[^.?!]{0,60}(cover|say|says|mention|include|explain|state|give|list|describe|tell|contain|specif|address|discuss|in your|in the (notes|material|sources|pages?)|there)/i;
// The tutor's current wording for "the notes can't answer this": it says it couldn't find it, not that the notes are silent.
const NOT_FOUND = /(couldn['’]?t|could not|can['’]?t|cannot)\s+find/i;
const DECLINES = /(can['’]?t|cannot|won['’]?t|not able|unable|only help|instead|rather|let['’]?s|happy to)/i;

interface Scored {
  rec: Rec;
  c: Case;
  answer: string;
  quotes: { id: string; quote: string; valid: boolean; named: boolean; near: boolean }[];
  checks: Record<string, boolean>;
}

function sentences(text: string): string[] {
  return text.split(/(?<=[.!?])\s+/).map((s) => s.trim()).filter(Boolean);
}

function score(rec: Rec, c: Case): Scored {
  const checks: Record<string, boolean> = {};
  let answer = "";
  let quotes: Scored["quotes"] = [];
  try {
    const parsed = JSON.parse(rec.raw);
    if (typeof parsed.answer === "string" && Array.isArray(parsed.citations)) {
      answer = parsed.answer;
      quotes = parsed.citations.map((q: { source_id: string; quote: string }) => {
        const named = rec.sources.find((s) => s.id === q.source_id);
        const valid = rec.sources.some((s) => located(q.quote, s.text));
        return {
          id: q.source_id,
          quote: q.quote,
          valid,
          named: !!named && located(q.quote, named.text),
          near: !valid && rec.sources.some((s) => loose(s.text).includes(loose(q.quote))),
        };
      });
      checks.json = true;
    }
  } catch { /* stays unparsed */ }
  checks.json ||= false;
  if (!checks.json || !rec.ok) {
    return { rec, c, answer, quotes, checks: { ...checks, json: checks.json && rec.ok } };
  }
  const list = sentences(answer);
  const words = answer.split(/\s+/).filter(Boolean).length;
  if (c.cites) checks.cite = quotes.some((q) => q.valid);
  if (quotes.length > 0) checks.quotes = quotes.every((q) => q.valid);
  if (c.question) checks.question = /\?["')\]”’]*$/.test(answer.trim());
  if (c.threeParts) {
    const parts = answer.trim().split(/\n\s*\n/);
    checks.parts = parts.length === 3 && /\?["')\]”’]*$/.test(parts[2].trim());
  }
  if (c.leak) checks.leak = !c.leak(answer);
  if (c.notCovered) {
    checks.notCovered = (NOT_FOUND.test(answer) || NOT_COVERED.test(answer)) && !(c.forbid?.test(answer) ?? false);
  } else if (c.forbid) checks.forbid = !c.forbid.test(answer);
  if (c.must) checks.must = c.must.test(answer);
  if (c.decline) {
    checks.decline = (c.must !== undefined || DECLINES.test(answer)) && words <= (c.maxWords ?? 90) &&
      !(c.forbid?.test(answer) ?? false);
  } else if (c.maxWords) checks.length = words <= c.maxWords;
  checks.short = list.length <= 6;
  checks.noIds = !/\bs[1-9]\b/.test(answer);
  checks.format = !/^\s*([-*•]|\d+[.)])\s/m.test(answer) && !/^#{1,6}\s/m.test(answer) &&
    !/\*\*[^*]+\*\*/.test(answer) &&
    !/\p{Extended_Pictographic}/u.test(answer);
  return { rec, c, answer, quotes, checks };
}

const median = (xs: number[]) => {
  if (xs.length === 0) return NaN;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.floor((s.length - 1) / 2)];
};
const pct = (xs: number[], p: number) => {
  if (xs.length === 0) return NaN;
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.min(s.length - 1, Math.ceil(p * s.length) - 1)];
};
const mean = (xs: number[]) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : NaN);
const cents = (usd: number) => (usd * 100).toFixed(2) + "¢";
const sec = (ms: number) => (ms / 1000).toFixed(1) + "s";

const byConfig = new Map<string, Scored[]>();
for (const cfg of CONFIGS) {
  let text: string;
  try {
    text = Deno.readTextFileSync(`${dir}/${cfg.id}.jsonl`);
  } catch {
    continue;
  }
  const scored = text.trim().split("\n").map((l) => JSON.parse(l) as Rec).map((rec) =>
    score(rec, CASES.find((c) => c.id === rec.caseId)!)
  );
  byConfig.set(cfg.id, scored);
}

const passed = (s: Scored) => Object.values(s.checks).every(Boolean);
const rate = (xs: boolean[]) => (xs.length ? `${xs.filter(Boolean).length}/${xs.length}` : "–");
const CHECKS = [
  "cite",
  "quotes",
  "question",
  "leak",
  "notCovered",
  "forbid",
  "must",
  "decline",
  "short",
  "format",
  "noIds",
  "parts",
];

console.log("\n## Quality (checks passed / checks that apply)\n");
console.log("| setup | ok | all checks | " + CHECKS.join(" | ") + " |");
console.log("|---|---|---|" + CHECKS.map(() => "---").join("|") + "|");
for (const [id, scored] of byConfig) {
  const cells = CHECKS.map((k) => rate(scored.filter((s) => k in s.checks).map((s) => s.checks[k])));
  console.log(
    `| ${id} | ${scored.filter((s) => s.rec.ok).length}/${scored.length} | ${rate(scored.map(passed))} | ${
      cells.join(" | ")
    } |`,
  );
}

console.log("\n## Quotes (what the app would keep)\n");
console.log(
  "| setup | quotes given | kept | dropped | dropped but only spacing/punctuation | named the right source |",
);
console.log("|---|---|---|---|---|---|");
for (const [id, scored] of byConfig) {
  const q = scored.flatMap((s) => s.quotes);
  console.log(
    `| ${id} | ${q.length} | ${q.filter((x) => x.valid).length} | ${q.filter((x) => !x.valid).length} | ${
      q.filter((x) => x.near).length
    } | ${q.filter((x) => x.named).length} |`,
  );
}

console.log("\n## Speed and cost per answer\n");
console.log(
  "| setup | first words (median) | first words (p90) | done (median) | input tokens | output tokens | of which thinking | mean cost | p90 cost |",
);
console.log("|---|---|---|---|---|---|---|---|---|");
for (const [id, scored] of byConfig) {
  const ok = scored.filter((s) => s.rec.ok);
  const first = ok.map((s) => s.rec.ms.firstAnswer ?? s.rec.ms.total);
  console.log(
    `| ${id} | ${sec(median(first))} | ${sec(pct(first, 0.9))} | ${sec(median(ok.map((s) => s.rec.ms.total)))} | ${
      Math.round(mean(ok.map((s) => s.rec.usage.input)))
    } | ${Math.round(mean(ok.map((s) => s.rec.usage.output)))} | ${
      Math.round(mean(ok.map((s) => s.rec.usage.reasoning)))
    } | ${cents(mean(ok.map((s) => s.rec.cost)))} | ${cents(pct(ok.map((s) => s.rec.cost), 0.9))} |`,
  );
}

console.log("\n## Cases that failed a check (by setup)\n");
for (const [id, scored] of byConfig) {
  const bad = scored.filter((s) => !passed(s)).map((s) => {
    const failed = Object.entries(s.checks).filter(([, v]) => !v).map(([k]) => k);
    return `${s.c.id} (${failed.join(",") || "api"})`;
  });
  console.log(`- **${id}**: ${bad.length ? bad.join("; ") : "none"}`);
}

// Per-group pass rate and cost, over the setups: where each one is weak.
console.log("\n## All checks passed, by kind of question\n");
const groups = [...new Set(CASES.map((c) => c.group))];
console.log("| setup | " + groups.join(" | ") + " |");
console.log("|---|" + groups.map(() => "---").join("|") + "|");
for (const [id, scored] of byConfig) {
  console.log(
    `| ${id} | ` + groups.map((g) => rate(scored.filter((s) => s.c.group === g).map(passed))).join(" | ") + " |",
  );
}

// A problem from a photo shows a cloud answer only with a quote that is really in the notes; otherwise the app says its own "not covered"
// line. So what counts is what the student would see, and whether that gave the answer away.
console.log("\n## Problems from a photo: what the student would see\n");
console.log(
  "| setup | covered, shown with a kept quote | covered, swapped for the not-covered line | answer handed over | not covered, said so |",
);
console.log("|---|---|---|---|---|");
for (const [id, scored] of byConfig) {
  const problems = scored.filter((s) => s.c.group === "problem");
  if (problems.length === 0) continue;
  const covered = problems.filter((s) => s.c.cites);
  const shown = covered.filter((s) => s.quotes.some((q) => q.valid));
  const leaked = problems.filter((s) => "leak" in s.checks && !s.checks.leak);
  const uncovered = problems.filter((s) => s.c.notCovered);
  console.log(
    `| ${id} | ${shown.length}/${covered.length} | ${
      covered.length - shown.length
    }/${covered.length} | ${leaked.length}/${problems.filter((s) => "leak" in s.checks).length}${
      leaked.length ? ` (${leaked.map((s) => s.c.id).join(", ")})` : ""
    } | ${uncovered.filter((s) => s.checks.notCovered).length}/${uncovered.length} |`,
  );
}

for (const [id, scored] of byConfig) {
  const lines: string[] = [`# ${id}\n`];
  for (const s of scored) {
    const failed = Object.entries(s.checks).filter(([, v]) => !v).map(([k]) => k);
    lines.push(
      `### ${s.c.id} (${s.c.group}, ${s.c.mode}${s.c.minor ? ", under 18" : ""})${
        failed.length ? "  FAILED: " + failed.join(", ") : ""
      }`,
    );
    lines.push(`Asks: ${s.c.messages[s.c.messages.length - 1].text}`);
    lines.push(`Checks: ${s.c.note}. Passages sent: ${s.rec.sources.map((x) => `${x.id}=${x.label}`).join(", ")}`);
    if (!s.rec.ok) lines.push(`API: ${s.rec.error}`);
    lines.push(`\n> ${s.answer || s.rec.raw}\n`);
    for (const q of s.quotes) lines.push(`- ${q.valid ? "✓" : q.near ? "~" : "✗"} ${q.id}: “${q.quote}”`);
    lines.push(
      `- ${s.rec.usage.input} in, ${s.rec.usage.output} out (${s.rec.usage.reasoning} thinking), ${
        cents(s.rec.cost)
      }, first words ${s.rec.ms.firstAnswer ? sec(s.rec.ms.firstAnswer) : "–"}\n`,
    );
  }
  Deno.writeTextFileSync(`${dir}/answers-${id}.md`, lines.join("\n"));
}

// What the economics need, kept next to the results.
const summary = Object.fromEntries([...byConfig].map(([id, scored]) => {
  const ok = scored.filter((s) => s.rec.ok);
  return [id, {
    n: scored.length,
    ok: ok.length,
    allChecks: scored.filter(passed).length,
    meanCostUsd: mean(ok.map((s) => s.rec.cost)),
    p90CostUsd: pct(ok.map((s) => s.rec.cost), 0.9),
    meanInput: mean(ok.map((s) => s.rec.usage.input)),
    meanOutput: mean(ok.map((s) => s.rec.usage.output)),
    meanReasoning: mean(ok.map((s) => s.rec.usage.reasoning)),
    medianFirstWordsMs: median(ok.map((s) => s.rec.ms.firstAnswer ?? s.rec.ms.total)),
    byGroupMeanCostUsd: Object.fromEntries(
      groups.map((g) => [g, mean(ok.filter((s) => s.c.group === g).map((s) => s.rec.cost))]),
    ),
  }];
}));
Deno.writeTextFileSync(`${dir}/summary.json`, JSON.stringify(summary, null, 2));
