// The real path, end to end without a key: the relay's handlers with the official Anthropic SDK pointed at a
// local mock of the Messages API, which checks each request's shape and answers with canned provider replies.

import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import { contractSchema, providerSchema } from "../_shared/schemas.ts";
import { validate } from "../_shared/schema.ts";
import { errorOf, fixtureJson, mockedProvider, rig, sseEvents } from "./_harness.ts";
import { messageJson, messageStream, type MockAnthropic, startMockAnthropic, TEST_API_KEY } from "./_mock_anthropic.ts";

async function withMock(run: (mock: MockAnthropic, r: ReturnType<typeof rig>) => Promise<void>) {
  const mock = startMockAnthropic();
  const r = rig({ provider: mockedProvider(mock.url) });
  r.store.addUser("user-1", "Maya", "UTC");
  try {
    await run(mock, r);
    await r.settle();
  } finally {
    await mock.close();
  }
}

const withoutModel = (name: string) => {
  const value = fixtureJson(name);
  delete value.model;
  return value;
};

Deno.test("generate: one Messages call to Claude Haiku 5.5 with a structured output, the pages as numbered lines", async () => {
  await withMock(async (mock, r) => {
    mock.answer(
      messageJson(withoutModel("generate"), { thinking: true, usage: { input_tokens: 3100, output_tokens: 2900 } }),
    );
    const res = await r.ai("generate", { body: fixtureJson("requests/generate") });
    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(validate(contractSchema("GenerateResponse"), body), []);
    assertEquals(body.model, "claude-haiku-5-5");
    assertEquals(body.items.length, 16);

    assertEquals(mock.requests.length, 1);
    const { path, search, headers, body: sent } = mock.requests[0];
    assertEquals(path + search, "/v1/messages", "Haiku has no server-side fallback: the plain Messages API");
    assertEquals(headers["authorization"], `Bearer ${TEST_API_KEY}`, "SDK 1.x sends the key as a bearer token");
    assertEquals(headers["anthropic-version"], "2026-10-21");
    assertEquals(headers["anthropic-beta"], undefined);
    assertEquals(sent.model, "claude-haiku-5-5");
    assertEquals(sent.max_tokens, 16000);
    assertEquals(sent.output_config, {
      effort: "medium",
      format: { type: "json_schema", schema: providerSchema("GenerateResponse") },
    });
    for (const key of ["temperature", "top_p", "top_k", "thinking", "stream", "fallbacks"]) assert(!(key in sent), key);
    assertEquals(sent.system.length, 1);
    assertEquals(sent.system[0].cache_control, { type: "ephemeral" });
    assertStringIncludes(sent.system[0].text, "Use only the material in this request");
    assertStringIncludes(sent.system[0].text, "Task: turn pages of a student's class material into practice questions");
    assertEquals(sent.messages.length, 1);
    assertEquals(sent.messages[0].role, "user");
    const text = sent.messages[0].content.map((b: { text?: string }) => b.text ?? "").join("\n");
    assertStringIncludes(text, '<page index="0" label="87">');
    assertStringIncludes(
      text,
      "[p0.l3] Mitosis is the process by which a single eukaryotic cell divides to produce two",
    );
    assertStringIncludes(text, "Formats: recall, apply, mcq, cloze, diagram, flashcard");
    assertStringIncludes(text, "maxItems: 16");
  });
  // The cost row: 3,100 in and 2,900 out on Haiku 5.5.
});

Deno.test("generate: the page photo goes first, as a base64 image block", async () => {
  await withMock(async (mock, r) => {
    mock.answer(messageJson(withoutModel("generate")));
    const request = fixtureJson("requests/generate");
    request.pages[0].image = "/9j/4AAQSkZJRgABAQAAAQABAAD";
    await (await r.ai("generate", { body: request })).body?.cancel();
    const content = mock.requests[0].body.messages[0].content;
    assertEquals(content[0], {
      type: "image",
      source: { type: "base64", media_type: "image/jpeg", data: "/9j/4AAQSkZJRgABAQAAAQABAAD" },
    });
  });
});

