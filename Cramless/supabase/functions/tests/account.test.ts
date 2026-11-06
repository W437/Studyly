// The account function: Squad (four seats, only the purchaser invites, single-use codes) and deletion.

import { assert, assertEquals } from "@std/assert";
import { inviteCode } from "../account/handler.ts";
import { contractSchema } from "../_shared/schemas.ts";
import { validate } from "../_shared/schema.ts";
import { errorOf, fixtureJson, rig } from "./_harness.ts";
import type { MemoryStore } from "./_memory_store.ts";

const ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
/** A random source that spells `code` (four characters after CAP-), then keeps returning fresh values. */
function spelling(...codes: string[]): () => number {
  const values = codes.flatMap((c) => [...c].map((ch) => (ALPHABET.indexOf(ch) + 0.5) / ALPHABET.length));
  let i = 0;
  return () => (i < values.length ? values[i++] : Math.random());
}

function squadEntitlement(store: MemoryStore, owner: string, expiresAt = "2027-10-01T00:00:00Z") {
  store.entitlements.push({
    userId: owner,
    plan: "squad",
    productId: "com.loopware.Capling.squad.yearly",
    originalTransactionId: `sq-${owner}`,
    transactionId: "t",
    purchaseDate: "2026-10-01T18:00:00Z",
    expiresAt,
    revokedAt: null,
    environment: "Production",
  });
}

function squadRig(random = spelling("7Q4K")) {
  const r = rig({ random });
  r.clock.set("2026-10-22T00:00:00Z");
  for (
    const [id, name] of [["u-owner", "Maya"], ["u-priya", "Priya"], ["u-3", "Sam"], ["u-4", "Lee"], ["u-5", "Ana"]]
  ) {
    r.store.addUser(id, name);
  }
  squadEntitlement(r.store, "u-owner");
  return r;
}

Deno.test("invite codes look like CAP-7Q4K", () => {
  for (let i = 0; i < 50; i++) assert(/^CAP-[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}$/.test(inviteCode(Math.random)));
  assertEquals(inviteCode(spelling("7Q4K")), "CAP-7Q4K");
});

Deno.test("the Squad purchaser invites, a friend redeems, and the members list is the contract's", async () => {
  const r = squadRig();
  const invite = await r.account("squad/invite", { user: "u-owner", body: {} });
  assertEquals(invite.status, 200);
  assertEquals(await invite.json(), fixtureJson("squad-invite"));

  r.clock.set("2026-10-03T20:12:00Z");
  const redeemed = await r.account("squad/redeem", { user: "u-priya", body: { code: "cap-7q4k " } });
  assertEquals(await redeemed.json(), fixtureJson("squad-redeem"));
  assertEquals((await (await r.ai("quota", { user: "u-priya" })).json()).plan, "squad", "a member has the plan");

  // Priya shares that she studied; Maya doesn't.
  assertEquals((await r.account("squad/share", { user: "u-priya", body: { on: true } })).status, 200);
  const marked = await r.account("squad/studied", { user: "u-priya", body: { dayKey: "2026-10-03" } });
  assertEquals(await marked.json(), fixtureJson("squad-studied"));

  // The squad was created with the first invite; the owner's seat dates from then.
  r.store.squads.forEach((s) => (s.createdAt = Date.parse("2026-10-01T18:00:00Z")));
  const members = await (await r.account("squad/members", { user: "u-owner" })).json();
  assertEquals(members, fixtureJson("squad-members"));
  assertEquals(
    await (await r.account("squad/members", { user: "u-priya" })).json(),
    { ...members, sharing: true },
    "members see the same list, and whether they share",
  );
  assertEquals(validate(contractSchema("SquadMembers"), members), []);
});

/** Maya owns a Squad, Priya and Sam are on it; Priya in Tokyo and Sam in New York. */
async function sharingRig() {
  const r = squadRig(spelling("AAAA", "BBBB"));
  r.clock.set("2026-11-06T20:00:00Z");
  r.store.profiles.get("u-priya")!.timeZone = "Asia/Tokyo";
  r.store.profiles.get("u-3")!.timeZone = "America/New_York";
  for (const user of ["u-priya", "u-3"]) {
    const { code } = await (await r.account("squad/invite", { user: "u-owner", body: {} })).json();
    assertEquals((await r.account("squad/redeem", { user, body: { code } })).status, 200);
  }
  return r;
}

