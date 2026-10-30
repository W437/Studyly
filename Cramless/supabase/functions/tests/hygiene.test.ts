// Repository rules the code review would otherwise have to remember.

import { assert, assertEquals } from "@std/assert";
import { renderGenerated } from "../_shared/bundle.ts";
import { costNano, formatUsd, HAIKU, readUsage, SONNET } from "../_shared/cost.ts";

const FUNCTIONS = new URL("../", import.meta.url);
const SUPABASE = new URL("../../", import.meta.url);

async function files(dir: URL, test: (name: string) => boolean): Promise<URL[]> {
  const out: URL[] = [];
  for await (const entry of Deno.readDir(dir)) {
    const url = new URL(entry.name + (entry.isDirectory ? "/" : ""), dir);
    if (entry.isDirectory) {
      if (entry.name === ".temp" || entry.name === ".branches" || entry.name === "node_modules") continue;
      out.push(...await files(url, test));
    } else if (test(entry.name)) out.push(url);
  }
  return out;
}

Deno.test("generated.ts is up to date with the fixtures, prompts, schemas and roots (deno task bundle)", async () => {
  const current = await Deno.readTextFile(new URL("_shared/generated.ts", FUNCTIONS));
  assert(current === await renderGenerated(), "run `deno task bundle`");
});

Deno.test("only log.ts writes to the console", async () => {
  for (const url of await files(FUNCTIONS, (n) => n.endsWith(".ts"))) {
    const path = url.pathname;
    // tools/ holds developer commands (deno task live) that print their reports; they're never deployed.
    if (
      path.endsWith("_shared/log.ts") || path.endsWith("tests/_mock_anthropic.ts") ||
      path.endsWith("hygiene.test.ts") ||
      path.includes("/tools/")
    ) {
      continue;
    }
    const text = await Deno.readTextFile(url);
    assert(!/\bconsole\.(log|info|warn|error|debug)\(/.test(text), `${path} writes to the console`);
  }
});

Deno.test(".env.example ships every value empty", async () => {
  const text = await Deno.readTextFile(new URL(".env.example", FUNCTIONS));
  const assignments = text.split("\n").filter((l) => /^[A-Z_]+=/.test(l));
  assert(assignments.length >= 7);
  for (const line of assignments) assert(line.endsWith("="), `${line.split("=")[0]} has a value`);
});

Deno.test("no secrets in supabase/", async () => {
  for (const url of await files(SUPABASE, (n) => /\.(ts|sql|toml|json|md|example)$/.test(n))) {
    const text = await Deno.readTextFile(url);
    assert(!/sk-ant-[A-Za-z0-9_-]{10,}/.test(text), `${url.pathname} holds an Anthropic key`);
    assert(!/\bsk-(proj-)?[A-Za-z0-9_-]{20,}/.test(text), `${url.pathname} holds an OpenAI key`);
    assert(!/eyJ[A-Za-z0-9_-]{20,}\.eyJ[A-Za-z0-9_-]{20,}/.test(text), `${url.pathname} holds a JWT`);
    assert(!/-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(text), `${url.pathname} holds a private key`);
  }
});

Deno.test("config.toml: project cramless, anonymous sign-ins and Sign in with Apple on, functions verify JWTs themselves", async () => {
  const toml = await Deno.readTextFile(new URL("config.toml", SUPABASE));
  assert(/^project_id = "cramless"$/m.test(toml));
  assert(/^enable_anonymous_sign_ins = true$/m.test(toml));
  assert(/\[auth\.external\.apple\]\nenabled = true\nclient_id = "com\.loopware\.Capling"/.test(toml));
  for (const fn of ["ai", "account", "appstore-notify"]) {
    assert(new RegExp(`\\[functions\\.${fn}\\]\\nverify_jwt = false`).test(toml), fn);
  }
});

Deno.test("every table has row-level security, and every RPC is revoked from clients", async () => {
  const sql = (await Promise.all(
    (await files(new URL("migrations/", SUPABASE), (n) => n.endsWith(".sql"))).map((u) => Deno.readTextFile(u)),
  )).join("\n");
  const tables = [...sql.matchAll(/create table public\.(\w+)/g)].map((m) => m[1]);
  assert(tables.length >= 16, `${tables.length} tables`);
  for (const t of tables) {
    const rls = new RegExp(`alter table public\\.${t} enable row level security`).test(sql) ||
      sql.includes(`'${t}'`) && sql.includes("execute format('alter table public.%I enable row level security', t)");
    assert(rls, `${t} has no row-level security`);
  }
  const rpcs = [...sql.matchAll(/create or replace function public\.(cramless_\w+)\(/g)].map((m) => m[1])
    .filter((f) =>
      !["cramless_sync_stamp", "cramless_handle_new_user", "cramless_my_squad_ids", "cramless_my_owned_squad_ids"]
        .includes(f)
    );
  for (const f of rpcs) assert(sql.includes(`'${f}(`), `${f} isn't in the revoke list`);
});

Deno.test("costs: Haiku 5.5 $0.10/$0.50 (long prompts $0.50/$2.50), Sonnet 5.5 $2/$10, cache 0.1×/1.25×", () => {
  const u = (input: number, output: number, read = 0, write = 0) => ({
    inputTokens: input,
    outputTokens: output,
    cacheReadTokens: read,
    cacheWriteTokens: write,
  });
  assertEquals(formatUsd(costNano(HAIKU, u(100_000, 1_000_000))), "0.510000000");
  assertEquals(
    formatUsd(costNano(HAIKU, u(1_000_000, 1_000_000))),
    "3.000000000",
    "a 1M-token prompt is on the long card",
  );
  assertEquals(formatUsd(costNano(SONNET, u(1_000_000, 1_000_000))), "12.000000000");
  assertEquals(formatUsd(costNano(HAIKU, u(0, 0, 50_000, 40_000))), "0.005500000", "cache reads 0.1×, writes 1.25×");
  assertEquals(formatUsd(costNano(HAIKU, u(150_000, 1_000))), "0.077500000", "over 100K tokens: the long-prompt card");
  assertEquals(formatUsd(costNano(SONNET, u(2400, 180))), "0.006600000");
  assertEquals(formatUsd(costNano("claude-sonnet-5", u(1000, 0))), "0.002000000", "fallback models priced as Sonnet");
  assertEquals(
    readUsage({ input_tokens: 5, output_tokens: 7, cache_read_input_tokens: 2, cache_creation_input_tokens: null }),
    u(5, 7, 2, 0),
  );
  assertEquals(formatUsd(1n), "0.000000001");
});
