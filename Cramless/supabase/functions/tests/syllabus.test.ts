// An exam's scope: `ai/syllabus` and `ai/exam-mention`. They meter on `extras`, refuse what the schema refuses, answer their fixtures in
// MOCK mode, and clean the model's reply: ids and dates must come from the request.

import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import type { ExamMentionRequest, SyllabusExam, SyllabusRequest } from "../_shared/contract.ts";
import { TERRA } from "../_shared/cost.ts";
import { systemFor } from "../_shared/prompts.ts";
import { contractSchema } from "../_shared/schemas.ts";
import { validate } from "../_shared/schema.ts";
import { isRealDay, sanitizeExamMentions, sanitizeSyllabus } from "../_shared/syllabus.ts";
import { errorOf, fixtureJson, rig, ScriptedProvider } from "./_harness.ts";

const TODAY = "2026-10-22";

const syllabusBody = () => fixtureJson("requests/syllabus") as SyllabusRequest;
const mentionBody = () => fixtureJson("requests/exam-mention") as ExamMentionRequest;

function exam(over: Partial<SyllabusExam> = {}): SyllabusExam {
  return {
    title: "Midterm",
    date: "2026-11-20",
    topics: [{ name: "Meiosis", lineIds: ["p0.l8"] }],
    format: {},
    ...over,
  };
}

Deno.test("syllabus: answers its fixture in MOCK mode, on the extras meter, without a model", async () => {
  const r = rig({ env: { CRAMLESS_MOCK: "1" } });
  r.store.addUser("user-1");
  const res = await r.ai("syllabus", { body: syllabusBody() });
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(validate(contractSchema("SyllabusResponse"), body), []);
  assertEquals(body.exams[0].title, "Midterm");
  assertEquals(r.store.used("user-1", "extras", TODAY), 1);
  assertEquals(r.store.used("user-1", "scans", TODAY), 0, "a syllabus never spends a free scan");
  assertEquals(r.sleeps, [1800]);
});

Deno.test("exam-mention: answers its fixture in MOCK mode, on the extras meter", async () => {
  const r = rig({ env: { CRAMLESS_MOCK: "1" } });
  r.store.addUser("user-1");
  const res = await r.ai("exam-mention", { body: mentionBody() });
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(validate(contractSchema("ExamMentionResponse"), body), []);
  assertEquals(body.mentions[0].isExam, true);
  assertEquals(r.store.used("user-1", "extras", TODAY), 1);
  assertEquals(r.sleeps, [900]);
});

Deno.test("the requests are limited: pages, topics, mentions, days", async () => {
  const r = rig({ env: { CRAMLESS_MOCK: "1" } });
  r.store.addUser("user-1");
  const page = syllabusBody().pages[0];
  const refused: [string, unknown][] = [
    ["syllabus", { ...syllabusBody(), pages: [] }],
    ["syllabus", { ...syllabusBody(), pages: Array.from({ length: 7 }, () => page) }],
    ["syllabus", { ...syllabusBody(), today: "next Tuesday" }],
    ["syllabus", { ...syllabusBody(), topics: Array.from({ length: 61 }, (_, i) => ({ id: `t${i}`, name: "A" })) }],
    ["exam-mention", { ...mentionBody(), mentions: [] }],
    ["exam-mention", { ...mentionBody(), mentions: Array.from({ length: 6 }, () => mentionBody().mentions[0]) }],
    ["exam-mention", { ...mentionBody(), recordedDay: "soon" }],
    ["exam-mention", { ...mentionBody(), mentions: [{ id: "m1", text: "The midterm", candidates: [] }] }],
    ["exam-mention", { ...mentionBody(), topics: Array.from({ length: 31 }, () => "A") }],
  ];
  for (const [route, body] of refused) {
    const res = await r.ai(route, { body });
    assertEquals(res.status, 400, JSON.stringify(body).slice(0, 80));
    assertEquals((await errorOf(res)).code, "bad_request");
  }
  assertEquals(r.store.used("user-1", "extras", TODAY), 0, "a refused request costs nothing");
});

Deno.test("a syllabus with no text is refused before anything is metered", async () => {
  const r = rig({ env: { CRAMLESS_MOCK: "1" } });
  r.store.addUser("user-1");
  const res = await r.ai("syllabus", { body: { ...syllabusBody(), pages: [{ page: 0, label: "1", lines: [] }] } });
  assertEquals(res.status, 400);
  assertEquals(r.store.used("user-1", "extras", TODAY), 0);
});

