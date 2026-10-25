# The relay contract

What the iPhone app sends to the Cramless backend and what comes back. The contract is ours, not a model
provider's: the app speaks it, the Supabase Edge Functions translate it, and a provider change never reaches a
shipped app.

- Swift types: `Cramless/AI/RelayContract.swift` (the source of truth).
- JSON schemas: `supabase/functions/_shared/schemas/contract.json` (replies) and `requests.json` (request bodies,
  with the size limits the relay enforces). `tests/schemas.test.ts` parses the Swift file and fails when a field
  name or its optionality differs from the schema.
- Examples: `supabase/functions/_shared/fixtures/*.json`. The app bundles the same folder for its mock transport,
  and the relay's MOCK mode serves these files byte for byte.

## Conventions

- Base URL: `https://<project>.supabase.co/functions/v1/` (the app builds it from `Secrets.xcconfig`).
- Every request: `Authorization: Bearer <Supabase access token>` and `apikey: <anon key>`. Request bodies are JSON
  (`Content-Type: application/json`).
- JSON keys are camelCase. Dates are ISO 8601 in UTC without fractions (`2026-11-05T00:00:00Z`), which
  `JSONDecoder.cramless` reads.
- Optional fields may be missing or `null`. New fields are added as optionals; a field is never repurposed. The
  relay ignores request fields it doesn't know.
- Line ids are `p<page>.l<n>` (recognised text) or `p<page>.c<n>` (cloud transcription); transcript segment ids
  are `s<n>`; key idea ids `k<n>`; item ids are short strings the generator picks (`i1`).

## Sessions

Every route needs a Supabase session. Anonymous sessions count: the app creates one on first need
(`AccountService.accessToken()`), so quotas and purchases work before anyone signs in. Sign in with Apple and email
one-time codes turn it into a real account (needed for sync and photo backup). The relay checks the token with
Supabase Auth (deleted users are refused) and caches the answer for a minute.

## Errors

Every failure is JSON with an HTTP status:

```json
{"error": {"code": "quota_exceeded", "message": "That's today's 20 graded answers on the free plan. Quick check still works, and it resets at midnight.", "quota": {"plan": "free", "meters": [{"key": "grades", "used": 20, "limit": 20, "period": "day"}]}}}
```

| code | HTTP | Meaning | App (`RelayError.from`) |
|---|---|---|---|
| `unauthorized` | 401 | No token, an expired or invalid one, or a deleted account. | `.unauthorized`: refresh the session, then retry once. |
| `quota_exceeded` | 429 | A free quota ran out (`quota` names the meter), a paid plan's fair-use ceiling (`retryAfter` in seconds, and a `Retry-After` header), or too many Squad code attempts. | `.quotaExceeded(quota, message)`: fall back to the on-device path; show the message. |
| `entitlement_required` | 403 | The request needs a paid plan or an active Squad (a scan over 10 pages on free, inviting without a Squad subscription, joining a lapsed Squad). | `.entitlementRequired`: offer the paywall. |
| `bad_request` | 400, 404, 405, 409, 410, 413, 422 | The body failed validation (the message names the first field: `The request isn't valid: /maxItems is below 1.`), an unknown route or method, a too-large body, a used, expired or unknown invite code, a purchase that failed verification (422). | `.badRequest(message)` |
| `upstream` | 500, 502, 503, 504, 422 | The model or the database failed, timed out, declined (422), or answered something unusable. `retryAfter` when a retry soon can work. The quota is given back. | `.upstream(message)`: quiet fallback to the offline path. |

Messages are short, safe to show and never contain the person's material.

## Plans and quotas

The plan is the best active entitlement (Squad > Pro > Exam Pass), or `squad` for a member of a Squad whose
owner's Squad subscription is active; otherwise `free`.

| Meter (`QuotaMeter.key`) | Period | Free | Pro, Squad, Exam Pass | Counted by |
|---|---|---|---|---|
| `scans` | week | 3 (up to 10 pages each) | unlimited (fair use 150; up to 40 pages per scan) | `generate`, `transcribe-image` |
| `grades` | day | 20 | unlimited (fair use 1,500) | `grade` |
| `tutor` | day | 10 | unlimited (fair use 300) | `tutor` |
| `lectures` | week | 1 | unlimited (fair use 40) | `lecture` |

