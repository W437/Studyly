// App Store Connect chores for the Capling record (com.loopware.Capling, Loopware team): the iOS 27 product page header and
// search-results card (Asset Library, API 4.5.1), placed on a version's localizations. Adapted from Keepable's keepable_asc.mjs
// (Cleanroll repo), which verified this flow on 2026-10-29. Re-runnable: it reads what is there and only writes what differs. It
// never submits for review, never touches prices and never prints credentials (they come from the app-store-connect skill's helper).
//
//   node scripts/asc/capling_asc.mjs --account loopware status
//   node scripts/asc/capling_asc.mjs --account loopware creative <locale> <header.png 3840x1646> <search.png 3:2> [--dry-run]
//   node scripts/asc/capling_asc.mjs --account loopware locales <folder> [--only de-DE,ja] [--dry-run]
//        <folder>/<locale>/header-<locale>.png and search-<locale>.png for every language (build_locales.py writes them). Adds the
//        language to the version when it is missing, places its two pictures, and gives the languages in REUSE (the English
//        variants) the same two images as their source language, uploaded once.
//   --dry-run reads and checks everything (file sizes, the version, what is placed already) and writes nothing.
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { basename, join } from 'node:path';
import { call, errors } from '/Users/drvanhoover/.claude/skills/app-store-connect/scripts/asc.mjs';

const BUNDLE = 'com.loopware.Capling';
const REUSE = { 'en-AU': 'en-US', 'en-CA': 'en-US', 'en-GB': 'en-US' };   // same as locales.py REUSE
const argv = process.argv.slice(2);
if (argv[argv.indexOf('--account') + 1] !== 'loopware') { console.error('pass --account loopware (Capling is on the Loopware team)'); process.exit(2); }
const dry = argv.includes('--dry-run');
const onlyIdx = argv.indexOf('--only');
const only = onlyIdx >= 0 ? argv[onlyIdx + 1].split(',') : null;
const args = argv.filter((a, i) => a !== '--account' && argv[i - 1] !== '--account' && a !== '--dry-run' && a !== '--only' && argv[i - 1] !== '--only');
const [command, ...rest] = args;
const log = (s) => console.log(s);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function api(method, path, body) {
  const r = await call(method, path, body);
  if (!r.ok) throw new Error(`${method} ${path.split('?')[0]} -> ${r.status} ${errors(r)}`.slice(0, 600));
  return r.json;
}
async function all(path) {
  const data = [];
  for (let next = path; next;) { const j = await api('GET', next); data.push(...(j.data ?? [])); next = j.links?.next; }
  return data;
}

// Sends each part Apple asks for, in the order and with the headers it gave.
async function sendParts(operations, bytes, label) {
  for (const op of operations ?? []) {
    const res = await fetch(op.url, { method: op.method, headers: Object.fromEntries(op.requestHeaders.map((h) => [h.name, h.value])), body: bytes.subarray(op.offset, op.offset + op.length) });
    if (!res.ok) throw new Error(`upload of ${label} (part at ${op.offset}) -> ${res.status}`);
  }
}
// Apple answers the "uploaded" PATCH with a 500 now and then; it works on a retry. The Asset Library commit takes no checksum.
async function markUploaded(path, type, id) {
  for (let attempt = 0; ; attempt++) {
    try { return await api('PATCH', path, { data: { type, id, attributes: { uploaded: true } } }); }
    catch (e) { if (attempt >= 3 || !/ 5\d\d /.test(e.message)) throw e; await sleep(3000); }
  }
}

const SLOTS = { PRODUCT_PAGE_HEADER_ASSET: 'header', APP_STORE_SEARCH_RESULTS_ASSET: 'search' };
const placements = (locId, type) => api('GET', `/v1/appStoreVersionLocalizations/${locId}/placements?filter[placementType]=${type}&include=image&limit=50`);

async function target() {
  const found = (await api('GET', `/v1/apps?filter[bundleId]=${BUNDLE}`)).data;
  if (found.length !== 1) throw new Error(`expected one app with bundle id ${BUNDLE}, found ${found.length}`);
  const app = found[0];
  const version = (await all(`/v1/apps/${app.id}/appStoreVersions`))[0];
  return { app, version };
}

