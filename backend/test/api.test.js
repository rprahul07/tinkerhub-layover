import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { fileURLToPath } from 'node:url';
import { createVoice } from '../src/voice/plivo.js';
import { createApp } from '../src/app.js';
import { Store } from '../src/store.js';
import { createGemini } from '../src/ammachi/gemini.js';
import { CitationSplitter, SentenceChunker } from '../src/ammachi/citations.js';
import { formatMoney, toAed } from '../src/currency.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const DEVICE = { 'x-device-id': 'test-device-1' };

// ---- helpers -------------------------------------------------------------------

function tempStore() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tg-'));
  fs.copyFileSync(path.join(here, '..', 'data', 'seed.json'), path.join(dir, 'seed.json'));
  return { dir, store: new Store(dir) };
}

async function serve(options = {}) {
  const { dir, store } = tempStore();
  const { app } = createApp({
    store,
    llm: null,
    tts: { enabled: false },
    voiceLines: { ready: false, filler: () => null, greeting: () => null },
    uploadsDir: path.join(dir, 'uploads'),
    docsDir: path.join(dir, 'docs'),
    dashboardKey: 'test-key-123',
    voice: createVoice({}, store), // tests never dial real numbers
    allowSpecimens: false,
    ...options,
  });
  const server = app.listen(0);
  await new Promise((r) => server.once('listening', r));
  const base = `http://127.0.0.1:${server.address().port}`;
  return { base, store, close: () => new Promise((r) => server.close(r)) };
}

async function json(base, url, init = {}) {
  const res = await fetch(base + url, { ...init, headers: { 'Content-Type': 'application/json', ...DEVICE, ...(init.headers ?? {}) } });
  return { status: res.status, body: await res.json() };
}

const post = (base, url, body, headers = {}) => json(base, url, { method: 'POST', body: body === undefined ? undefined : JSON.stringify(body), headers });

