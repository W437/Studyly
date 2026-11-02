// Uploads Capling's App Preview video to the Asset Library and places it on one language of the version (iPhone group
// IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE, 886x1920). Never submits. Re-runnable: a video of the same name and size already in the library is
// reused, and a language that already shows it is left alone. Credentials come from the app-store-connect skill's helper.
//   node scripts/asc/capling_preview.mjs --account loopware <locale> <video.mp4> [--frame 00:00:01:20] [--replace] [--dry-run]
import { readFileSync } from 'node:fs';
import { basename } from 'node:path';
import { execFileSync } from 'node:child_process';
import { call, errors } from '/Users/drvanhoover/.claude/skills/app-store-connect/scripts/asc.mjs';

const BUNDLE = 'com.loopware.Capling';
const argv = process.argv.slice(2);
if (argv[argv.indexOf('--account') + 1] !== 'loopware') { console.error('pass --account loopware'); process.exit(2); }
const dry = argv.includes('--dry-run'), replace = argv.includes('--replace');
const fi = argv.indexOf('--frame');
const frame = fi >= 0 ? argv[fi + 1] : '00:00:01:20';
const [locale, file] = argv.filter((a, i) => !a.startsWith('--') && argv[i - 1] !== '--account' && argv[i - 1] !== '--frame');
if (!locale || !file) { console.error('usage: <locale> <video.mp4> [--frame HH:MM:SS:FF] [--replace] [--dry-run]'); process.exit(2); }
const log = (s) => console.log(s);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function api(method, path, body) {
  const r = await call(method, path, body);
  if (!r.ok) throw new Error(`${method} ${path.split('?')[0]} -> ${r.status} ${errors(r)}`.slice(0, 600));
  return r.json;
}
async function all(path) { const d = []; for (let n = path; n;) { const j = await api('GET', n); d.push(...(j.data ?? [])); n = j.links?.next; } return d; }

// what the file says about itself, checked against Apple's spec before anything is sent
const probe = JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'stream=codec_type,width,height,r_frame_rate:format=duration', '-of', 'json', file], { encoding: 'utf8' }));
const v = probe.streams.find((s) => s.codec_type === 'video'), hasAudio = probe.streams.some((s) => s.codec_type === 'audio');
const [n, d] = v.r_frame_rate.split('/').map(Number), fps = n / d, secs = Number(probe.format.duration);
const bytes = readFileSync(file), name = basename(file);

const app = (await api('GET', `/v1/apps?filter[bundleId]=${BUNDLE}`)).data[0];
const version = (await all(`/v1/apps/${app.id}/appStoreVersions`))[0];
const library = (await api('GET', `/v1/apps/${app.id}/assetLibrary`)).data.id;
const ref = (await api('GET', '/v1/appAssetLibraryRefData?fields[appAssetLibraryRefData]=features,placementTypes,videoSpecs')).data[0].attributes;
const spec = ref.videoSpecs.find((s) => s.compatiblePlacementTypes.includes('APP_PREVIEW') && s.dimensions.minWidth === v.width && s.dimensions.minHeight === v.height);
if (!spec) throw new Error(`${v.width}x${v.height} is not an App Preview size`);
if (!hasAudio && spec.audioRequired) throw new Error('the spec needs an audio track');
if (fps < spec.frameRates[0].minFps || fps > spec.frameRates[0].maxFps) throw new Error(`${fps} fps is outside ${spec.shortName}`);
if (secs < 15 || secs > 30) throw new Error(`${secs} s is outside 15 to 30 s`);
if (bytes.length > spec.maxFileSize) throw new Error('file too large');
const group = ref.placementTypes.find((p) => p.placementTypeId === 'APP_PREVIEW').specMappings.find((m) => m.specs.includes(spec.specId) && m.placementGroupId === 'IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE').placementGroupId;
const loc = (await all(`/v1/appStoreVersions/${version.id}/appStoreVersionLocalizations?limit=200`)).find((l) => l.attributes.locale === locale);
if (!loc) throw new Error(`no ${locale} localization`);
log(`${app.attributes.name} ${version.attributes.versionString} ${version.attributes.appStoreState}, ${locale}: ${name} ${v.width}x${v.height} ${fps} fps ${secs.toFixed(1)} s, audio ${hasAudio}, ${bytes.length} bytes, spec ${spec.shortName}, group ${group}, poster ${frame}${dry ? ' (dry run)' : ''}`);

