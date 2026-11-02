// Request validation, and what the relay does to a model's reply: items must anchor to real line or segment ids
// from the request, be well formed for their kind, and keep within the request's formats and maxItems.

import { assert, assertEquals } from "@std/assert";
import type { GeneratedItem } from "../_shared/contract.ts";
import { sanitizeGrade, sanitizeItem, sanitizeItems, sanitizeVerdicts } from "../_shared/items.ts";
import { contractSchema } from "../_shared/schemas.ts";
import { validate } from "../_shared/schema.ts";
import { errorOf, fixtureJson, rig, ScriptedProvider } from "./_harness.ts";

const LINES = new Set(["p0.l1", "p0.l2", "p0.l3", "p0.l8", "p0.l9"]);
const rules = { validAnchors: LINES, requireAnchors: true, unknownAnchor: "drop" as const };

function item(over: Partial<GeneratedItem> = {}): GeneratedItem {
  return {
    id: "i1",
    kind: "flashcard",
    topic: "Mitosis",
    prompt: "Mitosis",
    answer: "Division into two identical cells.",
    explanation: "",
    keyIdeas: [],
    choices: [],
    anchors: ["p0.l1"],
    difficulty: 0.4,
    ...over,
  };
}

Deno.test("validation names the first problem, never a value", async () => {
  const r = rig({ env: { CRAMLESS_MOCK: "1" } });
  r.store.addUser("user-1");
  const cases: [string, unknown, string][] = [
    [
      "generate",
      { ...fixtureJson("requests/generate"), formats: ["essay"] },
      "/formats/0 isn't one of the allowed values",
    ],
    ["generate", { ...fixtureJson("requests/generate"), maxItems: 0 }, "/maxItems is below 1"],
    ["generate", { ...fixtureJson("requests/generate"), pages: [] }, "/pages has fewer than 1 items"],
    ["grade", { ...fixtureJson("requests/grade"), response: 7 }, "/response expected string"],
    ["tutor", { ...fixtureJson("requests/tutor"), mode: "essay" }, "/mode isn't one of the allowed values"],
    ["tutor", { ...fixtureJson("requests/tutor"), messages: [] }, "/messages has fewer than 1 items"],
    ["transcribe-image", { page: 0, label: "1" }, "/image is required"],
    ["lecture", {
      course: "B",
      title: "L",
      segments: [{ id: "bad id!", start: 0, end: 1, text: "x" }],
      flags: [],
      maxItems: 3,
    }, "/segments/0/id doesn't match the pattern"],
  ];
  for (const [route, body, problem] of cases) {
    const res = await r.ai(route, { body });
    assertEquals(res.status, 400, route);
    const error = await errorOf(res);
    assertEquals(error.code, "bad_request");
    assertEquals(error.message, `The request isn't valid: ${problem}.`, route);
  }
  // The tutor's last message must be the student's.
  const tutor = fixtureJson("requests/tutor");
  tutor.messages.push({ role: "assistant", text: "Hi" });
  assertEquals(
    (await errorOf(await r.ai("tutor", { body: tutor }))).message,
    "The last message must be the student's.",
  );
  // Unknown fields are fine (add fields as optionals).
  assertEquals((await r.ai("grade", { body: { ...fixtureJson("requests/grade"), hint: "new field" } })).status, 200);
});

Deno.test("an item whose anchors aren't real line ids is dropped", () => {
  assert(sanitizeItem(item(), rules));
  assertEquals(sanitizeItem(item({ anchors: ["p0.l1", "p9.l99"] }), rules), null);
  assertEquals(sanitizeItem(item({ anchors: [] }), rules), null, "grounded items need an anchor");
  assertEquals(sanitizeItem(item({ anchors: ["P0.L1"] }), rules), null, "ids are exact");
  // Confusions strip anchors instead: their requests carry no line ids at all.
  assertEquals(
    sanitizeItem(item({ anchors: ["p0.l14"] }), {
      validAnchors: new Set(),
      requireAnchors: false,
      unknownAnchor: "strip",
    })?.anchors,
    [],
  );
});

