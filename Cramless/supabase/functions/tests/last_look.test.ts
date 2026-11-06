// The last look on an exam's eve: `ai/last-look`. On the `extras` meter, limited in size, answers its fixture in MOCK mode, and the model's reply
// is cleaned: ids come from the request, one sentence each, on one line.

import { assertEquals, assertStringIncludes } from "@std/assert";
import type { LastLookRequest } from "../_shared/contract.ts";
import { TERRA } from "../_shared/cost.ts";
import { systemFor } from "../_shared/prompts.ts";
import { contractSchema } from "../_shared/schemas.ts";
import { validate } from "../_shared/schema.ts";
import { LAST_LOOK_MAX_SENTENCE, sanitizeLastLook } from "../_shared/syllabus.ts";
import { errorOf, fixtureJson, rig, ScriptedProvider } from "./_harness.ts";

const TODAY = "2026-10-22";
const body = () => fixtureJson("requests/last-look") as LastLookRequest;

Deno.test("last-look: answers its fixture in MOCK mode, on the extras meter", async () => {
  const r = rig({ env: { CRAMLESS_MOCK: "1" } });
  r.store.addUser("user-1");
  const res = await r.ai("last-look", { body: body() });
  assertEquals(res.status, 200);
  const reply = await res.json();
  assertEquals(validate(contractSchema("LastLookResponse"), reply), []);
  assertEquals(reply.ideas.map((i: { id: string }) => i.id), ["i1", "i2"]);
  assertEquals(r.store.used("user-1", "extras", TODAY), 1);
  assertEquals(r.sleeps, [900]);
});

Deno.test("last-look: the request is limited", async () => {
  const r = rig({ env: { CRAMLESS_MOCK: "1" } });
  r.store.addUser("user-1");
  const idea = body().ideas[0];
  const refused: unknown[] = [
    { ...body(), ideas: [] },
    { ...body(), ideas: Array.from({ length: 9 }, (_, i) => ({ ...idea, id: `i${i}` })) },
    { ...body(), ideas: [{ ...idea, prompt: "" }] },
    { ...body(), ideas: [{ ...idea, answer: "" }] },
    { ...body(), ideas: [{ ...idea, lines: Array.from({ length: 7 }, () => "A line") }] },
    { ...body(), ideas: [{ ...idea, lines: ["x".repeat(1001)] }] },
    { ...body(), course: "x".repeat(201) },
  ];
  for (const request of refused) {
    const res = await r.ai("last-look", { body: request });
    assertEquals(res.status, 400);
    assertEquals((await errorOf(res)).code, "bad_request");
  }
  assertEquals(r.store.used("user-1", "extras", TODAY) ?? 0, 0, "a refused request costs nothing");
});

Deno.test("last-look: sentences are cleaned", () => {
  const req = body();
  assertEquals(
    sanitizeLastLook([
      { id: "i1", sentence: "  In anaphase the sister\n chromatids separate.  " },
      { id: "i1", sentence: "A second sentence for the same idea." },
      { id: "i404", sentence: "About an idea nobody asked about." },
      { id: "i2", sentence: "   " },
    ], req),
    [{ id: "i1", sentence: "In anaphase the sister chromatids separate." }],
  );
  assertEquals(sanitizeLastLook([{ id: "i1", sentence: "x".repeat(LAST_LOOK_MAX_SENTENCE + 1) }], req), []);
  assertEquals(sanitizeLastLook(undefined, req), []);
});

Deno.test("last-look: the model sees each idea with its lines, at low effort, and a failure gives the meter back", async () => {
  const provider = new ScriptedProvider();
  const r = rig({ provider });
  r.store.addUser("user-1");
  provider.replyJson({ ideas: [{ id: "i1", sentence: "In anaphase the sister chromatids separate." }, { id: "ghost", sentence: "No." }] });
  const res = await r.ai("last-look", { body: body() });
  assertEquals(res.status, 200);
  const reply = await res.json();
  assertEquals(reply.ideas, [{ id: "i1", sentence: "In anaphase the sister chromatids separate." }]);
  const call = provider.jsonCalls[0];
  assertEquals(call.effort, "low");
  assertEquals(call.model, TERRA);
  const words = call.content.map((b) => (b.type === "text" ? b.text : "")).join("\n");
  assertStringIncludes(words, `<idea id="i1">`);
  assertStringIncludes(words, "Exam: Bio 101 Midterm");
  assertStringIncludes(words, "Line: The spindle pulls them to opposite poles of the cell.");

  provider.failJson(new Error("the provider is down"));
  const used = r.store.used("user-1", "extras", TODAY);
  const failed = await r.ai("last-look", { body: body() });
  assertEquals((await errorOf(failed)).code, "upstream");
  assertEquals(r.store.used("user-1", "extras", TODAY), used, "given back");
});

Deno.test("the last-look prompt says what the route promises", () => {
  const prompt = systemFor("last-look");
  assertStringIncludes(prompt, "Use only the material", "the shared rules come first");
  assertStringIncludes(prompt, "Add nothing they don't say");
  assertStringIncludes(prompt, "empty string");
});