const readPlacements = async () => {
  const j = await api('GET', `/v1/appStoreVersionLocalizations/${loc.id}/placements?filter[placementType]=APP_PREVIEW&include=video&limit=50`);
  const vids = new Map((j.included ?? []).map((i) => [i.id, i.attributes]));
  return j.data.filter((p) => p.attributes.placementGroup === group).map((p) => ({ id: p.id, state: p.attributes.state, video: vids.get(p.relationships?.video?.data?.id) ?? {} }));
};
let have = await readPlacements();
if (have.some((h) => h.video.fileName === name && h.video.fileSize === bytes.length && h.state === 'ACTIVE')) { log('already placed and active'); process.exit(0); }
if (have.length && !replace) throw new Error(`${locale} already has ${have.length} preview(s) (${have.map((h) => h.video.fileName).join(', ')}); pass --replace to take them off`);
if (dry) { log(`would upload and place${have.length ? ` after removing ${have.length}` : ''}`); process.exit(0); }
for (const h of have) await api('DELETE', `/v1/appAssetLibraryPlacements/${h.id}`);

const videos = await all(`/v1/appAssetLibraries/${library}/videos?limit=200`);
let video = videos.find((x) => x.attributes.fileName === name && x.attributes.fileSize === bytes.length && x.attributes.category === 'APP_SCREENSHOTS_AND_PREVIEWS');
if (!video) {
  video = (await api('POST', '/v1/appAssetLibraryVideos', { data: { type: 'appAssetLibraryVideos', attributes: { fileName: name, fileSize: bytes.length, category: 'APP_SCREENSHOTS_AND_PREVIEWS', referenceName: 'Capling App Preview', previewFrameTimeCode: frame }, relationships: { assetLibrary: { data: { type: 'appAssetLibraries', id: library } } } } })).data;
  log(`reserved video ${video.id}`);
  for (const op of video.attributes.uploadOperations ?? []) {
    const res = await fetch(op.url, { method: op.method, headers: Object.fromEntries(op.requestHeaders.map((h) => [h.name, h.value])), body: bytes.subarray(op.offset, op.offset + op.length) });
    if (!res.ok) throw new Error(`upload part at ${op.offset} -> ${res.status}`);
  }
  for (let a = 0; ; a++) {
    try { await api('PATCH', `/v1/appAssetLibraryVideos/${video.id}`, { data: { type: 'appAssetLibraryVideos', id: video.id, attributes: { uploaded: true } } }); break; }
    catch (e) { if (a >= 3 || !/ 5\d\d /.test(e.message)) throw e; await sleep(3000); }
  }
  log('uploaded, waiting for Apple to process it');
}
for (let i = 0; i < 200 && video.attributes.state !== 'PREPARE_FOR_SUBMISSION'; i++) {
  if (i) await sleep(5000);
  video = (await api('GET', `/v1/appAssetLibraryVideos/${video.id}`)).data;
  if (i % 6 === 0) log(`  state ${video.attributes.state}`);
  if (video.attributes.state === 'FAILED') throw new Error(`Apple rejected it: ${JSON.stringify(video.attributes.stateDetails)}`);
}
if (video.attributes.state !== 'PREPARE_FOR_SUBMISSION') throw new Error(`still ${video.attributes.state} after 16 minutes (video ${video.id} kept; run again)`);
if (video.attributes.specId !== spec.specId) throw new Error(`read as spec ${video.attributes.specId}, expected ${spec.specId}`);
await api('POST', '/v1/appAssetLibraryPlacements', { data: { type: 'appAssetLibraryPlacements', attributes: { placementType: 'APP_PREVIEW', placementGroup: group }, relationships: { video: { data: { type: 'appAssetLibraryVideos', id: video.id } }, appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: loc.id } } } } });
have = await readPlacements();
log(`placed: ${have.map((h) => `${h.video.fileName} ${h.state}`).join(', ')}`);
