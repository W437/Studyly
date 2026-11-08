// Capling's in-app purchases in App Store Connect (Loopware team, app com.loopware.Capling): the "Capling Pro" subscription group with
// Squad, Pro Yearly and Pro Monthly (the two yearly plans have a one-week free trial) and Exam Pass, a 30-day pass that never renews.
// Product ids, prices and trials mirror Cramless.storekit and Store/StoreCatalog.swift; the price in every other territory is Apple's
// equalised one from the US price. Adapted from Cairn's asc_products.mjs (verified 2026-10-27). Safe to re-run: what exists is kept and
// what is missing is added. It never submits anything.
//
//   node scripts/asc/capling_products.mjs --account loopware [--dry-run] [--review-shot paywall.png] [--shots squad=a.png,yearly=b.png,monthly=c.png,pass=d.png]
//
// --review-shot uploads that image as the App Review screenshot of every product that has none; --shots gives a product its own image
// (keys: squad, yearly, monthly, pass) and wins over --review-shot. Apple keeps a product in MISSING_METADATA until it has one.
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { basename } from 'node:path';
import { call, errors } from '/Users/drvanhoover/.claude/skills/app-store-connect/scripts/asc.mjs';

const BUNDLE = 'com.loopware.Capling';
const argv = process.argv.slice(2);
if (argv[argv.indexOf('--account') + 1] !== 'loopware') { console.error('pass --account loopware (Capling is on the Loopware team)'); process.exit(2); }
const dry = argv.includes('--dry-run');
const flag = (name) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : null; };
const SHOT = flag('--review-shot');
const SHOTS = Object.fromEntries((flag('--shots') ?? '').split(',').filter(Boolean).map((kv) => kv.split('=')));
const shotFor = (key) => SHOTS[key] ?? SHOT;
const log = (s) => console.log(s);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const GROUP = 'Capling Pro';
// level 1 is the highest tier of a group. Display names are at most 30 characters and descriptions 45 (Apple's limits, checked below).
const SUBS = [
  { key: 'squad', productId: 'com.loopware.Capling.squad.yearly', reference: 'Squad Yearly', name: 'Squad', description: 'Capling Pro for you and 3 friends, yearly.',
    period: 'ONE_YEAR', level: 1, usd: '99.99', trial: 'ONE_WEEK',
    note: 'Squad shares Capling Pro with up to three friends, billed once a year to the owner. Settings (your initial at the top of Today) > Subscription > Squad.' },
  { key: 'yearly', productId: 'com.loopware.Capling.pro.yearly', reference: 'Pro Yearly', name: 'Pro Yearly', description: 'Every Capling Pro feature, billed yearly.',
    period: 'ONE_YEAR', level: 2, usd: '49.99', trial: 'ONE_WEEK',
    note: 'Capling Pro is the AI work: no weekly limit on AI scans, PDFs and lecture notes, answers in your own words graded by Cloud AI, no daily limit on Cap\'s answers and drafts, and web research from trusted sites. Reviews, flashcards, a plan and readiness for every exam, mock exams and imports are free for everyone. The plans appear at the end of the welcome and later at Settings (your initial at the top of Today) > Subscription > See Pro. "Continue free" always closes them.' },
  { key: 'monthly', productId: 'com.loopware.Capling.pro.monthly', reference: 'Pro Monthly', name: 'Pro Monthly', description: 'Every Capling Pro feature, billed monthly.',
    period: 'ONE_MONTH', level: 3, usd: '9.99',
    note: 'The same Capling Pro features, billed monthly. The plans appear at the end of the welcome and later at Settings (your initial at the top of Today) > Subscription > See Pro.' },
];
const PASS = { key: 'pass', productId: 'com.loopware.Capling.exampass', reference: 'Exam Pass (30 days)', name: 'Exam Pass', description: "30 days of Capling Pro. Doesn't renew.", usd: '14.99',
  note: 'Exam Pass is 30 days of Capling Pro, bought once, with no renewal and nothing to cancel. Settings (your initial at the top of Today) > Subscription > Exam Pass.' };
for (const p of [...SUBS, PASS]) {
  if (p.name.length > 30) throw new Error(`${p.productId}: display name is ${p.name.length} characters, the limit is 30`);
  if (p.description.length > 45) throw new Error(`${p.productId}: description is ${p.description.length} characters, the limit is 45`);
}

