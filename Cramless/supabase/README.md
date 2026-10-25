# Cramless backend (Supabase)

Postgres with row-level security, Storage, Auth (anonymous, Sign in with Apple, email codes) and three Edge
Functions: `ai` (the AI relay), `account` (entitlements, Squad, deletion) and `appstore-notify` (App Store Server
Notifications). The contract the app speaks is in `../docs/relay-contract.md`.

```
supabase/
  config.toml                 local settings (ports 584xx, project_id cramless)
  migrations/                 schema + RLS + storage bucket, then the service-role RPCs
  tests/database/             pgTAP: RLS, grants and the RPCs (supabase test db)
  seed.sql
  functions/
    deno.json                 import map (pinned: @anthropic-ai/sdk 1.1.0, supabase-js 2.118.0) and tasks
    ai/ account/ appstore-notify/     index.ts (wiring) + handler.ts (the routes)
    _shared/
      fixtures/               canned replies: the app bundles this folder; MOCK mode serves it byte for byte
      schemas/                contract.json (reply types = the Swift types), requests.json (bodies + limits)
      prompts/                the system prompts, one file per task
      apple/                  Apple's root certificates (public)
      appstore/               App Store signed-data verifier (WebCrypto port: ASN.1, X.509, OCSP)
      generated.ts            fixtures, prompts, schemas and roots bundled for deploys (deno task bundle)
      anthropic.ts            the Claude calls (structured outputs, streamed citations, fallback)
      plans.ts items.ts mock.ts prompts.ts store*.ts entitlements.ts …
    tests/                    deno test: handlers in-process, mock Anthropic API, test PKI, in-memory store
```

## Tests

```bash
cd supabase/functions
deno task test        # 95 tests without a database (the Postgres-backed ones are skipped)
deno task check       # type-check every entry point and test
deno task lint
deno task bundle      # after editing fixtures, prompts, schemas or apple/: regenerates _shared/generated.ts
```

No Anthropic key is needed: real mode is tested by pointing the SDK at `tests/_mock_anthropic.ts`, which checks
each request's shape and answers with canned provider replies (`deno task mock-anthropic` runs it on
127.0.0.1:58499 for manual use).

With the local stack running, the same suite also runs the store contract against the real SQL functions and an
end-to-end pass through Auth, PostgREST and Storage:

```bash
supabase start -x edge-runtime,imgproxy,logflare,mailpit,postgres-meta,realtime,studio,supavisor,vector   # CLI 2.109 names
supabase test db                                  # pgTAP
eval "$(supabase status -o env | grep -E '^(API_URL|ANON_KEY|SERVICE_ROLE_KEY)=')"
cd supabase/functions && CRAMLESS_TEST_SUPABASE_URL=$API_URL CRAMLESS_TEST_ANON_KEY=$ANON_KEY \
  CRAMLESS_TEST_SERVICE_KEY=$SERVICE_ROLE_KEY deno task test     # 106 tests
supabase stop --no-backup
```

## Running the functions locally

```bash
cp supabase/functions/.env.example supabase/functions/.env   # fill in; gitignored
supabase start
supabase functions serve --env-file supabase/functions/.env
```

- MOCK mode: `CRAMLESS_MOCK=1` in `.env`. The AI routes answer with the fixtures after real auth, validation and
  quotas; `X-Cramless-Fixture: grade-incorrect` (or `tutor-error`, …) picks another reply.
- Real mode: `ANTHROPIC_API_KEY=…`. To test against the mock API instead, `deno task mock-anthropic` and
  `ANTHROPIC_BASE_URL=http://host.docker.internal:58499` with `ANTHROPIC_API_KEY=test-anthropic-key`.
- StoreKit testing in Xcode (`Cramless.storekit`): `CRAMLESS_ALLOW_XCODE_JWS=1` (honoured only on a local stack).
- Point the app at it: `Secrets.xcconfig` → `CRAMLESS_SUPABASE_HOST = http:/$()/127.0.0.1:58421` (the simulator;
  `$()` stops xcconfig reading `//` as a comment, and `AppConfig` keeps an explicit `http` scheme) and
  `CRAMLESS_SUPABASE_ANON_KEY = <ANON_KEY from supabase status>`. A device needs the Mac's LAN address or a tunnel.

## The app against the local stack

`scripts/local_stack.sh` runs exactly what the app needs and nothing else: `supabase start` with Postgres, Auth,
PostgREST, Storage and Kong (no Studio, analytics, vector, imgproxy, mail catcher, realtime or postgres-meta), then
`supabase functions serve` in MOCK mode with an env file it writes to `build/local-stack/functions.env`
(`CRAMLESS_MOCK=1`, no keys; `LOCAL_STACK_DIR` moves it). It never reads or writes `supabase/functions/.env`, and
it only ever touches this project's containers, so other local stacks keep running.

