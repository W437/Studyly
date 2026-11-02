// App Store Connect chores for the Capling record (com.loopware.Capling, Loopware team): the iOS 27 product page header and
// search-results card (Asset Library, API 4.5.1), placed on a version's localizations. Adapted from Keepable's keepable_asc.mjs
// (Cleanroll repo), which verified this flow on 2026-10-29. Re-runnable: it reads what is there and only writes what differs. It
// never submits for review, only sets the app's price when told to (`price`) and never prints credentials (they come from the
// app-store-connect skill's helper).
//
//   node scripts/asc/capling_asc.mjs --account loopware status
//   node scripts/asc/capling_asc.mjs --account loopware creative <locale> <header.png 3840x1646> <search.png 3:2> [--dry-run]
//   node scripts/asc/capling_asc.mjs --account loopware locales <folder> [--only de-DE,ja] [--dry-run]
//        <folder>/<locale>/header-<locale>.png and search-<locale>.png for every language (build_locales.py writes them). Adds the
//        language to the version when it is missing, places its two pictures, and gives the languages in REUSE (the English
//        variants) the same two images as their source language, uploaded once.
//   node scripts/asc/capling_asc.mjs --account loopware screenshots <locale> <folder> [--replace] [--dry-run]
//        <folder>/01.png .. 10.png: the iPhone screenshots of one language (1290x2796 or 1320x2868, no alpha). Uploads each to the
//        Asset Library (category APP_SCREENSHOTS_AND_PREVIEWS), places them on the language in file order (group and size checked
//        against Apple's reference data), then reads the order back. Never deletes: if the language already has screenshots that are
//        not these, it stops, unless --replace says to take them off first.
//   node scripts/asc/capling_asc.mjs --account loopware listing [--only text,translations,categories,age,rights,review] [--review-contact <json>] [--dry-run]
//        The rest of the listing: subtitle, description, keywords, promotional text, support and privacy URLs, copyright (English words in
//        capling_copy.json), the other languages' words (capling_copy_locales.json; the English variants reuse the English words),
//        categories, the age-rating questionnaire, the content-rights answer and the App Review notes. It writes only what differs. The
//        review contact (name, email, phone) is personal, so it is not in this file: pass --review-contact with a JSON file
//        {contactFirstName, contactLastName, contactEmail, contactPhone}; without it the review step is skipped.
//   node scripts/asc/capling_asc.mjs --account loopware price [--dry-run]
//        The app's price (free: the $0 point of the United States, the base territory) and where it is sold (every territory, new ones
//        included). The in-app purchases have their own prices: capling_products.mjs. Keeps what is already set.
//   node scripts/asc/capling_asc.mjs --account loopware build [build number] [--dry-run]
//        Waits until Apple has processed the uploaded build and attaches it to the version (never submits).
//   node scripts/asc/capling_asc.mjs --account loopware ready
//        Read-only: what the version still lacks before it can be submitted (build, text, screenshots, price, in-app purchases ...).
//   --dry-run reads and checks everything (file sizes, the version, what is placed already) and writes nothing.
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { basename, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { call, errors } from '/Users/drvanhoover/.claude/skills/app-store-connect/scripts/asc.mjs';

const BUNDLE = 'com.loopware.Capling';
const REUSE = { 'en-AU': 'en-US', 'en-CA': 'en-US', 'en-GB': 'en-US' };   // same as locales.py REUSE
const argv = process.argv.slice(2);
if (argv[argv.indexOf('--account') + 1] !== 'loopware') { console.error('pass --account loopware (Capling is on the Loopware team)'); process.exit(2); }
const dry = argv.includes('--dry-run');
const replace = argv.includes('--replace');
const contactIdx = argv.indexOf('--review-contact');
const contactFile = contactIdx >= 0 ? argv[contactIdx + 1] : null;
const onlyIdx = argv.indexOf('--only');
const only = onlyIdx >= 0 ? argv[onlyIdx + 1].split(',') : null;
const args = argv.filter((a, i) => a !== '--account' && argv[i - 1] !== '--account' && a !== '--dry-run' && a !== '--replace' && a !== '--review-contact' && argv[i - 1] !== '--review-contact' && a !== '--only' && argv[i - 1] !== '--only');
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
  const ref = (await api('GET', '/v1/appAssetLibraryRefData?fields[appAssetLibraryRefData]=features,imageSpecs,placementTypes')).data[0].attributes;
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

// ---- iPhone screenshots -------------------------------------------------------------------------------------------------------------

const SHOT = 'APP_SCREENSHOT', SHOT_CATEGORY = 'APP_SCREENSHOTS_AND_PREVIEWS';

// Reserves, uploads and waits for one file (an image already in the library with the same name and size is reused, not sent again).
async function ensureImage(ctx, file, bytes, name, category, referenceName) {
  let image = ctx.images().find((i) => i.attributes.fileName === name && i.attributes.fileSize === bytes.length && i.attributes.category === category);
  if (!image) {
    image = (await api('POST', '/v1/appAssetLibraryImages', { data: { type: 'appAssetLibraryImages', attributes: { fileName: name, fileSize: bytes.length, category, referenceName }, relationships: { assetLibrary: { data: { type: 'appAssetLibraries', id: ctx.library } } } } })).data;
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
  return image;
}

async function shotPlacements(locId) {
  const have = await api('GET', `/v1/appStoreVersionLocalizations/${locId}/placements?filter[placementType]=${SHOT}&sort=placementGroupPosition&include=image&limit=50`);
  const images = new Map((have.included ?? []).map((i) => [i.id, i.attributes]));
  return have.data.map((p) => ({ id: p.id, state: p.attributes.state, group: p.attributes.placementGroup, image: images.get(p.relationships?.image?.data?.id) ?? {} }));
}

async function screenshots(locale, folder) {
  if (!locale || !folder) throw new Error('usage: screenshots <locale> <folder of NN.png> [--replace] [--dry-run]');
  const names = readdirSync(folder).filter((f) => /^\d\d\.png$/.test(f)).sort();
  if (!names.length || names.length > 10) throw new Error(`${folder}: need 1 to 10 files named NN.png, found ${names.length}`);
  const files = names.map((n) => { const p = pngInfo(join(folder, n)); if (p.alpha) throw new Error(`${n} has an alpha channel (Apple takes none)`); return { n, ...p, name: `screenshot-${locale}-${n}` }; });
  if (new Set(files.map((f) => `${f.width}x${f.height}`)).size !== 1) throw new Error('the files are not all the same size');
  const { width, height } = files[0];
  const ctx = await context();
  const spec = ctx.ref.imageSpecs.find((s) => s.compatiblePlacementTypes.includes(SHOT) && s.dimensions.minWidth === width && s.dimensions.maxWidth === width && s.dimensions.minHeight === height && s.dimensions.maxHeight === height);
  if (!spec) throw new Error(`${width}x${height} is not a size Apple takes for ${SHOT}`);
  for (const f of files) if (f.bytes.length > spec.maxFileSize) throw new Error(`${f.n} is over the ${spec.maxFileSize} byte limit`);
  const group = ctx.ref.placementTypes.find((p) => p.placementTypeId === SHOT).specMappings.find((m) => m.specs.includes(spec.specId))?.placementGroupId;
  if (!group) throw new Error(`no placement group takes spec ${spec.shortName}`);
  const locs = await all(`/v1/appStoreVersions/${ctx.version.id}/appStoreVersionLocalizations?limit=200`);
  const loc = locs.find((l) => l.attributes.locale === locale);
  if (!loc) throw new Error(`no ${locale} localization on version ${ctx.version.attributes.versionString}`);
  log(`${ctx.app.attributes.name} (${ctx.app.id}) version ${ctx.version.attributes.versionString} ${ctx.version.attributes.appStoreState}, ${locale}: ${files.length} screenshots ${width}x${height} (spec ${spec.shortName}, group ${group})${dry ? ' (dry run: nothing is written)' : ''}`);

  const same = (have) => have.length === files.length && have.every((h, i) => h.image.fileName === files[i].name && h.image.fileSize === files[i].bytes.length && h.state === 'ACTIVE');
  let have = (await shotPlacements(loc.id)).filter((h) => h.group === group);
  if (same(have)) { log(`${locale}: these ${files.length} screenshots are already placed, in order`); return; }
  if (have.length && !replace) throw new Error(`${locale} already has ${have.length} screenshot(s) in ${group} (${have.map((h) => h.image.fileName).join(', ')}); nothing was changed. Pass --replace to take them off and place these.`);
  if (dry) { for (const f of files) log(`  would upload and place ${f.name} (${f.bytes.length} bytes)`); if (have.length) log(`  would first remove ${have.length} placement(s)`); return; }
  for (const h of have) await api('DELETE', `/v1/appAssetLibraryPlacements/${h.id}`);

  // all uploads at once (Apple processes them side by side), then the placements one after the other, in order
  const images = await Promise.all(files.map((f) => ensureImage(ctx, f, f.bytes, f.name, SHOT_CATEGORY, `Capling ${locale} screenshot ${f.n.replace('.png', '')}`)));
  for (let i = 0; i < images.length; i++) {
    if (images[i].attributes.specId !== spec.specId) throw new Error(`${files[i].name} was read as spec ${images[i].attributes.specId}, expected ${spec.specId} (${spec.shortName})`);
  }
  for (let round = 0; round < 2; round++) {
    for (const f of files.keys()) {
      await api('POST', '/v1/appAssetLibraryPlacements', { data: { type: 'appAssetLibraryPlacements', attributes: { placementType: SHOT, placementGroup: group }, relationships: { image: { data: { type: 'appAssetLibraryImages', id: images[f].id } }, appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: loc.id } } } } });
      log(`${locale}: placed ${files[f].name}`);
    }
    have = (await shotPlacements(loc.id)).filter((h) => h.group === group);
    if (same(have)) break;
    if (round) throw new Error(`placed, but the order read back is ${have.map((h) => h.image.fileName).join(', ')}`);
    log('the order read back is not the file order: taking the placements off and placing them again');   // a placement can't be edited
    for (const h of have) await api('DELETE', `/v1/appAssetLibraryPlacements/${h.id}`);
  }
  log(`${locale}: ${have.length} screenshots placed and active, in order: ${have.map((h) => h.image.fileName.replace(`screenshot-${locale}-`, '')).join(' ')}`);
}

