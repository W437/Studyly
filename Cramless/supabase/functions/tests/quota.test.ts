// Plans and quotas: the free limits, scans as capture sessions, refunds, fair use, local days and weeks.

import { assert, assertEquals } from "@std/assert";
import { localMidnight, periodEnd, periodStart, quotaStatus } from "../_shared/plans.ts";
import { ApiError } from "../_shared/errors.ts";
import { errorOf, fixtureJson, rig, ScriptedProvider } from "./_harness.ts";

const MOCK = { CRAMLESS_MOCK: "1" };
const page = (n: number) => ({
  page: n,
  label: String(n + 1),
  lines: [{ id: `p${n}.l0`, text: "Mitosis makes two cells." }],
});
const generateBody = (pages: number) => ({
  ...fixtureJson("requests/generate"),
  pages: Array.from({ length: pages }, (_, i) => page(i)),
});
const transcribe = (n = 0) => ({ image: "/9j/4AAQSkZJRgABAQAAAQABAAD", page: n, label: String(n + 1) });

function pro(r: ReturnType<typeof rig>, user = "user-1", plan: "pro" | "squad" | "pass" = "pro") {
  r.store.entitlements.push({
    userId: user,
    plan,
    productId: "com.loopware.Capling.pro.yearly",
    originalTransactionId: `otid-${user}-${plan}`,
    transactionId: "t1",
    purchaseDate: "2026-10-01T00:00:00Z",
    expiresAt: "2027-10-29T00:00:00Z",
    revokedAt: null,
    environment: "Production",
  });
}

Deno.test("the quota report is the app's QuotaStatus", async () => {
  const r = rig({ env: MOCK });
  r.store.addUser("user-1");
  r.store.counters.set("user-1|scans|2026-10-19", 1);
  r.store.counters.set("user-1|grades|2026-10-22", 6);
  r.store.counters.set("user-1|tutor|2026-10-22", 2);
  r.store.counters.set("user-1|grades|2026-10-21", 15); // yesterday's: not counted
  assertEquals(await (await r.ai("quota")).json(), fixtureJson("quota-free"));
  pro(r);
  r.store.counters.clear();
  assertEquals(await (await r.ai("quota")).json(), fixtureJson("quota-pro"));
});

Deno.test("free plan: 20 grades and 10 tutor messages a day, 1 lecture a week", async () => {
  const r = rig({ env: MOCK });
  r.store.addUser("user-1");
  for (let i = 0; i < 10; i++) {
    const res = await r.ai("tutor", { body: fixtureJson("requests/tutor") });
    assertEquals(res.status, 200);
    await res.body?.cancel();
  }
  await r.settle();
  const tutor = await r.ai("tutor", { body: fixtureJson("requests/tutor") });
  assertEquals(tutor.status, 429, "the 11th tutor message");
  assertEquals((await errorOf(tutor)).quota, {
    plan: "free",
    meters: [{ key: "tutor", used: 10, limit: 10, period: "day" }],
  });

  const lecture = {
    course: "Bio",
    title: "L6",
    segments: [{ id: "s1", start: 0, end: 10, text: "Hi" }],
    flags: [],
    maxItems: 3,
  };
  assertEquals((await r.ai("lecture", { body: lecture })).status, 200);
  const second = await r.ai("lecture", { body: lecture });
  assertEquals(second.status, 429);
  assertEquals((await errorOf(second)).message.startsWith("That's this week's AI notes for 1 lecture"), true);

  // The next day: grades and tutor reset; the lecture waits for Monday.
  r.clock.set("2026-10-23T09:00:00Z");
  assertEquals((await r.ai("tutor", { body: fixtureJson("requests/tutor") })).status, 200);
  assertEquals((await r.ai("lecture", { body: lecture })).status, 429);
  r.clock.set("2026-10-26T00:00:01Z");
  assertEquals((await r.ai("lecture", { body: lecture })).status, 200);
  await r.settle();
});

Deno.test("free plan: 3 scans a week, each a capture session of up to 10 pages", async () => {
  const r = rig({ env: MOCK });
  r.store.addUser("user-1");
  // Scan 1: four handwritten pages transcribed, then the generate call: one scan.
  for (let i = 0; i < 4; i++) assertEquals((await r.ai("transcribe-image", { body: transcribe(i) })).status, 200);
  assertEquals((await r.ai("generate", { body: generateBody(4) })).status, 200);
  assertEquals(r.store.used("user-1", "scans", "2026-10-19"), 1);
  // Scan 2: a typed page, generate only.
  assertEquals((await r.ai("generate", { body: generateBody(1) })).status, 200);
  assertEquals(r.store.used("user-1", "scans", "2026-10-19"), 2);
  // Scan 3 starts with transcriptions; an 11th page in the same session opens another scan, which is the 4th.
  for (let i = 0; i < 10; i++) assertEquals((await r.ai("transcribe-image", { body: transcribe(i) })).status, 200);
  assertEquals(r.store.used("user-1", "scans", "2026-10-19"), 3);
  const fourth = await r.ai("transcribe-image", { body: transcribe(10) });
  assertEquals(fourth.status, 429);
  const error = await errorOf(fourth);
  assertEquals(error.code, "quota_exceeded");
  assertEquals(error.quota, { plan: "free", meters: [{ key: "scans", used: 3, limit: 3, period: "week" }] });
  // Its generate call still closes scan 3.
  assertEquals((await r.ai("generate", { body: generateBody(10) })).status, 200);
  assertEquals(r.store.used("user-1", "scans", "2026-10-19"), 3);
  // A session that sat for more than 30 minutes is over.
  r.clock.advance(31 * 60_000);
  assertEquals((await r.ai("generate", { body: generateBody(1) })).status, 429);
});