// A PNG's size and colour type from its header, so a wrong file is stopped before anything is sent.
function pngInfo(file) {
  const b = readFileSync(file);
  if (b.subarray(1, 4).toString() !== 'PNG') throw new Error(`${file} is not a PNG`);
  return { bytes: b, width: b.readUInt32BE(16), height: b.readUInt32BE(20), alpha: b[25] === 4 || b[25] === 6 };
}
function checkFile(type, file) {
  const p = pngInfo(file);
  const ratio = p.width / p.height;
  if (p.alpha) throw new Error(`${file} has an alpha channel (Apple takes none)`);
  if (type === 'PRODUCT_PAGE_HEADER_ASSET' && (p.width !== 3840 || p.height !== 1646)) throw new Error(`${file} is ${p.width}x${p.height}, the header must be 3840x1646`);
  if (type === 'APP_STORE_SEARCH_RESULTS_ASSET' && (Math.abs(ratio - 1.5) > 0.002 || p.width < 1920 || p.width > 3840)) throw new Error(`${file} is ${p.width}x${p.height}, the search card must be 3:2, 1920 to 3840 wide`);
  return p;
}

async function status() {
  const { app, version } = await target();
  log(`${app.attributes.name} (${app.id}) ${app.attributes.bundleId}, version ${version.attributes.versionString} ${version.attributes.appStoreState}`);
  const locs = await all(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=200`);
  const odd = [];
  const counts = { header: 0, search: 0 };
  for (const loc of locs) for (const type of Object.keys(SLOTS)) {
    const have = await placements(loc.id, type);
    const images = new Map((have.included ?? []).map((i) => [i.id, i.attributes]));
    const rows = have.data.map((p) => { const i = images.get(p.relationships?.image?.data?.id); return `${i?.fileName} ${i?.imageAsset?.width}x${i?.imageAsset?.height} ${p.attributes.state}`; });
    if (have.data.length && have.data.every((p) => p.attributes.state === 'ACTIVE')) counts[SLOTS[type]]++;
    else odd.push(`${loc.attributes.locale} ${SLOTS[type]}: ${rows.join('; ') || 'nothing placed'}`);
  }
  log(`${locs.length} localizations: ${counts.header} headers and ${counts.search} search cards placed and active`);
  for (const o of odd) log(`  ${o}`);
}

// Reserves, uploads and places one picture for one slot of one localization (an image already in the library is reused, not sent again).
async function placeSlot(ctx, loc, locale, type, file) {
  const bytes = readFileSync(file), name = basename(file), label = SLOTS[type];
  const { library, ref } = ctx;
  const group = ref.features.find((f) => f.featureId === 'APP_STORE_VERSIONS').placementPolicies.find((p) => p.placementType === type).groupLimits[0].groupIds[0];
  const have = loc ? await placements(loc.id, type) : { data: [], included: [] };
  const images = new Map((have.included ?? []).map((i) => [i.id, i.attributes]));
  if (have.data.some((p) => { const i = images.get(p.relationships?.image?.data?.id); return i?.fileName === name && i.fileSize === bytes.length; })) { log(`${locale} ${label}: ${name} is already placed`); return; }
  if (dry) { log(`${locale} ${label}: would ${have.data.length ? `replace ${have.data.length} placement(s) with` : 'upload and place'} ${name} (group ${group})`); return; }
  for (const p of have.data) await api('DELETE', `/v1/appAssetLibraryPlacements/${p.id}`);
  let image = ctx.images().find((i) => i.attributes.fileName === name && i.attributes.fileSize === bytes.length && i.attributes.category === 'CREATIVE_ASSETS');
  if (!image) {
    image = (await api('POST', '/v1/appAssetLibraryImages', { data: { type: 'appAssetLibraryImages', attributes: { fileName: name, fileSize: bytes.length, category: 'CREATIVE_ASSETS', referenceName: name }, relationships: { assetLibrary: { data: { type: 'appAssetLibraries', id: library } } } } })).data;
    ctx.addImage(image);
    await sendParts(image.attributes.uploadOperations, bytes, name);
    await markUploaded(`/v1/appAssetLibraryImages/${image.id}`, 'appAssetLibraryImages', image.id);
  }
  for (let i = 0; i < 160 && image.attributes.state !== 'PREPARE_FOR_SUBMISSION'; i++) {
    if (i) await sleep(3000);
    image = (await api('GET', `/v1/appAssetLibraryImages/${image.id}`)).data;
    if (image.attributes.state === 'FAILED') throw new Error(`Apple rejected ${name}: ${JSON.stringify(image.attributes.stateDetails)}`);
  }
  if (image.attributes.state !== 'PREPARE_FOR_SUBMISSION') throw new Error(`${name} is still ${image.attributes.state} after 8 minutes (image ${image.id} kept; run again to keep waiting)`);
  const spec = ref.imageSpecs.find((s) => s.specId === image.attributes.specId);
  if (!spec?.compatiblePlacementTypes.includes(type)) throw new Error(`${name} (${image.attributes.state}, spec ${spec?.shortName ?? image.attributes.specId}) does not fit ${type}`);
  await api('POST', '/v1/appAssetLibraryPlacements', { data: { type: 'appAssetLibraryPlacements', attributes: { placementType: type, placementGroup: group }, relationships: { image: { data: { type: 'appAssetLibraryImages', id: image.id } }, appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: loc.id } } } } });
  log(`${locale} ${label}: ${name} placed (${spec.shortName}, group ${group})`);
}

async function context() {
  const { app, version } = await target();
  const library = (await api('GET', `/v1/apps/${app.id}/assetLibrary`)).data.id;
  const ref = (await api('GET', '/v1/appAssetLibraryRefData?fields[appAssetLibraryRefData]=features,imageSpecs')).data[0].attributes;
  let images = await all(`/v1/appAssetLibraries/${library}/images?limit=200`);
  return { app, version, library, ref, images: () => images, addImage: (i) => images.push(i) };
}

async function placeLocale(ctx, locale, headerFile, searchFile, locs) {
  const files = [['PRODUCT_PAGE_HEADER_ASSET', headerFile], ['APP_STORE_SEARCH_RESULTS_ASSET', searchFile]];
  for (const [type, file] of files) checkFile(type, file);
  let loc = locs.find((l) => l.attributes.locale === locale);
  if (!loc) {
    if (dry) log(`${locale}: would add the language to version ${ctx.version.attributes.versionString}`);
    else {
      loc = (await api('POST', '/v1/appStoreVersionLocalizations', { data: { type: 'appStoreVersionLocalizations', attributes: { locale }, relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: ctx.version.id } } } } })).data;
      locs.push(loc);
      log(`${locale}: language added to version ${ctx.version.attributes.versionString}`);
    }
  }
  await Promise.all(files.map(([type, file]) => placeSlot(ctx, loc, locale, type, file)));   // both at once: Apple processes them side by side
}

async function creative(locale, headerFile, searchFile) {
  if (!locale || !headerFile || !searchFile) throw new Error('usage: creative <locale> <header.png> <search.png>');
  const ctx = await context();
  const locs = await all(`/v1/appStoreVersions/${ctx.version.id}/appStoreVersionLocalizations?limit=200`);
  if (!locs.find((l) => l.attributes.locale === locale)) throw new Error(`no ${locale} localization on version ${ctx.version.attributes.versionString} (use "locales" to add languages)`);
  log(`${ctx.app.attributes.name} (${ctx.app.id}) version ${ctx.version.attributes.versionString} ${ctx.version.attributes.appStoreState}${dry ? ' (dry run: nothing is written)' : ''}`);
  await placeLocale(ctx, locale, headerFile, searchFile, locs);
}

async function locales(folder) {
  if (!folder) throw new Error('usage: locales <folder> [--only codes] [--dry-run]');
  const ctx = await context();
  const locs = await all(`/v1/appStoreVersions/${ctx.version.id}/appStoreVersionLocalizations?limit=200`);
  const built = readdirSync(folder).filter((d) => statSync(join(folder, d)).isDirectory());
  const wanted = [...built, ...Object.keys(REUSE)].filter((c) => !only || only.includes(c));
  log(`${ctx.app.attributes.name} (${ctx.app.id}) version ${ctx.version.attributes.versionString} ${ctx.version.attributes.appStoreState}: ${wanted.length} languages${dry ? ' (dry run: nothing is written)' : ''}`);
  // the source languages first, so that the languages that reuse their images find them in the library
  const order = [...wanted.filter((c) => !REUSE[c]), ...wanted.filter((c) => REUSE[c])];
  const failures = [];
  let next = 0;
  async function worker() {
    for (;;) {
      const i = next++;
      if (i >= order.length) return;
      const code = order[i], src = REUSE[code] ?? code;
      try { await placeLocale(ctx, code, join(folder, src, `header-${src}.png`), join(folder, src, `search-${src}.png`), locs); }
      catch (e) { failures.push(`${code}: ${e.message}`); log(`${code}: FAILED ${e.message}`); }
    }
  }
  const plain = order.filter((c) => !REUSE[c]).length;
  await Promise.all(Array.from({ length: 3 }, worker));     // three languages at a time
  if (failures.length) throw new Error(`${failures.length} language(s) failed:\n  ${failures.join('\n  ')}`);
}

const commands = { status, creative: () => creative(rest[0], rest[1], rest[2]), locales: () => locales(rest[0]) };
if (!commands[command]) { console.error('usage: capling_asc.mjs --account loopware status | creative <locale> <header.png> <search.png> [--dry-run] | locales <folder> [--only codes] [--dry-run]'); process.exit(2); }
commands[command]().catch((e) => { console.error(`FAILED: ${e.message}`); process.exit(1); });