Deno.test("grade: apply questions and long answers go to Claude Sonnet 5.5 with server-side fallback", async () => {
  await withMock(async (mock, r) => {
    mock.answer(messageJson(withoutModel("grade-partial"), { model: "claude-sonnet-5-5" }));
    const res = await r.ai("grade", { body: { ...fixtureJson("requests/grade"), kind: "apply" } });
    const body = await res.json();
    assertEquals(body.model, "claude-sonnet-5-5");
    const { path, search, headers, body: sent } = mock.requests[0];
    assertEquals(path + search, "/v1/messages?beta=true");
    assertStringIncludes(headers["anthropic-beta"], "server-side-fallback-2026-07-01");
    assertEquals(sent.fallbacks, "default");
    assertEquals(sent.model, "claude-sonnet-5-5");
    assertEquals(sent.output_config.effort, "medium");
    assertEquals(sent.output_config.format.schema, providerSchema("GradeResponse"));
    assert(!("betas" in sent), "betas travel as a header, not in the body");

    mock.answer(messageJson(withoutModel("grade-correct")));
    const long = "So the body can grow and repair tissue. ".repeat(20);
    await (await r.ai("grade", { body: { ...fixtureJson("requests/grade"), response: long } })).body?.cancel();
    assertEquals(mock.requests[1].body.model, "claude-sonnet-5-5");

    mock.answer(messageJson(withoutModel("grade-partial")));
    const short = await (await r.ai("grade", { body: fixtureJson("requests/grade") })).json();
    assertEquals(short.model, "claude-haiku-5-5");
    assertEquals(mock.requests[2].path + mock.requests[2].search, "/v1/messages");
    assertEquals(mock.requests[2].body.output_config.effort, "low");
    const prompt = mock.requests[2].body.messages[0].content[0].text;
    assertStringIncludes(
      prompt,
      "<student_answer>So the body can grow and repair tissue, making two identical cells.</student_answer>",
    );
    assertStringIncludes(prompt, '"id": "k3"');
  });
});

Deno.test("tutor: a streamed beta call over search results with citations, read as the contract's events", async () => {
  await withMock(async (mock, r) => {
    mock.answer(messageStream([
      { text: "Let's work it out from your page. " },
      {
        cite: {
          source: "s1",
          title: "Biology textbook · Textbook p. 87",
          cited_text: "During mitosis, the genetic material (DNA) is copied and equally separated into two new nuclei.",
        },
      },
      { text: "What does the page say is divided in cytokinesis?" },
    ]));
    const res = await r.ai("tutor", { body: fixtureJson("requests/tutor") });
    assertEquals(res.status, 200);
    const events = await sseEvents(res);
    assertEquals(events, [
      { event: "start", data: { model: "claude-sonnet-5-5" } },
      { event: "delta", data: { text: "Let's work it out from your page. " } },
      {
        event: "citation",
        data: {
          sourceId: "s1",
          label: "Textbook p. 87",
          quote: "During mitosis, the genetic material (DNA) is copied and equally separated into two new nuclei.",
        },
      },
      { event: "delta", data: { text: "What does the page say is divided in cytokinesis?" } },
      { event: "done", data: { model: "claude-sonnet-5-5" } },
    ]);

    const { path, search, headers, body: sent } = mock.requests[0];
    assertEquals(path + search, "/v1/messages?beta=true");
    assertStringIncludes(headers["anthropic-beta"], "server-side-fallback-2026-07-01");
    assertEquals(sent.stream, true);
    assertEquals(sent.model, "claude-sonnet-5-5");
    assertEquals(sent.fallbacks, "default");
    assertEquals(sent.output_config, { effort: "low" });
    assertStringIncludes(sent.system[0].text, "You are Cap");
    const last = sent.messages.at(-1);
    assertEquals(last.role, "user");
    const result = last.content[0];
    assertEquals(result.type, "search_result");
    assertEquals(result.source, "s1");
    assertEquals(result.title, "Biology textbook · Textbook p. 87");
    assertEquals(result.citations, { enabled: true });
    assert(result.content.length > 5, "the passage is split into sentence blocks for tight citations");
    assert(
      result.content.some((b: { text: string }) =>
        b.text === "During mitosis, the genetic material (DNA) is copied and equally separated into two new nuclei."
      ),
    );
    assertEquals(last.content.at(-1), { type: "text", text: "What's the difference between mitosis and cytokinesis?" });
  });
});

