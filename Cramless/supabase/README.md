# Cramless backend (Supabase)

Postgres with row-level security, Storage, Auth (anonymous, Sign in with Apple, email codes) and three Edge
Functions: `ai` (the AI relay), `account` (entitlements, Squad, deletion) and `appstore-notify` (App Store Server
Notifications). The contract the app speaks is in `../docs/relay-contract.md`.

```
supabase/
  config.toml                 local settings (ports 584xx, project_id cramless)
  migrations/                 schema + RLS + storage bucket, then the service-role RPCs, then day_records.quest_mask (the quests
                              a day finished, one bit each; the app joins two devices' masks by OR), the assistant's meters, and
                              `cramless_spent_since` (what a person's AI calls cost today: the relay's daily cost cap, 10¢,
                              `DAILY_COST_CAP_USD`). Apply the migrations before deploying the functions that use them.
  tests/database/             pgTAP: RLS, grants and the RPCs (supabase test db)
  seed.sql
  functions/
    deno.json                 import map (pinned: supabase-js 2.118.0) and tasks
    ai/ account/ appstore-notify/     index.ts (wiring) + handler.ts (the routes)
    _shared/
      fixtures/               canned replies: the app bundles this folder; MOCK mode serves it byte for byte
      schemas/                contract.json (reply types = the Swift types), requests.json (bodies + limits)
      prompts/                the system prompts, one file per task
      apple/                  Apple's root certificates (public)
      appstore/               App Store signed-data verifier (WebCrypto port: ASN.1, X.509, OCSP)
      generated.ts            fixtures, prompts, schemas and roots bundled for deploys (deno task bundle)
      provider.ts             the call and event types every route uses, and the Provider interface
      openai.ts               every route on OpenAI: strict structured outputs for the JSON routes, the tutor's streamed JSON answer with its quotes checked against the passages
      openai_assistant.ts     the assistant (tools) and web research
      research_sources.ts     the sites web research never uses (OpenStax, Chegg, Quizlet, …): the one list, applied to the prompt, the search and the reply
      plans.ts items.ts mock.ts prompts.ts store*.ts entitlements.ts …
    tests/                    deno test: handlers in-process, a mock of OpenAI's Responses API, test PKI, in-memory store
```

## Tests

```bash
cd supabase/functions
deno task test        # 95 tests without a database (the Postgres-backed ones are skipped)
deno task check       # type-check every entry point and test
deno task lint
deno task bundle      # after editing fixtures, prompts, schemas or apple/: regenerates _shared/generated.ts
```

No OpenAI key is needed to test: real mode is tested by pointing the provider at `tests/_mock_openai.ts`, which checks
each request's shape (a strict structured output, nothing stored) and answers with canned replies (`deno task mock-openai`
runs it on 127.0.0.1:58499 for manual use).

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
- Real mode: `OPENAI_API_KEY=…` (every AI route runs on OpenAI). To test against the mock API instead, `deno task mock-openai` and
  `OPENAI_BASE_URL=http://host.docker.internal:58499/v1` with `OPENAI_API_KEY=test-openai-key`.
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
the secrets (`OPENAI_API_KEY`, `APPLE_BUNDLE_ID`, `APPLE_APP_ID`), `supabase functions deploy ai account
appstore-notify`, and register the notifications URL in App Store Connect. Nothing in this folder deploys itself.

## Notes

- New tables get no privileges by default on current Supabase: every grant is explicit in the first migration.
- The functions verify the session themselves (`verify_jwt = false`), so every failure comes back in the
  contract's error envelope and new asymmetric JWT keys work too.
- Logs are one allow-listed JSON line per request; nothing the person wrote or scanned is logged or stored by the
  relay. `ai_requests` keeps route, model, tokens and cost.

## Real OpenAI, every route, once

```bash
cd supabase/functions
OPENAI_API_KEY=sk-… deno task live      # a few cents; nothing stored; the key never written anywhere
```

`tools/live_check.ts` runs the `ai` handler in-process with the real OpenAI provider on the sample page (GPT 6.1 Terra on
every route): generate, check, grade three answers, and the streamed tutor in both modes, printing what the app would show, a
PASS/FAIL per check (enough questions, three formats, real line anchors, one right answer per choice question, expected
verdicts, quotes that are the student's words, citations, hints asking a question back) and the cost. `LIVE_ONLY=grade,check`
runs some of them. Run it after any change in `_shared/prompts/` (then `deno task bundle`) and before launch.
`OPENAI_BASE_URL=http://127.0.0.1:58499/v1` with `deno task mock-openai` dry-runs the script's plumbing only.

## Real OpenAI, once

```bash
cd supabase/functions
OPENAI_API_KEY=sk-… deno task live-openai      # a fraction of a cent; nothing stored; the key never written anywhere
```

`tools/live_openai.ts` runs the `ai` handler in-process with the real OpenAI provider (GPT 6.1 Terra at low reasoning
unless `OPENAI_TUTOR_MODEL` / `OPENAI_TUTOR_EFFORT` say otherwise) and asks the tutor four questions about the sample page:
hints, explain, a question the page can't answer and an under-18 account. It prints what the app would show, a PASS/FAIL
per check (a quote that is on the page, hints ending on a question, no source id in the answer, no outside knowledge) and
the cost. Run it before the tutor changes and after changing the tutor's prompts. The 33-question comparison
that chose the model is `tools/tutor_bakeoff/` (docs/BUILD.md ▸ Ask Cap on OpenAI).

## Checking prompts with a model answered elsewhere

`tools/prompt_replay.ts` records the relay's exact model calls (model, system prompt, user content, the reply's
JSON schema) and replays a reply through the relay's own validation and cleaning:

```bash
deno run -A tools/prompt_replay.ts record generate        # → ../../build/prompt_replay/generate.call.json
# … have the model answer the call (the API, or another model session given the call file) into generate.reply.json …
deno run -A tools/prompt_replay.ts replay generate ../../build/prompt_replay/generate.reply.json
```

Routes: `generate`, `check` (checks the last replayed generate), `grade-1|2|3` (a partial, a paraphrased and a wrong
answer), `tutor-hints|tutor-explain` (recorded only: the search-result sources are written out as tagged text).