async function sse(base, body) {
  const res = await fetch(`${base}/api/ammachi/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...DEVICE },
    body: JSON.stringify(body),
  });
  assert.equal(res.headers.get('content-type'), 'text/event-stream; charset=utf-8');
  const raw = await res.text();
  return raw
    .split('\n\n')
    .filter(Boolean)
    .map((block) => ({ event: block.match(/^event: (.+)$/m)[1], data: JSON.parse(block.match(/^data: (.+)$/m)[1]) }));
}

async function signUp(base, name, handle) {
  const { status, body } = await post(base, '/api/creators', { name, handle, phone: '+971501234567', consent: true });
  assert.equal(status, 201);
  return body.creator;
}

let api;
before(async () => {
  api = await serve();
});
after(async () => {
  await api.close();
});

// ---- feed, destinations, filters ---------------------------------------------

test('For you feed: every post is attributed, priced and has photos; destinations and suggestions come along', async () => {
  const { status, body } = await json(api.base, '/api/feed');
  assert.equal(status, 200);
  assert.equal(body.tab, 'foryou');
  assert.equal(body.journeys.length, 10);
  for (const j of body.journeys) {
    assert.ok(j.creator.name && j.creator.handle, `creator on ${j.id}`);
    assert.match(j.coverPhoto.url, /^http:\/\/127\.0\.0\.1:\d+\/static\/seed\/.+\.jpg$/);
    assert.ok(j.photos.length >= 1);
    assert.ok(j.currency && j.budgetAed > 0);
  }
  assert.ok(body.destinations.some((d) => d.name === 'Dubai' && d.country === 'United Arab Emirates'));
  assert.ok(body.suggested.length > 0);
  const photo = await fetch(body.journeys[0].coverPhoto.url);
  assert.equal(photo.status, 200);
});

test('trip detail: places carry their own expenses and details; the budget adds up', async () => {
  const { status, body } = await json(api.base, '/api/journeys/j_dubai_budget');
  assert.equal(status, 200);
  const j = body.journey;
  assert.equal(j.currency, 'AED');
  assert.equal(j.budgetTotal, 893);
  assert.equal(j.budget.reduce((s, c) => s + c.amount, 0), 893);
  const souk = j.stops.find((s) => s.name.startsWith('Gold Souk'));
  assert.deepEqual(souk.expenses.map((e) => e.amount), [85, 45]);
  assert.ok(j.stops[0].fields.some((f) => f.label === 'Entry fee'));
  assert.ok(j.fields.length > 0);
  assert.ok(body.related.length > 0);
});

test('trips in other currencies are compared in AED', async () => {
  const { body } = await json(api.base, '/api/journeys/j_muscat');
  assert.equal(body.journey.currency, 'OMR');
  assert.equal(body.journey.budgetAed, toAed(body.journey.budgetTotal, 'OMR'));
  assert.equal(formatMoney(12000, 'INR'), '₹12,000');
  assert.equal(formatMoney(1234567, 'AED'), 'AED 1,234,567');
});

test('browse by destination, budget and length', async () => {
  const dubai = (await json(api.base, '/api/journeys?destination=Dubai')).body.journeys;
  assert.deepEqual(dubai.map((j) => j.id), ['j_dubai_budget']);
  const cheap = (await json(api.base, '/api/journeys?maxAed=1000')).body.journeys;
  assert.ok(cheap.length > 0 && cheap.every((j) => j.budgetAed <= 1000));
  const long = (await json(api.base, '/api/journeys?minDays=3')).body.journeys;
  assert.ok(long.every((j) => j.durationDays >= 3));
  const dest = (await json(api.base, '/api/destinations')).body.destinations;
  const hatta = dest.find((d) => d.name === 'Hatta');
  assert.equal(hatta.count, 1);
  assert.equal(hatta.minAed, 360);
  assert.equal((await json(api.base, '/api/journeys/nope')).status, 404);
});

// ---- people: follow, following feed, "I'm going" -------------------------------

test('follow a creator → their trips fill the Following feed; follower counts update', async () => {
  const me = await signUp(api.base, 'Follow Tester', 'follow.tester');
  const H = { 'x-user-id': me.id };
  assert.equal((await json(api.base, '/api/feed?tab=following', { headers: H })).body.journeys.length, 0);
  const before = (await json(api.base, '/api/creators/c_omar')).body.creator.followers;
  const r = await post(api.base, '/api/creators/c_omar/follow', undefined, H);
  assert.deepEqual(r.body, { following: true, followers: before + 1 });
  const following = (await json(api.base, '/api/feed?tab=following', { headers: H })).body.journeys;
  assert.ok(following.length === 2 && following.every((j) => j.creator.id === 'c_omar' && j.creator.isFollowing));
  assert.equal((await post(api.base, '/api/creators/c_omar/follow')).status, 401); // needs a profile
});

test('"I\'m going" counts the trip and records an interest lead', async () => {
  const me = await signUp(api.base, 'Going Tester', 'going.tester');
  const H = { 'x-user-id': me.id };
  const base = (await json(api.base, '/api/journeys/j_hatta')).body.journey.goingCount;
  const r = await post(api.base, '/api/journeys/j_hatta/going', undefined, H);
  assert.deepEqual(r.body, { going: true, goingCount: base + 1 });
  assert.deepEqual((await json(api.base, '/api/me/going', { headers: H })).body.journeys.map((j) => j.id), ['j_hatta']);
  const lead = api.store.leads().find((l) => l.userId === me.id);
  assert.equal(lead.source, 'going');
  assert.equal(lead.qualified, false);
  assert.equal(lead.destination, 'Hatta');
});

test('save and like toggle per device', async () => {
  assert.deepEqual((await post(api.base, '/api/journeys/j_georgia/save')).body, { saved: true, saves: 1 });
  assert.deepEqual((await json(api.base, '/api/me/saved')).body.journeys.map((j) => j.id), ['j_georgia']);
  const likes = (await json(api.base, '/api/journeys/j_georgia')).body.journey.likes;
  assert.deepEqual((await post(api.base, '/api/journeys/j_georgia/like')).body, { liked: true, likes: likes + 1 });
});

// ---- posting a tracked trip --------------------------------------------------------

test('post a tracked trip with photos, expenses and custom details → it leads the feed', async () => {
  const me = await signUp(api.base, 'Test Traveller', 'test.traveller');
  const form = new FormData();
  const jpeg = fs.readFileSync(path.join(here, '..', 'public', 'seed', fs.readdirSync(path.join(here, '..', 'public', 'seed'))[0]));
  form.append('photo', new Blob([jpeg], { type: 'image/jpeg' }), 'trip.jpg');
  const up = await fetch(`${api.base}/api/uploads`, { method: 'POST', body: form });
  assert.equal(up.status, 201);
  const { url } = await up.json();

  const invalid = await post(api.base, '/api/journeys', { creatorId: me.id, title: 'x', stops: [] });
  assert.equal(invalid.status, 400);
  assert.ok(invalid.body.details.title && invalid.body.details.stops);

  const created = await post(api.base, '/api/journeys', {
    creatorId: me.id,
    title: 'Al Qudra Weekend',
    dek: 'Lakes, flamingos and a desert sunset.',
    region: 'Dubai',
    country: 'United Arab Emirates',
    currency: 'AED',
    travelers: 2,
    tags: ['Desert', 'couples'],
    fields: [{ label: 'Bring', value: 'Bug spray' }],
    stops: [
      { name: 'Al Qudra Lakes', day: 1, lat: 24.8387, lng: 55.3713, story: 'Flamingos at dawn.', photos: [{ url }], fields: [{ label: 'Entry fee', value: 'Free' }], expenses: [{ category: 'transport', label: 'Fuel', amount: 60 }] },
      { name: 'Love Lake', day: 2, lat: 24.82, lng: 55.37, expenses: [{ category: 'food', label: 'Picnic', amount: 90 }, { category: 'bogus', label: 'Firewood', amount: 25 }] },
    ],
    budget: [{ category: 'stay', label: 'Tent', amount: 200 }],
    coverPhotoUrl: url,
  });
  assert.equal(created.status, 201);
  const j = created.body.journey;
  assert.equal(j.creator.name, 'Test Traveller');
  assert.equal(j.budgetTotal, 375);
  assert.equal(j.durationDays, 2);
  assert.deepEqual(j.tags, ['desert', 'couples']);
  assert.equal(j.coverPhoto.url, url);
  assert.deepEqual(j.stops[0].fields, [{ label: 'Entry fee', value: 'Free' }]);
  assert.deepEqual(j.stops[1].expenses.map((e) => e.category), ['food', 'other']);
  assert.deepEqual(j.fields, [{ label: 'Bring', value: 'Bug spray' }]);

  assert.equal((await json(api.base, '/api/feed')).body.journeys[0].id, j.id);
  const profile = await json(api.base, `/api/creators/${me.id}`);
  assert.equal(profile.body.stats.journeys, 1);
});

test('place search covers the Gulf and beyond', async () => {
  const { body } = await json(api.base, '/api/places?q=jebel');
  assert.ok(body.places.some((p) => p.name === 'Jebel Jais' && p.country === 'United Arab Emirates'));
});

// ---- budget planner & leads ------------------------------------------------------------

test('budget planner builds a plan from real trips, scaled to the group (no AI)', async () => {
  const { status, body } = await post(api.base, '/api/planner', { budget: 1000, currency: 'AED', days: 1, travelers: 2, interests: ['mountains'], lang: 'en' });
  assert.equal(status, 201);
  const plan = body.plan;
  assert.equal(plan.source, 'catalogue');
  assert.ok(plan.days.length >= 1);
  assert.ok(plan.trips.length >= 1 && plan.trips.every((t) => t.creator.name));
  assert.ok(plan.days.flatMap((d) => d.items).every((it) => plan.basedOn.includes(it.journeyId)));
  assert.equal(plan.totalAed, plan.days.flatMap((d) => d.items).reduce((s, it) => s + it.costAed, 0));
  assert.match(plan.summary, /I recommend/);
  assert.equal((await post(api.base, '/api/planner', { days: 2 })).status, 400);
});

test('planner keeps only real trips from the model and recomputes the total', async () => {
  const llm = {
    name: 'fake',
    model: 'fake-1',
    async *stream() {},
    async json({ system }) {
      assert.match(system, /ONLY from the trips below/);
      return {
        title: 'Hatta Day',
        summary: 'Sara did this one.',
        days: [{ day: 1, title: 'Hatta', items: [
          { place: 'Hatta Dam', journeyId: 'j_hatta', what: 'Kayak', category: 'activities', costAed: 120 },
          { place: 'Made-up Spa', journeyId: 'j_invented', what: 'Massage', category: 'other', costAed: 900 },
        ] }],
        tips: [],
      };
    },
  };
  const s = await serve({ llm });
  try {
    const { body } = await post(s.base, '/api/planner', { budget: 500, currency: 'AED', days: 1, travelers: 2 });
    assert.equal(body.plan.source, 'gemini');
    assert.deepEqual(body.plan.basedOn, ['j_hatta']);
    assert.equal(body.plan.totalAed, 120);
    assert.equal(body.plan.fits, true);
  } finally {
    await s.close();
  }
});

test('confirming a plan with consent creates a qualified lead on the key-protected dashboard', async () => {
  const me = await signUp(api.base, 'Lead Tester', 'lead.tester');
  const H = { 'x-user-id': me.id };
  const plan = (await post(api.base, '/api/planner', { budget: 1500, currency: 'AED', days: 2, travelers: 2, month: 12 }, H)).body.plan;
  const noConsent = await post(api.base, '/api/leads', { planId: plan.id, name: 'Lead Tester', phone: '+971501234567', consent: false }, H);
  assert.equal(noConsent.body.lead.qualified, false);
  const bad = await post(api.base, '/api/leads', { planId: plan.id, name: 'Lead Tester', phone: '12', consent: true }, H);
  assert.equal(bad.status, 400);
  const ok = await post(api.base, '/api/leads', { planId: plan.id, name: 'Lead Tester', phone: '+971 50 123 4567', consent: true }, H);
  assert.equal(ok.status, 201);
  assert.equal(ok.body.lead.qualified, true);
  assert.ok(ok.body.lead.score >= 70);
  assert.equal(api.store.leads().filter((l) => l.planId === plan.id).length, 1); // the richer request replaced the first

  assert.equal((await fetch(`${api.base}/dashboard`)).status, 401);
  const page = await (await fetch(`${api.base}/dashboard?key=test-key-123&stage=Qualified`)).text();
  assert.match(page, /Lead Tester/);
  assert.match(page, /wa\.me\/971501234567/);
  assert.match(page, /AI call<\/button>/);
  const csv = await (await fetch(`${api.base}/dashboard/leads.csv?key=test-key-123`)).text();
  assert.match(csv.split('\n')[0], /^createdAt,stage,score,docScore,name/);
  assert.match(csv, /"Qualified"/);
});

// ---- Ammachi -------------------------------------------------------------------------

test('Ammachi offline mode recommends real trips with creator attribution', async () => {
  const events = await sse(api.base, { messages: [{ role: 'user', text: 'ദുബായിൽ നിന്ന് മലയിൽ പോകണം' }], lang: 'ml' });
  assert.deepEqual(events[0], { event: 'meta', data: { mode: 'offline', model: null, voice: false } });
  const cites = events.filter((e) => e.event === 'cite').map((e) => e.data.journey);
  assert.ok(cites.length >= 1 && cites[0].tags.includes('mountains'));
  const text = events.filter((e) => e.event === 'delta').map((e) => e.data.text).join('');
  assert.ok(!text.includes('[['));
  assert.ok(text.includes(cites[0].creator.name));
  assert.doesNotMatch(text, /\s[,.!?]|\s{2,}/);
  assert.equal(events.at(-1).event, 'done');
});

test('Ammachi streams a model answer, keeps valid citations and drops invented ones', async () => {
  const seen = {};
  const llm = {
    name: 'fake',
    model: 'fake-1',
    async *stream({ system, history, modelOverride }) {
      Object.assign(seen, { system, history, modelOverride });
      yield 'Kunje, Omar wrote [[jour';
      yield 'ney:j_musandam]] about the fjords. ';
      yield 'Also see [[journey:j_made_up]] and [journey:j_hatta]. Go!';
    },
  };
  const s = await serve({ llm, callModel: 'fast-model' });
  try {
    const events = await sse(s.base, { messages: [{ role: 'ammachi', text: 'Hello!' }, { role: 'user', text: 'Boat trip?' }], lang: 'en', journeyId: 'j_hatta', mode: 'call' });
    assert.equal(events[0].data.mode, 'gemini');
    assert.equal(events[0].data.model, 'fast-model');
    assert.deepEqual(events.filter((e) => e.event === 'cite').map((e) => e.data.journey.id), ['j_musandam', 'j_hatta']);
    assert.equal(events.filter((e) => e.event === 'delta').map((e) => e.data.text).join(''), 'Kunje, Omar wrote about the fjords. Also see and. Go!');
    assert.deepEqual(seen.history, [{ role: 'user', text: 'Boat trip?' }]);
    assert.equal(seen.modelOverride, 'fast-model');
    assert.match(seen.system, /\[j_musandam\] "Musandam: Arabia’s Fjords by Dhow" by Omar Haddad/);
    assert.match(seen.system, /You are on a voice call/);
    assert.match(seen.system, /looking at the trip \[j_hatta\]/);
  } finally {
    await s.close();
  }
});

test('Ammachi falls back to the catalogue when the model fails before speaking', async () => {
  const llm = {
    name: 'fake',
    model: 'fake-1',
    // eslint-disable-next-line require-yield
    async *stream() {
      throw new Error('quota exceeded');
    },
  };
  const s = await serve({ llm });
  try {
    const events = await sse(s.base, { messages: [{ role: 'user', text: 'cheap beach trip' }], lang: 'en' });
    assert.equal(events.filter((e) => e.event === 'meta').at(-1).data.reason, 'model_unavailable');
    assert.ok(events.some((e) => e.event === 'cite'));
    assert.equal(events.at(-1).event, 'done');
  } finally {
    await s.close();
  }
});

test('Ammachi voice: an instant filler first, then sentences strictly in order', async () => {
  const tts = {
    enabled: true,
    async synthesize(text) {
      await new Promise((r) => setTimeout(r, text.startsWith('One') ? 60 : 5));
      return `/static/tts/${encodeURIComponent(text.slice(0, 5))}.mp3`;
    },
  };
  const voiceLines = { ready: true, filler: () => ({ url: '/static/tts/filler.mp3', text: 'Hmm, let me see.' }), greeting: () => '/static/tts/hello.mp3' };
  const llm = {
    name: 'fake',
    model: 'fake-1',
    async *stream() {
      yield 'One sentence comes first here. ';
      yield 'Two sentences follow after that. Three is the last one.';
    },
  };
  const s = await serve({ llm, tts, voiceLines });
  try {
    const events = await sse(s.base, { messages: [{ role: 'user', text: 'hi' }], lang: 'en' });
    const audio = events.filter((e) => e.event === 'audio').map((e) => e.data);
    assert.equal(events[1].event, 'audio');
    assert.equal(audio[0].filler, true);
    assert.deepEqual(audio.slice(1).map((a) => a.index), [0, 1, 2]);
    assert.ok(audio[1].text.startsWith('One') && audio[3].text.startsWith('Three'));
    const status = (await json(s.base, '/api/ammachi/status')).body;
    assert.match(status.greeting.ml, /\/static\/tts\/hello\.mp3$/);
  } finally {
    await s.close();
  }
});

// ---- Gemini SDK wiring, against a local mock of the Gemini REST API ----------------

test('Gemini client streams through the official SDK with our system prompt and thinking level', async () => {
  let captured;
  const mock = http.createServer((req, res) => {
    let body = '';
    req.on('data', (d) => (body += d));
    req.on('end', () => {
      captured = { url: req.url, headers: req.headers, body: JSON.parse(body) };
      res.writeHead(200, { 'Content-Type': 'text/event-stream' });
      for (const text of ['നമസ്കാരം ', 'കുഞ്ഞേ!']) {
        res.write(`data: ${JSON.stringify({ candidates: [{ content: { role: 'model', parts: [{ text }] }, index: 0 }] })}\r\n\r\n`);
      }
      res.end();
    });
  });
  mock.listen(0);
  await new Promise((r) => mock.once('listening', r));
  try {
    const gemini = createGemini({ apiKey: 'test-key', model: 'gemini-flash-latest', thinkingLevel: 'LOW', baseUrl: `http://127.0.0.1:${mock.address().port}` });
    let out = '';
    for await (const t of gemini.stream({ system: 'You are Ammachi.', history: [{ role: 'user', text: 'Hi' }] })) out += t;
    assert.equal(out, 'നമസ്കാരം കുഞ്ഞേ!');
    assert.match(captured.url, /models\/gemini-flash-latest:streamGenerateContent\?alt=sse/);
    assert.equal(captured.headers['x-goog-api-key'], 'test-key');
    assert.equal(captured.body.systemInstruction.parts[0].text, 'You are Ammachi.');
    assert.equal(captured.body.generationConfig.thinkingConfig.thinkingLevel, 'LOW');
  } finally {
    mock.close();
  }
});

