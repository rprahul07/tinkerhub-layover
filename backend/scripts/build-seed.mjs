// Builds data/seed.json from seed-source.mjs:
//   - geocodes each stop with OpenStreetMap Nominatim (1 req/s, per usage policy)
//   - finds a freely licensed photo per stop on Wikimedia Commons and downloads
//     a 1280px rendition into public/seed/, keeping author + licence for credit
// Run: npm run seed:build   (needs network; output is committed so the app runs offline)
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { creators, journeys } from './seed-source.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const photoDir = path.join(root, 'public', 'seed');
const outFile = path.join(root, 'data', 'seed.json');
const UA = 'TravelgramHackathon/1.0 (seed builder; contact: info@alphatechenterprises.in)';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const slug = (s) => s.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '');
const stripHtml = (s = '') => s.replace(/<[^>]+>/g, '').replace(/\s+/g, ' ').trim();

function km(a, b) {
  const R = 6371;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((a.lat * Math.PI) / 180) * Math.cos((b.lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

async function geocode(stop) {
  const url = `https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&accept-language=en&q=${encodeURIComponent(stop.geocode)}`;
  try {
    const res = await fetch(url, { headers: { 'User-Agent': UA } });
    const [hit] = await res.json();
    await sleep(1100);
    if (!hit) return { lat: stop.lat, lng: stop.lng, source: 'manual' };
    const found = { lat: Number(hit.lat), lng: Number(hit.lon) };
    // Guard against wrong matches: trust OSM only near our hand-placed estimate.
    if (km(found, stop) > 25) return { lat: stop.lat, lng: stop.lng, source: 'manual' };
    return { ...found, source: 'osm' };
  } catch {
    return { lat: stop.lat, lng: stop.lng, source: 'manual' };
  }
}

const BAD_TITLE = /\bmap\b|logo|\bplan\b|diagram|stamp|coat.of.arms|signboard|notice.?board|\.svg|\.png|\.gif|\.tif|panorama\b|ticket|chart|poster/i;

async function findPhoto(query, usedTitles) {
  // An override may pin an exact Commons file ("File:Name.jpg") instead of a search.
  const select = query.startsWith('File:')
    ? `&titles=${encodeURIComponent(query)}`
    : `&generator=search&gsrsearch=${encodeURIComponent(query)}&gsrnamespace=6&gsrlimit=20`;
  const api =
    'https://commons.wikimedia.org/w/api.php?action=query&format=json' +
    select +
    '&prop=imageinfo&iiprop=url|size|mime|extmetadata&iiurlwidth=1280' +
    '&iiextmetadatafilter=Artist|LicenseShortName|ObjectName';
  const res = await fetch(api, { headers: { 'User-Agent': UA } });
  const json = await res.json();
  const pages = Object.values(json?.query?.pages ?? {}).sort((a, b) => (a.index ?? 0) - (b.index ?? 0));
  const candidates = pages
    .map((p) => ({ title: p.title, info: p.imageinfo?.[0] }))
    .filter((c) => c.info && c.info.mime === 'image/jpeg' && !BAD_TITLE.test(c.title) && !usedTitles.has(c.title));
  const landscape = candidates.filter((c) => {
    const r = c.info.width / c.info.height;
    return c.info.width >= 1200 && r >= 1.2 && r <= 2.0;
  });
  const usable = candidates.filter((c) => {
    const r = c.info.width / c.info.height;
    return c.info.width >= 900 && r >= 0.7 && r <= 2.2;
  });
  // A pinned file was chosen by hand: take it as long as it is a JPEG.
  if (query.startsWith('File:')) return candidates[0] ?? null;
  return landscape[0] ?? usable[0] ?? null;
}

async function download(url, file) {
  const res = await fetch(url, { headers: { 'User-Agent': UA } });
  if (!res.ok) throw new Error(`download ${res.status} for ${url}`);
  await fs.writeFile(file, Buffer.from(await res.arrayBuffer()));
}

async function main() {
  // Start clean so photos from earlier seeds don't linger.
  await fs.rm(photoDir, { recursive: true, force: true });
  await fs.mkdir(photoDir, { recursive: true });
  const usedTitles = new Set();
  const overrides = JSON.parse(await fs.readFile(path.join(here, 'photo-overrides.json'), 'utf8').catch(() => '{}'));
  const outJourneys = [];

  for (const j of journeys) {
    console.log(`\n# ${j.title}`);
    const stops = [];
    for (const [i, s] of j.stops.entries()) {
      const geo = await geocode(s);
      const stopId = `${j.id}_s${i + 1}`;
      const fileName = `${slug(s.name)}.jpg`;
      let photo = null;
      try {
        const query = overrides[stopId] ?? s.query;
        const hit = await findPhoto(query, usedTitles);
        if (hit) {
          usedTitles.add(hit.title);
          await download(hit.info.thumburl, path.join(photoDir, fileName));
          const meta = hit.info.extmetadata ?? {};
          photo = {
            url: `/static/seed/${fileName}`,
            width: hit.info.thumbwidth,
            height: hit.info.thumbheight,
            caption: s.name,
            credit: {
              author: stripHtml(meta.Artist?.value) || 'Unknown',
              license: meta.LicenseShortName?.value || 'See source',
              source: hit.info.descriptionurl,
            },
          };
          await sleep(300);
        }
      } catch (err) {
        console.warn(`  ! photo failed for ${s.name}: ${err.message}`);
      }
      console.log(`  ${s.name.padEnd(28)} geo:${geo.source} photo:${photo ? photo.credit.author.slice(0, 30) : 'NONE'}`);
      const { query: _q, geocode: _g, lat: _la, lng: _ln, expenses: _e, ...rest } = s;
      stops.push({ id: stopId, ...rest, fields: s.fields ?? [], lat: Number(geo.lat.toFixed(5)), lng: Number(geo.lng.toFixed(5)), photos: photo ? [photo] : [] });
    }
    const { coverStop, extras = [], ...rest } = j;
    // One canonical list of expenses; place-level ones remember their place.
    const budget = [...extras, ...j.stops.flatMap((s, i) => (s.expenses ?? []).map((x) => ({ ...x, stopId: stops[i].id })))];
    outJourneys.push({ ...rest, coverPhoto: stops[coverStop]?.photos[0] ?? stops.find((s) => s.photos[0])?.photos[0] ?? null, stops, budget });
  }

  await fs.mkdir(path.dirname(outFile), { recursive: true });
  await fs.writeFile(outFile, JSON.stringify({ creators, journeys: outJourneys }, null, 2));
  console.log(`\nWrote ${outFile}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