// One request, retried a few times when Apple is busy (429 or 5xx). In a dry run only reads are sent.
async function api(method, path, body) {
  if (dry && method !== 'GET') { log(`    [dry run] ${method} ${path.split('?')[0]}`); return { data: { id: `dry-${method}-${path.split('?')[0]}`, attributes: {} } }; }
  for (let attempt = 0; ; attempt++) {
    const r = await call(method, path, body);
    if (r.ok) return r.json;
    if (attempt < 4 && (r.status === 429 || r.status >= 500)) { await sleep(2000 * (attempt + 1)); continue; }
    throw new Error(`${method} ${path.split('?')[0]} -> ${r.status} ${errors(r)}`.slice(0, 500));
  }
}
const soft = (e) => { if (/ 404 /.test(e.message)) return null; throw e; };
async function all(path) {
  const data = [];
  for (let next = path; next;) { const j = await api('GET', next); data.push(...(j.data ?? [])); next = j.links?.next; }
  return data;
}
// Runs fn over items, a few at a time (about 175 territories per product).
async function each(items, fn, width = 4) {
  let next = 0;
  await Promise.all(Array.from({ length: width }, async () => { while (next < items.length) { const i = next++; await fn(items[i], i); } }));
}
const rel = (type, id) => ({ data: { type, id } });
const isDry = (x) => dry && String(x.id).startsWith('dry-');

// ---- one product's pieces ---------------------------------------------------------------------------------------------------------------

async function ensureLocalization(label, listPath, postPath, type, owner, ownerType, ownerRel, name, description) {
  const have = (await all(listPath)).find((l) => l.attributes.locale === 'en-US');
  if (have) { log(`  ${label}: English name and description there`); return; }
  await api('POST', postPath, { data: { type, attributes: { name, locale: 'en-US', description }, relationships: { [ownerRel]: rel(ownerType, owner) } } });
  log(`  ${label}: added the English name and description`);
}

async function priceSubscription(sub, plan, territories) {
  const have = new Set((await all(`/v1/subscriptions/${sub.id}/prices?limit=200&include=territory`)).map((p) => p.relationships?.territory?.data?.id));
  const us = (await all(`/v1/subscriptions/${sub.id}/pricePoints?filter[territory]=USA&limit=200`)).find((p) => p.attributes.customerPrice === plan.usd);
  if (!us) throw new Error(`no US price point at $${plan.usd} for ${plan.productId}`);
  const equal = await all(`/v1/subscriptionPricePoints/${us.id}/equalizations?limit=200&include=territory`);
  const points = [{ id: us.id, territory: 'USA' }, ...equal.map((p) => ({ id: p.id, territory: p.relationships?.territory?.data?.id })).filter((p) => p.territory)];
  const todo = points.filter((p) => !have.has(p.territory));
  if (!todo.length) { log(`  price: $${plan.usd} in ${have.size} territories already`); return; }
  await each(todo, (p) => api('POST', '/v1/subscriptionPrices', { data: { type: 'subscriptionPrices', attributes: { startDate: null, preserveCurrentPrice: false },
    relationships: { subscription: rel('subscriptions', sub.id), subscriptionPricePoint: rel('subscriptionPricePoints', p.id), territory: rel('territories', p.territory) } } }));
  log(`  price: $${plan.usd} set in ${todo.length} more territories (${points.length} in all, equalised from the US price)`);
}

async function trialOffers(sub, plan, territories) {
  const have = new Set((await all(`/v1/subscriptions/${sub.id}/introductoryOffers?limit=200&include=territory`)).map((o) => o.relationships?.territory?.data?.id));
  const todo = territories.filter((t) => !have.has(t));
  if (!todo.length) { log(`  free trial: one week in ${have.size} territories already`); return; }
  let failed = 0;
  await each(todo, async (t) => {
    try {
      await api('POST', '/v1/subscriptionIntroductoryOffers', { data: { type: 'subscriptionIntroductoryOffers', attributes: { duration: plan.trial, offerMode: 'FREE_TRIAL', numberOfPeriods: 1, startDate: null, endDate: null },
        relationships: { subscription: rel('subscriptions', sub.id), territory: rel('territories', t) } } });
    } catch (e) { failed++; log(`  free trial not set in ${t}: ${e.message.slice(0, 140)}`); }
  });
  log(`  free trial: one week set in ${todo.length - failed} more territories${failed ? `, ${failed} failed` : ''}`);
}

async function subscriptionAvailability(sub, territories) {
  const have = await api('GET', `/v1/subscriptions/${sub.id}/subscriptionAvailability`).catch(soft);
  if (have?.data) { log('  availability: set already'); return; }
  await api('POST', '/v1/subscriptionAvailabilities', { data: { type: 'subscriptionAvailabilities', attributes: { availableInNewTerritories: true },
    relationships: { subscription: rel('subscriptions', sub.id), availableTerritories: { data: territories.map((id) => ({ type: 'territories', id })) } } } });
  log(`  availability: ${territories.length} territories, new ones included`);
}