// ---- the rest of the English listing ---------------------------------------------------------------------------------------------------

const HERE = dirname(fileURLToPath(import.meta.url));
const URLS = { support: 'https://loopware.app/support', privacy: 'https://loopware.app/privacy' };
const WORDS = ['subtitle', 'promotionalText', 'keywords', 'description'];
const EULA = 'https://www.apple.com/legal/internet-services/itunes/dev/stdeula/';
const COPYRIGHT = '2026 Loopware LLC';
const CATEGORIES = { primary: 'EDUCATION', secondary: 'PRODUCTIVITY' };
// Apple's age-rating questionnaire, answered for what Capling is: an AI study assistant a student chats with (never with other people),
// no browser (web research is the server reading a fixed list of study sites), no ads, Squad shares a plan and shows display names only.
// ageAssurance is false: the app has Apple's Declared Age Range entitlement and code for it (Services/AgeRange.swift), but nothing calls
// it yet (found 2026-11-01), so no age check happens; set it to true when that is wired in. Every answer is the developer's to confirm in
// App Store Connect.
const AGE = {
  advertising: false, alcoholTobaccoOrDrugUseOrReferences: 'NONE', contests: 'NONE', gambling: false, gamblingSimulated: 'NONE',
  gunsOrOtherWeapons: 'NONE', healthOrWellnessTopics: false, lootBox: false, medicalOrTreatmentInformation: 'NONE',
  messagingAndChat: false, parentalControls: false, profanityOrCrudeHumor: 'NONE', ageAssurance: false,
  sexualContentGraphicAndNudity: 'NONE', sexualContentOrNudity: 'NONE', horrorOrFearThemes: 'NONE', matureOrSuggestiveThemes: 'NONE',
  unrestrictedWebAccess: false, userGeneratedContent: false, socialMedia: false, violenceCartoonOrFantasy: 'NONE', violenceRealistic: 'NONE',
  violenceRealisticProlongedGraphicOrSadistic: 'NONE',
};
const LIMITS = { subtitle: 30, promotionalText: 170, keywords: 100, description: 4000, reviewNotes: 4000 };

