// Request validation, and what the relay does to a model's reply: items must anchor to real line or segment ids
// from the request, be well formed for their kind, and keep within the request's formats and maxItems.

import { assert, assertEquals } from "@std/assert";
import type { GeneratedItem } from "../_shared/contract.ts";
import { sanitizeGrade, sanitizeItem, sanitizeItems, sanitizeVerdicts } from "../_shared/items.ts";
import { contractSchema, MAX_SOURCE_CHARS, requestSchema } from "../_shared/schemas.ts";
import { validate } from "../_shared/schema.ts";
import { GENERATE_TIMEOUT_MS } from "../ai/handler.ts";
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

const checkBody = () => ({
  pages: fixtureJson("requests/generate").pages,
  items: fixtureJson("generate").items.slice(0, 2),
});
const tutorSource = () => fixtureJson("requests/tutor").sources[0];

Deno.test("the new optional request fields are accepted at their limits, and a request without them still validates", async () => {
  const r = rig({ env: { CRAMLESS_MOCK: "1" } });
  r.store.addUser("user-1");
  r.store.entitlements.push({
    userId: "user-1",
    plan: "pro",
    productId: "com.loopware.Capling.pro.yearly",
    originalTransactionId: "otid",
    transactionId: "t1",
    purchaseDate: "2026-10-01T00:00:00Z",
    expiresAt: "2027-10-29T00:00:00Z",
    revokedAt: null,
    environment: "Production",
  });
  const ok: [string, unknown][] = [
    ["check", checkBody()],
    ["check", {
      ...checkBody(),
      sourceTitle: "x".repeat(200),
      headings: Array(60).fill("h".repeat(120)),
      lenient: true,
    }],
    ["check", { ...checkBody(), sourceTitle: "", headings: [], lenient: false }],
    ["tutor", fixtureJson("requests/tutor")],
    ["tutor", { ...fixtureJson("requests/tutor"), materials: Array(20).fill("m".repeat(120)) }],
    ["tutor", { ...fixtureJson("requests/tutor"), materials: [] }],
    ["tutor", { ...fixtureJson("requests/tutor"), fromPhoto: true }],
    ["tutor", { ...fixtureJson("requests/tutor"), fromPhoto: false }],
    ["tutor", { ...fixtureJson("requests/tutor"), sources: Array(100).fill(tutorSource()) }],
    ["assistant", fixtureJson("requests/assistant")],
    ["assistant", { ...fixtureJson("requests/assistant"), materials: ["Lecture 7 (38 min)"] }],
    ["assistant", { ...fixtureJson("requests/assistant"), sources: Array(100).fill(tutorSource()) }],
    [
      "lecture",
      { course: "B", title: "L", segments: [{ id: "s1", start: 0, end: 1, text: "x" }], flags: [], maxItems: 10 },
    ],
  ];
  for (const [route, body] of ok) {
    const res = await r.ai(route, { body });
    assertEquals(res.status, 200, route);
    await res.body?.cancel();
    r.store.counters.clear();
  }
  const tooMany = await r.ai("assistant", {
    body: { ...fixtureJson("requests/assistant"), sources: Array(101).fill(tutorSource()) },
  });
  assertEquals((await errorOf(tooMany)).message, "The request isn't valid: /sources has more than 100 items.");
});

Deno.test("the passages of one tutor or assistant request hold at most 200,000 characters in all, refused before anything is metered", async () => {
  assertEquals(MAX_SOURCE_CHARS, 200_000);
  const provider = new ScriptedProvider();
  const r = rig({ provider });
  r.store.addUser("user-1");
  const passage = (n: number, chars: number) => ({
    id: `s${n}`,
    title: "Notes",
    label: `p. ${n}`,
    text: "x".repeat(chars),
  });
  const passages = (count: number, chars: number) => Array.from({ length: count }, (_, i) => passage(i + 1, chars));
  const message = "That's more of your notes than Cap can read in one question. Try asking about one part of them.";
  for (const route of ["tutor", "assistant"]) {
    const base = fixtureJson(`requests/${route}`);
    const used = () =>
      (["tutor", "rounds", "drafts"] as const).map((meter) => r.store.used("user-1", meter, "2026-10-22"));

    // Ten passages at the 20,000-character limit are 200,000 in all: allowed.
    const ok = await r.ai(route, { body: { ...base, sources: passages(10, 20_000) } });
    assertEquals(ok.status, 200, route);
    await ok.body?.cancel();
    await r.settle();
    r.store.counters.clear();

    // One character more is not: a plain bad_request, nothing metered, the model never asked.
    const calls = provider.tutorCalls.length + provider.assistantCalls.length;
    const over = await r.ai(route, { body: { ...base, sources: [...passages(10, 20_000), passage(11, 1)] } });
    assertEquals(over.status, 413, route);
    const error = await errorOf(over);
    assertEquals([error.code, error.message], ["bad_request", message], route);
    assertEquals(used(), [0, 0, 0], `${route}: a refused request costs nothing`);
    assertEquals(provider.tutorCalls.length + provider.assistantCalls.length, calls, `${route}: no model call`);

    // The hand-built worst case under the body limit (100 passages of 20,000) is refused the same way.
    const worst = await r.ai(route, { body: { ...base, sources: passages(100, 20_000) } });
    assertEquals(worst.status, 413, route);

    // Passages that repeat an id count once, and real notes (a hundred of sixty words) are nowhere near it.
    const repeated = await r.ai(route, { body: { ...base, sources: Array(20).fill(passage(1, 20_000)) } });
    assertEquals(repeated.status, 200, route);
    await repeated.body?.cancel();
    await r.settle();
    r.store.counters.clear();
    const real = await r.ai(route, { body: { ...base, sources: passages(100, 400) } });
    assertEquals(real.status, 200, route);
    await real.body?.cancel();
    await r.settle();
    r.store.counters.clear();
  }
});

