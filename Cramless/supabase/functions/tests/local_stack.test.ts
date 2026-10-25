// End to end on the local stack (skipped unless it's running): real Auth, PostgREST, Storage and the relay's
// handlers with GoTrue authentication and PostgresStore, in MOCK mode. The PostgREST requests are the ones the
// app's Sync client sends (Cramless/Sync/SupabaseClient.swift, SyncEngine.swift), header for header.
//   CRAMLESS_TEST_SUPABASE_URL=http://127.0.0.1:58421 CRAMLESS_TEST_ANON_KEY=… CRAMLESS_TEST_SERVICE_KEY=… deno task test

import { assert, assertEquals } from "@std/assert";
import { goTrueAuthenticator } from "../_shared/auth.ts";
import { defaultDeps } from "../_shared/deps.ts";
import { createAdmin, PostgresStore } from "../_shared/store_postgres.ts";
import { aiHandler } from "../ai/handler.ts";
import { accountHandler } from "../account/handler.ts";
import { fixture, fixtureJson, testEnv } from "./_harness.ts";

const URL_ = Deno.env.get("CRAMLESS_TEST_SUPABASE_URL") ?? "";
const ANON = Deno.env.get("CRAMLESS_TEST_ANON_KEY") ?? "";
const SERVICE = Deno.env.get("CRAMLESS_TEST_SERVICE_KEY") ?? "";
const ignore = !(URL_ && ANON && SERVICE);

async function api(
  method: string,
  path: string,
  o: { token?: string; body?: unknown; headers?: Record<string, string> } = {},
) {
  const headers: Record<string, string> = { apikey: ANON, ...(o.headers ?? {}) };
  if (o.token) headers.authorization = `Bearer ${o.token}`;
  if (o.body !== undefined && !headers["Content-Type"]) headers["Content-Type"] = "application/json";
  const body = o.body === undefined ? undefined : o.body instanceof Uint8Array ? o.body : JSON.stringify(o.body);
  return await fetch(`${URL_}/${path}`, { method, headers, body: body as BodyInit | undefined });
}

