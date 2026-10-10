// Place search for the trip tracker. Matches our own gazetteer first (every
// place already on Travelgram plus well-known UAE, GCC and world places) so it
// is instant and works offline, then OpenStreetMap Nominatim for anything else.
import { Router } from 'express';

const GAZETTEER = [
  // UAE
  ['Dubai', 'Dubai', 'United Arab Emirates', 25.2048, 55.2708],
  ['Burj Khalifa', 'Dubai', 'United Arab Emirates', 25.1972, 55.2744],
  ['Dubai Marina', 'Dubai', 'United Arab Emirates', 25.0805, 55.1403],
  ['Palm Jumeirah', 'Dubai', 'United Arab Emirates', 25.1124, 55.139],
  ['Al Fahidi Historical Neighbourhood', 'Dubai', 'United Arab Emirates', 25.2637, 55.2972],
  ['Dubai Creek', 'Dubai', 'United Arab Emirates', 25.2627, 55.2961],
  ['Museum of the Future', 'Dubai', 'United Arab Emirates', 25.2195, 55.2819],
  ['Al Qudra Lakes', 'Dubai', 'United Arab Emirates', 24.8387, 55.3713],
  ['Abu Dhabi', 'Abu Dhabi', 'United Arab Emirates', 24.4539, 54.3773],
  ['Sheikh Zayed Grand Mosque', 'Abu Dhabi', 'United Arab Emirates', 24.4128, 54.475],
  ['Louvre Abu Dhabi', 'Abu Dhabi', 'United Arab Emirates', 24.5337, 54.3983],
  ['Yas Island', 'Abu Dhabi', 'United Arab Emirates', 24.4672, 54.6031],
  ['Sharjah', 'Sharjah', 'United Arab Emirates', 25.3463, 55.4209],
  ['Ras Al Khaimah', 'Ras Al Khaimah', 'United Arab Emirates', 25.8007, 55.9762],
  ['Jebel Jais', 'Ras Al Khaimah', 'United Arab Emirates', 25.9536, 56.1285],
  ['Hatta', 'Dubai', 'United Arab Emirates', 24.7969, 56.1176],
  ['Fujairah', 'Fujairah', 'United Arab Emirates', 25.1288, 56.3265],
  ['Khor Fakkan', 'Sharjah', 'United Arab Emirates', 25.3392, 56.3566],
  ['Al Ain', 'Abu Dhabi', 'United Arab Emirates', 24.2075, 55.7447],
  ['Jebel Hafeet', 'Al Ain', 'United Arab Emirates', 24.0586, 55.7766],
  ['Liwa Oasis', 'Abu Dhabi', 'United Arab Emirates', 23.129, 53.778],
  ['Umm Al Quwain', 'Umm Al Quwain', 'United Arab Emirates', 25.5647, 55.5552],
  // GCC
  ['Muscat', 'Muscat', 'Oman', 23.588, 58.3829],
  ['Khasab', 'Musandam', 'Oman', 26.1797, 56.2475],
  ['Wadi Shab', 'Ash Sharqiyah', 'Oman', 22.838, 59.239],
  ['Jebel Akhdar', 'Ad Dakhiliyah', 'Oman', 23.0717, 57.6656],
  ['Salalah', 'Dhofar', 'Oman', 17.0151, 54.0924],
  ['Doha', 'Doha', 'Qatar', 25.2854, 51.531],
  ['Manama', 'Capital', 'Bahrain', 26.2285, 50.586],
  ['AlUla', 'Medina', 'Saudi Arabia', 26.6177, 37.9235],
  ['Riyadh', 'Riyadh', 'Saudi Arabia', 24.7136, 46.6753],
  // Popular from the Gulf
  ['Tbilisi', 'Tbilisi', 'Georgia', 41.7151, 44.8271],
  ['Kazbegi (Stepantsminda)', 'Mtskheta-Mtianeti', 'Georgia', 42.6567, 44.6433],
  ['Baku', 'Baku', 'Azerbaijan', 40.4093, 49.8671],
  ['Istanbul', 'Istanbul', 'Türkiye', 41.0082, 28.9784],
  ['Cappadocia', 'Nevşehir', 'Türkiye', 38.6431, 34.8289],
  ['Almaty', 'Almaty', 'Kazakhstan', 43.222, 76.8512],
  ['Malé', 'Malé', 'Maldives', 4.1755, 73.5093],
  ['Bali', 'Bali', 'Indonesia', -8.4095, 115.1889],
  ['Kochi', 'Kerala', 'India', 9.9312, 76.2673],
  ['Munnar', 'Kerala', 'India', 10.0889, 77.0595],
  ['Goa', 'Goa', 'India', 15.2993, 74.124],
  ['Colombo', 'Western', 'Sri Lanka', 6.9271, 79.8612],
  ['Bangkok', 'Bangkok', 'Thailand', 13.7563, 100.5018],
  ['Paris', 'Île-de-France', 'France', 48.8566, 2.3522],
  ['London', 'England', 'United Kingdom', 51.5072, -0.1276],
].map(([name, region, country, lat, lng]) => ({ name, region, country, lat, lng }));

const cache = new Map();

export function placesRouter(store) {
  const r = Router();

  r.get('/places', async (req, res) => {
    const q = String(req.query.q ?? '').trim().toLowerCase();
    if (q.length < 2) return res.json({ places: [] });

    const local = new Map();
    for (const p of GAZETTEER) {
      if (p.name.toLowerCase().includes(q)) local.set(p.name.toLowerCase(), { ...p, source: 'travelgram' });
    }
    for (const j of store.journeys()) {
      for (const s of j.stops) {
        if (s.name.toLowerCase().includes(q) && !local.has(s.name.toLowerCase())) {
          local.set(s.name.toLowerCase(), { name: s.name, region: j.region, country: j.country ?? '', lat: s.lat, lng: s.lng, source: 'travelgram' });
        }
      }
    }

    let remote = [];
    if (local.size < 5) remote = await nominatim(q);

    const seen = new Set(local.keys());
    const places = [...local.values(), ...remote.filter((p) => !seen.has(p.name.toLowerCase()))].slice(0, 8);
    res.json({ places });
  });

  return r;
}

async function nominatim(q) {
  if (cache.has(q)) return cache.get(q);
  try {
    const url = `https://nominatim.openstreetmap.org/search?format=jsonv2&limit=6&addressdetails=1&accept-language=en&q=${encodeURIComponent(q)}`;
    const res = await fetch(url, {
      headers: { 'User-Agent': 'TravelgramHackathon/1.0 (place search)' },
      signal: AbortSignal.timeout(4000),
    });
    if (!res.ok) return [];
    const hits = await res.json();
    const places = hits.map((h) => ({
      name: h.name || h.display_name.split(',')[0],
      region: h.address?.city || h.address?.town || h.address?.state || h.address?.county || '',
      country: h.address?.country || '',
      lat: Number(h.lat),
      lng: Number(h.lon),
      source: 'osm',
    }));
    cache.set(q, places);
    return places;
  } catch {
    return [];
  }
}