const list = async (r: Awaited<ReturnType<typeof sharingRig>>, user = "u-owner") =>
  await (await r.account("squad/members", { user })).json();
const studiedToday = (members: { members: { id: string; studiedToday?: boolean }[] }, id: string) =>
  members.members.find((m) => m.id === id)?.studiedToday;

Deno.test("the dot is off by default: nothing is kept and nothing is shown until someone opts in", async () => {
  const r = await sharingRig();
  const before = await list(r);
  assertEquals(before.sharing, false);
  for (const m of before.members) assert(!("studiedToday" in m), "not false: not there at all");

  const res = await r.account("squad/studied", { user: "u-priya", body: { dayKey: "2026-11-07" } });
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { recorded: false });
  assertEquals(r.store.activity.size, 0, "nothing kept for someone who hasn't opted in");

  // Opted in, nothing yet: a false, for the people who share.
  await r.account("squad/share", { user: "u-priya", body: { on: true } });
  const shared = await list(r);
  assertEquals(studiedToday(shared, "u-priya"), false);
  assertEquals(studiedToday(shared, "u-3"), undefined);
  assertEquals((await list(r, "u-priya")).sharing, true);
  assertEquals((await list(r, "u-3")).sharing, false);
});

Deno.test("studied today is by each member's own time zone", async () => {
  const r = await sharingRig();
  await r.account("squad/share", { user: "u-priya", body: { on: true } });
  await r.account("squad/share", { user: "u-3", body: { on: true } });
  // 20:00 UTC on the 6th: in Tokyo it's already the 7th, in New York still the 6th.
  assertEquals(await (await r.account("squad/studied", { user: "u-priya", body: { dayKey: "2026-11-07" } })).json(), { recorded: true });
  assertEquals(await (await r.account("squad/studied", { user: "u-3", body: { dayKey: "2026-11-06" } })).json(), { recorded: true });
  let members = await list(r);
  assertEquals(studiedToday(members, "u-priya"), true);
  assertEquals(studiedToday(members, "u-3"), true);
  // Five hours on: it's the 7th in New York too, and Tokyo's day is still the 7th.
  r.clock.set("2026-11-07T05:00:00Z");
  members = await list(r);
  assertEquals(studiedToday(members, "u-priya"), true);
  assertEquals(studiedToday(members, "u-3"), false, "yesterday's dot is gone at their midnight");
  // Twice in a day is once.
  await r.account("squad/studied", { user: "u-3", body: { dayKey: "2026-11-07" } });
  await r.account("squad/studied", { user: "u-3", body: { dayKey: "2026-11-07" } });
  assertEquals([...r.store.activity.get("u-3")!].sort(), ["2026-11-06", "2026-11-07"]);
});

Deno.test("a day has to be real and about today", async () => {
  const r = await sharingRig();
  await r.account("squad/share", { user: "u-3", body: { on: true } });
  for (const dayKey of ["2026-11-20", "2026-10-30", "2026-02-30", "tomorrow"]) {
    const res = await r.account("squad/studied", { user: "u-3", body: { dayKey } });
    assertEquals(res.status, 400, dayKey);
    assertEquals((await errorOf(res)).code, "bad_request");
  }
  assertEquals((await r.account("squad/studied", { user: "u-3", body: {} })).status, 400);
  assertEquals((await r.account("squad/share", { user: "u-3", body: {} })).status, 400);
  assertEquals(r.store.activity.size, 0);
});

Deno.test("turning sharing off, leaving and deleting all take the dot away at once", async () => {
  const r = await sharingRig();
  await r.account("squad/share", { user: "u-3", body: { on: true } });
  await r.account("squad/studied", { user: "u-3", body: { dayKey: "2026-11-06" } });
  assertEquals(studiedToday(await list(r), "u-3"), true);

  const off = await (await r.account("squad/share", { user: "u-3", body: { on: false } })).json();
  assertEquals(off.sharing, false);
  assertEquals(studiedToday(off, "u-3"), undefined);
  assertEquals(r.store.activity.has("u-3"), false, "what was shared is deleted");

  // Leaving ends sharing: a later Squad never sees it unless it's switched on again.
  await r.account("squad/share", { user: "u-3", body: { on: true } });
  await r.account("squad/studied", { user: "u-3", body: { dayKey: "2026-11-06" } });
  const left = await r.account("squad/remove", { user: "u-3", body: { memberId: "u-3" } });
  assertEquals((await left.json()).sharing, false);
  assertEquals(r.store.activity.has("u-3"), false);
  assertEquals(r.store.profiles.get("u-3")?.shares, false);
  assertEquals(await (await r.account("squad/studied", { user: "u-3", body: { dayKey: "2026-11-06" } })).json(), { recorded: false });

  // The owner deleting the account ends the Squad, and everyone's sharing on it.
  await r.account("squad/share", { user: "u-priya", body: { on: true } });
  await r.account("squad/studied", { user: "u-priya", body: { dayKey: "2026-11-07" } });
  assertEquals((await r.account("delete", { user: "u-owner", body: {} })).status, 200);
  assertEquals(r.store.activity.has("u-priya"), false);
  assertEquals(r.store.profiles.get("u-priya")?.shares, false);
});