async function write(method, path, body) {
  if (dry) { log(`    [dry run] ${method} ${path.split('?')[0]} ${body ? JSON.stringify(body).slice(0, 110) : ''}`); return { data: { id: 'dry-run', attributes: {} } }; }
  return api(method, path, body);
}
// Patches only the attributes that differ, and says which (quiet: only returns whether it wrote).
async function patchDiff(label, type, id, current, wanted, quiet = false) {
  const changed = Object.fromEntries(Object.entries(wanted).filter(([k, v]) => current[k] !== v));
  if (!Object.keys(changed).length) { if (!quiet) log(`  ${label}: already as wanted`); return false; }
  if (!quiet) log(`  ${label}: setting ${Object.keys(changed).join(', ')}`);
  await write('PATCH', `/v1/${type}/${id}`, { data: { type, id, attributes: changed } });
  return true;
}

// The words of every other language: capling_copy_locales.json (written by hand-checked machine drafts, for a native read) plus the
// English variants, which reuse the English words. Checked against Apple's limits before anything is written.
function otherWords(english) {
  const file = join(HERE, 'capling_copy_locales.json');
  const words = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : {};
  for (const locale of Object.keys(REUSE)) words[locale] ??= Object.fromEntries(WORDS.map((k) => [k, english[k]]));
  for (const [locale, w] of Object.entries(words)) {
    for (const k of WORDS) {
      if (typeof w[k] !== 'string' || !w[k].trim()) throw new Error(`${locale}: ${k} is missing`);
      if (w[k].length > LIMITS[k]) throw new Error(`${locale}: ${k} is ${w[k].length} characters, the limit is ${LIMITS[k]}`);
    }
    if (!w.description.includes(EULA)) throw new Error(`${locale}: the Terms of Use link is not in the description`);
  }
  return words;
}