Deno.test("free plan: more than 10 pages in one scan needs Pro; paid plans take up to 40", async () => {
  const r = rig({ env: MOCK });
  r.store.addUser("user-1");
  const big = await r.ai("generate", { body: generateBody(11) });
  assertEquals(big.status, 403);
  assertEquals((await errorOf(big)).code, "entitlement_required");
  assertEquals(r.store.used("user-1", "scans", "2026-10-19"), 0, "a refused scan costs nothing");
  pro(r);
  assertEquals((await r.ai("generate", { body: generateBody(11) })).status, 200);
});

Deno.test("paid plans are unlimited with fair use", async () => {
  const r = rig({ env: MOCK });
  r.store.addUser("user-1");
  pro(r, "user-1", "pass");
  for (let i = 0; i < 25; i++) assertEquals((await r.ai("grade", { body: fixtureJson("requests/grade") })).status, 200);
  r.store.counters.set("user-1|grades|2026-10-22", 1500);
  const over = await r.ai("grade", { body: fixtureJson("requests/grade") });
  assertEquals(over.status, 429);
  const error = await errorOf(over);
  assertEquals(error.quota, { plan: "pass", meters: [{ key: "grades", used: 1500, limit: null, period: "day" }] });
  assertEquals(error.retryAfter, 15 * 3600, "until midnight UTC");
  assertEquals(over.headers.get("retry-after"), String(15 * 3600));
});

Deno.test("a failed request gives its quota back", async () => {
  const provider = new ScriptedProvider();
  const r = rig({ provider });
  r.store.addUser("user-1");
  provider.failJson(new ApiError("upstream", "Cap is busy right now. Try again in a moment.", { retryAfter: 15 }, 503));
  const res = await r.ai("grade", { body: fixtureJson("requests/grade") });
  assertEquals(res.status, 503);
  assertEquals(r.store.used("user-1", "grades", "2026-10-22"), 0);

  provider.failJson(new Error("socket hang up"));
  assertEquals((await r.ai("generate", { body: generateBody(2) })).status, 502);
  assertEquals(r.store.used("user-1", "scans", "2026-10-19"), 0, "the counted scan is refunded");

  // A generate that rode on an open scan reopens it when it fails, so the retry rides on it again.
  provider.replyJson({ lines: [{ id: "x", text: "Mitosis notes" }] });
  assertEquals((await r.ai("transcribe-image", { body: transcribe(0) })).status, 200);
  provider.failJson(new Error("timeout"));
  assertEquals((await r.ai("generate", { body: generateBody(1) })).status, 502);
  provider.replyJson({
    title: "Mitosis",
    topics: [],
    items: [{
      id: "i1",
      kind: "flashcard",
      topic: "T",
      prompt: "Mitosis",
      answer: "Two cells",
      explanation: "",
      keyIdeas: [],
      choices: [],
      anchors: ["p0.l0"],
      difficulty: 0.3,
    }],
  });
  assertEquals((await r.ai("generate", { body: generateBody(1) })).status, 200);
  assertEquals(r.store.used("user-1", "scans", "2026-10-19"), 1);
  await r.settle();
  assertEquals(r.store.requests.map((q) => q.status), [503, 502, 200, 502, 200]);
});

Deno.test("days and weeks are the person's own", async () => {
  // 09:00 UTC on Thursday is 02:00 in Los Angeles (still Thursday) and 18:00 in Tokyo.
  const at = new Date("2026-10-22T09:00:00Z");
  assertEquals(periodStart("day", at, "America/Los_Angeles"), "2026-10-22");
  assertEquals(periodStart("day", new Date("2026-10-22T05:00:00Z"), "America/Los_Angeles"), "2026-10-21");
  assertEquals(periodStart("day", new Date("2026-10-22T16:00:00Z"), "Asia/Tokyo"), "2026-10-23");
  assertEquals(periodStart("week", at, "UTC"), "2026-10-19");
  assertEquals(periodStart("week", new Date("2026-10-19T00:30:00Z"), "Asia/Jerusalem"), "2026-10-19");
  assertEquals(periodStart("week", new Date("2026-10-18T23:30:00Z"), "UTC"), "2026-10-12", "Sunday is the old week");
  assertEquals(periodStart("day", at, "Not/AZone"), "2026-10-22", "unknown zones count as UTC");
  // Midnight across a daylight-saving change (Los Angeles falls back on 1 November 2026).
  assertEquals(localMidnight("2026-11-01", "America/Los_Angeles").toISOString(), "2026-11-01T07:00:00.000Z");
  assertEquals(localMidnight("2026-11-02", "America/Los_Angeles").toISOString(), "2026-11-02T08:00:00.000Z");
  assertEquals(periodEnd("week", at, "UTC").toISOString(), "2026-10-26T00:00:00.000Z");

  const r = rig({ env: MOCK });
  r.store.addUser("user-1", "", "America/Los_Angeles");
  r.clock.set("2026-10-22T06:59:00Z"); // 23:59 on Wednesday in Los Angeles
  await r.ai("grade", { body: fixtureJson("requests/grade") });
  assertEquals(r.store.used("user-1", "grades", "2026-10-21"), 1);
  r.clock.set("2026-10-22T07:01:00Z");
  await r.ai("grade", { body: fixtureJson("requests/grade") });
  assertEquals(r.store.used("user-1", "grades", "2026-10-22"), 1);
});

Deno.test("the quota report never shows a paid plan's fair-use ceiling", () => {
  const status = quotaStatus("squad", { scans: 40, grades: 300 });
  assert(status.meters.every((m) => m.limit === null));
  assertEquals(status.meters.map((m) => m.key), ["scans", "grades", "tutor", "lectures"]);
});