/** The Swift client's percent-encoding of a value inside a filter. */
const enc = (s: string) =>
  encodeURIComponent(s).replace(/[!'()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);

function relay() {
  const admin = createAdmin(URL_, SERVICE);
  const env = testEnv({ SUPABASE_URL: URL_, SUPABASE_SERVICE_ROLE_KEY: SERVICE, CRAMLESS_MOCK: "1" });
  // Work after the response (the ai_requests row) is collected so the test can wait for it, as
  // EdgeRuntime.waitUntil does on the platform.
  const pending: Promise<unknown>[] = [];
  const deps = defaultDeps({
    env,
    store: new PostgresStore(admin),
    authenticate: goTrueAuthenticator(admin),
    sleep: () => Promise.resolve(),
    background: (task) => {
      pending.push(task.catch(() => {}));
    },
  });
  const settle = async () => {
    while (pending.length > 0) await pending.shift();
  };
  return { admin, ai: aiHandler(deps), account: accountHandler(deps), settle };
}

Deno.test({
  name: "local stack: an anonymous session uses the relay; quotas reset at its own midnight",
  ignore,
  sanitizeResources: false,
  sanitizeOps: false,
  fn: async () => {
    const signup = await api("POST", "auth/v1/signup", { body: { data: {} } });
    assertEquals(signup.status, 200, "anonymous sign-ins are on");
    const session = await signup.json();
    assertEquals(session.user.is_anonymous, true);
    const token = session.access_token as string;
    const { admin, ai, account, settle } = relay();
    const call = (h: (r: Request) => Promise<Response>, path: string, body?: unknown) =>
      h(
        new Request(`${URL_}/functions/v1/${path}`, {
          method: body === undefined ? "GET" : "POST",
          headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
          body: body === undefined ? undefined : JSON.stringify(body),
        }),
      );

    // The app sets its name and time zone.
    const profile = await api("POST", "rest/v1/profiles?on_conflict=id", {
      token,
      body: [{
        id: session.user.id,
        display_name: "Maya",
        timezone: "America/Los_Angeles",
        updated_at: new Date().toISOString(),
      }],
      headers: { Prefer: "resolution=merge-duplicates,return=minimal" },
    });
    assert(profile.ok, `profile upsert answered ${profile.status}`);

    const quota = await call(ai, "ai/quota");
    assertEquals(quota.status, 200);
    assertEquals((await quota.json()).plan, "free");
    const grade = await call(ai, "ai/grade", fixtureJson("requests/grade"));
    assertEquals(await grade.text(), fixture("grade-partial"));
    await settle();
    const { data: rows } = await admin.from("ai_requests").select("route, model, mock, cost_usd").eq(
      "user_id",
      session.user.id,
    );
    assertEquals(rows, [{ route: "grade", model: "mock", mock: true, cost_usd: 0 }]);
    const { data: usage } = await admin.from("usage_counters").select("meter, used, period_start").eq(
      "user_id",
      session.user.id,
    );
    const losAngeles = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Los_Angeles" }).format(new Date());
    assertEquals(usage, [{ meter: "grades", used: 1, period_start: losAngeles }]);

    // Anonymous sessions can't back up files.
    const upload = await api("POST", `storage/v1/object/sources/${session.user.id}/s1/p1.jpg`, {
      token,
      body: new Uint8Array([0xff, 0xd8, 0xff]),
      headers: { "x-upsert": "true", "Content-Type": "image/jpeg" },
    });
    assert(upload.status >= 400, `anonymous upload answered ${upload.status}`);
    await upload.body?.cancel();

    const deleted = await call(account, "account/delete", {});
    assertEquals(await deleted.json(), { deleted: true });
    const after = await call(ai, "ai/quota");
    assertEquals(after.status, 401, "the deleted account's token no longer works");
    await after.body?.cancel();
  },
});

Deno.test({
  name: "local stack: the Sync client's PostgREST requests (upsert, last writer wins, append-only, cursor pull)",
  ignore,
  sanitizeResources: false,
  sanitizeOps: false,
  fn: async () => {
    const { admin, account } = relay();
    const email = `sync-${crypto.randomUUID()}@capling.test`;
    const { data: created } = await admin.auth.admin.createUser({
      email,
      password: "correct horse battery",
      email_confirm: true,
    });
    const userId = created.user!.id;
    const signin = await api("POST", "auth/v1/token?grant_type=password", {
      body: { email, password: "correct horse battery" },
    });
    const token = (await signin.json()).access_token as string;
    const upsert = (table: string, rows: unknown[], onConflict = "id", resolution = "merge-duplicates") =>
      api("POST", `rest/v1/${table}?on_conflict=${onConflict}`, {
        token,
        body: rows,
        headers: { Prefer: `resolution=${resolution},return=minimal` },
      });

    const courseId = crypto.randomUUID();
    const course = (name: string, updated: string) => ({
      id: courseId,
      name,
      color: "sky",
      symbol: "book.closed",
      sort_order: 0,
      created_at: "2026-10-22T09:00:00.000Z",
      updated_at: updated,
      deleted_at: null,
    });
    assert((await upsert("courses", [course("Bio 101", "2026-10-22T10:00:00.123Z")])).ok);
    assert((await upsert("courses", [course("Older edit", "2026-10-22T09:30:00.000Z")])).ok);
    assert(
      (await upsert("courses", [{
        ...course("Bio 101", "2026-10-22T11:00:00.000Z"),
        deleted_at: "2026-10-22T11:00:00.000Z",
      }])).ok,
    );

    const review = {
      id: crypto.randomUUID(),
      item_id: crypto.randomUUID(),
      course_id: courseId,
      reviewed_at: "2026-10-22T10:05:00.000Z",
      rating: 3,
      score: -1,
      graded_by: "person",
      duration_ms: 4000,
    };
    assert((await upsert("review_logs", [review], "id", "ignore-duplicates")).ok);
    assert((await upsert("review_logs", [{ ...review, rating: 1 }], "id", "ignore-duplicates")).ok);
    const merge = await upsert("review_logs", [{ ...review, rating: 1 }]);
    assert(merge.status >= 400, "merging into a review needs UPDATE, which clients don't have");
    await merge.body?.cancel();
    assert(
      (await upsert(
        "day_records",
        [{ day_key: "2026-10-22", day: "2026-10-22T07:00:00.000Z", sessions: 1 }],
        "user_id,day_key",
      )).ok,
    );
    assert(
      (await upsert(
        "day_records",
        [{ day_key: "2026-10-22", day: "2026-10-22T07:00:00.000Z", sessions: 2 }],
        "user_id,day_key",
      )).ok,
    );

    // Pull: first by synced_at, then with the (synced_at, id) cursor exactly as SyncEngine.cursorFilter writes it.
    const first = await api(
      "GET",
      `rest/v1/courses?select=*&synced_at=gt.${enc("2026-01-01T00:00:00+00:00")}&order=synced_at.asc,id.asc&limit=500`,
      { token },
    );
    const pulled = await first.json();
    assertEquals(pulled.length, 1);
    assertEquals([pulled[0].name, pulled[0].updated_at, pulled[0].user_id], [
      "Bio 101",
      "2026-10-22T11:00:00+00:00",
      userId,
    ]);
    assert(pulled[0].deleted_at, "the tombstone travels");
    const ts = enc(pulled[0].synced_at);
    const next = await api(
      "GET",
      `rest/v1/courses?select=*&or=(synced_at.gt.%22${ts}%22,and(synced_at.eq.%22${ts}%22,id.gt.%22${
        enc(courseId)
      }%22))&order=synced_at.asc,id.asc&limit=500`,
      { token },
    );
    assertEquals(next.status, 200);
    assertEquals(await next.json(), [], "nothing after the cursor");
    const reviews = await (await api("GET", "rest/v1/review_logs?select=rating", { token })).json();
    assertEquals(reviews, [{ rating: 3 }]);
    const days = await (await api("GET", "rest/v1/day_records?select=sessions", { token })).json();
    assertEquals(days, [{ sessions: 2 }]);

    // A signed-in account backs up a page photo into its own folder; deleting the account removes it.
    const upload = await api("POST", `storage/v1/object/sources/${userId}/${courseId}/p1.jpg`, {
      token,
      body: new Uint8Array([0xff, 0xd8, 0xff, 0xe0]),
      headers: { "x-upsert": "true", "Content-Type": "image/jpeg" },
    });
    assertEquals(upload.status, 200, await upload.clone().text());
    const otherFolder = await api("POST", `storage/v1/object/sources/${crypto.randomUUID()}/x/p1.jpg`, {
      token,
      body: new Uint8Array([0xff, 0xd8]),
      headers: { "x-upsert": "true", "Content-Type": "image/jpeg" },
    });
    assert(otherFolder.status >= 400, "never another person's folder");
    await otherFolder.body?.cancel();
    const download = await api("GET", `storage/v1/object/authenticated/sources/${userId}/${courseId}/p1.jpg`, {
      token,
    });
    assertEquals(new Uint8Array(await download.arrayBuffer()), new Uint8Array([0xff, 0xd8, 0xff, 0xe0]));

    const deleted = await account(
      new Request(`${URL_}/functions/v1/account/delete`, {
        method: "POST",
        headers: { authorization: `Bearer ${token}` },
      }),
    );
    assertEquals(await deleted.json(), { deleted: true });
    const { data: left } = await admin.storage.from("sources").list(userId);
    assertEquals(left, []);
    const { count } = await admin.from("courses").select("*", { count: "exact", head: true }).eq("user_id", userId);
    assertEquals(count, 0);
  },
});