// The App Review screenshot of one subscription ('sub') or in-app purchase ('iap'); skipped when it has one.
async function reviewShot(kind, ownerId, label, file) {
  const [getPath, postPath, type, relName, relType] = kind === 'sub'
    ? [`/v1/subscriptions/${ownerId}/appStoreReviewScreenshot`, '/v1/subscriptionAppStoreReviewScreenshots', 'subscriptionAppStoreReviewScreenshots', 'subscription', 'subscriptions']
    : [`/v2/inAppPurchases/${ownerId}/appStoreReviewScreenshot`, '/v1/inAppPurchaseAppStoreReviewScreenshots', 'inAppPurchaseAppStoreReviewScreenshots', 'inAppPurchaseV2', 'inAppPurchases'];
  const have = (await api('GET', getPath).catch(soft))?.data;
  if (have && ['COMPLETE', 'UPLOAD_COMPLETE'].includes(have.attributes.assetDeliveryState?.state)) { log(`  ${label}: review screenshot there already`); return; }
  if (have) await api('DELETE', `${postPath}/${have.id}`);       // a reservation that never finished uploading
  const bytes = readFileSync(file);
  const made = (await api('POST', postPath, { data: { type, attributes: { fileName: basename(file), fileSize: bytes.length }, relationships: { [relName]: rel(relType, ownerId) } } })).data;
  for (const op of made.attributes.uploadOperations ?? []) {
    const res = await fetch(op.url, { method: op.method, headers: Object.fromEntries(op.requestHeaders.map((h) => [h.name, h.value])), body: bytes.subarray(op.offset, op.offset + op.length) });
    if (!res.ok) throw new Error(`upload for ${label} (part at ${op.offset}) -> ${res.status}`);
  }
  await api('PATCH', `${postPath}/${made.id}`, { data: { type, id: made.id, attributes: { uploaded: true, sourceFileChecksum: createHash('md5').update(bytes).digest('hex') } } });
  log(`  ${label}: review screenshot uploaded`);
}

// A product's App Review note follows the words here: creating a product sets it, and this keeps one that exists in step. Not yet run against the live record.
async function syncNote(type, product, plan) {
  if (isDry(product) || product.attributes.reviewNote === plan.note) return;
  const path = type === 'inAppPurchases' ? `/v2/inAppPurchases/${product.id}` : `/v1/subscriptions/${product.id}`;
  await api('PATCH', path, { data: { type, id: product.id, attributes: { reviewNote: plan.note } } });
  log('  review note: updated');
}

// ---- the whole set ----------------------------------------------------------------------------------------------------------------------