Deno.test("sharing needs a Squad", async () => {
  const r = await sharingRig();
  const res = await r.account("squad/share", { user: "u-4", body: { on: true } });
  assertEquals(res.status, 404);
  assertEquals((await errorOf(res)).code, "bad_request");
  // A studied note from someone with no Squad is simply not kept, so a stale phone isn't told off.
  assertEquals(await (await r.account("squad/studied", { user: "u-4", body: { dayKey: "2026-11-06" } })).json(), { recorded: false });
  // Nothing without a session.
  assertEquals((await r.account("squad/share", { user: null, body: { on: true } })).status, 401);
  assertEquals((await r.account("squad/studied", { user: null, body: { dayKey: "2026-11-06" } })).status, 401);
});

Deno.test("only someone with an active Squad subscription can invite", async () => {
  const r = squadRig();
  const res = await r.account("squad/invite", { user: "u-priya", body: {} });
  assertEquals(res.status, 403);
  assertEquals((await errorOf(res)).code, "entitlement_required");
  // A Pro subscriber isn't a Squad owner either.
  r.store.entitlements.push({ ...r.store.entitlements[0], userId: "u-3", plan: "pro", originalTransactionId: "pro-3" });
  assertEquals((await r.account("squad/invite", { user: "u-3", body: {} })).status, 403);
});

Deno.test("four seats: the owner and three friends", async () => {
  const r = squadRig(spelling("AAAA", "BBBB", "CCCC", "DDDD"));
  const codes: string[] = [];
  for (let i = 0; i < 3; i++) {
    codes.push((await (await r.account("squad/invite", { user: "u-owner", body: {} })).json()).code);
  }
  for (const [i, user] of ["u-priya", "u-3", "u-4"].entries()) {
    assertEquals((await r.account("squad/redeem", { user, body: { code: codes[i] } })).status, 200);
  }
  const full = await r.account("squad/invite", { user: "u-owner", body: {} });
  assertEquals(full.status, 409);
  assertEquals((await errorOf(full)).message, "Your Squad is full: 4 of 4 seats.");
  assertEquals((await (await r.account("squad/members", { user: "u-owner" })).json()).members.length, 4);
});

Deno.test("codes are single use, expire after 14 days, and can't be your own", async () => {
  const r = squadRig(spelling("AAAA", "BBBB", "CCCC"));
  const a = (await (await r.account("squad/invite", { user: "u-owner", body: {} })).json()).code;
  assertEquals((await r.account("squad/redeem", { user: "u-priya", body: { code: a } })).status, 200);
  const reused = await r.account("squad/redeem", { user: "u-3", body: { code: a } });
  assertEquals([reused.status, (await errorOf(reused)).message], [
    409,
    "That invite code was already used. Ask your friend for a new one.",
  ]);
  // Redeeming again in a Squad you're already in is fine.
  assertEquals((await r.account("squad/redeem", { user: "u-priya", body: { code: a } })).status, 200);

  const own = (await (await r.account("squad/invite", { user: "u-owner", body: {} })).json()).code;
  assertEquals((await r.account("squad/redeem", { user: "u-owner", body: { code: own } })).status, 409);
  r.clock.advance(14 * 86_400_000 + 1);
  assertEquals((await r.account("squad/redeem", { user: "u-3", body: { code: own } })).status, 410);
  assertEquals((await r.account("squad/redeem", { user: "u-3", body: { code: "CAP-ZZZZ" } })).status, 404);
});