// ---- stream parsing units ---------------------------------------------------------

test('CitationSplitter handles markers split at every possible point', () => {
  const input = 'Try [[journey:j_a]] or [[journey:j_b]]!';
  for (let cut = 1; cut < input.length; cut++) {
    for (let cut2 = cut + 1; cut2 <= input.length; cut2++) {
      const s = new CitationSplitter();
      const parts = [...s.push(input.slice(0, cut)), ...s.push(input.slice(cut, cut2)), ...s.push(input.slice(cut2)), ...s.flush()];
      assert.equal(parts.filter((p) => p.type === 'text').map((p) => p.text).join(''), 'Try or!', `cuts at ${cut}/${cut2}`);
      assert.deepEqual(parts.filter((p) => p.type === 'cite').map((p) => p.id), ['j_a', 'j_b']);
    }
  }
});

test('SentenceChunker splits Malayalam and English sentences', () => {
  const c = new SentenceChunker(10);
  const out = [...c.push('മഴ കാണാനാണോ കുഞ്ഞേ? അമ്മച്ചിക്ക് '), ...c.push('പറ്റിയ ഒന്നുണ്ട്. Go'), ...c.flush()];
  assert.deepEqual(out, ['മഴ കാണാനാണോ കുഞ്ഞേ?', 'അമ്മച്ചിക്ക് പറ്റിയ ഒന്നുണ്ട്.', 'Go']);
});

