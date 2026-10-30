// One suite for both stores: MemoryStore always, and PostgresStore (the SQL functions in supabase/migrations) when
// a local stack is running and these are set:
//   CRAMLESS_TEST_SUPABASE_URL=http://127.0.0.1:58421 CRAMLESS_TEST_SERVICE_KEY=<service_role key> deno task test
// So the in-memory rules the handler tests rely on are the database's rules.

import { assert, assertEquals } from "@std/assert";
import { createAdmin, PostgresStore } from "../_shared/store_postgres.ts";
import type { EntitlementRow, Store } from "../_shared/store.ts";
import { MemoryStore } from "./_memory_store.ts";

interface Subject {
  store: Store;
  user(name?: string, timeZone?: string): Promise<string>;
}

const NOW = new Date("2026-10-22T09:00:00Z");
const WEEK = "2026-10-19";
const DAY = "2026-10-22";
const MIN = 60_000;

function memorySubject(): Subject {
  const store = new MemoryStore();
  return { store, user: (name = "", tz = "UTC") => Promise.resolve(store.addUser(crypto.randomUUID(), name, tz)) };
}

const PG_URL = Deno.env.get("CRAMLESS_TEST_SUPABASE_URL") ?? "";
const PG_KEY = Deno.env.get("CRAMLESS_TEST_SERVICE_KEY") ?? "";

function postgresSubject(): Subject {
  const admin = createAdmin(PG_URL, PG_KEY);
  return {
    store: new PostgresStore(admin),
    user: async (name = "", tz = "UTC") => {
      const { data, error } = await admin.auth.admin.createUser({
        email: `store-${crypto.randomUUID()}@capling.test`,
        email_confirm: true,
      });
      if (error || !data.user) throw new Error(`createUser: ${error?.message}`);
      const { error: e2 } = await admin.from("profiles").update({ display_name: name, timezone: tz }).eq(
        "id",
        data.user.id,
      );
      if (e2) throw new Error(`profile: ${e2.message}`);
      return data.user.id;
    },
  };
}

function entitlement(o: Partial<EntitlementRow> = {}): EntitlementRow {
  return {
    plan: "pro",
    productId: "com.loopware.Capling.pro.yearly",
    originalTransactionId: `otid-${crypto.randomUUID()}`,
    transactionId: "t1",
    purchaseDate: "2026-10-01T00:00:00Z",
    expiresAt: "2027-10-01T00:00:00Z",
    revokedAt: null,
    environment: "Sandbox",
    ...o,
  };
}

const code = () => `CAP-${crypto.randomUUID().replace(/-/g, "").slice(0, 4).toUpperCase()}`;