Deno.test("tutor: earlier turns go as plain text, and 'Explain my mistake' adds the question", async () => {
  await withMock(async (mock, r) => {
    mock.answer(messageStream([{ text: "Sure." }]));
    const request = {
      ...fixtureJson("requests/tutor"),
      messages: [
        { role: "assistant", text: "Hi! Ask me about your notes." },
        { role: "user", text: "What is anaphase?" },
        { role: "assistant", text: "It's when chromatids are pulled apart." },
        { role: "user", text: "Why did I get it wrong?" },
      ],
      context: { itemPrompt: "Describe anaphase.", expected: "Chromatids pulled apart.", given: "Envelopes form." },
    };
    await sseEvents(await r.ai("tutor", { body: request }));
    const messages = mock.requests[0].body.messages;
    assertEquals(messages.slice(0, 2), [
      { role: "user", content: "What is anaphase?" },
      { role: "assistant", content: "It's when chromatids are pulled apart." },
    ]);
    const texts = messages[2].content.filter((b: { type: string }) => b.type === "text").map((b: { text: string }) =>
      b.text
    );
    assertStringIncludes(texts[0], "<their_answer>Envelopes form.</their_answer>");
    assertEquals(texts.at(-1), "Why did I get it wrong?");
  });
});

Deno.test("tutor: an error event from the model becomes the contract's error event", async () => {
  await withMock(async (mock, r) => {
    mock.answer(messageStream([{ text: "Partly" }, { error: { type: "overloaded_error", message: "Overloaded" } }]));
    const events = await sseEvents(await r.ai("tutor", { body: fixtureJson("requests/tutor") }));
    assertEquals(events.map((e) => e.event), ["start", "delta", "error"]);
    assertEquals(events[2].data.code, "upstream");
  });
});

Deno.test("transcribe-image sends the photo; the relay numbers the lines", async () => {
  await withMock(async (mock, r) => {
    mock.answer(messageJson({ lines: [{ id: "a", text: "Mitosis notes" }, { id: "b", text: "PMAT" }] }));
    const res = await r.ai("transcribe-image", { body: { image: "/9j/4AAQSkZJRgABAQAAAQABAAD", page: 0, label: "1" } });
    assertEquals(await res.json(), {
      model: "claude-haiku-5-5",
      lines: [{ id: "p0.c0", text: "Mitosis notes" }, { id: "p0.c1", text: "PMAT" }],
    });
    const content = mock.requests[0].body.messages[0].content;
    assertEquals(content[0].type, "image");
    assertEquals(mock.requests[0].body.output_config.effort, "low");
  });
});

Deno.test("check, confusions, lecture and cards use Claude Haiku 5.5 with their own schemas", async () => {
  await withMock(async (mock, r) => {
    const pages = fixtureJson("requests/generate").pages;
    const items = fixtureJson("generate").items.slice(0, 2);
    mock.answer(
      messageJson({
        verdicts: [{ id: "i1", verdict: "supported", reason: "On the page." }, {
          id: "i2",
          verdict: "supported",
          reason: "Yes.",
        }],
      }),
    );
    const check = await (await r.ai("check", { body: { pages, items } })).json();
    assertEquals(check.verdicts.length, 2);
    const checkText = mock.requests[0].body.messages[0].content.map((b: { text: string }) => b.text).join("\n");
    assertStringIncludes(checkText, "[p0.l36]", "the lines the items anchor to");
    assert(!checkText.includes("[p0.l0]"), "only the anchored lines");

    mock.answer(messageJson(withoutModel("confusions")));
    const mistakes = ["i4", "i11"].map((itemId) => ({
      itemId,
      topic: "T",
      prompt: "P",
      expected: "E",
      given: "G",
      misses: 2,
    }));
    await (await r.ai("confusions", { body: { course: "Bio", mistakes } })).body?.cancel();
    mock.answer(messageJson(withoutModel("lecture")));
    const segments = ["s3", "s4", "s5"].map((id, i) => ({ id, start: i * 400, end: i * 400 + 300, text: "…" }));
    await (await r.ai("lecture", {
      body: { course: "Bio", title: "Lecture 6", segments, flags: [{ time: 725, text: "midterm" }], maxItems: 6 },
    })).body?.cancel();
    mock.answer(messageJson(withoutModel("cards-from-chat")));
    await (await r.ai("cards-from-chat", { body: { messages: [{ role: "user", text: "Hi" }], maxItems: 4 } })).body
      ?.cancel();

    const schemas = ["CheckResponse", "ConfusionsResponse", "LectureResponse", "CardsFromChatResponse"];
    for (const [i, name] of schemas.entries()) {
      const sent = mock.requests[i].body;
      assertEquals(sent.model, "claude-haiku-5-5", name);
      assertEquals(sent.output_config.format.schema, providerSchema(name), name);
    }
    assertStringIncludes(mock.requests[2].body.messages[0].content[0].text, "[s4 6:40–11:40] …");
    assertStringIncludes(mock.requests[2].body.messages[0].content[0].text, "[12:05 = 725 s] midterm");
  });
});