Deno.test("syllabus: the model is asked at low effort with its schema, as text, and its reply is cleaned", async () => {
  const provider = new ScriptedProvider();
  const r = rig({ provider });
  r.store.addUser("user-1");
  provider.replyJson({
    exams: [
      {
        title: " Midterm ",
        date: "2026-11-20",
        time: "10:00",
        dateQuote: "Friday, November 20, 10:00 AM",
        topics: [
          { name: "Phases of mitosis", topicId: "t1", lineIds: ["p0.l6", "p9.l9"] },
          { name: "phases of mitosis", topicId: "t1", lineIds: [] },
          { name: "Meiosis", topicId: "t99", lineIds: ["p0.l8"] },
        ],
        format: { multipleChoice: true, questionCount: 9000, minutes: 90, notes: " open book " },
      },
      { title: "Nothing to say", date: "2026-02-31", topics: [], format: {} },
    ],
  });
  const body = syllabusBody();
  // A photo in the request is not passed on.
  body.pages[0].image = "A".repeat(40);
  const res = await r.ai("syllabus", { body });
  assertEquals(res.status, 200);
  const reply = await res.json();
  assertEquals(reply.model, TERRA);
  assertEquals(reply.exams.length, 1, "a bad date with no topics is an exam with nothing to say");
  assertEquals(reply.exams[0].title, "Midterm");
  assertEquals(reply.exams[0].topics, [
    { name: "Phases of mitosis", topicId: "t1", lineIds: ["p0.l6"] },
    { name: "Meiosis", lineIds: ["p0.l8"] },
  ]);
  assertEquals(reply.exams[0].format, { multipleChoice: true, minutes: 90, notes: "open book" });

  const call = provider.jsonCalls[0];
  assertEquals(call.effort, "low");
  assertEquals(call.maxTokens, 4_000);
  assertEquals(call.schema.properties.exams.items.$ref, "#/$defs/SyllabusExam");
  assert(call.content.every((b) => b.type === "text"), "text only: the photo stays on the phone");
  const words = call.content.map((b) => (b.type === "text" ? b.text : "")).join("\n");
  assertStringIncludes(words, "[p0.l6] Week 4: Phases of mitosis");
  assertStringIncludes(words, "t1: Phases of mitosis");
  assertStringIncludes(words, "Today: 2026-11-06");
  assertEquals(r.store.used("user-1", "extras", TODAY), 1);
});

Deno.test("syllabus: a failure gives the extras use back", async () => {
  const provider = new ScriptedProvider();
  const r = rig({ provider });
  r.store.addUser("user-1");
  const res = await r.ai("syllabus", { body: syllabusBody() });
  assertEquals(res.status, 502);
  assertEquals(r.store.used("user-1", "extras", TODAY), 0);
});

Deno.test("sanitizeSyllabus: dates, times, quotes, the cap of four", () => {
  const req = syllabusBody();
  const past = sanitizeSyllabus([exam({ date: "2026-11-05", time: "10:00", dateQuote: "Nov 5" })], req);
  assertEquals(past[0].date, undefined, "a date gone by goes");
  assertEquals(past[0].time, undefined, "and its time");
  assertEquals(past[0].dateQuote, undefined, "and its quote");
  assertEquals(past[0].topics.length, 1, "the topics stay");
  assertEquals(sanitizeSyllabus([exam({ date: "2026-11-05", topics: [] })], req), [], "nothing left to say");
  assertEquals(sanitizeSyllabus([exam({ time: "25:00" })], req)[0].time, undefined);
  assertEquals(sanitizeSyllabus([exam({ title: "  " })], req)[0].title, "Exam");
  assertEquals(sanitizeSyllabus(Array.from({ length: 6 }, () => exam()), req).length, 4);
  assertEquals(sanitizeSyllabus(undefined, req), []);
  assert(isRealDay("2028-02-29"));
  assert(!isRealDay("2027-02-29"));
  assert(!isRealDay("20-11-2026"));
});

Deno.test("exam-mention: a date must be a candidate, a topic the course's, an id the request's", () => {
  const req = mentionBody();
  const out = sanitizeExamMentions([
    {
      id: "m1",
      isExam: true,
      title: " Midterm ",
      date: "2026-11-21",
      time: "10:00",
      scopePhrase: " weeks one to seven ",
      topics: ["cytokinesis", "Astrology"],
    },
    { id: "m1", isExam: false, topics: [] },
    { id: "m404", isExam: true, date: "2026-11-20", topics: [] },
  ], req);
  assertEquals(out, [{
    id: "m1",
    isExam: true,
    title: "Midterm",
    scopePhrase: "weeks one to seven",
    topics: ["Cytokinesis"],
  }]);

  const right = sanitizeExamMentions([{ id: "m1", isExam: true, date: "2026-11-20", time: "10:00", topics: [] }], req);
  assertEquals(right[0].date, "2026-11-20");
  assertEquals(right[0].time, "10:00");

  const no = sanitizeExamMentions([{
    id: "m1",
    isExam: false,
    title: "Paper",
    date: "2026-11-20",
    topics: ["Cytokinesis"],
  }], req);
  assertEquals(no, [{ id: "m1", isExam: false, topics: [] }], "not an exam: nothing else is kept");
});

Deno.test("exam-mention: the model sees the sentences with their candidates; a bad date never comes back", async () => {
  const provider = new ScriptedProvider();
  const r = rig({ provider });
  r.store.addUser("user-1");
  provider.replyJson({ mentions: [{ id: "m1", isExam: true, title: "Midterm", date: "2027-01-01", topics: [] }] });
  const res = await r.ai("exam-mention", { body: mentionBody() });
  const reply = await res.json();
  assertEquals(reply.mentions[0].date, undefined);
  const call = provider.jsonCalls[0];
  assertEquals(call.effort, "low");
  const words = call.content.map((b) => (b.type === "text" ? b.text : "")).join("\n");
  assertStringIncludes(words, `candidates="2026-11-20"`);
  assertStringIncludes(words, "Recorded on: 2026-11-02");
  assertStringIncludes(words, "weeks one to seven");
});

Deno.test("the prompts say what the routes promise", () => {
  const syllabus = systemFor("syllabus");
  assertStringIncludes(syllabus, "Use only the material", "the shared rules come first");
  assertStringIncludes(syllabus, "Never guess");
  assertStringIncludes(syllabus, "dateQuote");
  const mention = systemFor("exam-mention");
  assertStringIncludes(mention, "Never write a day that isn't a candidate");
});
