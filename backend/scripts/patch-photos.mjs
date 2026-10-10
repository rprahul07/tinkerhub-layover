// Re-fetches only the photos pinned in photo-overrides.json ("File:…" titles)
// and patches data/seed.json — quicker than a full seed:build.
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const UA = 'TravelgramHackathon/1.0 (photo patcher; contact: info@alphatechenterprises.in)';
const stripHtml = (s = '') => s.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');

const overrides = JSON.parse(await fs.readFile(path.join(here, 'photo-overrides.json'), 'utf8'));
const seedFile = path.join(root, 'data', 'seed.json');
const seed = JSON.parse(await fs.readFile(seedFile, 'utf8'));

for (const [stopId, title] of Object.entries(overrides)) {
  if (!title.startsWith('File:')) continue;
  const journey = seed.journeys.find((j) => j.stops.some((s) => s.id === stopId));
  const stop = journey?.stops.find((s) => s.id === stopId);
  if (!stop) continue;
  const api = `https://commons.wikimedia.org/w/api.php?action=query&format=json&titles=${encodeURIComponent(title)}&prop=imageinfo&iiprop=url|extmetadata&iiurlwidth=1280&iiextmetadatafilter=Artist|LicenseShortName`;
  const info = Object.values((await (await fetch(api, { headers: { 'User-Agent': UA } })).json()).query.pages)[0]?.imageinfo?.[0];
  if (!info) { console.log(`  ! ${title} not found`); continue; }
  const file = `${slug(stop.name)}.jpg`;
  const res = await fetch(info.thumburl, { headers: { 'User-Agent': UA } });
  await fs.writeFile(path.join(root, 'public', 'seed', file), Buffer.from(await res.arrayBuffer()));
  const old = stop.photos[0]?.url;
  const photo = {
    url: `/static/seed/${file}`,
    width: info.thumbwidth,
    height: info.thumbheight,
    caption: stop.name,
    credit: { author: stripHtml(info.extmetadata?.Artist?.value) || 'Unknown', license: info.extmetadata?.LicenseShortName?.value || 'See source', source: info.descriptionurl },
  };
  stop.photos = [photo];
  if (!journey.coverPhoto || journey.coverPhoto.url === old) journey.coverPhoto = photo;
  console.log(`  ${stopId.padEnd(24)} ← ${title.slice(5, 60)} (${photo.credit.author.slice(0, 24)})`);
  await new Promise((r) => setTimeout(r, 300));
}
await fs.writeFile(seedFile, JSON.stringify(seed, null, 2));
console.log('patched seed.json');
