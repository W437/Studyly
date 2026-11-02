// Repository rules the code review would otherwise have to remember.

import { assert, assertEquals } from "@std/assert";
import { renderGenerated } from "../_shared/bundle.ts";
import { costNano, formatUsd, TERRA } from "../_shared/cost.ts";
import { readUsage } from "../_shared/openai.ts";

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
      path.endsWith("_shared/log.ts") || path.endsWith("tests/_mock_openai.ts") ||
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

Deno.test("costs: exact nano-dollars; an unknown model is priced as Terra; OpenAI's usage object, cached tokens split out", () => {
  const u = (input: number, output: number, read = 0, write = 0) => ({
    inputTokens: input,
    outputTokens: output,
    cacheReadTokens: read,
    cacheWriteTokens: write,
  });
  assertEquals(formatUsd(costNano(TERRA, u(2400, 180))), "0.003300000");
  assertEquals(formatUsd(costNano("gpt-9-unknown", u(1000, 0))), "0.001000000", "unknown models priced as Terra");
  assertEquals(
    readUsage({ input_tokens: 12, output_tokens: 7, input_tokens_details: { cached_tokens: 5 } }),
    u(7, 7, 5, 0),
  );
  assertEquals(
    readUsage({ input_tokens: 3, input_tokens_details: { cached_tokens: 9 } }),
    u(0, 0, 3, 0),
    "never negative",
  );
  assertEquals(readUsage(undefined), u(0, 0, 0, 0));
  assertEquals(formatUsd(1n), "0.000000001");
});