Deno.test("model calls: generate has its own, longer time limit; every other route keeps the provider's", async () => {
  assertEquals(GENERATE_TIMEOUT_MS, 115_000, "the app waits 120 s, the platform ends a function at about 150 s");
  const provider = new ScriptedProvider();
  const r = rig({ provider });
  r.store.addUser("user-1");
  r.store.entitlements.push({
    userId: "user-1",
    plan: "pro",
    productId: "com.loopware.Capling.pro.yearly",
    originalTransactionId: "otid",
    transactionId: "t1",
    purchaseDate: "2026-10-01T00:00:00Z",
    expiresAt: "2027-10-29T00:00:00Z",
    revokedAt: null,
    environment: "Production",
  });
  const generate = fixtureJson("generate");
  delete generate.model;
  provider.replyJson(generate);
  await (await r.ai("generate", { body: fixtureJson("requests/generate") })).text();

  const check = { verdicts: [{ id: "i1", verdict: "supported", reason: "On the page." }] };
  provider.replyJson(check);
  await (await r.ai("check", {
    body: { pages: fixtureJson("requests/generate").pages, items: generate.items.slice(0, 1) },
  }))
    .text();
  const grade = fixtureJson("grade-partial");
  delete grade.model;
  provider.replyJson(grade);
  await (await r.ai("grade", { body: fixtureJson("requests/grade") })).text();
  const lecture = fixtureJson("lecture");
  delete lecture.model;
  provider.replyJson(lecture);
  const segments = [{ id: "s5", start: 0, end: 30, text: "…" }];
  await (await r.ai("lecture", { body: { course: "Bio", title: "L6", segments, flags: [], maxItems: 10 } })).text();

  assertEquals(provider.jsonCalls.map((call) => call.timeoutMs), [
    GENERATE_TIMEOUT_MS,
    undefined,
    undefined,
    undefined,
  ]);
});

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
    ["check", { ...checkBody(), sourceTitle: "x".repeat(201) }, "/sourceTitle is longer than 200"],
    ["check", { ...checkBody(), headings: Array(61).fill("h") }, "/headings has more than 60 items"],
    ["check", { ...checkBody(), headings: ["x".repeat(121)] }, "/headings/0 is longer than 120"],
    ["check", { ...checkBody(), headings: "Facts" }, "/headings expected array"],
    ["check", { ...checkBody(), lenient: "yes" }, "/lenient expected boolean"],
    [
      "tutor",
      { ...fixtureJson("requests/tutor"), materials: Array(21).fill("Deck") },
      "/materials has more than 20 items",
    ],
    ["tutor", { ...fixtureJson("requests/tutor"), materials: ["x".repeat(121)] }, "/materials/0 is longer than 120"],
    ["tutor", { ...fixtureJson("requests/tutor"), materials: "Deck" }, "/materials expected array"],
    ["tutor", { ...fixtureJson("requests/tutor"), fromPhoto: "yes" }, "/fromPhoto expected boolean"],
    [
      "tutor",
      { ...fixtureJson("requests/tutor"), sources: Array(101).fill(tutorSource()) },
      "/sources has more than 100 items",
    ],
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

Deno.test("a set of forty questions is kept whole, and a forty-first is not", () => {
  const items = Array.from({ length: 45 }, (_, n) => item({ id: `i${n + 1}`, prompt: `Question ${n + 1}` }));
  const kept = sanitizeItems(items, { ...rules, maxItems: 40 });
  assertEquals(kept.length, 40);
  assertEquals(kept.at(-1)!.id, "i40");
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

Deno.test("lecture: leftOut is cleaned to a whole number from 1 to 99, and nothing is sent when there are none", async () => {
  const provider = new ScriptedProvider();
  const r = rig({ provider });
  r.store.addUser("user-1");
  const segments = ["s3", "s4"].map((id, i) => ({ id, start: i * 300, end: i * 300 + 290, text: "…" }));
  const ask = async (leftOut: unknown) => {
    r.store.counters.clear();
    const reply = fixtureJson("lecture");
    delete reply.model;
    if (leftOut !== undefined) reply.leftOut = leftOut;
    provider.replyJson(reply);
    const res = await r.ai("lecture", {
      body: { course: "Bio", title: "Lecture 6", segments, flags: [], maxItems: 10 },
    });
    assertEquals(res.status, 200);
    return await res.json();
  };
  assertEquals((await ask(3)).leftOut, 3);
  assertEquals((await ask(120)).leftOut, 99);
  for (const none of [0, -2, null, undefined, "many"]) {
    const body = await ask(none);
    assertEquals("leftOut" in body, false, String(none));
  }
});

Deno.test("a look-alike request may say so: a boolean, or nothing at all", () => {
  const mistake = {
    itemId: "i7",
    topic: "Phases",
    prompt: "Which phase?",
    expected: "Metaphase",
    given: "",
    misses: 0,
  };
  const schema = requestSchema("ConfusionsRequest");
  assertEquals(validate(schema, { course: "Bio", mistakes: [mistake] }).length, 0, "old apps send nothing");
  assertEquals(validate(schema, { course: "Bio", mistakes: [mistake], lookAlike: true }).length, 0);
  assert(validate(schema, { course: "Bio", mistakes: [mistake], lookAlike: "yes" }).length > 0);
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