- Days and weeks are the person's own: local midnight and Monday in the time zone of their profile (the app
  writes `profiles.timezone`; UTC until it does).
- A scan is a capture session: the page transcriptions (`transcribe-image`, one page each) and the `generate` call
  that closes them count once, within 30 minutes and 10 pages. A `generate` without transcriptions is one scan.
  On free, a `generate` with more than 10 pages is `entitlement_required`.
- A request that fails (an `upstream` error, a refusal, a tutor stream that breaks before any text) gives its quota
  back. A refused request (validation, quota) costs nothing.
- `check`, `confusions` and `cards-from-chat` share an internal meter (`extras`: 120 a day on free, 800 paid) that
  the app never shows; Squad code attempts are capped at 10 a day.
- Reviews are never metered: they happen on the device.

## AI routes (`ai` function)

Models: Claude Haiku 5.5 (`claude-haiku-5-5`) for everything except the tutor and grading `apply` questions or
answers over 700 characters, which use Claude Sonnet 5.5 (`claude-sonnet-5-5`). Every reply the app consumes is a
structured output (a JSON schema derived from `contract.json`, without `model`, which the relay sets to the model
that answered). Sonnet calls use server-side refusal fallback (`fallbacks: "default"`). Prompts are files in
`supabase/functions/_shared/prompts/`: grounded only in the given material, material treated as data, no essays
or "humanizing", hints first and teen-safe for minors, "Your material doesn't cover that" when ungrounded.

### `POST ai/generate` → `GenerateResponse`

Request `GenerateRequest`: `course`, `sourceTitle`, `level?`, `language` (BCP 47), `formats` (any of `recall`,
`apply`, `mcq`, `cloze`, `diagram`, `flashcard`), `maxItems` (1–40), `pages` (1–40 `PageInput`: `page` index,
`label` as printed, `lines` [`{id, text}`], `image?` base64 JPEG, only with "Send page photos" on).

Reply: `title`, `model`, `topics` [`{name, summary}`], `items` [`GeneratedItem`]. A `GeneratedItem` has `id`,
`kind`, `topic`, `prompt`, `answer`, `explanation`, `keyIdeas` [`{id, label, terms}`: lowercase phrasings that
count], `choices` [`{text, correct, why?}`], `cloze?` (`{text}` with `{{…}}` around each blank, `alternates`
per blank), `diagramLabels?` (line ids of the labels to hide), `anchors` (the line ids it came from), `difficulty`
(0–1).

