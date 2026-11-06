// MOCK mode: the fixtures, byte for byte, after the same auth, validation and quota logic, with believable latency.

import { assert, assertEquals } from "@std/assert";
import type { GradeRequest } from "../_shared/contract.ts";
import { gradeFixture } from "../_shared/mock.ts";
import { errorOf, fixture, fixtureJson, rig, sseEvents } from "./_harness.ts";

const MOCK = { CRAMLESS_MOCK: "1" };

function mockRig() {
  const r = rig({ env: MOCK });
  r.store.addUser("user-1", "Maya", "UTC");
  return r;
}

const transcribeBody = { image: "/9j/4AAQSkZJRgABAQAAAQABAAD", page: 0, label: "87" };
const lectureBody = {
  course: "Bio 101",
  title: "Lecture 6",
  segments: [{ id: "s3", start: 340, end: 360, text: "The spindle forms from the centrosomes." }],
  flags: [{ time: 725, text: "this will be on the midterm" }],
  maxItems: 6,
};
const confusionsBody = {
  course: "Bio 101",
  mistakes: [
    {
      itemId: "i4",
      topic: "Phases",
      prompt: "Anaphase?",
      expected: "Pulled apart",
      given: "Envelopes form",
      misses: 2,
    },
    {
      itemId: "i11",
      topic: "Phases",
      prompt: "Telophase?",
      expected: "Envelopes form",
      given: "Pulled apart",
      misses: 2,
    },
  ],
};
const cardsBody = {
  course: "Bio 101",
  messages: [
    { role: "user", text: "Mitosis vs cytokinesis?" },
    { role: "assistant", text: "Mitosis splits the nucleus; cytokinesis splits the cytoplasm." },
  ],
  maxItems: 4,
};

Deno.test("MOCK: every JSON route answers its fixture byte for byte, with believable latency", async () => {
  const r = mockRig();
  const generate = fixtureJson("generate");
  const cases: [string, unknown, string, number][] = [
    ["generate", fixtureJson("requests/generate"), "generate", 2500],
    ["check", { pages: fixtureJson("requests/generate").pages, items: generate.items }, "check", 1500],
    ["grade", fixtureJson("requests/grade"), "grade-partial", 900],
    ["confusions", confusionsBody, "confusions", 1800],
    ["confusions", { ...confusionsBody, lookAlike: true }, "confusions-lookalike", 1800],
    ["lecture", lectureBody, "lecture", 2500],
    ["cards-from-chat", cardsBody, "cards-from-chat", 1200],
    ["transcribe-image", transcribeBody, "transcribe-image", 1500],
  ];
  for (const [route, body, name, latency] of cases) {
    r.sleeps.length = 0;
    const res = await r.ai(route, { body });
    assertEquals(res.status, 200, route);
    assertEquals(res.headers.get("content-type"), "application/json; charset=utf-8");
    assertEquals(await res.text(), fixture(name), `${route} → ${name}`);
    assertEquals(r.sleeps, [latency], route);
  }
  await r.settle();
  assertEquals(r.store.requests.length, cases.length);
  assert(r.store.requests.every((row) => row.mock && row.model === "mock" && row.costUsd === "0.000000000"));
});

Deno.test("MOCK: the grade fixture follows a simple term match", () => {
  const base = fixtureJson("requests/grade") as GradeRequest;
  assertEquals(gradeFixture(base), "grade-partial");
  assertEquals(
    gradeFixture({ ...base, response: "Growth, identical cells, the same number of chromosomes." }),
    "grade-correct",
  );
  assertEquals(gradeFixture({ ...base, response: "To make sex cells for reproduction." }), "grade-incorrect");
});

Deno.test("MOCK: the tutor replays its script as server-sent events, with the script's delays", async () => {
  const r = mockRig();
  const res = await r.ai("tutor", { body: fixtureJson("requests/tutor") });
  assertEquals(res.status, 200);
  assertEquals(res.headers.get("content-type"), "text/event-stream; charset=utf-8");
  const events = await sseEvents(res);
  await r.settle();
  const script = fixtureJson("tutor-hints").events;
  assertEquals(events, script.map((e: { event: string; data: unknown }) => ({ event: e.event, data: e.data })));
  assertEquals(r.sleeps, script.map((e: { delayMs: number }) => e.delayMs));

  const explain = await sseEvents(await r.ai("tutor", { body: { ...fixtureJson("requests/tutor"), mode: "explain" } }));
  assertEquals(explain.map((e) => e.data), fixtureJson("tutor-explain").events.map((e: { data: unknown }) => e.data));
  // A minor always gets hints first.
  const minor = await sseEvents(
    await r.ai("tutor", { body: { ...fixtureJson("requests/tutor"), mode: "explain", minor: true } }),
  );
  assertEquals(minor.map((e) => e.data), fixtureJson("tutor-hints").events.map((e: { data: unknown }) => e.data));
});

Deno.test("MOCK: X-Cramless-Fixture picks another reply of the same route", async () => {
  const r = mockRig();
  const res = await r.ai("grade", {
    body: fixtureJson("requests/grade"),
    headers: { "x-cramless-fixture": "grade-incorrect" },
  });
  assertEquals(await res.text(), fixture("grade-incorrect"));
  // Not a reply of this route: ignored.
  const other = await r.ai("grade", {
    body: fixtureJson("requests/grade"),
    headers: { "x-cramless-fixture": "generate" },
  });
  assertEquals(await other.text(), fixture("grade-partial"));

  const error = await sseEvents(
    await r.ai("tutor", { body: fixtureJson("requests/tutor"), headers: { "x-cramless-fixture": "tutor-error" } }),
  );
  await r.settle();
  assertEquals(error.map((e) => e.event), ["start", "error"]);
  assertEquals(error[1].data, { code: "upstream", message: "Cap couldn't reach the tutor. Try again in a moment." });
  // The error came before any text: the tutor message is given back.
  assertEquals(r.store.used("user-1", "tutor", "2026-10-22"), 0);
});

Deno.test("MOCK: validation and quotas still apply", async () => {
  const r = mockRig();
  const bad = await r.ai("grade", { body: { kind: "recall" } });
  assertEquals(bad.status, 400);
  assertEquals((await errorOf(bad)).code, "bad_request");
  assertEquals(r.sleeps, [], "no latency for a refused request");

  for (let i = 0; i < 20; i++) assertEquals((await r.ai("grade", { body: fixtureJson("requests/grade") })).status, 200);
  const over = await r.ai("grade", { body: fixtureJson("requests/grade") });
  assertEquals(over.status, 429);
  assertEquals(await over.json(), fixtureJson("error-quota"), "the free plan's 21st grade is the error-quota fixture");

  const anonymous = await r.ai("generate", { user: null, body: fixtureJson("requests/generate") });
  assertEquals(anonymous.status, 401);
});