test('sign-up needs a phone number, and it stays private', async () => {
  const bad = await post(api.base, '/api/creators', { name: 'No Phone', handle: 'no.phone' });
  assert.equal(bad.status, 400);
  assert.ok(bad.body.details.phone);
  const me = await signUp(api.base, 'Phone Person', 'phone.person');
  assert.equal(me.phone, undefined);
});

test('document check scores uploads; ≥ 70 with consent auto-triggers the AI call and shows in the CRM', async () => {
  const s = await serve();
  try {
    const me = await signUp(s.base, 'Visa Ready', 'visa.ready');
    const big = new Blob([new Uint8Array(40_000)], { type: 'image/jpeg' });
    const form = new FormData();
    for (const id of ['passport', 'residence', 'bank']) form.append(id, big, `${id}.jpg`);
    form.append('destination', 'Georgia');
    form.append('travelers', '2');
    const res = await fetch(`${s.base}/api/documents/check`, { method: 'POST', body: form, headers: { ...DEVICE, 'x-user-id': me.id } });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.score, 85); // passport 35 + residence 25 + bank 25, no photo
    assert.equal(body.checks.find((c) => c.doc === 'photo').status, 'missing');
    assert.equal(body.qualified, true);
    assert.equal(body.call.status, 'simulated'); // no Plivo keys in tests
    const lead = s.store.lead(body.leadId);
    assert.equal(lead.call.status, 'simulated');

    const html = await (await fetch(`${s.base}/dashboard?key=test-key-123`)).text();
    assert.match(html, /Visa Ready/);
    assert.match(html, /Call simulated/);
    const users = await (await fetch(`${s.base}/dashboard?key=test-key-123&view=users`)).text();
    assert.match(users, /\+971501234567/);

    // The agent reports the call → the lead shows its outcome.
    const r2 = await fetch(`${s.base}/api/voice/result/${lead.id}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-agent-key': 'test-key-123' },
      body: JSON.stringify({ transcript: [{ role: 'assistant', text: 'Where would you like to go?' }, { role: 'user', text: 'Georgia in December, two of us' }] }),
    });
    assert.equal(r2.status, 200);
    assert.equal(s.store.lead(lead.id).call.status, 'completed');
    const denied = await fetch(`${s.base}/api/voice/lead/${lead.id}`);
    assert.equal(denied.status, 401);
  } finally {
    await s.close();
  }
});

test('Plivo answer webhook streams the call to the agent', async () => {
  const res = await fetch(`${api.base}/voice/answer/l_test`, { method: 'POST' });
  const xml = await res.text();
  assert.match(xml, /<Stream bidirectional="true"[^>]*>wss?:\/\/.+\/voice\/ws\/l_test<\/Stream>/);
});

test('booking a stay from a trip takes a demo payment and earns 10%', async () => {
  const me = await signUp(api.base, 'Booker', 'the.booker');
  const feed = await json(api.base, '/api/feed');
  const j = feed.body.journeys[0];
  const { status, body } = await post(api.base, '/api/bookings', { journeyId: j.id, item: 'Hotel', category: 'stay', amount: 500, guests: 2, date: '2026-12-01' }, { 'x-user-id': me.id });
  assert.equal(status, 201);
  assert.match(body.booking.ref, /^TG-/);
  assert.equal(body.booking.payment, 'demo');
  assert.equal(body.booking.commissionAed, Math.round(body.booking.amountAed * 0.1));
  const mine = await json(api.base, '/api/me/bookings', { headers: { 'x-user-id': me.id } });
  assert.equal(mine.body.bookings.length, 1);
});

test('uploaded identity documents are private: only the key-protected dashboard serves them', async () => {
  const s = await serve();
  try {
    const me = await signUp(s.base, 'Doc Privacy', 'doc.privacy');
    const form = new FormData();
    form.append('passport', new Blob([new Uint8Array(40_000)], { type: 'image/jpeg' }), 'evil.html');
    form.append('residence', new Blob(['<svg onload=alert(1)>'], { type: 'image/svg+xml' }), 'x.svg');
    const body = await (await fetch(`${s.base}/api/documents/check`, { method: 'POST', body: form, headers: { ...DEVICE, 'x-user-id': me.id } })).json();
    const id = body.leadId;
    assert.equal((await fetch(`${s.base}/static/docs/${id}/passport.jpg`)).status, 404); // never public
    assert.equal((await fetch(`${s.base}/dashboard/docs/${id}/passport.jpg`)).status, 401); // needs the key
    const ok = await fetch(`${s.base}/dashboard/docs/${id}/passport.jpg?key=test-key-123`);
    assert.equal(ok.status, 200);
    assert.equal(ok.headers.get('x-content-type-options'), 'nosniff');
    assert.equal((await fetch(`${s.base}/dashboard/docs/${id}/passport.html?key=test-key-123`)).status, 404); // extension comes from the type, not the name
    assert.equal((await fetch(`${s.base}/dashboard/docs/${id}/residence.svg?key=test-key-123`)).status, 404); // SVG rejected
    assert.equal((await fetch(`${s.base}/dashboard/docs/${id}/..%2F..%2Fdb.json?key=test-key-123`)).status, 404);
  } finally {
    await s.close();
  }
});
