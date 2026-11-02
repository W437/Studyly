// The tutor's server-sent events: framing, pings, and the real path's normalized events.

import { assert, assertEquals } from "@std/assert";
import { ApiError } from "../_shared/errors.ts";
import { EventStream, formatEvent, parseSse } from "../_shared/sse.ts";
import { errorOf, fixtureJson, rig, ScriptedProvider, sseEvents } from "./_harness.ts";

const USAGE = { inputTokens: 2400, outputTokens: 180, cacheReadTokens: 0, cacheWriteTokens: 0 };

Deno.test("an event is `event:`, one `data:` line of JSON and a blank line", () => {
  assertEquals(formatEvent("delta", { text: "Hi\nthere" }), 'event: delta\ndata: {"text":"Hi\\nthere"}\n\n');
});

Deno.test("parseSse reads events, joins multi-line data and skips comments", async () => {
  const body = new Response(': ping\n\nevent: start\ndata: {"model":"m"}\n\nevent: x\ndata: a\ndata: b\n\n').body!;
  const out = [];
  for await (const m of parseSse(body)) out.push(m);
  assertEquals(out, [{ event: "start", data: '{"model":"m"}' }, { event: "x", data: "a\nb" }]);
});

Deno.test("a silent stream sends a ping comment, and a client that leaves runs the cancel handlers", async () => {
  const stream = new EventStream(20);
  let cancelled = false;
  stream.onCancel(() => (cancelled = true));
  const reader = stream.response.body!.getReader();
  const first = new TextDecoder().decode((await reader.read()).value);
  assertEquals(first, ": ping\n\n");
  await reader.cancel();
  assert(cancelled && stream.closed);
  stream.send("delta", { text: "dropped" }); // no throw after the client left
});

function tutorRig() {
  const provider = new ScriptedProvider();
  const r = rig({ provider });
  r.store.addUser("user-1");
  return { r, provider };
}

Deno.test("the tutor streams start, deltas, citations (with the source's label) and done", async () => {
  const { r, provider } = tutorRig();
  provider.replyTutor([
    { type: "start", model: "gpt-6.1-terra" },
    { type: "delta", text: "Mitosis splits the nucleus, " },
    { type: "citation", source: "s1", quote: "During mitosis, the genetic material (DNA) is copied." },
    { type: "citation", source: "s1", quote: "During mitosis, the genetic material (DNA) is copied." },
    { type: "citation", source: "not-sent", quote: "Invented." },
    { type: "delta", text: "cytokinesis splits the cell." },
    { type: "done", model: "gpt-6.1-terra", usage: USAGE, stop: "end_turn" },
  ]);
  const res = await r.ai("tutor", { body: fixtureJson("requests/tutor") });
  assertEquals(res.headers.get("content-type"), "text/event-stream; charset=utf-8");
  const events = await sseEvents(res);
  await r.settle();
  assertEquals(events, [
    { event: "start", data: { model: "gpt-6.1-terra" } },
    { event: "delta", data: { text: "Mitosis splits the nucleus, " } },
    {
      event: "citation",
      data: { sourceId: "s1", label: "Textbook p. 87", quote: "During mitosis, the genetic material (DNA) is copied." },
    },
    { event: "delta", data: { text: "cytokinesis splits the cell." } },
    { event: "done", data: { model: "gpt-6.1-terra" } },
  ]);
  // The fixture scripts use the same event names and payload fields.
  const names = new Set(fixtureJson("tutor-explain").events.map((e: { event: string }) => e.event));
  assert(events.every((e) => names.has(e.event)));
  const row = r.store.requests[0];
  assertEquals([row.route, row.model, row.status, row.inputTokens, row.outputTokens], [
    "tutor",
    "gpt-6.1-terra",
    200,
    2400,
    180,
  ]);
  assertEquals(row.costUsd, "0.003300000", "2,400 in and 180 out on Terra");
  assertEquals(r.store.used("user-1", "tutor", "2026-10-22"), 1);
});

Deno.test("the tutor asks for hints first, teen-safe for a minor", async () => {
  const { r, provider } = tutorRig();
  provider.replyTutor([{ type: "done", model: "gpt-6.1-terra", usage: USAGE, stop: "end_turn" }]);
  await sseEvents(await r.ai("tutor", { body: { ...fixtureJson("requests/tutor"), mode: "explain", minor: true } }));
  await r.settle();
  const system = provider.tutorCalls[0].system;
  assert(system.includes("Mode: hints first."));
  assert(!system.includes("Mode: explain."));
  assert(system.includes("This student is under 18."));
  assert(system.includes("Your material doesn't cover that."));
  assert(system.includes("Never write the student's essay"));
});

Deno.test("an upstream failure before any text is an error event, and the message is given back", async () => {
  const { r, provider } = tutorRig();
  provider.replyTutor([
    { type: "start", model: "gpt-6.1-terra" },
    new ApiError("upstream", "Cap is busy right now. Try again in a moment.", { retryAfter: 15 }, 503),
  ]);
  const events = await sseEvents(await r.ai("tutor", { body: fixtureJson("requests/tutor") }));
  await r.settle();
  assertEquals(events.at(-1), {
    event: "error",
    data: { code: "upstream", message: "Cap is busy right now. Try again in a moment." },
  });
  assertEquals(r.store.used("user-1", "tutor", "2026-10-22"), 0);
  assertEquals(r.store.requests[0].status, 503);
});

Deno.test("a failure after text keeps the message counted; a refusal is an error event", async () => {
  const { r, provider } = tutorRig();
  provider.replyTutor([{ type: "delta", text: "Partly " }, new Error("socket closed")]);
  const failed = await sseEvents(await r.ai("tutor", { body: fixtureJson("requests/tutor") }));
  assertEquals(failed.map((e) => e.event), ["delta", "error"]);
  provider.replyTutor([{ type: "done", model: "gpt-6.1-terra", usage: USAGE, stop: "refusal" }]);
  const refused = await sseEvents(await r.ai("tutor", { body: fixtureJson("requests/tutor") }));
  await r.settle();
  assertEquals(refused, [{
    event: "error",
    data: { code: "upstream", message: "Cap can't help with that one. Try asking about your notes." },
  }]);
  assertEquals(r.store.used("user-1", "tutor", "2026-10-22"), 1, "the refused one was given back");
});

Deno.test("errors before the stream starts are plain JSON envelopes", async () => {
  const { r } = tutorRig();
  r.store.counters.set("user-1|tutor|2026-10-22", 10);
  const res = await r.ai("tutor", { body: fixtureJson("requests/tutor") });
  assertEquals(res.status, 429);
  assertEquals(res.headers.get("content-type"), "application/json; charset=utf-8");
  assertEquals((await errorOf(res)).code, "quota_exceeded");
});

Deno.test("when the person leaves, the stream stops reading from the model", async () => {
  const provider = new ScriptedProvider();
  const r = rig({ provider });
  r.store.addUser("user-1");
  let pulled = 0;
  provider.tutor = async function* () {
    yield { type: "start", model: "gpt-6.1-terra" };
    for (let i = 0; i < 1000; i++) {
      pulled++;
      await new Promise((resolve) => setTimeout(resolve, 1));
      yield { type: "delta", text: `${i} ` };
    }
  };
  const res = await r.ai("tutor", { body: fixtureJson("requests/tutor") });
  const reader = res.body!.getReader();
  await reader.read();
  await reader.cancel();
  await r.settle();
  assert(pulled < 50, `stopped after ${pulled} deltas`);
});
