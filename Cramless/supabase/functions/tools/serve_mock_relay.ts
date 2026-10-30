// The relay's `ai` function in MOCK mode on a local port, for the app's wire tests (CramlessTests/AssistantWireTests): the
// app's real HTTP client against the relay's real code (routing, validation, quotas, server-sent events), with the canned
// model replies of `_shared/fixtures`. One signed-in student, "user-1", whose token is `token-user-1`, on the Pro plan so that
// web research works. Nothing leaves the Mac.
//
//   deno run -A tools/serve_mock_relay.ts [--port 54990]

import { defaultDeps } from "../_shared/deps.ts";
import { aiHandler } from "../ai/handler.ts";
import { testEnv, tokenAuthenticator } from "../tests/_harness.ts";
import { MemoryStore } from "../tests/_memory_store.ts";

const at = Deno.args.indexOf("--port");
const port = at >= 0 ? Number(Deno.args[at + 1]) : 54990;

const store = new MemoryStore();
store.addUser("user-1", "Maya", "UTC");
store.entitlements.push({
  userId: "user-1",
  plan: "pro",
  productId: "com.loopware.Capling.pro.yearly",
  originalTransactionId: "otid-user-1",
  transactionId: "t1",
  purchaseDate: "2026-10-01T00:00:00Z",
  expiresAt: "2027-10-29T00:00:00Z",
  revokedAt: null,
  environment: "Production",
});

const deps = defaultDeps({
  env: testEnv({ CRAMLESS_MOCK: "1" }),
  store,
  authenticate: tokenAuthenticator(),
  background: (task) => void task.catch(() => {}),
});

Deno.serve({
  hostname: "127.0.0.1",
  port,
  onListen: ({ port }) => console.log(`mock relay on http://127.0.0.1:${port}`),
}, aiHandler(deps));