Deno.test("a reply after a server-side fallback is read the same way, and names the model that answered", async () => {
  await withMock(async (mock, r) => {
    const reply = messageJson(withoutModel("grade-partial"), { model: "claude-sonnet-5" }) as {
      json: { content: unknown[] };
    };
    reply.json.content.unshift({
      type: "fallback",
      from: { model: "claude-sonnet-5-5" },
      to: { model: "claude-sonnet-5" },
    });
    mock.answer(reply);
    const body = await (await r.ai("grade", { body: { ...fixtureJson("requests/grade"), kind: "apply" } })).json();
    assertEquals(body.model, "claude-sonnet-5");
    assertEquals(body.hits.length, 2);
  });
});

Deno.test("provider failures are `upstream` errors and give the quota back", async () => {
  await withMock(async (mock, r) => {
    const cases: [Parameters<MockAnthropic["answer"]>[0], number, string][] = [
      [
        { status: 429, error: { type: "rate_limit_error", message: "slow down" }, headers: { "retry-after": "7" } },
        503,
        "Cap is busy",
      ],
      [{ status: 529, error: { type: "overloaded_error", message: "Overloaded" } }, 503, "Cap is busy"],
      [{ status: 500, error: { type: "api_error", message: "boom" } }, 503, "Cap is busy"],
      [{ status: 400, error: { type: "invalid_request_error", message: "bad" } }, 502, "couldn't answer"],
      [messageJson({}, { stop: "refusal" }), 422, "can't help"],
      [messageJson({}, { stop: "max_tokens", raw: '{"score": 0.5, "verd' }), 502, "cut off"],
      [messageJson({}, { raw: "not json" }), 502, "unreadable"],
      [messageJson({ score: 0.5 }), 502, "didn't match the contract"],
    ];
    for (const [answer, status, words] of cases) {
      mock.answer(answer);
      const res = await r.ai("grade", { body: fixtureJson("requests/grade") });
      assertEquals(res.status, status, words);
      const error = await errorOf(res);
      assertEquals(error.code, "upstream");
      assertStringIncludes(error.message, words);
    }
    const first = await r.ai("grade", { body: fixtureJson("requests/grade"), headers: {} });
    await first.body?.cancel();
    assertEquals(r.store.used("user-1", "grades", "2026-10-22"), 0, "every failed grade was given back");
  });
});

Deno.test("a 429 says when to retry", async () => {
  await withMock(async (mock, r) => {
    mock.answer({
      status: 429,
      error: { type: "rate_limit_error", message: "slow down" },
      headers: { "retry-after": "7" },
    });
    const res = await r.ai("grade", { body: fixtureJson("requests/grade") });
    assertEquals((await errorOf(res)).retryAfter, 7);
    assertEquals(res.headers.get("retry-after"), "7");
  });
});

Deno.test("real mode without a key answers upstream, and the mock refuses a malformed request", async () => {
  const r = rig({ env: { ANTHROPIC_API_KEY: "" }, provider: undefined });
  r.store.addUser("user-1");
  const { defaultDeps } = await import("../_shared/deps.ts");
  const deps = defaultDeps({ env: r.deps.env, store: r.store, authenticate: r.deps.authenticate, now: r.deps.now });
  assertEquals(r.deps.env.faults.includes("anthropic_key_missing"), true);
  const { aiHandler } = await import("../ai/handler.ts");
  const res = await aiHandler(deps)(
    new Request("http://localhost/functions/v1/ai/grade", {
      method: "POST",
      headers: { authorization: "Bearer token-user-1" },
      body: JSON.stringify(fixtureJson("requests/grade")),
    }),
  );
  assertEquals(res.status, 503);
  assertEquals((await errorOf(res)).message, "Cloud AI isn't set up on this server.");

  const mock = startMockAnthropic();
  try {
    const bad = await fetch(`${mock.url}/v1/messages`, {
      method: "POST",
      headers: { "x-api-key": TEST_API_KEY, "anthropic-version": "2026-10-21", "content-type": "application/json" },
      body: JSON.stringify({
        model: "claude-haiku-5-5",
        max_tokens: 10,
        temperature: 0,
        messages: [{ role: "user", content: "x" }],
      }),
    });
    assertEquals(bad.status, 400);
    assertStringIncludes((await bad.json()).error.message, "temperature");
  } finally {
    await mock.close();
  }
});
