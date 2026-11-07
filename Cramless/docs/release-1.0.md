# Release 1.0: from here to Submit

Every step from main at 3105a20 (2026-11-07) to the owner pressing Submit for Review, in order. Each says who does it and the
exact command or website step. Nothing here has been run: it was read from the code, the scripts and `docs/BUILD.md`. The
places I couldn't make certain are under "Not certain" at the end.

**Who:** *Owner* is a step only the owner can do (accounts, money, legal, the phone, Submit). *Claude, on your go* is a step
that writes to something real (the production database and relay, App Store Connect, a public site) and waits for the
owner's word each time. *Claude* is local work.

**Names used below:** the Supabase project `capling` (ref `xwzhopcsdqjvgqntatel`, org Amplified); the App Store Connect app
6828649543 (`com.loopware.Capling`, Loopware team, version 1.0, build 1.0 (5) attached today); lockbox entries
`SUPABASE_ACCESS_TOKEN` and `OPENAI_KEY_CAPLING_APP-PROD` (it sets `OPENAI_API_KEY`); `G=~/.claude/skills/app-store-connect/scripts`.
Commands run from `Cramless/` of a checkout of main unless they say otherwise.

## The owner's decisions (any time before the step that needs them)

| Decision | Needed by | Where to decide |
|---|---|---|
| The store page: the 8 screenshots, image 5's word, the two extra images, the description, the video in or out of the preview slot | Steps 20 to 23 | https://macbook-pro.tail9699dc.ts.net:4898/capling-launch-store/ |
| App Privacy: declare the time zone kept with the account ("Other Data Types")? | Step 10 (it changes the privacy manifest inside the build) | `docs/privacy-wording.md` section 3 |
| The age rating: `ageAssurance` true once the phone has shown the age sheet working, and 4+ or 13+ | Step 24 | `docs/privacy-wording.md` section 4 |
| Approve the relay deploy | Steps 7 and 8 | Step 6's results |
| Approve the upload | Step 16 | The full suite's result, step 12 |
| A featuring date, and with it the release option | Steps 26 and 27 | `docs/featuring-nomination-draft.md` |
| The paywall headline: keep "You'll be ready." (a promise, while the exam page says "not a promise"), or "Sleep the night before. You'll know where you stand.", or "More of Cap, right up to the exam." | Step 12 (it's in the build) | The paywall screen; `Features/Paywall/PaywallCopy.swift` |
| Delete the test users on production: the simulated user tests' `~/Documents/capling-user-test/stage2/cleanup.sql` and `stage34/cleanup.sql`, the 28 anonymous users a test run made at 22:14 UTC on 6 Nov, and `f5aac1be-6b6b-475d-abb4-e0ea2d21301e` (a filming take); each delete waits for a yes at the Supabase prompt | Before real users | `docs/BUILD.md` ▸ The build plan's gates |

## A. The owner's accounts (now, in parallel with everything else)

1. **Upgrade the Supabase plan.** *Owner.* supabase.com ▸ the Amplified organization ▸ Billing ▸ upgrade from Free to Pro. The free
   plan pauses a project after a week without traffic. A paused project during App Review means no Cloud AI, sign-in, sync,
   purchases or Squad for the reviewer, and the review notes promise them.
2. **Set an OpenAI spend limit.** *Owner.* platform.openai.com ▸ the project the Capling key belongs to ▸ Limits: a monthly budget
   and an alert. The relay's own caps stay as they are (10¢ a day per free account, 40¢ a day and 70¢ a week per paid one).
3. **Register capling.app.** *Owner.* A Squad invite is a link to `https://capling.app/squad/<code>` (`DEFAULT_INVITE_BASE_URL` in
   `supabase/functions/_shared/env.ts`). The app has no associated domain, so nothing in it breaks without the domain, but a
   tapped link goes nowhere until the domain exists and serves a page. The code typed in still works.
4. **File the trademark** for "Capling". *Owner.* Not needed to submit; needed before money is spent on the name.
5. **The Paid Applications agreement.** *Owner* (the Account Holder). App Store Connect ▸ Business: the agreement is Active and no
   banner asks to accept an updated schedule. Nothing can be sold until it is.

## B. The relay and the database (before the build reaches anyone signed in)

The new build syncs a field the production database doesn't have yet (`items.rung_of`). Until the first migration is applied,
sync fails for anyone signed in with Apple or email, the owner's TestFlight copy included. So the database goes first, then the
functions, then the build.

6. **The checks before the deploy.** *Claude.* All on main, nothing touches production:
   - The relay's tests, including the check that `_shared/generated.ts` matches the prompts and fixtures:
     `cd supabase/functions && deno task check && deno task test`.
   - The two migrations and the store contract on a real Postgres (Docker must be running): `scripts/local_stack.sh up` (it applies
     all seven migrations), then `eval "$(scripts/local_stack.sh env --service --deno)"; (cd supabase/functions && deno task test)`,
     which also runs `tests/store_contract.test.ts` and `tests/local_stack.test.ts` against the real SQL functions, Squad ones
     included; `supabase test db` (pgTAP); then `scripts/local_stack.sh down`. Stage 4 ran its SQL only on a throwaway Postgres
     with stubs, because Docker was off then.
   - Every new route on the real model (a few cents; the owner approves the lockbox prompt):
     `cd supabase/functions && lockbox run OPENAI_KEY_CAPLING_APP-PROD -- env LIVE_ONLY=lookalike,syllabus,exam-mention,tutor,mistake,photo,reports,rung,last-look deno task live`.
     Pass: no FAIL line.
   - The tutor bakeoff, for snapping a problem and the mistake's three parts (never run with a key):
     `cd supabase/functions && lockbox run OPENAI_KEY_CAPLING_APP-PROD -- deno run --no-check --allow-net=api.openai.com --allow-env=HOME,OPENAI_API_KEY --allow-read --allow-write tools/tutor_bakeoff/run.ts --configs terra-low --groups problem,mistake`,
     then `deno run --no-check --allow-read --allow-write tools/tutor_bakeoff/report.ts <the folder it printed>`. Pass: hints
     mode hands over the answer no more often than Terra at low effort did in `build/bakeoff/run4` (13%), and every mistake reply
     passes `parts`. **Note:** `run.ts` reads `~/.config/capling/openai_key` before the environment, and that file exists on this
     Mac, so this run uses the file's key, not lockbox's (see "Not certain").
7. **Apply the two migrations, in this order.** *Claude, on your go.*
   1. `supabase/migrations/20261107000000_cramless_rung_of.sql`: adds the nullable `items.rung_of` (a harder question points at the
      easier one). The new build's sync needs it.
   2. `supabase/migrations/20261108000000_cramless_squad_activity.sql`: `profiles.share_squad_activity` (off by default), the
      `squad_activity` table, two new service-role functions (`cramless_squad_share`, `cramless_squad_studied`) and new
      versions of `cramless_squad_members`, `cramless_squad_remove` and `cramless_delete_account_data`. The new `account`
      function calls them.

   Both only add: a new column with a default, a new table, functions with the same signatures returning extra fields, so the
   relay that is live now (`ai` v13 and the current `account`) keeps working between this step and the next. Route: first read
   what production has (Supabase MCP `list_migrations` on `xwzhopcsdqjvgqntatel`; it should list the five up to
   `20261027000100`), then Supabase MCP `apply_migration` with each file's name and its SQL, one at a time, and `list_migrations`
   again. The CLI way is `lockbox run SUPABASE_ACCESS_TOKEN -- supabase link --project-ref xwzhopcsdqjvgqntatel`, then
   `supabase db push --dry-run` and `supabase db push`, which asks for the database password (it isn't in lockbox).
8. **Deploy the functions from main.** *Claude, on your go.* After step 7:
   `lockbox run SUPABASE_ACCESS_TOKEN -- supabase functions deploy account --project-ref xwzhopcsdqjvgqntatel --use-api`, then the same
   with `ai` (it becomes version 14). What they carry since v13: the look-alike lesson, a snapped problem (`fromPhoto`) and the
   mistake's three parts, `check` with reports and `generate` with a rung, `syllabus`, `exam-mention`, `last-look`, the Squad's
   share and studied routes, and the fix questions' fixture. No new secret. `appstore-notify` has no change that matters and stays
   as it is.
9. **Right after the deploy.** *Claude.* `curl -s https://xwzhopcsdqjvgqntatel.supabase.co/functions/v1/ai/quota` answers 401 in
   the contract's error envelope (the function boots); Supabase MCP `list_edge_functions` shows `ai` and `account` with new
   versions; `query_logs` for the edge functions shows no boot error. The two-account Squad check is step 19, once a build talks to
   this relay.

## C. The release build

10. **The time zone row, if the owner wants it.** *Claude, on your go.* Add `NSPrivacyCollectedDataTypeOtherDataTypes` (linked, not
    tracking, App Functionality) to `Cramless/Resources/PrivacyInfo.xcprivacy`, beside the nine declared types. It is inside the
    build, so it comes before the archive. The App Privacy answer itself is step 25.
11. **The build number.** *Claude.* `project.yml`: `CURRENT_PROJECT_VERSION: "5"` becomes `"6"` (`MARKETING_VERSION` stays "1.0"; the
    widget extension takes the same number). Commit on a branch, merge to main.
12. **The full suite on the release tree.** *Claude.* `simq sim --device "iPhone 17 Pro" --os 27.0 --udid`, then
    `TZ=America/New_York SIM_ID=<udid> scripts/xcq.sh test`, then `simq sim release <udid>`. Pass: 0 failures (the last run, on
    3105a20: 2,344 run, 27 skipped, 0 failures). Any later fix means this step again.
13. **The relay's address in the build.** *Claude.* `Cramless/Secrets.xcconfig` (gitignored) gets
    `CRAMLESS_SUPABASE_HOST = xwzhopcsdqjvgqntatel.supabase.co` and `CRAMLESS_SUPABASE_ANON_KEY = <the project's anon key>` (public;
    Supabase MCP `get_publishable_keys`, or the dashboard ▸ Project Settings ▸ API). Builds 2 to 5 had a 32-character host and a
    208-character key. A build with blank values has no Cloud AI, sign-in, sync or Squad.
14. **Signing.** *Claude.* `node $G/asc-sign.mjs --account loopware status` (the Loopware distribution certificate runs to
    2027-10-26; the profiles are `Claude App Store com.loopware.Capling` and `Claude App Store com.loopware.Capling.Widgets`). If a
    profile is missing or expired: `node $G/asc-sign.mjs --account loopware profile com.loopware.Capling`, and the same for
    `com.loopware.Capling.Widgets`. Then `node $G/asc-sign.mjs --account loopware unlock`.
15. **The Release archive and the IPA.** *Claude.*
    ```bash
    xcodegen generate
    F=$(node $G/asc-sign.mjs --account loopware flags com.loopware.Capling | sed "s/PROVISIONING_PROFILE_SPECIFIER='[^']*' //")
    eval "simq run build -- xcodebuild -project Cramless.xcodeproj -scheme Cramless -configuration Release \
      -destination 'generic/platform=iOS' -archivePath build/archive/Capling-1.0-6/Capling.xcarchive archive $F \
      PROVISIONING_PROFILE_SPECIFIER='\$(ASC_PROFILE_\$(PRODUCT_BUNDLE_IDENTIFIER:identifier))' \
      ASC_PROFILE_com_loopware_Capling='Claude App Store com.loopware.Capling' \
      ASC_PROFILE_com_loopware_Capling_Widgets='Claude App Store com.loopware.Capling.Widgets'"
    cp <main checkout>/Cramless/build/archive/Capling-1.0-5/ExportOptions.plist build/archive/Capling-1.0-6/
    xcodebuild -exportArchive -archivePath build/archive/Capling-1.0-6/Capling.xcarchive \
      -exportPath build/archive/Capling-1.0-6 -exportOptionsPlist build/archive/Capling-1.0-6/ExportOptions.plist
    ```
    Build 5's `ExportOptions.plist` is the one that worked (both profiles, manual signing, the Loopware certificate). Check the
    IPA as builds 3 to 5 were checked: version 1.0 (6), the widget 6, `Apple Distribution: Loopware LLC`, get-task-allow false,
    no device list, iPhone only. Then blank `Secrets.xcconfig` again and note the IPA's SHA-256 in BUILD.md.
16. **Upload.** *Claude, on your go.* `node $G/asc-sign.mjs --account loopware upload build/archive/Capling-1.0-6/Capling.ipa`
    (altool with the API key). Apple took about three minutes to reach `VALID` for builds 3 to 5.
17. **Attach it to version 1.0.** *Claude, on your go.* `node scripts/asc/capling_asc.mjs --account loopware build 6 --dry-run`, then
    without `--dry-run`: it waits for `VALID` and attaches build 6 in place of build 5. Never submits.

## D. On the owner's phone

18. **TestFlight.** *Claude, then Owner.* Check for an internal group: `node $G/asc.mjs --account loopware get /v1/apps/6828649543/betaGroups`.
    If none, make one with access to all builds and add the account holder as its tester (the app-store-connect skill ▸ Getting
    a build to TestFlight, step 1). Then the owner opens TestFlight on the iPhone, signed in with that Apple ID, and installs
    Capling 1.0 (6). (`phone-install` can't: this build is signed for the App Store.) Purchases inside TestFlight are sandbox
    purchases and cost nothing; the server accepts sandbox transactions.
19. **The device checks.** *Owner*, with Claude on the second account. The list is under "Device checks owed" below. Anything that
    fails is fixed, then steps 11 to 17 again with the next build number. The two-account Squad check: the phone buys Squad in
    TestFlight, signs in (Settings ▸ Account) and invites (Settings ▸ Squad ▸ Invite a friend). The friend is a second phone on
    TestFlight, or the Simulator with a Debug build that has step 13's `Secrets.xcconfig`, signed in by email code, joining
    with the code. Both turn on "Show when I've studied"; the friend finishes a session; within 15 minutes the phone shows them
    as studied today, on the Squad page and in Today's "Your plan". Then the friend turns sharing off and the mark goes.

## E. The store page (after the owner approves it)

20. **Screenshots.** *Claude, on your go.* Put the chosen frames from the main checkout's
    `Cramless/build/review/launch-finish/final/en-US/` into one folder as `01.png` to `10.png` (01 to 04; 05 as `05.png`,
    `05-cards.png` or `05-help.png`; 06 to 08; then the two extras, for example `x-notice.png` and `x-mock.png`, as 09 and 10). Then
    `node scripts/asc/capling_asc.mjs --account loopware screenshots en-US <folder> --replace --dry-run`, and without `--dry-run`.
    English only; Apple shows the English set in every other language.
21. **The words in 39 languages.** *Claude, on your go.* `node scripts/asc/capling_asc.mjs --account loopware listing --only text,translations --dry-run`,
    then without. Only the description changes; the subtitle, keywords and promotional text are what's there.
22. **The review notes.** *Claude, on your go.* First the list in `docs/review-notes-draft.md` ▸ "Before these go in": cut any line
    the phone didn't confirm in step 19, in the draft and in `reviewNotes` of `scripts/asc/capling_copy.json`, which hold the
    same text. Then `node scripts/asc/capling_asc.mjs --account loopware listing --only review --dry-run` and without (it keeps
    the contact on the record). The three attachments (`busy-ask-card.png`, `squad-switch.png`,
    `mock-card-after-sample-and-paste.png`, in the main checkout's `build/review/launch-words/`) go in App Review Information ▸
    Attachment on the website.
23. **The video.** *Claude, on your go.* The preview in the slot today still says 42% to 91%. Either replace it:
    `node scripts/asc/capling_preview.mjs --account loopware en-US <main checkout>/Cramless/build/review/launch-store/video/capling-app-preview.mp4 --frame 00:00:01:20 --replace --dry-run`,
    then without; or, as I'd do for the first submission (App Review 2.3.4: previews are screen captures, and this one is drawn),
    take it out of the preview slot on the website (version 1.0 ▸ App Previews ▸ delete). The header and search card stay.
24. **The age rating.** *Claude, on your go.* If the owner changes `ageAssurance` or the rating, edit `AGE` in
    `scripts/asc/capling_asc.mjs`, then `listing --only age --dry-run` and without.
25. **App Privacy and the purchases on the version.** *Owner* (or Claude in the automation browser after
    `node $G/asc-browser.mjs login`). Both are website-only:
    - App Privacy: no answer changes for 1.0 (`docs/privacy-wording.md` section 3). If step 10 was done, add Other Data ▸ Other
      Data Types (App Functionality, linked to the user, not tracking), then Publish.
    - Version 1.0 ▸ In-App Purchases and Subscriptions: select the three plans of "Capling Pro" and the Exam Pass. A first purchase
      can only be reviewed with an app version.
    - Then the products' own review notes, which still list plans and readiness under Pro: `node scripts/asc/capling_products.mjs --account loopware --dry-run`,
      then without. This update has never run against the live record.
    - Last, `node scripts/asc/capling_asc.mjs --account loopware ready`: nothing missing.

## F. Publishing what goes with it

26. **The release option.** *Owner.* Version 1.0 ▸ App Store Version Release: "Manually release this version" if a featuring date
    was nominated (the approved build waits for that day), otherwise "Automatically release this version".
27. **The featuring nomination.** *Owner.* App Store Connect ▸ Capling ▸ Featuring ▸ Nominations ▸ + ▸ Create Nomination, App Launch,
    with the fields in `docs/featuring-nomination-draft.md`, at least three weeks before the publish date.
28. **Loopware's privacy page.** *Claude, on your go*, the day of submission. In `~/Documents/GitHub/loopware-landing`, a new
    worktree from a fresh `origin/main`: the `#capling` section of `src/components/PrivacyPage.jsx` becomes the text of
    `docs/privacy-page-draft.md`; `npm ci`, `npm run build`, eslint, a render of the page; fetch again, then push to main as a
    fast-forward (Netlify publishes in about a minute; other sessions push there too); check https://loopware.app/privacy.
    It describes this build, and App Review reads it during review. Build 1.0 (5) is in no one's hands, so nobody is misled
    by it going up the day of submission.

## G. Submit

29. **Submit for Review.** *Owner only.* Version 1.0 ▸ Add for Review ▸ Submit for Review, with build 6 and the four purchases.

## Device checks owed

From `docs/BUILD.md` (each stage's "not checked" and "Left for the owner ▸ On a device"), the four stage review pages' "Try on
your phone" and `docs/review-notes-draft.md`. Most of the app has only run on the simulator. Step 19 is where these happen.

- **Age:** iOS's age range sheet appears once in onboarding and doesn't come back; an answer of under 13 shows "Capling is free for you" on
  the paywall and keeps Cloud AI off; 13 to 17 gives hints first. (Then `ageAssurance`, step 24.)
- **Permissions as the review notes describe them:** the microphone prompt on the first Study out loud, lecture or Teach Cap;
  whether iOS also asks for Speech Recognition (`scripts/device_probe.sh` reports the status before and after a transcription;
  the purpose string stays until this is known); the camera on first use; the calendar prompt after "Check my calendar".
- **The camera:** the document camera on real pages (+ ▸ Scan pages), on a real syllabus (exam ▸ ⋯ ▸ Set from your syllabus: is
  the date right, are the topics yours?) and on a printed problem in Ask (are the words right, math too; does the first reply
  give a hint with a page chip?).
- **Study out loud on a walk:** screen locked, Cap keeps asking and hearing, and doesn't take his own voice for yours; with
  AirPods; a call mid-question pauses and asks again; saying "B", "it's C", "the second one"; Repeat and Skip from the Lock
  Screen and the Dynamic Island; "Study out loud with Capling" to Siri.
- **A lecture:** record a few minutes with the screen locked, play it back under the notes, lock the phone (it keeps playing,
  with the Lock Screen controls); headphones; a call.
- **The calendar:** a real day 1 to 6 days out with 3 hours or more of busy events and an exam within 14 days gets "Monday looks
  busy"; Undo gives the minutes back.
- **Purchases and accounts:** a sandbox purchase of Pro (the yearly plan's trial), the Exam Pass and Restore; Sign in with Apple
  and the email code; the Squad check in step 19.
- **Notifications:** a ping from Cap in the week before an exam replaces that day's reminder, and opens Today with that card first.
- **In the background:** a question kept with "Answer it later" in Airplane mode arrives as a quiet notification once the
  connection is back; a timed mock reaching zero while locked has "Time's up" waiting with the answers kept; the last look
  prepared 48 hours before an exam opens in Airplane mode.
- **Live Activities, widgets and the Control:** the session's activity on the Lock Screen and in the Dynamic Island, the exam
  week's activity, the three widgets, the Control in Control Center; "How ready am I in Capling" answering without opening the app.
- **Feel:** the flashcard swipe's two haptic ticks; Today's sky tilting with the phone; a real swipe through Today and pull to
  refresh staying smooth; Cap's clips (and with Low Power Mode and Reduce Motion); the alternate icon's system alert.
- **VoiceOver:** a real session with the Undo pill (announced, reachable, long enough), the sky's rotors. Never checked on a phone.
- **Look and words:** the dashed "about 70% after today" ring on the day card reads as a projection, not a second score.

## Not certain

- **How production's migrations are applied.** BUILD.md says the first five were applied on 2026-11-02 without saying how, and
  the database password isn't in lockbox, so `supabase db push` would need the owner. The Supabase MCP route depends on that
  server reaching the Amplified organization from the session that does it. Step 7 reads the list first either way.
- **The store contract after the deploy.** The brief named it among the checks after; it creates users through the service key,
  so I put it on the local stack, before the deploy (step 6), where it tests the same SQL without leaving test users in
  production. After the deploy, the two-account Squad check covers the real thing.
- **The tutor bakeoff's key.** `tools/tutor_bakeoff/run.ts` takes `~/.config/capling/openai_key` before `OPENAI_API_KEY`, and the
  file exists on this Mac (I checked only that it exists). Under lockbox, the run would still use the file. Moving that key into
  lockbox and deleting the file, or changing the script's order, is the owner's call. `deno task live` reads only the environment.
- **The archive command.** BUILD.md records what builds 3 to 5 were (signed, profiles, checks) but not the command line. Step 15 is
  the app-store-connect skill's form for an app with a widget, and build 5's `ExportOptions.plist`, which did work.
- **The bakeoff's bar.** 13% comes from the hints mode of 2026-10-26; the problem group has no earlier number to compare with.
- **App Privacy and the purchases on the version** have no API in our scripts, so step 25's first two items are website steps
  I haven't seen for this app.
- **The migrations only add,** as far as I can read: the live `account` (deployed 2026-11-02; `store_postgres.ts` is the same at 2b5bf10 and 056ae19) takes only `id`, `name`,
  `joined_at` and `is_owner` from `cramless_squad_members`, so the new fields pass it by. I didn't run the old function against the
  new SQL.
