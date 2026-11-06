// Routing, authentication and the error envelope, for both functions.

import { assert, assertEquals } from "@std/assert";
import { goTrueAuthenticator } from "../_shared/auth.ts";
import { ApiError } from "../_shared/errors.ts";
import { routeOf } from "../_shared/http.ts";
import { createAdmin } from "../_shared/store_postgres.ts";
import { contractSchema } from "../_shared/schemas.ts";
import { validate } from "../_shared/schema.ts";
import { errorOf, fixtureJson, logLines, rig } from "./_harness.ts";

Deno.test("routeOf takes the path after the function's name", () => {
  assertEquals(routeOf("http://x/functions/v1/ai/generate", "ai"), "/generate");
  assertEquals(routeOf("http://x/ai/cards-from-chat?x=1", "ai"), "/cards-from-chat");
  assertEquals(routeOf("http://x/functions/v1/account/squad/invite", "account"), "/squad/invite");
  assertEquals(routeOf("http://x/functions/v1/ai", "ai"), "/");
});

Deno.test("unknown routes and wrong methods answer in the error envelope", async () => {
  const r = rig({ env: { CRAMLESS_MOCK: "1" } });
  r.store.addUser("user-1");
  for (
    const [res, status] of [
      [await r.ai("nope", { body: {} }), 404],
      [await r.ai("generate"), 405],
      [await r.ai("quota", { method: "POST", body: {} }), 405],
      [await r.account("squad/nope", { body: {} }), 404],
      [await r.account("delete"), 405],
    ] as [Response, number][]
  ) {
    assertEquals(res.status, status);
    const body = await res.json();
    assertEquals(validate(contractSchema("RelayErrorBody"), body), []);
    assertEquals(body.error.code, "bad_request");
  }
});

Deno.test("every route needs a session; a deleted account is refused", async () => {
  const r = rig({ env: { CRAMLESS_MOCK: "1" } });
  r.store.addUser("user-1");
  for (
    const path of [
      "generate",
      "check",
      "grade",
      "tutor",
      "confusions",
      "lecture",
      "cards-from-chat",
      "transcribe-image",
      "syllabus",
      "exam-mention",
      "last-look",
    ]
  ) {
    const res = await r.ai(path, { user: null, body: {} });
    assertEquals(res.status, 401, path);
    assertEquals((await errorOf(res)).code, "unauthorized");
  }
  assertEquals((await r.ai("quota", { user: null })).status, 401);
  assertEquals((await r.account("entitlements", { user: null })).status, 401);
  const deleted = await r.ai("quota", { user: "ghost" });
  assertEquals(deleted.status, 401);
  assertEquals((await errorOf(deleted)).message, "This account was deleted.");
});

Deno.test("anonymous sessions use the relay like any other", async () => {
  const r = rig({ env: { CRAMLESS_MOCK: "1" }, anonymous: new Set(["anon-1"]) });
  r.store.addUser("anon-1");
  const res = await r.ai("grade", { user: "anon-1", body: fixtureJson("requests/grade") });
  assertEquals(res.status, 200);
});

Deno.test("a body that isn't JSON, or is too large, is a bad request", async () => {
  const r = rig({ env: { CRAMLESS_MOCK: "1" } });
  r.store.addUser("user-1");
  const notJson = await r.ai("grade", { method: "POST", rawBody: "{nope" });
  assertEquals(notJson.status, 400);
  assertEquals((await errorOf(notJson)).message, "The body isn't valid JSON.");
  const big = await r.ai("grade", { method: "POST", rawBody: JSON.stringify({ pad: "x".repeat(300 * 1024) }) });
  assertEquals(big.status, 413);
  assertEquals((await errorOf(big)).code, "bad_request");
});

Deno.test("unexpected failures are a bare 500 that says nothing about the cause", async () => {
  const r = rig({ env: { CRAMLESS_MOCK: "1" } });
  r.store.addUser("user-1");
  r.store.context = () => Promise.reject(new Error("connection refused at 10.0.0.3"));
  const res = await r.ai("quota");
  assertEquals(res.status, 500);
  const error = await errorOf(res);
  assertEquals(error.code, "upstream");
  assert(!error.message.includes("10.0.0.3"));
});

Deno.test("log lines carry no content, ids or tokens", async () => {
  const r = rig({ env: { CRAMLESS_MOCK: "1" } });
  r.store.addUser("user-secret-id");
  logLines.length = 0;
  await r.ai("grade", { user: "user-secret-id", body: fixtureJson("requests/grade") });
  await r.settle();
  const line = logLines.join("\n");
  assert(line.includes('"route":"/grade"'));
  assert(!line.includes("user-secret-id"));
  assert(!line.includes("token-"));
  assert(!line.includes("repair tissue"), "no answer text");
});

Deno.test("the GoTrue authenticator checks the token with Auth and caches the answer", async () => {
  let calls = 0;
  const fakeFetch: typeof fetch = (input, init) => {
    const url = String(input instanceof Request ? input.url : input);
    calls++;
    const given = (init as { headers?: HeadersInit } | undefined)?.headers;
    const auth = new Headers(given ?? (input instanceof Request ? input.headers : undefined)).get("authorization");
    if (!url.endsWith("/auth/v1/user") || auth !== "Bearer good-token") {
      return Promise.resolve(new Response(JSON.stringify({ code: 401, msg: "invalid JWT" }), { status: 401 }));
    }
    return Promise.resolve(
      new Response(
        JSON.stringify({
          id: "1B4E28BA-2FA1-11D2-883F-0016D3CCA427",
          aud: "authenticated",
          role: "authenticated",
          is_anonymous: true,
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      ),
    );
  };
  const admin = createAdmin("http://127.0.0.1:58421", "service-role-key", fakeFetch);
  let clock = 1_000_000;
  const authenticate = goTrueAuthenticator(admin, () => clock);
  const req = () => new Request("http://x/ai/quota", { headers: { authorization: "Bearer good-token" } });
  const caller = await authenticate(req());
  assertEquals(caller, { userId: "1b4e28ba-2fa1-11d2-883f-0016d3cca427", isAnonymous: true, email: null });
  await authenticate(req());
  assertEquals(calls, 1, "cached for a minute");
  clock += 61_000;
  await authenticate(req());
  assertEquals(calls, 2);
  const refused = await authenticate(new Request("http://x", { headers: { authorization: "Bearer bad" } })).catch((e) =>
    e
  );
  assert(refused instanceof ApiError && refused.code === "unauthorized");
  const missing = await authenticate(new Request("http://x")).catch((e) => e);
  assert(missing instanceof ApiError && missing.code === "unauthorized");
});