Deno.test("one Squad at a time, and a lapsed Squad lets nobody in", async () => {
  const r = squadRig(spelling("AAAA", "BBBB", "CCCC"));
  r.store.addUser("u-owner-2", "Jo");
  squadEntitlement(r.store, "u-owner-2");
  const first = (await (await r.account("squad/invite", { user: "u-owner", body: {} })).json()).code;
  const second = (await (await r.account("squad/invite", { user: "u-owner-2", body: {} })).json()).code;
  assertEquals((await r.account("squad/redeem", { user: "u-priya", body: { code: first } })).status, 200);
  const other = await r.account("squad/redeem", { user: "u-priya", body: { code: second } });
  assertEquals([other.status, (await errorOf(other)).message], [
    409,
    "You're already in a Squad. Leave it first to join this one.",
  ]);

  const third = (await (await r.account("squad/invite", { user: "u-owner", body: {} })).json()).code;
  r.store.entitlements[0].expiresAt = "2026-10-21T00:00:00Z";
  const lapsed = await r.account("squad/redeem", { user: "u-3", body: { code: third } });
  assertEquals([lapsed.status, (await errorOf(lapsed)).code], [403, "entitlement_required"]);
  assertEquals((await (await r.ai("quota", { user: "u-priya" })).json()).plan, "free", "members fall back to free");
});

Deno.test("the owner removes a member; a member can leave; nobody else can remove", async () => {
  const r = squadRig(spelling("AAAA", "BBBB"));
  for (const [code, user] of [["CAP-AAAA", "u-priya"], ["CAP-BBBB", "u-3"]]) {
    await r.account("squad/invite", { user: "u-owner", body: {} });
    await r.account("squad/redeem", { user, body: { code } });
  }
  const notAllowed = await r.account("squad/remove", { user: "u-3", body: { memberId: "u-priya" } });
  assertEquals(notAllowed.status, 403);
  assertEquals((await errorOf(notAllowed)).code, "bad_request");

  const removed = await (await r.account("squad/remove", { user: "u-owner", body: { memberId: "u-priya" } })).json();
  assertEquals(removed.members.map((m: { id: string }) => m.id), ["u-owner", "u-3"]);
  const left = await (await r.account("squad/remove", { user: "u-3", body: { memberId: "u-3" } })).json();
  assertEquals(left, { seats: 4, sharing: false, members: [] });
  assertEquals((await r.account("squad/members", { user: "u-3" })).status, 404);
  assertEquals((await r.account("squad/remove", { user: "u-owner", body: { memberId: "u-3" } })).status, 404);
});

Deno.test("guessing codes is capped at 10 attempts a day", async () => {
  const r = squadRig();
  for (let i = 0; i < 10; i++) {
    assertEquals((await r.account("squad/redeem", { user: "u-5", body: { code: `CAP-${i}AAA` } })).status, 404);
  }
  const capped = await r.account("squad/redeem", { user: "u-5", body: { code: "CAP-7Q4K" } });
  assertEquals(capped.status, 429);
  assertEquals((await errorOf(capped)).code, "quota_exceeded");
});

Deno.test("delete AI data clears the request log; delete account removes everything", async () => {
  const r = squadRig();
  r.deps.env.mock = true;
  await r.ai("grade", { user: "u-owner", body: fixtureJson("requests/grade") });
  await r.settle();
  assertEquals(r.store.requests.length, 1);
  const cleared = await r.account("delete-ai-data", { user: "u-owner", body: {} });
  assertEquals(await cleared.json(), fixtureJson("account-delete"));
  assertEquals(r.store.requests.length, 0);
  assertEquals(r.store.used("u-owner", "grades", "2026-10-22"), 1, "quota usage stays (it holds counts only)");

  await r.account("squad/invite", { user: "u-owner", body: {} });
  await r.account("squad/redeem", { user: "u-priya", body: { code: "CAP-7Q4K" } });
  const deleted = await r.account("delete", { user: "u-owner", body: {} });
  assertEquals(await deleted.json(), fixtureJson("account-delete"));
  assert(r.store.deleted.has("u-owner"));
  assertEquals(r.store.entitlements.filter((e) => e.userId === "u-owner"), []);
  assertEquals(r.store.squads.size, 0);
  assertEquals((await r.ai("quota", { user: "u-owner" })).status, 401);
  assertEquals((await (await r.ai("quota", { user: "u-priya" })).json()).plan, "free", "the Squad went with its owner");
  // Deleting again still answers deleted.
  assertEquals((await r.account("delete", { user: "u-owner", body: {} })).status, 200);
});