async function listing() {
  const copy = JSON.parse(readFileSync(join(HERE, 'capling_copy.json'), 'utf8'))['en-US'];
  for (const [k, v] of Object.entries(copy)) if (LIMITS[k] && v.length > LIMITS[k]) throw new Error(`${k} is ${v.length} characters, the limit is ${LIMITS[k]}`);
  const steps = only ?? ['text', 'translations', 'categories', 'age', 'rights', 'review'];
  const words = steps.includes('translations') ? otherWords(copy) : {};
  const { app, version } = await target();
  const info = (await all(`/v1/apps/${app.id}/appInfos`)).find((i) => i.attributes.state === 'PREPARE_FOR_SUBMISSION');
  if (!info) throw new Error('no app info in PREPARE_FOR_SUBMISSION');
  const infoLocs = await all(`/v1/appInfos/${info.id}/appInfoLocalizations?limit=200`);
  const verLocs = await all(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=200`);
  const infoLoc = infoLocs.find((l) => l.attributes.locale === 'en-US');
  const verLoc = verLocs.find((l) => l.attributes.locale === 'en-US');
  log(`${app.attributes.name} (${app.id}) version ${version.attributes.versionString} ${version.attributes.appStoreState}, en-US${dry ? ' (dry run: nothing is written)' : ''}`);

  if (steps.includes('text')) {
    log('Text');
    await patchDiff('app info', 'appInfoLocalizations', infoLoc.id, infoLoc.attributes, { subtitle: copy.subtitle, privacyPolicyUrl: URLS.privacy });
    await patchDiff('version text', 'appStoreVersionLocalizations', verLoc.id, verLoc.attributes,
      { description: copy.description, keywords: copy.keywords, promotionalText: copy.promotionalText, supportUrl: URLS.support });
    await patchDiff('version', 'appStoreVersions', version.id, version.attributes, { copyright: COPYRIGHT });
  }
  if (steps.includes('translations')) {
    log('Other languages');
    let wrote = 0, kept = 0;
    const missing = [];
    for (const l of infoLocs.filter((x) => x.attributes.locale !== 'en-US')) {
      const w = words[l.attributes.locale];
      if (!w) { missing.push(l.attributes.locale); continue; }
      (await patchDiff(`${l.attributes.locale} app info`, 'appInfoLocalizations', l.id, l.attributes, { subtitle: w.subtitle, privacyPolicyUrl: URLS.privacy }, true)) ? wrote++ : kept++;
    }
    for (const l of verLocs.filter((x) => x.attributes.locale !== 'en-US')) {
      const w = words[l.attributes.locale];
      if (!w) continue;
      (await patchDiff(`${l.attributes.locale} version text`, 'appStoreVersionLocalizations', l.id, l.attributes,
        { description: w.description, keywords: w.keywords, promotionalText: w.promotionalText, supportUrl: URLS.support }, true)) ? wrote++ : kept++;
    }
    log(`  ${wrote} records written, ${kept} already as wanted${missing.length ? `; no words yet for ${missing.join(', ')}` : ''}`);
  }
  if (steps.includes('categories')) {
    log('Categories');
    const have1 = (await api('GET', `/v1/appInfos/${info.id}/relationships/primaryCategory`)).data?.id;
    const have2 = (await api('GET', `/v1/appInfos/${info.id}/relationships/secondaryCategory`)).data?.id;
    if (have1 === CATEGORIES.primary && have2 === CATEGORIES.secondary) log('  already as wanted');
    else {
      log(`  setting ${CATEGORIES.primary} + ${CATEGORIES.secondary}`);
      await write('PATCH', `/v1/appInfos/${info.id}`, { data: { type: 'appInfos', id: info.id, relationships: {
        primaryCategory: { data: { type: 'appCategories', id: CATEGORIES.primary } }, secondaryCategory: { data: { type: 'appCategories', id: CATEGORIES.secondary } } } } });
    }
  }
  if (steps.includes('age')) {
    log('Age rating');
    const declaration = await api('GET', `/v1/appInfos/${info.id}/ageRatingDeclaration`);
    await patchDiff('questionnaire', 'ageRatingDeclarations', declaration.data.id, declaration.data.attributes, AGE);
  }
  if (steps.includes('rights')) {
    log('Content rights');
    // The Ask Cap research route shows summaries of pages on a fixed list of study sites, with links, so the answer is yes.
    await patchDiff('declaration', 'apps', app.id, app.attributes, { contentRightsDeclaration: 'USES_THIRD_PARTY_CONTENT' });
  }
  if (steps.includes('review')) {
    log('Review details');
    const current = (await api('GET', `/v1/appStoreVersions/${version.id}/appStoreReviewDetail`)).data;
    if (!contactFile && current) await patchDiff('notes (the contact stays as it is)', 'appStoreReviewDetails', current.id, current.attributes, { demoAccountRequired: false, notes: copy.reviewNotes });
    else if (!contactFile) log('  skipped: pass --review-contact <json file with contactFirstName, contactLastName, contactEmail, contactPhone>');
    else {
      const wanted = { ...JSON.parse(readFileSync(contactFile, 'utf8')), demoAccountRequired: false, notes: copy.reviewNotes };
      if (current) await patchDiff('contact and notes', 'appStoreReviewDetails', current.id, current.attributes, wanted);
      else {
        log('  creating');
        await write('POST', '/v1/appStoreReviewDetails', { data: { type: 'appStoreReviewDetails', attributes: wanted, relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: version.id } } } } });
      }
    }
  }
  const after = (await api('GET', `/v1/appInfos/${info.id}`)).data.attributes;
  log(`Age rating Apple reads back: ${after.appStoreAgeRating ?? 'not computed yet'}`);
}

// ---- the app's price and where it is sold ---------------------------------------------------------------------------------------------
// Adapted from Dozen's asc_app_price.mjs (verified on Cairn and Dozen). Free, with the United States as the base territory.

async function price() {
  const { app } = await target();
  log(`${app.attributes.name} (${app.id})${dry ? ' (dry run: nothing is written)' : ''}`);
  const soft = (e) => { if (/ 404 /.test(e.message)) return null; throw e; };

  const manual = await api('GET', `/v1/appPriceSchedules/${app.id}/manualPrices?include=appPricePoint&limit=50`).catch(soft);
  if (manual?.data?.length) {
    const points = (manual.included ?? []).filter((i) => i.type === 'appPricePoints').map((p) => p.attributes.customerPrice);
    log(`  price: already set (${manual.data.length} entries, customer price ${points.join(', ') || '?'})`);
  } else {
    const found = (await api('GET', `/v1/apps/${app.id}/appPricePoints?filter[territory]=USA&limit=200`)).data;
    const free = found.find((p) => Number(p.attributes.customerPrice) === 0);
    if (!free) throw new Error('no $0 price point for the United States');
    log('  price: setting free (United States base territory)');
    await write('POST', '/v1/appPriceSchedules', {
      data: { type: 'appPriceSchedules', relationships: {
        app: { data: { type: 'apps', id: app.id } }, baseTerritory: { data: { type: 'territories', id: 'USA' } },
        manualPrices: { data: [{ type: 'appPrices', id: '${free}' }] } } },
      included: [{ type: 'appPrices', id: '${free}', attributes: { startDate: null }, relationships: { appPricePoint: { data: { type: 'appPricePoints', id: free.id } } } }],
    });
  }

  const have = await api('GET', `/v2/appAvailabilities/${app.id}`).catch(soft);
  if (have) log('  availability: already set');
  else {
    const territories = (await all('/v1/territories?limit=200')).map((t) => t.id);
    log(`  availability: setting ${territories.length} territories, new ones included`);
    await write('POST', '/v2/appAvailabilities', {
      data: { type: 'appAvailabilities', attributes: { availableInNewTerritories: true }, relationships: {
        app: { data: { type: 'apps', id: app.id } },
        territoryAvailabilities: { data: territories.map((t) => ({ type: 'territoryAvailabilities', id: `\${${t}}` })) } } },
      included: territories.map((t) => ({ type: 'territoryAvailabilities', id: `\${${t}}`, attributes: { available: true },
        relationships: { territory: { data: { type: 'territories', id: t } } } })),
    });
  }
  if (!dry) {
    const rows = await all(`/v2/appAvailabilities/${app.id}/territoryAvailabilities?limit=200&fields[territoryAvailabilities]=available`);
    log(`  read back: ${rows.filter((r) => r.attributes.available).length} of ${rows.length} territories available`);
  }
}

// ---- the uploaded build ------------------------------------------------------------------------------------------------------------------
// Waits for Apple to finish processing the newest build of the version's number (or the one named) and attaches it to the version.
// A build stays out of /v1/builds for the first minutes after the upload; processing takes about ten.

async function attachBuild() {
  const { app, version } = await target();
  const want = rest[0];
  for (let attempt = 0; attempt < 90; attempt++) {
    const builds = await all(`/v1/builds?filter[app]=${app.id}&filter[preReleaseVersion.version]=${version.attributes.versionString}&sort=-uploadedDate&limit=10`);
    const b = builds.find((x) => !want || x.attributes.version === want);
    if (!b) log(`${new Date().toLocaleTimeString('en-GB')} no build ${want ?? ''} for ${version.attributes.versionString} yet`);
    else {
      const state = b.attributes.processingState;
      log(`${new Date().toLocaleTimeString('en-GB')} build ${b.attributes.version}: ${state}${b.attributes.expired ? ' (expired)' : ''}`);
      if (state === 'FAILED' || state === 'INVALID') throw new Error(`Apple marked build ${b.attributes.version} ${state}`);
      if (state === 'VALID') {
        await write('PATCH', `/v1/appStoreVersions/${version.id}/relationships/build`, { data: { type: 'builds', id: b.id } });
        if (!dry) {
          const now = (await api('GET', `/v1/appStoreVersions/${version.id}/build`)).data;
          log(`attached: version ${version.attributes.versionString} now has build ${now?.attributes.version} (${now?.attributes.processingState})`);
        }
        return;
      }
    }
    await sleep(20000);
  }
  throw new Error('gave up waiting for the build to finish processing');
}

// ---- what the version still lacks before it can be submitted (read-only) ----------------------------------------------------------------

async function ready() {
  const { app, version } = await target();
  const info = (await all(`/v1/apps/${app.id}/appInfos`)).find((i) => i.attributes.state === 'PREPARE_FOR_SUBMISSION');
  const infoLocs = await all(`/v1/appInfos/${info.id}/appInfoLocalizations?limit=200`);
  const verLocs = await all(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=200`);
  const soft = (e) => { if (/ 404 /.test(e.message)) return null; throw e; };
  const lines = [];
  const check = (good, yes, no) => lines.push(`${good ? 'ok     ' : 'MISSING'} ${good ? yes : no}`);

  const build = (await api('GET', `/v1/appStoreVersions/${version.id}/build`).catch(soft))?.data;
  check(!!build, `build ${build?.attributes.version} attached (${build?.attributes.processingState})`, 'no build attached to the version');
  const withText = verLocs.filter((l) => l.attributes.description && l.attributes.keywords && l.attributes.supportUrl).length;
  check(withText === verLocs.length, `description, keywords and support URL in all ${verLocs.length} languages`, `description, keywords or support URL missing in ${verLocs.length - withText} of ${verLocs.length} languages`);
  const withInfo = infoLocs.filter((l) => l.attributes.subtitle && l.attributes.privacyPolicyUrl).length;
  check(withInfo === infoLocs.length, `subtitle and privacy policy URL in all ${infoLocs.length} languages`, `subtitle or privacy policy URL missing in ${infoLocs.length - withInfo} of ${infoLocs.length} languages`);
  const en = verLocs.find((l) => l.attributes.locale === 'en-US');
  const shots = (await api('GET', `/v1/appStoreVersionLocalizations/${en.id}/placements?filter[placementType]=APP_SCREENSHOT&limit=50`)).data;
  check(shots.length > 0 && shots.every((p) => p.attributes.state === 'ACTIVE'), `${shots.length} iPhone screenshots active in en-US`, 'no active iPhone screenshots in en-US');
  const cats = (await api('GET', `/v1/appInfos/${info.id}/relationships/primaryCategory`)).data?.id;
  check(!!cats, `categories set (primary ${cats})`, 'no category');
  const infoNow = (await api('GET', `/v1/appInfos/${info.id}`)).data.attributes;
  check(!!infoNow.appStoreAgeRating, `age rating ${infoNow.appStoreAgeRating}`, 'no age rating yet');
  check(!!app.attributes.contentRightsDeclaration, `content rights ${app.attributes.contentRightsDeclaration}`, 'content rights not answered');
  check(!!version.attributes.copyright, `copyright ${version.attributes.copyright}`, 'no copyright');
  const review = (await api('GET', `/v1/appStoreVersions/${version.id}/appStoreReviewDetail`).catch(soft))?.data;
  check(!!(review?.attributes.contactEmail && review?.attributes.notes), 'App Review contact and notes set', 'App Review contact or notes missing');
  const price = await api('GET', `/v1/appPriceSchedules/${app.id}/manualPrices?limit=5`).catch(soft);
  check(!!price?.data?.length, 'app price set', 'no app price');
  const avail = await api('GET', `/v2/appAvailabilities/${app.id}`).catch(soft);
  check(!!avail, 'availability set', 'no availability');
  const groups = await all(`/v1/apps/${app.id}/subscriptionGroups?limit=50`);
  const subs = [];
  for (const g of groups) subs.push(...await all(`/v1/subscriptionGroups/${g.id}/subscriptions?limit=50`));
  const iaps = await all(`/v1/apps/${app.id}/inAppPurchasesV2?limit=50`);
  const states = [...subs, ...iaps].map((p) => `${p.attributes.productId.split('.').slice(-2).join('.')} ${p.attributes.state}`);
  check(states.length > 0 && [...subs, ...iaps].every((p) => p.attributes.state === 'READY_TO_SUBMIT' || p.attributes.state === 'APPROVED'), `in-app purchases: ${states.join(', ')}`, `in-app purchases not ready: ${states.join(', ') || 'none'}`);
  lines.push('check   App Privacy has no API: its page in App Store Connect says whether it is published');
  log(`${app.attributes.name} ${version.attributes.versionString} ${version.attributes.appStoreState}`);
  for (const l of lines) log(l);
}

const commands = { status, ready, listing, price, build: attachBuild, creative: () => creative(rest[0], rest[1], rest[2]), locales: () => locales(rest[0]), screenshots: () => screenshots(rest[0], rest[1]) };
if (!commands[command]) { console.error('usage: capling_asc.mjs --account loopware status | ready | build [number] | creative <locale> <header.png> <search.png> [--dry-run] | locales <folder> [--only codes] [--dry-run] | screenshots <locale> <folder> [--replace] [--dry-run] | listing [--only steps] [--review-contact file] [--dry-run] | price [--dry-run]'); process.exit(2); }
commands[command]().catch((e) => { console.error(`FAILED: ${e.message}`); process.exit(1); });