async function main() {
  const apps = (await api('GET', `/v1/apps?filter[bundleId]=${BUNDLE}`)).data;
  if (apps.length !== 1) throw new Error(`expected one app with bundle id ${BUNDLE}, found ${apps.length}`);
  const app = apps[0];
  log(`${app.attributes.name} (${app.id})${dry ? ' (dry run: only reads are sent)' : ''}`);
  const territories = (await all('/v1/territories?limit=200')).map((t) => t.id);

  let group = (await all(`/v1/apps/${app.id}/subscriptionGroups?limit=200`)).find((g) => g.attributes.referenceName === GROUP);
  if (!group) {
    group = (await api('POST', '/v1/subscriptionGroups', { data: { type: 'subscriptionGroups', attributes: { referenceName: GROUP }, relationships: { app: rel('apps', app.id) } } })).data;
    log(`Subscription group ${GROUP}: created`);
  } else log(`Subscription group ${GROUP}: there`);
  if (!isDry(group)) {
    const have = (await all(`/v1/subscriptionGroups/${group.id}/subscriptionGroupLocalizations`)).find((l) => l.attributes.locale === 'en-US');
    if (!have) {
      await api('POST', '/v1/subscriptionGroupLocalizations', { data: { type: 'subscriptionGroupLocalizations', attributes: { name: GROUP, locale: 'en-US' }, relationships: { subscriptionGroup: rel('subscriptionGroups', group.id) } } });
      log('  group name: added');
    }
  }

  const existing = isDry(group) ? [] : await all(`/v1/subscriptionGroups/${group.id}/subscriptions?limit=200`);
  for (const plan of SUBS) {
    let sub = existing.find((s) => s.attributes.productId === plan.productId);
    log(`${plan.productId}: ${sub ? 'there' : 'creating'}`);
    if (!sub) {
      sub = (await api('POST', '/v1/subscriptions', { data: { type: 'subscriptions', attributes: {
        name: plan.reference, productId: plan.productId, subscriptionPeriod: plan.period, familySharable: false, groupLevel: plan.level, reviewNote: plan.note,
      }, relationships: { group: rel('subscriptionGroups', group.id) } } })).data;
    }
    await syncNote('subscriptions', sub, plan);
    if (isDry(sub) || isDry(group)) continue;
    await ensureLocalization('name', `/v1/subscriptions/${sub.id}/subscriptionLocalizations`, '/v1/subscriptionLocalizations', 'subscriptionLocalizations', sub.id, 'subscriptions', 'subscription', plan.name, plan.description);
    await subscriptionAvailability(sub, territories);     // Apple refuses a price in a territory the product is not available in yet
    await priceSubscription(sub, plan, territories);
    if (plan.trial) await trialOffers(sub, plan, territories);
  }

  // Exam Pass: a non-renewing subscription, which App Store Connect files under in-app purchases.
  let pass = (await all(`/v1/apps/${app.id}/inAppPurchasesV2?limit=200`)).find((i) => i.attributes.productId === PASS.productId);
  log(`${PASS.productId}: ${pass ? 'there' : 'creating'}`);
  if (!pass) {
    pass = (await api('POST', '/v2/inAppPurchases', { data: { type: 'inAppPurchases', attributes: {
      name: PASS.reference, productId: PASS.productId, inAppPurchaseType: 'NON_RENEWING_SUBSCRIPTION', reviewNote: PASS.note, familySharable: false,
    }, relationships: { app: rel('apps', app.id) } } })).data;
  }
  await syncNote('inAppPurchases', pass, PASS);
  if (!isDry(pass)) {
    await ensureLocalization('name', `/v2/inAppPurchases/${pass.id}/inAppPurchaseLocalizations`, '/v1/inAppPurchaseLocalizations', 'inAppPurchaseLocalizations', pass.id, 'inAppPurchases', 'inAppPurchaseV2', PASS.name, PASS.description);
    if (!(await api('GET', `/v2/inAppPurchases/${pass.id}/iapPriceSchedule`).catch(soft))?.data) {
      const point = (await all(`/v2/inAppPurchases/${pass.id}/pricePoints?filter[territory]=USA&limit=200`)).find((p) => p.attributes.customerPrice === PASS.usd);
      if (!point) throw new Error(`no US price point at $${PASS.usd} for ${PASS.productId}`);
      await api('POST', '/v1/inAppPurchasePriceSchedules', {
        data: { type: 'inAppPurchasePriceSchedules', relationships: { inAppPurchase: rel('inAppPurchases', pass.id), baseTerritory: rel('territories', 'USA'),
          manualPrices: { data: [{ type: 'inAppPurchasePrices', id: '${price-usa}' }] } } },
        included: [{ type: 'inAppPurchasePrices', id: '${price-usa}', attributes: { startDate: null }, relationships: {
          inAppPurchaseV2: rel('inAppPurchases', pass.id), inAppPurchasePricePoint: rel('inAppPurchasePricePoints', point.id) } }],
      });
      log(`  price: $${PASS.usd}, the other territories follow the US price`);
    } else log('  price: set already');
    if (!(await api('GET', `/v2/inAppPurchases/${pass.id}/inAppPurchaseAvailability`).catch(soft))?.data) {
      await api('POST', '/v1/inAppPurchaseAvailabilities', { data: { type: 'inAppPurchaseAvailabilities', attributes: { availableInNewTerritories: true },
        relationships: { inAppPurchase: rel('inAppPurchases', pass.id), availableTerritories: { data: territories.map((id) => ({ type: 'territories', id })) } } } });
      log(`  availability: ${territories.length} territories, new ones included`);
    } else log('  availability: set already');
  }

  if ((SHOT || Object.keys(SHOTS).length) && !dry) {
    log('Review screenshots');
    for (const sub of await all(`/v1/subscriptionGroups/${group.id}/subscriptions?limit=200`)) {
      const file = shotFor(SUBS.find((p) => p.productId === sub.attributes.productId)?.key);
      if (file) await reviewShot('sub', sub.id, sub.attributes.productId, file);
    }
    if (shotFor(PASS.key)) await reviewShot('iap', pass.id, PASS.productId, shotFor(PASS.key));
  }

  if (!dry) {
    log('State');
    for (const s of await all(`/v1/subscriptionGroups/${group.id}/subscriptions?limit=200`)) log(`  ${s.attributes.productId}: ${s.attributes.state}`);
    const p = (await api('GET', `/v2/inAppPurchases/${pass.id}`)).data;
    log(`  ${p.attributes.productId}: ${p.attributes.state}`);
    if (!SHOT && !Object.keys(SHOTS).length) log('Each product stays in MISSING_METADATA until it has a review screenshot: pass --review-shot <png> or --shots key=png,...');
  }
}

main().catch((e) => { console.error(`FAILED: ${e.message}`); process.exit(1); });