Deno.test("items must be well formed for their kind", () => {
  const mcq = item({
    kind: "mcq",
    answer: "wrong text",
    choices: [{ text: "Prophase", correct: false }, { text: "Metaphase", correct: true, why: "Equator." }],
  });
  const kept = sanitizeItem(mcq, rules)!;
  assertEquals(kept.answer, "Metaphase", "the answer is the correct choice");
  assertEquals(kept.choices, [{ text: "Prophase", correct: false }, {
    text: "Metaphase",
    correct: true,
    why: "Equator.",
  }]);
  assertEquals(sanitizeItem({ ...mcq, choices: mcq.choices.map((c) => ({ ...c, correct: true })) }, rules), null);
  assertEquals(sanitizeItem({ ...mcq, choices: [mcq.choices[1]] }, rules), null);

  const cloze = sanitizeItem(
    item({
      kind: "cloze",
      answer: "",
      cloze: { text: "During {{telophase}}, envelopes {{form}}.", alternates: [["telophase."]] },
    }),
    rules,
  )!;
  assertEquals(cloze.cloze, { text: "During {{telophase}}, envelopes {{form}}.", alternates: [["telophase."], []] });
  assertEquals(cloze.answer, "telophase, form");
  assertEquals(sanitizeItem(item({ kind: "cloze", cloze: { text: "No blank here.", alternates: [] } }), rules), null);

  const diagram = sanitizeItem(
    item({ kind: "diagram", diagramLabels: ["p0.l8", "p0.l9"], anchors: ["p0.l8"] }),
    rules,
  )!;
  assertEquals(diagram.anchors, ["p0.l8", "p0.l9"]);
  assertEquals(sanitizeItem(item({ kind: "diagram", diagramLabels: ["p0.l77"] }), rules), null);
  assertEquals(sanitizeItem(item({ kind: "diagram" }), rules), null);

  assertEquals(sanitizeItem(item({ kind: "recall", keyIdeas: [] }), rules), null, "own-words items need key ideas");
  const recall = sanitizeItem(
    item({ kind: "recall", keyIdeas: [{ id: "k1", label: "Growth", terms: [" Grow ", "grow", ""] }] }),
    rules,
  )!;
  assertEquals(recall.keyIdeas, [{ id: "k1", label: "Growth", terms: ["grow"] }]);
  assertEquals(sanitizeItem(item({ difficulty: 7 }), rules)!.difficulty, 1);
  assertEquals("cloze" in sanitizeItem(item({ cloze: { text: "{{x}}", alternates: [] } }), rules)!, false);
});

Deno.test("formats, maxItems and unique ids", () => {
  const items = sanitizeItems(
    [
      item(),
      item({ kind: "mcq", choices: [] }),
      item({ id: "i1", prompt: "Second" }),
      item({ id: "i3" }),
      item({ id: "i4" }),
    ],
    { ...rules, formats: new Set(["flashcard"]), maxItems: 3 },
  );
  assertEquals(items.map((i) => i.id), ["i1", "i1-2", "i3"]);
});

Deno.test("generate: the reply is cleaned, and an all-dropped reply refunds the scan", async () => {
  const provider = new ScriptedProvider();
  const r = rig({ provider });
  r.store.addUser("user-1");
  const request = fixtureJson("requests/generate");
  const reply = fixtureJson("generate");
  delete reply.model;
  reply.items.push({ ...reply.items[0], id: "i99", anchors: ["p0.l1", "p3.l2"] }); // a line that isn't on the page
  provider.replyJson(reply);
  const res = await r.ai("generate", { body: request });
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(validate(contractSchema("GenerateResponse"), body), []);
  assertEquals(body.model, "gpt-6.1-terra");
  assertEquals(body.items.length, 16, "the item with a made-up anchor is dropped");
  assertEquals(
    body.items.map((i: GeneratedItem) => i.id),
    fixtureJson("generate").items.map((i: GeneratedItem) => i.id),
  );

  provider.replyJson({ title: "x", topics: [], items: [{ ...reply.items[0], anchors: ["nope"] }] });
  const empty = await r.ai("generate", { body: { ...request, pages: [request.pages[0]] } });
  assertEquals(empty.status, 502);
  assertEquals((await errorOf(empty)).code, "upstream");
  assertEquals(r.store.used("user-1", "scans", "2026-10-19"), 1, "only the first scan counted");
});

Deno.test("check: ungrounded items are unsupported without asking the model; every item gets a verdict", async () => {
  const provider = new ScriptedProvider();
  const r = rig({ provider });
  r.store.addUser("user-1");
  const pages = fixtureJson("requests/generate").pages;
  const items = fixtureJson("generate").items.slice(0, 3);
  items.push({ ...items[0], id: "i-made-up", anchors: ["p7.l1"] });
  provider.replyJson({
    verdicts: [
      { id: "i1", verdict: "supported", reason: "On p. 87." },
      {
        id: "i2",
        verdict: "fixed",
        reason: "Added the chromosome number.",
        fixedAnswer: "Same DNA and chromosome number.",
      },
      { id: "i-unknown", verdict: "supported", reason: "?" },
    ],
  });
  const res = await r.ai("check", { body: { pages, items } });
  const body = await res.json();
  assertEquals(body.verdicts.map((v: { id: string; verdict: string }) => [v.id, v.verdict]), [
    ["i1", "supported"],
    ["i2", "fixed"],
    ["i3", "unsupported"],
    ["i-made-up", "unsupported"],
  ]);
  const call = (provider as ScriptedProvider).jsonCalls[0];
  assert(!JSON.stringify(call.content).includes("i-made-up"), "an ungrounded item never reaches the model");

  // A "fixed" verdict without a fix is just supported.
  assertEquals(
    sanitizeVerdicts([items[0]], [{ id: "i1", verdict: "fixed", reason: "r" }], new Set())[0].verdict,
    "supported",
  );
});