```bash
scripts/local_stack.sh up                       # waits until ai/quota answers 401 in the envelope, prints the env
eval "$(scripts/local_stack.sh env --service --test-runner)"
SIM_ID=<udid> scripts/xc.sh test -only-testing:CramlessTests/LocalStackTests
eval "$(scripts/local_stack.sh env --service --deno)"
(cd supabase/functions && deno task test)       # the Postgres-backed tests run too
scripts/local_stack.sh down                     # stops the functions, supabase stop --no-backup (this project)
```

- `env` prints the API URL and the anon key as export lines (`CRAMLESS_LOCAL_STACK_URL`, `_ANON_KEY`); the service
  key only with `--service`. `--test-runner` adds the `TEST_RUNNER_` prefix xcodebuild forwards to the test host,
  `--deno` prints the names the Deno tests read.
- `CramlessTests/LocalStackTests` drive the app's own classes over HTTP to localhost (the simulator shares the
  Mac's): `AccountService` (anonymous sessions, refresh, email codes, sign-out), `HTTPRelayTransport` (every route,
  the tutor's stream, quotas, refusals), `SyncEngine` between two in-memory `AppModel`s on one account (rows, page
  photos, paging, tombstones), Squad, deletion and, with `TEST_RUNNER_CRAMLESS_STOREKIT_TESTS=1` too, a StoreKit
  purchase posted to `account/entitlements` (the env file's `CRAMLESS_ALLOW_XCODE_JWS=1`). They skip without the
  variables. The service key is used only by `LocalStack.Admin` (`LocalStackSupport.swift`): reading out sign-in
  codes (Auth's admin API: the local stack sends no mail), granting a Squad purchase, and reading what the server
  holds. The app never sees it.
- Boot the simulator before a StoreKit run (`xcrun simctl bootstatus <udid> -b`): when xcodebuild cold-boots it,
  purchases can fall through to a real Apple Account request and the purchase-flow tests skip.

## Deploying

See "Deploying" in `../docs/relay-contract.md`: link the project, `supabase db push`, set the Auth providers, set
the secrets (`ANTHROPIC_API_KEY`, `APPLE_BUNDLE_ID`, `APPLE_APP_ID`), `supabase functions deploy ai account
appstore-notify`, and register the notifications URL in App Store Connect. Nothing in this folder deploys itself.

## Notes

- New tables get no privileges by default on current Supabase: every grant is explicit in the first migration.
- The functions verify the session themselves (`verify_jwt = false`), so every failure comes back in the
  contract's error envelope and new asymmetric JWT keys work too.
- Logs are one allow-listed JSON line per request; nothing the person wrote or scanned is logged or stored by the
  relay. `ai_requests` keeps route, model, tokens and cost.

## Real Claude, once

```bash
cd supabase/functions
ANTHROPIC_API_KEY=sk-ant-… deno task live      # a few cents; nothing stored; the key never written anywhere
```

`tools/live_check.ts` runs the `ai` handler in-process with the real Anthropic provider on the sample page:
generate (Haiku 5.5), check, grade three answers, and the streamed tutor in both modes (Sonnet 5.5), printing what
the app would show, a PASS/FAIL per check (enough questions, three formats, real line anchors, one right answer per
choice question, expected verdicts, quotes that are the student's words, citations, hints asking a question back)
and the cost. Run it after any change in `_shared/prompts/` (then `deno task bundle`) and before launch.
`ANTHROPIC_BASE_URL=http://127.0.0.1:58499` with `deno task mock-anthropic` dry-runs the script's plumbing only.

## Checking prompts with a model answered elsewhere

`tools/prompt_replay.ts` records the relay's exact Claude calls (model, system prompt, user content, the reply's
JSON schema) and replays a reply through the relay's own validation and cleaning:

```bash
deno run -A tools/prompt_replay.ts record generate        # → ../../build/prompt_replay/generate.call.json
# … have the model answer the call (the API, or a Claude session given the call file) into generate.reply.json …
deno run -A tools/prompt_replay.ts replay generate ../../build/prompt_replay/generate.reply.json
```

Routes: `generate`, `check` (checks the last replayed generate), `grade-1|2|3` (a partial, a paraphrased and a wrong
answer), `tutor-hints|tutor-explain` (recorded only: the search-result sources are written out as tagged text).