function suite(label: string, make: () => Subject, ignore = false) {
  const t = (name: string, fn: (s: Subject) => Promise<void>) =>
    Deno.test({
      name: `${label}: ${name}`,
      ignore,
      sanitizeResources: false,
      sanitizeOps: false,
      fn: () => fn(make()),
    });

  t("context: a profile exists, with its time zone; a stranger doesn't", async ({ store, user }) => {
    const id = await user("Maya", "Asia/Tokyo");
    assertEquals(await store.context(id, NOW), {
      exists: true,
      plan: "free",
      expiresAt: null,
      timeZone: "Asia/Tokyo",
      displayName: "Maya",
    });
    assertEquals((await store.context(crypto.randomUUID(), NOW)).exists, false);
  });

  t("consume stops at the limit; refund gives back; null is unlimited", async ({ store, user }) => {
    const id = await user();
    assertEquals(await store.consume(id, "grades", DAY, 1, 2), { allowed: true, used: 1 });
    assertEquals(await store.consume(id, "grades", DAY, 1, 2), { allowed: true, used: 2 });
    assertEquals(await store.consume(id, "grades", DAY, 1, 2), { allowed: false, used: 2 });
    await store.refund(id, "grades", DAY, 1);
    assertEquals(await store.consume(id, "grades", DAY, 1, 2), { allowed: true, used: 2 });
    assertEquals((await store.consume(id, "tutor", DAY, 1, null)).allowed, true);
    assertEquals(
      await store.usage(id, [{ meter: "grades", period: DAY }, { meter: "tutor", period: DAY }, {
        meter: "scans",
        period: WEEK,
      }]),
      {
        grades: 2,
        tutor: 1,
        scans: 0,
      },
    );
  });

  t("a scan is its transcriptions and the generate that closes it", async ({ store, user }) => {
    const id = await user();
    const scan = (kind: "transcribe" | "generate", pages: number, at = NOW, limit: number | null = 3) =>
      store.consumeScan(id, kind, pages, WEEK, limit, at, 30, 10);
    assertEquals(await scan("transcribe", 1), { allowed: true, used: 1, counted: true });
    assertEquals(await scan("transcribe", 1), { allowed: true, used: 1, counted: false });
    assertEquals(await scan("generate", 2), { allowed: true, used: 1, counted: false });
    assertEquals(
      await scan("generate", 2),
      { allowed: true, used: 2, counted: true },
      "a closed scan doesn't take more",
    );
    assertEquals((await scan("transcribe", 1)).counted, true);
    for (let i = 0; i < 9; i++) assertEquals((await scan("transcribe", 1)).counted, false, `page ${i + 2}`);
    assertEquals(
      await scan("transcribe", 1),
      { allowed: false, used: 3, counted: false },
      "the 11th page needs a 4th scan",
    );
    assertEquals((await scan("generate", 10)).counted, false, "the generate still closes scan 3");
    assertEquals((await scan("generate", 1, new Date(NOW.getTime() + 40 * MIN))).allowed, false);
    assertEquals(
      (await scan("generate", 1, new Date(NOW.getTime() + 40 * MIN), null)).counted,
      true,
      "unlimited plans",
    );
  });

  t("a failed scan request is undone", async ({ store, user }) => {
    const id = await user();
    const first = await store.consumeScan(id, "transcribe", 1, WEEK, 3, NOW, 30, 10);
    await store.refundScan(id, "transcribe", 1, WEEK, first.counted);
    assertEquals((await store.usage(id, [{ meter: "scans", period: WEEK }])).scans, 0);
    assertEquals((await store.consumeScan(id, "transcribe", 1, WEEK, 3, NOW, 30, 10)).counted, true);
    const generate = await store.consumeScan(id, "generate", 1, WEEK, 3, NOW, 30, 10);
    assertEquals(generate.counted, false);
    await store.refundScan(id, "generate", 1, WEEK, false);
    assertEquals(
      (await store.consumeScan(id, "generate", 1, WEEK, 3, NOW, 30, 10)).counted,
      false,
      "the retry rides on it",
    );
  });

  t("the plan is the best active entitlement", async ({ store, user }) => {
    const id = await user();
    await store.saveEntitlements(id, [entitlement({ plan: "pass", expiresAt: "2026-11-01T00:00:00Z" })], NOW);
    assertEquals((await store.context(id, NOW)).plan, "pass");
    await store.saveEntitlements(id, [entitlement({ plan: "pro", expiresAt: "2027-10-01T00:00:00Z" })], NOW);
    assertEquals(await store.context(id, NOW).then((c) => [c.plan, c.expiresAt]), ["pro", "2027-10-01T00:00:00Z"]);
    const expired = await user();
    await store.saveEntitlements(expired, [entitlement({ expiresAt: "2026-10-01T00:00:00Z" })], NOW);
    assertEquals((await store.context(expired, NOW)).plan, "free");
    const revoked = await user();
    await store.saveEntitlements(revoked, [entitlement({ revokedAt: "2026-10-10T00:00:00Z" })], NOW);
    assertEquals((await store.context(revoked, NOW)).plan, "free");
  });

  t(
    "a purchase moves to the account that synced it last; older transactions don't roll it back",
    async ({ store, user }) => {
      const a = await user();
      const b = await user();
      const row = entitlement();
      await store.saveEntitlements(a, [row], NOW);
      await store.saveEntitlements(b, [row], NOW);
      assertEquals([(await store.context(a, NOW)).plan, (await store.context(b, NOW)).plan], ["free", "pro"]);
      await store.saveEntitlements(b, [{
        ...row,
        transactionId: "t0",
        purchaseDate: "2025-01-01T00:00:00Z",
        expiresAt: "2025-02-01T00:00:00Z",
      }], NOW);
      assertEquals((await store.context(b, NOW)).expiresAt, "2027-10-01T00:00:00Z");
      assertEquals(
        await store.applyNotification({ ...row, purchaseDate: "2025-01-01T00:00:00Z" } as never, NOW),
        "stale",
      );
      assertEquals(
        await store.applyNotification({
          environment: "Sandbox",
          originalTransactionId: row.originalTransactionId,
          transactionId: "t2",
          productId: row.productId,
          plan: "pro",
          purchaseDate: "2026-10-20T00:00:00Z",
          expiresAt: "2026-10-21T00:00:00Z",
          revokedAt: null,
        }, NOW),
        "applied",
      );
      assertEquals((await store.context(b, NOW)).plan, "free", "the notification ended it");
      assertEquals(
        await store.applyNotification({ ...row, originalTransactionId: "never-seen" } as never, NOW),
        "unknown",
      );
    },
  );

  t("Squad: the purchaser's Squad, single-use codes, four seats", async ({ store, user }) => {
    const owner = await user("Maya");
    const friends = [await user("Priya"), await user("Sam"), await user("Lee"), await user("Ana")];
    const c1 = code();
    assertEquals(await store.squadInvite(owner, c1, new Date(NOW.getTime() + 14 * 1440 * MIN), NOW), {
      ok: false,
      reason: "not_owner",
    });
    await store.saveEntitlements(owner, [
      entitlement({ plan: "squad", productId: "com.loopware.Capling.squad.yearly" }),
    ], NOW);
    const invite = await store.squadInvite(owner, c1, new Date(NOW.getTime() + 14 * 1440 * MIN), NOW);
    assert(invite.ok);
    assertEquals(await store.squadInvite(owner, c1, new Date(NOW.getTime() + 1440 * MIN), NOW), {
      ok: false,
      reason: "code_taken",
    });

    assertEquals(await store.squadRedeem(friends[0], "CAP-0000", NOW), { ok: false, reason: "not_found" });
    assertEquals(await store.squadRedeem(owner, c1, NOW), { ok: false, reason: "own_squad" });
    assertEquals(await store.squadRedeem(friends[0], c1.toLowerCase(), NOW), { ok: true, ownerName: "Maya" });
    assertEquals(await store.squadRedeem(friends[0], c1, NOW), { ok: true, ownerName: "Maya" }, "already in it");
    assertEquals(await store.squadRedeem(friends[1], c1, NOW), { ok: false, reason: "used" });
    assertEquals((await store.context(friends[0], NOW)).plan, "squad");

    const c2 = code();
    await store.squadInvite(owner, c2, new Date(NOW.getTime() + MIN), NOW);
    assertEquals(await store.squadRedeem(friends[1], c2, new Date(NOW.getTime() + 2 * MIN)), {
      ok: false,
      reason: "expired",
    });
    for (const [i, friend] of [friends[1], friends[2]].entries()) {
      const c = code();
      assert((await store.squadInvite(owner, c, new Date(NOW.getTime() + 60 * MIN), NOW)).ok);
      assertEquals((await store.squadRedeem(friend, c, new Date(NOW.getTime() + (i + 1) * MIN))).ok, true);
    }
    assertEquals(await store.squadInvite(owner, code(), new Date(NOW.getTime() + 60 * MIN), NOW), {
      ok: false,
      reason: "full",
    });

    const members = await store.squadMembers(friends[2]);
    assert(members.ok);
    assertEquals(members.members.map((m) => [m.id, m.name, m.isOwner]), [
      [owner, "Maya", true],
      [friends[0], "Priya", false],
      [friends[1], "Sam", false],
      [friends[2], "Lee", false],
    ]);
    assertEquals(await store.squadMembers(friends[3]), { ok: false, reason: "no_squad" });

    assertEquals(await store.squadRemove(friends[1], friends[0]), { ok: false, reason: "not_allowed" });
    assertEquals(await store.squadRemove(owner, friends[0]), { ok: true });
    assertEquals(await store.squadRemove(friends[1], friends[1]), { ok: true }, "leaving");
    assertEquals(await store.squadRemove(owner, friends[3]), { ok: false, reason: "not_found" });
    assertEquals((await store.context(friends[0], NOW)).plan, "free");
  });

  t("Squad: members of a lapsed Squad fall back to free, and nobody new gets in", async ({ store, user }) => {
    const owner = await user("Jo");
    const friend = await user();
    const late = await user();
    await store.saveEntitlements(owner, [entitlement({ plan: "squad", expiresAt: "2026-11-01T00:00:00Z" })], NOW);
    const c = code();
    await store.squadInvite(owner, c, new Date("2026-12-01T00:00:00Z"), NOW);
    await store.squadRedeem(friend, c, NOW);
    const later = new Date("2026-11-02T00:00:00Z");
    assertEquals((await store.context(friend, later)).plan, "free");
    const c2 = code();
    await store.squadInvite(owner, c2, new Date("2026-12-01T00:00:00Z"), NOW);
    assertEquals(await store.squadRedeem(late, c2, later), { ok: false, reason: "owner_lapsed" });
  });

  t("the day's spending: the calls since a moment, per person, in whole nano-dollars", async ({ store, user }) => {
    const id = await user();
    const other = await user();
    const row = (userId: string, createdAt: string, costUsd: string, mock = false) => ({
      userId,
      route: "tutor",
      model: "gpt-6.1-terra",
      plan: "pro" as const,
      status: 200,
      mock,
      inputTokens: 100,
      outputTokens: 50,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
      costUsd,
      latencyMs: 400,
      createdAt,
    });
    const since = new Date("2026-10-22T07:00:00Z");
    assertEquals(await store.spentSince(id, since), 0n, "nothing yet");
    await store.logRequest(row(id, "2026-10-22T06:59:59Z", "0.500000000")); // before the moment
    await store.logRequest(row(id, "2026-10-22T07:00:00Z", "0.012345678"));
    await store.logRequest(row(id, "2026-10-22T08:00:00Z", "0.000000001"));
    await store.logRequest(row(id, "2026-10-22T08:30:00Z", "0.000000000", true)); // a MOCK reply costs nothing
    await store.logRequest(row(other, "2026-10-22T08:00:00Z", "0.200000000"));
    assertEquals(await store.spentSince(id, since), 12_345_679n);
    assertEquals(await store.spentSince(other, since), 200_000_000n);
    assertEquals(await store.spentSince(id, new Date("2026-10-22T08:00:01Z")), 0n);
  });

  t("deletion: AI data, then everything", async ({ store, user }) => {
    const id = await user();
    await store.logRequest({
      userId: id,
      route: "grade",
      model: "claude-haiku-5-5",
      plan: "free",
      status: 200,
      mock: false,
      inputTokens: 10,
      outputTokens: 5,
      cacheReadTokens: 0,
      cacheWriteTokens: 0,
      costUsd: "0.000003500",
      latencyMs: 900,
      createdAt: "2026-10-22T09:00:00Z",
    });
    await store.consume(id, "grades", DAY, 1, 20);
    await store.deleteAiData(id);
    assertEquals((await store.usage(id, [{ meter: "grades", period: DAY }])).grades, 1, "counts stay");
    await store.saveEntitlements(id, [entitlement()], NOW);
    await store.deleteAccount(id);
    assertEquals((await store.context(id, NOW)).exists, false);
  });
}

suite("MemoryStore", memorySubject);
suite("PostgresStore", postgresSubject, !(PG_URL && PG_KEY));