The relay drops any item whose anchors aren't line ids of the request (or that has none), any item not in
`formats`, and any item malformed for its kind (a multiple choice without exactly one correct choice, a cloze
without a blank, a diagram whose labels aren't real lines, an own-words item without key ideas), and keeps at most
`maxItems`. If nothing survives, the answer is `upstream` and the scan is given back. Meter: `scans`. Haiku 5.5,
effort medium.

### `POST ai/check` → `CheckResponse`

Request `CheckRequest`: `pages` (as above) and `items` (generated items). Reply: `model` and one `verdicts` entry
per request item, in request order: `id`, `verdict` (`supported`, `fixed`: use `fixedAnswer?` / `fixedChoices?`,
`unsupported`: drop it), `reason` (a sentence the person can read). Items whose anchors aren't in the pages are
`unsupported` without reaching the model (and `model` is `relay` when none are left); an item the model skipped is
`unsupported`. Meter: `extras`. Haiku 5.5, effort medium.

### `POST ai/grade` → `GradeResponse`

Request `GradeRequest`: `kind`, `level?`, `prompt`, `modelAnswer`, `keyIdeas`, `response` (the person's answer),
`sourceExcerpt?`. Reply: `model`, `score` (0–1), `verdict` (`correct`, `partial`, `incorrect`), `confidence` (0–1;
below 0.6 the app offers "Grade again"), `hits` [`{ideaId, quote}`: words copied from the answer; the app highlights
a quote only where it finds it verbatim], `missing` (the key ideas without a hit), `feedback`, `fix` (one sentence
that completes the answer; empty when nothing is missing). An empty answer is graded `incorrect` without a model
call or a quota. Meter: `grades`. Haiku 5.5 at low effort; Sonnet 5.5 at medium for `apply` and long answers.

### `POST ai/tutor` → server-sent events

Request `TutorRequest`: `mode` (`hints`, `explain`), `minor` (always hints first, teen-safe scope), `course?`,
`messages` [`{role: user|assistant, text}`, the last one the person's], `sources` [`{id, title, label, text}`: the
passages the app retrieved; the model never searches], `context?` (`{itemPrompt, expected, given}` for "Explain my
mistake").

Reply: `Content-Type: text/event-stream`. Each event is `event: <name>`, one `data: <JSON>` line and a blank line;
`: ping` comments keep a quiet connection open.

| event | data | Meaning |
|---|---|---|
| `start` | `{model}` | The answer has started. |
| `delta` | `{text}` | More of the answer; append it. |
| `citation` | `{sourceId, label, quote}` | The words just streamed rest on this passage: `sourceId` is a request source's `id`, `label` its label, `quote` the cited sentence(s) of it. |
| `done` | `{model}` | The answer is complete. |
| `error` | `{code, message}` | The answer stopped (codes as above, usually `upstream`). |

Errors before the stream starts (auth, validation, quota) are ordinary JSON envelopes. The sources go to Sonnet 5.5
as `search_result` blocks with citations on, split into sentence-sized blocks so citations stay tight. Closing the
connection stops the model. Meter: `tutor` (given back if the stream fails before any text). MOCK: the
`tutor-hints` script (or `tutor-explain` when `mode` is `explain` and the person isn't a minor), with its delays.

### `POST ai/confusions` → `ConfusionsResponse`

Request `ConfusionsRequest`: `course`, `mistakes` [`{itemId, topic, prompt, expected, given, misses}`]. Reply:
`model`, `confusions` (0–3) [`{name, explanation, itemIds, lesson, questions}`]: `itemIds` are request item ids
(others are removed; a confusion without any is dropped); `questions` are generated items without anchors (the
request has no line ids). Meter: `extras`. Haiku 5.5, effort low.

### `POST ai/lecture` → `LectureResponse`

Request `LectureRequest`: `course`, `title`, `segments` [`{id, start, end, text}`, seconds], `flags` [`{time,
text}`: moments the person tapped], `maxItems`. Reply: `model`, `title`, `summary`, `sections` [`{id, title,
start, end, bullets}`], `keyTerms`, `examFlags` [`{time, text, why}`], `items` (anchored to segment ids; others
dropped). Times are clamped to the recording. Meter: `lectures` (AI notes for one lecture a week on free). Haiku 5.5,
effort medium.

### `POST ai/cards-from-chat` → `CardsFromChatResponse`

Request `CardsFromChatRequest`: `course?`, `messages` (the tutor chat), `maxItems` (1–20). Reply: `model`, `items`
(flashcards, multiple choice, recall or cloze, with empty `anchors`: an item claiming line ids is dropped, since a
chat has none). Meter: `extras`. Haiku 5.5, effort low.

### `POST ai/transcribe-image` → `TranscribeImageResponse`

Request `TranscribeImageRequest`: `image` (base64 JPEG; PNG is detected too), `page`, `label`. Reply: `model`,
`lines` [`{id, text}`] in reading order, ids `p<page>.c<n>` assigned by the relay. Cloud lines have no geometry:
they can be cited and searched, never boxed on the page. Meter: `scans` (one page of the open scan). Haiku 5.5,
effort low.

### `GET ai/quota` → `QuotaStatus`

`plan` and `meters` [`{key, used, limit, period}`] for `scans`, `grades`, `tutor`, `lectures`, in that order.
`limit` is `null` (unlimited) on paid plans; `used` still counts.

## Account routes (`account` function)

### `POST account/entitlements` → `EntitlementResponse`

Request `EntitlementRequest`: `signedTransactions`, the `jwsRepresentation` of every current StoreKit entitlement
(up to 20). Each is verified like Apple's `SignedDataVerifier` (the x5c chain to Apple's roots, Apple's certificate
markers, OCSP for both links, ES256, then bundle ID and environment). A transaction for another app, or for an
environment the server doesn't accept (Xcode on a hosted project), is skipped; any other failure rejects the whole
request (422 `bad_request`, or 503 `upstream` when Apple's OCSP service is unreachable). Verified transactions are
saved by original transaction: a purchase synced from another account moves to this one (restoring purchases on a
new install), and an older transaction never rolls a newer one back.

| Product | Plan | Ends |
|---|---|---|
| `com.loopware.Capling.pro.yearly`, `…pro.monthly` | `pro` | the transaction's `expiresDate` |
| `com.loopware.Capling.squad.yearly` | `squad` (the purchaser owns a Squad) | `expiresDate` |
| `com.loopware.Capling.exampass` | `pass` | purchase + 30 days (non-renewing) |

Reply: `plan` (after Squad membership too), `expiresAt?` and `quota` (as `ai/quota`). `GET account/entitlements`
returns the same without syncing.

### Squad

Four seats: the owner (who bought Squad) and three friends. Codes look like `CAP-7Q4K`, are single use and expire
after 14 days.

| Route | Request | Reply | Errors |
|---|---|---|---|
| `POST account/squad/invite` | `{}` | `SquadInvite` `{code, url, expiresAt}` | 403 `entitlement_required` (no active Squad subscription), 409 `bad_request` (full) |
| `POST account/squad/redeem` | `{code}` (any case) | `SquadRedeemResponse` `{plan: "squad", ownerName}` | 404 unknown, 409 used / own Squad / already in another Squad / full, 410 expired, 403 `entitlement_required` (the owner's subscription ended), 429 after 10 attempts a day |
| `GET account/squad/members` | | `SquadMembers` `{seats: 4, members: [{id, name, joinedAt, isOwner}]}`, owner first | 404 not in a Squad |
| `POST account/squad/remove` | `{memberId}` | `SquadMembers` (empty `members` after leaving) | 403 `bad_request` (only the owner removes someone else), 404 |

Redeeming a code of the Squad you're already in succeeds and leaves the code unused. When the owner's Squad
subscription ends, members are back on free; when the owner deletes their account, the Squad goes with it.

### Deletion

- `POST account/delete-ai-data` `{}` → `{deleted: true}`: deletes the AI request log (`ai_requests`, which never
  held content) and the open scan. Quota counts stay, so deleting can't reset a quota.
- `POST account/delete` `{}` → `{deleted: true}`: deletes every row the person owns, their storage folder and the
  auth user. The token stops working; a second call (or a 401 right after) means it's done.

## App Store Server Notifications (`appstore-notify`)

`POST appstore-notify` with Apple's `{signedPayload}` (Version 2; Production and Sandbox, never Xcode). Apple's
signature is the authentication. A renewal, expiry, refund or revocation updates the row of its original
transaction when it is newer; unknown transactions are ignored (the app syncs them on its next launch). Anything
that verifies answers 200 `{ok, outcome: applied|stale|unknown|ignored, type}`; an unverifiable payload answers 400.

## MOCK mode

`CRAMLESS_MOCK=1` on the functions (local or a staging project, never production): the AI routes answer with the
fixtures, after the same authentication, plan, validation and quota logic, so the app can be exercised against a
real backend without a model key.

| Route | Fixture | Latency |
|---|---|---|
| `generate` | `generate.json` | 2.5 s |
| `check` | `check.json` | 1.5 s |
| `grade` | `grade-correct`, `grade-partial` or `grade-incorrect`: every key idea named in the answer (a term or the label, case-insensitive) → correct, some → partial, none → incorrect | 0.9 s |
| `tutor` | `tutor-hints.json` (or `tutor-explain.json`), events at the script's `delayMs` | per event |
| `confusions` | `confusions.json` | 1.8 s |
| `lecture` | `lecture.json` | 2.5 s |
| `cards-from-chat` | `cards-from-chat.json` | 1.2 s |
| `transcribe-image` | `transcribe-image.json` | 1.5 s |

The JSON replies are the fixture files' bytes. The output cleaning of real mode (anchor filtering) doesn't apply:
the fixtures are the reference answers. A request header `X-Cramless-Fixture: <name>` picks another fixture of the
same route (`grade-incorrect`, `tutor-error`, …) so every state can be shown. Account routes have no MOCK mode; the
app's own mock transport covers them offline.

## Logging and cost

One JSON log line per request with an allow-list of fields (route, status, code, latency, plan, model, tokens,
cost); never bodies, prompts, the person's material, user ids or tokens. Each AI call also writes an `ai_requests`
row (route, model, plan, status, tokens, cost, latency). Costs are computed in integer nano-dollars from list
prices: Haiku 5.5 $0.10 / $0.50 per million input / output tokens ($0.50 / $2.50 for prompts over 100K tokens),
Sonnet 5.5 $2 / $10; cache reads 0.1× and cache writes 1.25× the input price.

## The database (for the Sync client)

Tables in `supabase/migrations/`, all with row-level security:

- Synced, owned by `auth.uid()`: `courses`, `topics`, `sources`, `source_pages`, `items`, `review_logs`, `exams`,
  `study_sessions`, `day_records`, `confusions`. Columns are the Swift model fields in snake_case; `…Data` blobs are
  `jsonb`. Clients select, insert and update their own rows (never delete: tombstones are `deleted_at`).
  `review_logs` is insert-only (`Prefer: resolution=ignore-duplicates`). `user_id` defaults to the caller and can't
  change; `synced_at` is stamped by the server on every write and is the pull cursor (`order=synced_at.asc,id.asc`,
  then `or=(synced_at.gt."<ts>",and(synced_at.eq."<ts>",id.gt."<id>"))`). An update whose `updated_at` is older than
  the stored row's changes nothing (last writer wins).
- `profiles` (display name for Squad, time zone for quotas), readable and writable by their owner.
- Service only (the functions): `entitlements`, `usage_counters`, `scan_windows`, `squads`, `squad_members`,
  `squad_invites`, `ai_requests`. Owners can read their own entitlements, usage and Squad.
- Storage: the private `sources` bucket, one folder per person (`<user id>/<source id>/<file>`), 15 MB a file; a
  signed-in (not anonymous) session uploads, the owner reads.

## Deploying

Nothing here deploys by itself. With the Supabase CLI logged in (`supabase login`):

1. Create the project, then `supabase link --project-ref <ref>` from the folder that holds `supabase/`.
2. `supabase db push` applies the migrations.
3. Auth (dashboard → Authentication): enable anonymous sign-ins; enable Apple with the bundle ID
   `com.loopware.Capling` as an authorized client ID (native sign-in needs no secret); keep email sign-in on with
   a 6-digit code (set the "Magic Link" template to show `{{ .Token }}`); set rate limits for anonymous sign-ins
   (Supabase's default of 30 an hour per IP is fine).
4. Secrets: `supabase secrets set ANTHROPIC_API_KEY=… APPLE_BUNDLE_ID=com.loopware.Capling APPLE_APP_ID=<numeric
   App Apple ID>` (optional: `CRAMLESS_INVITE_BASE_URL`). Never set `CRAMLESS_MOCK` or `CRAMLESS_ALLOW_XCODE_JWS`
   on production.
5. `supabase functions deploy ai account appstore-notify` (each uses `supabase/functions/deno.json`; JWT
   verification is done inside the functions, so `verify_jwt = false` in `config.toml` is intended).
6. App Store Connect → the app → App Information → App Store Server Notifications: Version 2, Production and
   Sandbox URL `https://<ref>.supabase.co/functions/v1/appstore-notify`.
7. The app: `Secrets.xcconfig` gets `CRAMLESS_SUPABASE_HOST = <ref>.supabase.co` and
   `CRAMLESS_SUPABASE_ANON_KEY = <anon or publishable key>` (gitignored).
