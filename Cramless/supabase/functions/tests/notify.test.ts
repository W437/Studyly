// App Store Server Notifications V2: renewals, expiries and refunds update the entitlement row they name.

import { assertEquals } from "@std/assert";
import { buildVerifiers } from "../_shared/appstore/verifier.ts";
import { APP_APPLE_ID, BUNDLE_ID, NOW, rig } from "./_harness.ts";
import { makeChain, signJws, signXcodeJws } from "./_pki.ts";

const now = new Date(NOW);
const DAY = 86_400_000;

async function setup() {
  const chain = await makeChain({ now });
  const verifiers = buildVerifiers({
    roots: [chain.root.der],
    bundleId: BUNDLE_ID,
    appAppleId: APP_APPLE_ID,
    allowXcode: true,
    onlineChecks: false,
    now: () => now,
  });
  const r = rig({ verifiers });
  r.store.addUser("user-1");
  r.store.entitlements.push({
    userId: "user-1",
    plan: "pro",
    productId: "com.loopware.Capling.pro.monthly",
    originalTransactionId: "1000",
    transactionId: "1001",
    purchaseDate: "2026-10-01T00:00:00Z",
    expiresAt: "2026-11-01T00:00:00Z",
    revokedAt: null,
    environment: "Production",
  });
  const notification = async (type: string, t: Record<string, unknown>) =>
    await signJws(chain, {
      notificationType: type,
      notificationUUID: crypto.randomUUID(),
      signedDate: now.getTime(),
      data: {
        bundleId: BUNDLE_ID,
        appAppleId: APP_APPLE_ID,
        environment: "Production",
        signedTransactionInfo: await signJws(chain, {
          transactionId: "1002",
          originalTransactionId: "1000",
          bundleId: BUNDLE_ID,
          productId: "com.loopware.Capling.pro.monthly",
          purchaseDate: Date.parse("2026-11-01T00:00:00Z"),
          expiresDate: Date.parse("2026-12-01T00:00:00Z"),
          type: "Auto-Renewable Subscription",
          environment: "Production",
          signedDate: now.getTime(),
          ...t,
        }),
      },
    });
  return { r, notification, chain };
}

Deno.test("a renewal extends the subscription; a refund revokes it", async () => {
  const { r, notification } = await setup();
  const renewed = await r.notify({ signedPayload: await notification("DID_RENEW", {}) });
  assertEquals(await renewed.json(), { ok: true, outcome: "applied", type: "DID_RENEW" });
  assertEquals(r.store.entitlements[0].expiresAt, "2026-12-01T00:00:00Z");
  assertEquals((await (await r.ai("quota")).json()).plan, "pro");

  await r.notify({ signedPayload: await notification("REFUND", { revocationDate: now.getTime() - DAY }) });
  assertEquals(r.store.entitlements[0].revokedAt, "2026-10-21T09:00:00Z");
  assertEquals((await (await r.ai("quota")).json()).plan, "free");
});

Deno.test("an older transaction is stale; one we've never seen is ignored", async () => {
  const { r, notification } = await setup();
  const stale = await r.notify({
    signedPayload: await notification("DID_RENEW", { purchaseDate: Date.parse("2026-09-01T00:00:00Z") }),
  });
  assertEquals((await stale.json()).outcome, "stale");
  const unknown = await r.notify({
    signedPayload: await notification("SUBSCRIBED", { originalTransactionId: "9999" }),
  });
  assertEquals((await unknown.json()).outcome, "unknown");
  assertEquals(r.store.entitlements.length, 1);
});

Deno.test("unverifiable payloads are 400; Xcode payloads never count here", async () => {
  const { r } = await setup();
  assertEquals((await r.notify({ signedPayload: "a.b.c" })).status, 400);
  assertEquals((await r.notify({ nope: true })).status, 400);
  const xcode = await signXcodeJws({
    notificationType: "DID_RENEW",
    data: { bundleId: BUNDLE_ID, environment: "Xcode" },
  });
  assertEquals((await r.notify({ signedPayload: xcode })).status, 400);
  const otherRoot = await makeChain({ now });
  const forged = await signJws(otherRoot, {
    notificationType: "REFUND",
    data: { bundleId: BUNDLE_ID, appAppleId: APP_APPLE_ID, environment: "Production" },
  });
  assertEquals((await r.notify({ signedPayload: forged })).status, 400);
});
