// The JSON routes on OpenAI, end to end without a key: the relay's handlers with the OpenAI provider pointed at a local
// mock of the Responses API, which checks each request's shape (a strict structured output, nothing stored, not streamed)
// and answers with canned whole responses.

import { assert, assertEquals, assertStringIncludes } from "@std/assert";
import { TERRA } from "../_shared/cost.ts";
import { defaultDeps } from "../_shared/deps.ts";
import { OpenAIProvider, strictSchema, withoutNulls } from "../_shared/openai.ts";
import { contractSchema, providerSchema } from "../_shared/schemas.ts";
import { validate } from "../_shared/schema.ts";
import { errorOf, fixtureJson, mockedProvider, rig } from "./_harness.ts";
import {
  type MockOpenAI,
  type MockOpenAIAnswer,
  replyJsonResponse,
  startMockOpenAI,
  TEST_OPENAI_KEY,
} from "./_mock_openai.ts";

async function withMock(run: (mock: MockOpenAI, r: ReturnType<typeof rig>) => Promise<void>) {
  const mock = startMockOpenAI();
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

const textOf = (sent: { input: { content: { text?: string }[] }[] }) =>
  sent.input[0].content.map((p) => p.text ?? "").join("\n");

Deno.test("generate: one Responses call to Terra with a strict structured output, the pages as numbered lines", async () => {
  await withMock(async (mock, r) => {
    mock.answer(replyJsonResponse(withoutModel("generate"), { usage: { input: 3100, output: 2900 } }));
    const res = await r.ai("generate", { body: fixtureJson("requests/generate") });
    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(validate(contractSchema("GenerateResponse"), body), []);
    assertEquals(body.model, TERRA);
    assertEquals(body.items.length, 16);

    assertEquals(mock.requests.length, 1);
    const { path, headers, body: sent } = mock.requests[0];
    assertEquals(path, "/v1/responses");
    assertEquals(headers["authorization"], `Bearer ${TEST_OPENAI_KEY}`);
    assertEquals(sent.model, TERRA);
    assertEquals(sent.max_output_tokens, 16000);
    assertEquals(sent.reasoning, { effort: "medium" });
    assertEquals(sent.store, false, "nothing is kept at OpenAI");
    assertEquals(sent.text.format.type, "json_schema");
    assertEquals(sent.text.format.strict, true);
    assertEquals(sent.text.format.schema, strictSchema(providerSchema("GenerateResponse")));
    for (const key of ["temperature", "top_p", "stream", "tools", "previous_response_id"]) assert(!(key in sent), key);
    assertStringIncludes(sent.instructions, "Use only the material in this request");
    assertStringIncludes(sent.instructions, "Task: turn pages of a student's class material into practice questions");
    assertEquals(sent.input.length, 1);
    assertEquals(sent.input[0].role, "user");
    const text = textOf(sent);
    assertStringIncludes(text, '<page index="0" label="87">');
    assertStringIncludes(
      text,
      "[p0.l3] Mitosis is the process by which a single eukaryotic cell divides to produce two",
    );
    assertStringIncludes(text, "Formats: recall, apply, mcq, cloze, diagram, flashcard");
    assertStringIncludes(text, "maxItems: 16");

    await r.settle();
    const row = r.store.requests.at(-1)!;
    assertEquals([row.route, row.model, row.inputTokens, row.outputTokens, row.status], [
      "generate",
      TERRA,
      3100,
      2900,
      200,
    ]);
    assertEquals(row.costUsd, "0.017600000", "3,100 in at $1 and 2,900 out at $5 per million");
  });
});

Deno.test("strict schemas: every property required, the optional ones nullable; the reply is read back without its nulls", () => {
  for (const name of ["GenerateResponse", "CheckResponse", "GradeResponse", "TranscribeImageResponse"]) {
    const plain = providerSchema(name);
    const strict = strictSchema(plain);
    // deno-lint-ignore no-explicit-any
    const walk = (node: any, original: any) => {
      if (!node || typeof node !== "object") return;
      if (node.properties) {
        assertEquals(node.required, Object.keys(node.properties), name);
        assertEquals(node.additionalProperties, false, name);
        for (const key of Object.keys(node.properties)) {
          const optional = !(original.required ?? []).includes(key);
          assertEquals("anyOf" in node.properties[key], optional, `${name}.${key}`);
          walk(optional ? node.properties[key].anyOf[0] : node.properties[key], original.properties[key]);
        }
      }
      if (node.items) walk(node.items, original.items);
      for (const [k, v] of Object.entries(node.$defs ?? {})) walk(v, original.$defs[k]);
    };
    walk(strict, plain);
  }
  assertEquals(withoutNulls({ a: 1, b: null, c: [{ d: null, e: 2 }, null] }), { a: 1, c: [{ e: 2 }, null] });
  // The input is not changed.
  const plain = providerSchema("GenerateResponse");
  const before = JSON.stringify(plain);
  strictSchema(plain);
  assertEquals(JSON.stringify(plain), before);
});

Deno.test("generate: optional fields the model writes as null are dropped before the reply is checked", async () => {
  await withMock(async (mock, r) => {
    const reply = withoutModel("generate");
    for (const item of reply.items) {
      item.cloze = null;
      item.diagramLabels = null;
      for (const choice of item.choices) choice.why = null;
    }
    mock.answer(replyJsonResponse(reply));
    const res = await r.ai("generate", { body: fixtureJson("requests/generate") });
    assertEquals(res.status, 200);
    const body = await res.json();
    assertEquals(validate(contractSchema("GenerateResponse"), body), []);
    assert(body.items.every((i: Record<string, unknown>) => !("cloze" in i && i.cloze === null)));
  });
});

Deno.test("generate: the page photo goes first, as a base64 data URL", async () => {
  await withMock(async (mock, r) => {
    mock.answer(replyJsonResponse(withoutModel("generate")));
    const request = fixtureJson("requests/generate");
    request.pages[0].image = "/9j/4AAQSkZJRgABAQAAAQABAAD";
    await (await r.ai("generate", { body: request })).body?.cancel();
    assertEquals(mock.requests[0].body.input[0].content[0], {
      type: "input_image",
      image_url: "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQAAAQABAAD",
    });
  });
});

Deno.test("grade: apply questions and long answers think harder; every grade runs on Terra", async () => {
  await withMock(async (mock, r) => {
    mock.answer(replyJsonResponse(withoutModel("grade-partial")));
    const res = await r.ai("grade", { body: { ...fixtureJson("requests/grade"), kind: "apply" } });
    assertEquals((await res.json()).model, TERRA);
    const sent = mock.requests[0].body;
    assertEquals(sent.model, TERRA);
    assertEquals(sent.reasoning, { effort: "medium" });
    assertEquals(sent.max_output_tokens, 8000);
    assertEquals(sent.text.format.schema, strictSchema(providerSchema("GradeResponse")));

    mock.answer(replyJsonResponse(withoutModel("grade-correct")));
    const long = "So the body can grow and repair tissue. ".repeat(20);
    await (await r.ai("grade", { body: { ...fixtureJson("requests/grade"), response: long } })).body?.cancel();
    assertEquals(mock.requests[1].body.reasoning, { effort: "medium" });

    mock.answer(replyJsonResponse(withoutModel("grade-partial")));
    const short = await (await r.ai("grade", { body: fixtureJson("requests/grade") })).json();
    assertEquals(short.model, TERRA);
    assertEquals(mock.requests[2].body.reasoning, { effort: "low" });
    assertEquals(mock.requests[2].body.max_output_tokens, 6000);
    const prompt = textOf(mock.requests[2].body);
    assertStringIncludes(
      prompt,
      "<student_answer>So the body can grow and repair tissue, making two identical cells.</student_answer>",
    );
    assertStringIncludes(prompt, '"id": "k3"');
  });
});

Deno.test("transcribe-image sends the photo; the relay numbers the lines", async () => {
  await withMock(async (mock, r) => {
    mock.answer(replyJsonResponse({ lines: [{ id: "a", text: "Mitosis notes" }, { id: "b", text: "PMAT" }] }));
    const res = await r.ai("transcribe-image", { body: { image: "/9j/4AAQSkZJRgABAQAAAQABAAD", page: 0, label: "1" } });
    assertEquals(await res.json(), {
      model: TERRA,
      lines: [{ id: "p0.c0", text: "Mitosis notes" }, { id: "p0.c1", text: "PMAT" }],
    });
    const sent = mock.requests[0].body;
    assertEquals(sent.input[0].content[0].type, "input_image");
    assertEquals(sent.input[0].content[1].type, "input_text");
    assertEquals(sent.reasoning, { effort: "low" });
  });
});

Deno.test("a PNG photo is sent with its own media type", async () => {
  await withMock(async (mock, r) => {
    mock.answer(replyJsonResponse({ lines: [{ id: "a", text: "x" }] }));
    await (await r.ai("transcribe-image", { body: { image: "iVBORw0KGgoAAAANSUhEUg", page: 0, label: "1" } })).json();
    assertStringIncludes(mock.requests[0].body.input[0].content[0].image_url, "data:image/png;base64,iVBORw0KGgo");
  });
});

Deno.test("check, confusions, lecture and cards run on Terra with their own schemas", async () => {
  await withMock(async (mock, r) => {
    const pages = fixtureJson("requests/generate").pages;
    const items = fixtureJson("generate").items.slice(0, 2);
    mock.answer(
      replyJsonResponse({
        verdicts: [{ id: "i1", verdict: "supported", reason: "On the page." }, {
          id: "i2",
          verdict: "supported",
          reason: "Yes.",
        }],
      }),
    );
    const check = await (await r.ai("check", { body: { pages, items } })).json();
    assertEquals(check.verdicts.length, 2);
    const checkText = textOf(mock.requests[0].body);
    assertStringIncludes(checkText, "[p0.l36]", "the lines the items anchor to");
    assert(!checkText.includes("[p0.l0]"), "only the anchored lines");

    mock.answer(replyJsonResponse(withoutModel("confusions")));
    const mistakes = ["i4", "i11"].map((itemId) => ({
      itemId,
      topic: "T",
      prompt: "P",
      expected: "E",
      given: "G",
      misses: 2,
    }));
    await (await r.ai("confusions", { body: { course: "Bio", mistakes } })).body?.cancel();
    mock.answer(replyJsonResponse(withoutModel("lecture")));
    const segments = ["s3", "s4", "s5"].map((id, i) => ({ id, start: i * 400, end: i * 400 + 300, text: "…" }));
    await (await r.ai("lecture", {
      body: { course: "Bio", title: "Lecture 6", segments, flags: [{ time: 725, text: "midterm" }], maxItems: 6 },
    })).body?.cancel();
    mock.answer(replyJsonResponse(withoutModel("cards-from-chat")));
    await (await r.ai("cards-from-chat", { body: { messages: [{ role: "user", text: "Hi" }], maxItems: 4 } })).body
      ?.cancel();

    const schemas = ["CheckResponse", "ConfusionsResponse", "LectureResponse", "CardsFromChatResponse"];
    for (const [i, name] of schemas.entries()) {
      const sent = mock.requests[i].body;
      assertEquals(sent.model, TERRA, name);
      assertEquals(sent.text.format.schema, strictSchema(providerSchema(name)), name);
    }
    assertStringIncludes(textOf(mock.requests[2].body), "[s4 6:40–11:40] …");
    assertStringIncludes(textOf(mock.requests[2].body), "[12:05 = 725 s] midterm");
  });
});

Deno.test("a reply that names a dated snapshot is read the same way, and names the model that answered", async () => {
  await withMock(async (mock, r) => {
    mock.answer(replyJsonResponse(withoutModel("grade-partial"), { model: "gpt-6.1-terra-2026-10-13" }));
    const body = await (await r.ai("grade", { body: { ...fixtureJson("requests/grade"), kind: "apply" } })).json();
    assertEquals(body.model, "gpt-6.1-terra-2026-10-13");
    assertEquals(body.hits.length, 2);
  });
});

Deno.test("provider failures are `upstream` errors, give the quota back, and the tokens of a wasted reply still count", async () => {
  await withMock(async (mock, r) => {
    const cases: [MockOpenAIAnswer, number, string][] = [
      [
        {
          status: 429,
          error: { type: "rate_limit_error", message: "slow down", code: "rate_limit_exceeded" },
          headers: { "retry-after": "7" },
        },
        503,
        "Cap is busy",
      ],
      [{ status: 503, error: { type: "server_error", message: "Overloaded" } }, 503, "Cap is busy"],
      [{ status: 500, error: { type: "server_error", message: "boom" } }, 503, "Cap is busy"],
      [{ status: 400, error: { type: "invalid_request_error", message: "bad" } }, 502, "couldn't answer"],
      [{ response: { status: "failed", error: { code: "server_error", message: "x" } } }, 503, "Cap is busy"],
      [replyJsonResponse({}, { refusal: "I can't help with that." }), 422, "can't help"],
      [replyJsonResponse({}, { reason: "content_filter", raw: "" }), 422, "can't help"],
      [replyJsonResponse({}, { reason: "max_output_tokens", raw: '{"score": 0.5, "verd' }), 502, "cut off"],
      [replyJsonResponse({}, { raw: "not json" }), 502, "unreadable"],
      [replyJsonResponse({ score: 0.5 }), 502, "didn't match the contract"],
      [{ response: { status: "completed", model: TERRA, output: [] } }, 502, "came back empty"],
    ];
    for (const [answer, status, words] of cases) {
      mock.answer(answer);
      const res = await r.ai("grade", { body: fixtureJson("requests/grade") });
      assertEquals(res.status, status, words);
      const error = await errorOf(res);
      assertEquals(error.code, "upstream");
      assertStringIncludes(error.message, words);
    }
    assertEquals(r.store.used("user-1", "grades", "2026-10-22"), 0, "every failed grade was given back");
    await r.settle();
    // The unreadable reply and the one that didn't match were billed all the same (900 in, 150 out each).
    const billed = r.store.requests.filter((row) => row.outputTokens > 0);
    assertEquals(billed.length, 5, "cut off, filtered by content, refused, unreadable and not matching");
    assert(billed.every((row) => row.costUsd !== "0.000000000"));
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

Deno.test("a busy model is tried once more before the person sees an error", async () => {
  const mock = startMockOpenAI();
  try {
    const provider = new OpenAIProvider({
      apiKey: TEST_OPENAI_KEY,
      baseURL: `${mock.url}/v1`,
      maxRetries: 1,
      retryDelayMs: 0,
    });
    const r = rig({ provider });
    r.store.addUser("user-1");
    mock.answer({ status: 503, error: { type: "server_error", message: "Overloaded" } });
    mock.answer(replyJsonResponse(withoutModel("grade-partial")));
    const res = await r.ai("grade", { body: fixtureJson("requests/grade") });
    assertEquals(res.status, 200);
    assertEquals(mock.requests.length, 2);
    await r.settle();
  } finally {
    await mock.close();
  }
});

Deno.test("real mode without a key answers upstream, and the mock refuses a malformed request", async () => {
  const r = rig({ env: { OPENAI_API_KEY: "" }, provider: undefined });
  r.store.addUser("user-1");
  const deps = defaultDeps({ env: r.deps.env, store: r.store, authenticate: r.deps.authenticate, now: r.deps.now });
  assertEquals(r.deps.env.faults.includes("openai_key_missing"), true);
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

  const mock = startMockOpenAI();
  try {
    const send = (extra: Record<string, unknown>) =>
      fetch(`${mock.url}/v1/responses`, {
        method: "POST",
        headers: { authorization: `Bearer ${TEST_OPENAI_KEY}`, "content-type": "application/json" },
        body: JSON.stringify({
          model: TERRA,
          instructions: "s",
          input: [{ role: "user", content: [{ type: "input_text", text: "x" }] }],
          reasoning: { effort: "low" },
          max_output_tokens: 10,
          store: false,
          text: {
            format: {
              type: "json_schema",
              name: "result",
              strict: true,
              schema: strictSchema(providerSchema("GradeResponse")),
            },
          },
          ...extra,
        }),
      });
    const bad = await send({ temperature: 0 });
    assertEquals(bad.status, 400);
    assertStringIncludes((await bad.json()).error.message, "temperature");
    // A schema with a keyword strict mode doesn't take, or a property left optional, is refused too.
    const long = await send({
      text: {
        format: {
          type: "json_schema",
          name: "result",
          strict: true,
          schema: {
            type: "object",
            properties: { a: { type: "string", maxLength: 5 } },
            required: ["a"],
            additionalProperties: false,
          },
        },
      },
    });
    assertEquals(long.status, 400);
    assertStringIncludes((await long.json()).error.message, "maxLength");
    const loose = await send({
      text: {
        format: {
          type: "json_schema",
          name: "result",
          strict: true,
          schema: { type: "object", properties: { a: { type: "string" } }, required: [], additionalProperties: false },
        },
      },
    });
    assertEquals(loose.status, 400);
    assertStringIncludes((await loose.json()).error.message, "required");
  } finally {
    await mock.close();
  }
});
