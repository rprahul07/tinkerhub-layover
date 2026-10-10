// Retrieval over the live trip database. Ammachi only ever recommends what is
// in here, and every recommendation carries the creator who wrote it.
import { formatMoney, toAed } from '../currency.js';
import { budgetAed, budgetTotal } from '../present.js';

// What people say (English, Manglish, Malayalam), mapped to our tags.
const KEYWORDS = {
  desert: ['desert', 'dune', 'sand', 'camp', 'glamping', 'safari', 'മരുഭൂമി', 'മണൽ', 'ക്യാമ്പ്'],
  beach: ['beach', 'sea', 'island', 'snorkel', 'swim', 'coast', 'diving', 'കടൽ', 'ബീച്ച്', 'ദ്വീപ്', 'കടപ്പുറം'],
  mountains: ['mountain', 'hike', 'hiking', 'trek', 'peak', 'cold', 'cool', 'മല', 'തണുപ്പ്', 'ട്രെക്ക്'],
  city: ['city', 'mall', 'skyline', 'metro', 'shopping', 'നഗരം', 'സിറ്റി'],
  culture: ['culture', 'museum', 'mosque', 'heritage', 'history', 'fort', 'souk', 'മ്യൂസിയം', 'പള്ളി', 'കോട്ട', 'ചരിത്ര'],
  food: ['food', 'eat', 'restaurant', 'biryani', 'shawarma', 'khachapuri', 'ഭക്ഷണ', 'രുചി', 'ബിരിയാണി'],
  adventure: ['adventure', 'zipline', 'kayak', 'paraglid', 'thrill', 'സാഹസ'],
  family: ['family', 'kids', 'children', 'parents', 'കുടുംബ', 'കുട്ടികൾ'],
  couples: ['couple', 'honeymoon', 'romantic', 'wife', 'husband', 'ഭാര്യ', 'ഭർത്താവ്', 'ഹണിമൂൺ'],
  solo: ['solo', 'alone', 'ഒറ്റയ്ക്ക്', 'തനിച്ച്'],
  friends: ['friends', 'gang', 'കൂട്ടുകാർ'],
  budget: ['cheap', 'budget', 'low cost', 'affordable', 'കുറഞ്ഞ', 'ചെലവ് കുറ', 'പൈസ'],
  'day trip': ['day trip', 'one day', 'ഒരു ദിവസ'],
  monsoon: ['monsoon', 'rain', 'മഴ'],
};

// Malayalam place names → the names trips use.
const ALIASES = {
  ദുബായ്: 'dubai',
  ദുബൈ: 'dubai',
  അബുദാബി: 'abu dhabi',
  ഷാർജ: 'sharjah',
  റാസൽഖൈമ: 'ras al khaimah',
  ഫുജൈറ: 'fujairah',
  ഹത്ത: 'hatta',
  ലിവ: 'liwa',
  ഒമാൻ: 'oman',
  മസ്കറ്റ്: 'muscat',
  മുസന്ദം: 'musandam',
  ജോർജിയ: 'georgia',
  മൂന്നാർ: 'munnar',
  കേരളം: 'india',
};

function normalise(text) {
  let t = text.toLowerCase();
  for (const [ml, en] of Object.entries(ALIASES)) t = t.replaceAll(ml, ` ${en} `);
  return t;
}

export function interpret(text) {
  const t = normalise(text);
  const tags = Object.entries(KEYWORDS)
    .filter(([, words]) => words.some((w) => t.includes(w)))
    .map(([tag]) => tag);

  // Budgets: "1000 dirhams", "AED 800", "1.5k", "₹20,000", "20000 rupees", "പതിനായിരം രൂപ"
  const currency = /₹|\brs\.?|\binr\b|rupee|രൂപ/.test(t) ? 'INR' : /\$|\busd\b|dollar|ഡോളർ/.test(t) ? 'USD' : 'AED';
  let amount;
  const k = t.replace(/,/g, '').match(/(\d+(?:\.\d+)?)\s*k\b/);
  const n = t.replace(/,/g, '').match(/(\d{3,7})/);
  if (k) amount = Math.round(Number(k[1]) * 1000);
  else if (n) amount = Number(n[1]);
  else if (t.includes('പതിനായിരം')) amount = 10000;
  else if (t.includes('ആയിരം')) amount = 1000;
  const days = t.match(/(\d+)\s*(day|days|ദിവസ|night)/);
  return {
    tags,
    maxAed: amount ? toAed(amount, currency) : undefined,
    maxDays: days ? Number(days[1]) : t.includes('weekend') || t.includes('വീക്കെൻഡ്') ? 2 : undefined,
    words: t.split(/[^\p{L}\p{M}\p{N}]+/u).filter((w) => w.length > 3),
  };
}

