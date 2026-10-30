// Record the relay's exact Claude calls, and replay a real model's replies through the relay's own validation and
// cleaning. For checking prompt quality with a model answered elsewhere (no API key needed here):
//
//   deno run -A tools/prompt_replay.ts record generate            → build/prompt_replay/generate.call.json
//   deno run -A tools/prompt_replay.ts replay generate <reply.json>  → what the app would receive, with verdicts
//   deno run -A tools/prompt_replay.ts record check                (needs a generate replay first: checks its items)
//   deno run -A tools/prompt_replay.ts record grade-1|grade-2|grade-3
//
// A call file holds the model, the system prompt, the user content as text and the JSON schema the reply must match.

import type { JsonCall } from "../_shared/anthropic.ts";
import { fixtureJson, rig, ScriptedProvider } from "../tests/_harness.ts";

const OUT = new URL("../../../build/prompt_replay/", import.meta.url);
await Deno.mkdir(OUT, { recursive: true });

const answers = [
  "So the body can grow and repair tissue, making two identical cells.",
  "To grow and fix damaged tissue; each new cell is an exact genetic copy with the same number of chromosomes.",
  "To make sex cells with half the chromosomes.",
];

// deno-lint-ignore no-explicit-any
async function requestFor(route: string): Promise<{ path: string; body: any }> {
  if (route === "generate") return { path: "generate", body: fixtureJson("requests/generate") };
  if (route === "check") {
    const generated = JSON.parse(await Deno.readTextFile(new URL("generate.out.json", OUT)));
    return { path: "check", body: { pages: fixtureJson("requests/generate").pages, items: generated.items } };
  }
  if (route === "tutor-hints" || route === "tutor-explain") {
    return { path: "tutor", body: { ...fixtureJson("requests/tutor"), mode: route.replace("tutor-", "") } };
  }
  const n = Number(route.replace("grade-", ""));
  if (route.startsWith("grade-") && n >= 1 && n <= 3) {
    return { path: "grade", body: { ...fixtureJson("requests/grade"), response: answers[n - 1] } };
  }
  throw new Error(`unknown route ${route}`);
}

function placeholder(route: string): unknown {
  if (route === "generate") return fixtureJson("generate");
  if (route === "check") return fixtureJson("check");
  return fixtureJson("grade-partial");
}

function asText(call: JsonCall): string {
  return call.content.map((block) =>
    ("text" in block && typeof block.text === "string") ? block.text : JSON.stringify(block)
  )
    .join("\n\n");
}

const [mode, route, replyPath] = Deno.args;
if (!mode || !route) {
  console.error("usage: prompt_replay.ts record|replay <route> [reply.json]");
  Deno.exit(2);
}
const provider = new ScriptedProvider();
const t = rig({ provider });
t.store.addUser("user-1", "Prompt replay", "UTC");
const { path, body } = await requestFor(route);

if (mode === "record" && route.startsWith("tutor-")) {
  provider.replyTutor([{ type: "start", model: "placeholder" }, { type: "delta", text: "…" }]);
  await (await t.ai(path, { body })).text();
  const call = provider.tutorCalls[0];
  // The person's material goes as search-result blocks (the API cites them); written out here as tagged text.
  const user = call.messages.map((m) => {
    const blocks = typeof m.content === "string" ? [{ type: "text", text: m.content }] : m.content;
    // deno-lint-ignore no-explicit-any
    const parts = (blocks as any[]).map((b) =>
      b.type === "text"
        ? b.text
        : b.type === "search_result"
        ? `<source id="${b.source}" title="${b.title}">${
          (b.content ?? []).map((c: { text: string }) => c.text).join(" ")
        }</source>`
        : JSON.stringify(b)
    );
    return `[${m.role}]\n${parts.join("\n")}`;
  }).join("\n\n");
  const file = new URL(`${route}.call.json`, OUT);
  await Deno.writeTextFile(
    file,
    JSON.stringify({ model: call.model, effort: call.effort, system: call.system, user }, null, 2),
  );
  console.log(`recorded ${route}: ${file.pathname}`);
  Deno.exit(0);
}

if (mode === "record") {
  provider.replyJson(placeholder(route));
  await (await t.ai(path, { body })).text();
  const call = provider.jsonCalls[0];
  const file = new URL(`${route}.call.json`, OUT);
  await Deno.writeTextFile(
    file,
    JSON.stringify(
      {
        model: call.model,
        effort: call.effort,
        maxTokens: call.maxTokens,
        system: call.system,
        user: asText(call),
        schema: call.schema,
      },
      null,
      2,
    ),
  );
  console.log(`recorded ${route}: ${file.pathname}`);
  Deno.exit(0);
}

// replay
const reply = JSON.parse(await Deno.readTextFile(replyPath));
provider.replyJson(reply);
const res = await t.ai(path, { body });
const text = await res.text();
console.log(`HTTP ${res.status}`);
if (res.status !== 200) {
  console.log(text);
  Deno.exit(1);
}
const out = JSON.parse(text);
if (route === "generate") await Deno.writeTextFile(new URL("generate.out.json", OUT), JSON.stringify(out, null, 2));
console.log(JSON.stringify(out, null, 2));