Deno.test("grade: hits name real ideas, missing is the rest, numbers stay in 0…1", () => {
  const request = fixtureJson("requests/grade");
  const out = sanitizeGrade({
    score: 1.4,
    verdict: "partial",
    confidence: -2,
    hits: [{ ideaId: "k1", quote: "grow and repair tissue" }, { ideaId: "k1", quote: "again" }, {
      ideaId: "k9",
      quote: "x",
    }],
    missing: ["k2"],
    feedback: " Good start. ",
    fix: "",
  }, request);
  assertEquals(out.hits, [{ ideaId: "k1", quote: "grow and repair tissue" }]);
  assertEquals(out.missing, ["k2", "k3"]);
  assertEquals([out.score, out.confidence, out.feedback], [1, 0, "Good start."]);
});

Deno.test("grade: an empty answer is graded without a model call or a quota", async () => {
  const provider = new ScriptedProvider();
  const r = rig({ provider });
  r.store.addUser("user-1");
  const res = await r.ai("grade", { body: { ...fixtureJson("requests/grade"), response: "   " } });
  const body = await res.json();
  assertEquals([body.verdict, body.missing], ["incorrect", ["k1", "k2", "k3"]]);
  assertEquals(provider.jsonCalls.length, 0);
  assertEquals(r.store.used("user-1", "grades", "2026-10-22"), 0);
});

Deno.test("lecture, confusions, cards and transcription replies are cleaned too", async () => {
  const provider = new ScriptedProvider();
  const r = rig({ provider });
  r.store.addUser("user-1");

  const lecture = fixtureJson("lecture");
  delete lecture.model;
  lecture.items.push({ ...lecture.items[0], id: "l9", anchors: ["s99"] });
  lecture.sections.push({ id: "n9", title: "After the end", start: 5000, end: 9000, bullets: [] });
  provider.replyJson(lecture);
  const segments = ["s3", "s4", "s5"].map((id, i) => ({ id, start: 300 + i * 300, end: 1040 + i, text: "…" }));
  const lec =
    await (await r.ai("lecture", { body: { course: "Bio", title: "Lecture 6", segments, flags: [], maxItems: 6 } }))
      .json();
  assertEquals(lec.items.map((i: GeneratedItem) => i.id), ["l1", "l2", "l3"]);
  assertEquals(lec.sections.at(-1), { id: "n9", title: "After the end", start: 1042, end: 1042, bullets: [] });

  const confusions = fixtureJson("confusions");
  delete confusions.model;
  confusions.confusions[0].itemIds.push("i404");
  confusions.confusions.push({ ...confusions.confusions[0], name: "Made up", itemIds: ["nope"] });
  provider.replyJson(confusions);
  const mistakes = ["i4", "i11"].map((itemId) => ({
    itemId,
    topic: "T",
    prompt: "P",
    expected: "E",
    given: "G",
    misses: 2,
  }));
  const conf = await (await r.ai("confusions", { body: { course: "Bio", mistakes } })).json();
  assertEquals(conf.confusions.length, 1);
  assertEquals(conf.confusions[0].itemIds, ["i4", "i11"]);
  assert(conf.confusions[0].questions.every((q: GeneratedItem) => q.anchors.length === 0));

  const cards = fixtureJson("cards-from-chat");
  delete cards.model;
  cards.items.push({ ...cards.items[0], id: "m3", anchors: ["p0.l1"] });
  provider.replyJson(cards);
  const chat =
    await (await r.ai("cards-from-chat", { body: { messages: [{ role: "user", text: "Hi" }], maxItems: 5 } })).json();
  assertEquals(chat.items.map((i: GeneratedItem) => i.id), ["m1", "m2"], "the chat has no line ids to anchor to");

  provider.replyJson({
    lines: [{ id: "x9", text: " Mitosis notes " }, { id: "x9", text: "" }, { id: "y", text: "PMAT" }],
  });
  const lines =
    await (await r.ai("transcribe-image", { body: { image: "iVBORw0KGgoAAAANSUhEUgAA", page: 2, label: "3" } })).json();
  assertEquals(lines.lines, [{ id: "p2.c0", text: "Mitosis notes" }, { id: "p2.c1", text: "PMAT" }]);
  assertEquals(
    (provider.jsonCalls.at(-1)!.content[0] as { mediaType: string }).mediaType,
    "image/png",
  );
});