export function rank(store, text, { contextJourneyId } = {}) {
  const intent = interpret(text);
  const month = new Date().getMonth() + 1;
  const scored = store.journeys().map((j) => {
    let score = 0;
    for (const tag of intent.tags) if (j.tags.includes(tag)) score += 3;
    if (intent.tags.includes('budget')) score += budgetAed(j) < 1500 ? 3 : 0;
    if (intent.maxAed) score += budgetAed(j) <= intent.maxAed ? 4 : -4;
    if (intent.maxDays) score += j.durationDays <= intent.maxDays ? 2 : -2;
    const hay = `${j.title} ${j.region} ${j.country ?? ''} ${j.stops.map((s) => s.name).join(' ')}`.toLowerCase();
    for (const word of intent.words) if (hay.includes(word)) score += 2;
    if ((j.bestMonths ?? []).includes(month)) score += 1;
    if (j.id === contextJourneyId) score += 5;
    score += Math.min(j.likes, 2500) / 2500; // popularity as a tiebreaker
    // Fresh posts have no likes yet; give the past week's a lift.
    if (Date.now() - Date.parse(j.createdAt) < 7 * 86400000) score += 1.5;
    return { journey: j, score, intent };
  });
  return scored.sort((a, b) => b.score - a.score);
}

export function priceOf(j) {
  const currency = j.currency ?? 'AED';
  const total = formatMoney(budgetTotal(j), currency);
  return currency === 'AED' ? total : `${total} (≈ ${formatMoney(budgetAed(j), 'AED')})`;
}

function describe(store, j, detailed) {
  const creator = store.creator(j.creatorId);
  const cur = j.currency ?? 'AED';
  const head = `- [${j.id}] "${j.title}" by ${creator?.name ?? 'a traveller'} (@${creator?.handle ?? ''}) — ${j.region}${j.country ? `, ${j.country}` : ''}; ${j.durationDays} day(s); ${j.travelers} traveller(s); total ${priceOf(j)}; tags: ${j.tags.join(', ')}; best months: ${(j.bestMonths ?? []).join(', ') || 'any'}`;
  if (!detailed) return head;
  const stops = j.stops
    .map((s) => {
      const spent = j.budget.filter((b) => b.stopId === s.id).map((b) => `${b.label} ${formatMoney(b.amount, cur)}`).join(', ');
      const facts = (s.fields ?? []).map((f) => `${f.label}: ${f.value}`).join('; ');
      return `    • Day ${s.day}: ${s.name}${s.tip ? ` (tip: ${s.tip})` : ''}${spent ? ` [spent: ${spent}]` : ''}${facts ? ` [${facts}]` : ''}`;
    })
    .join('\n');
  const extra = j.budget.filter((b) => !b.stopId).map((b) => `${b.label} ${formatMoney(b.amount, cur)}`).join('; ');
  const fields = (j.fields ?? []).map((f) => `${f.label}: ${f.value}`).join('; ');
  return `${head}\n  Summary: ${j.dek}\n  Places:\n${stops}${extra ? `\n  Other costs: ${extra}` : ''}${fields ? `\n  Good to know: ${fields}` : ''}`;
}

// The catalogue that goes into Ammachi's instructions: the best matches in
// full detail, everything else as one line each.
export function catalogFor(store, text, opts) {
  const ranked = rank(store, text, opts);
  return [
    ...ranked.slice(0, 8).map((r) => describe(store, r.journey, true)),
    ...ranked.slice(8, 60).map((r) => describe(store, r.journey, false)),
  ].join('\n');
}
