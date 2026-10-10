import { Router } from 'express';
import { CURRENCIES, toAed } from '../currency.js';
import { scoreLead } from '../leads.js';
import { BUDGET_CATEGORIES, budgetAed, card, creatorView, detail, forYouScore, matches, viewerOf } from '../present.js';

export class HttpError extends Error {
  constructor(status, message, details) {
    super(message);
    this.status = status;
    this.details = details;
  }
}

const num = (v) => (v === undefined || v === '' ? undefined : Number(v));

function requireUser(viewer) {
  if (!viewer.userId) throw new HttpError(401, 'Create your profile first.');
  return viewer.userId;
}

export function journeysRouter(store) {
  const r = Router();

  // Home feed: "For you" (everyone, fresh and popular first) or "Following".
  r.get('/feed', (req, res) => {
    const viewer = viewerOf(req, store);
    const tab = req.query.tab === 'following' ? 'following' : 'foryou';
    let list = store.journeys();
    if (tab === 'following') {
      const ids = viewer.userId ? store.followingIds(viewer.userId) : [];
      list = list.filter((j) => ids.includes(j.creatorId)).sort((a, b) => b.createdAt.localeCompare(a.createdAt));
    } else {
      list = [...list].sort((a, b) => forYouScore(b, store) - forYouScore(a, store));
    }
    const suggested = store
      .creators()
      .filter((c) => c.id !== viewer.userId && !store.isFollowing(viewer.userId, c.id) && store.journeys().some((j) => j.creatorId === c.id))
      .sort((a, b) => store.followerCount(b.id) - store.followerCount(a.id))
      .slice(0, 8)
      .map((c) => creatorView(store, c, viewer));
    res.json({
      tab,
      journeys: list.map((j) => card(req, store, j, viewer)),
      destinations: destinationsOf(req, store).slice(0, 12),
      suggested,
    });
  });

  r.get('/journeys', (req, res) => {
    const viewer = viewerOf(req, store);
    const filter = {
      q: req.query.q?.toString().trim() || undefined,
      tag: req.query.tag?.toString() || undefined,
      destination: req.query.destination?.toString() || undefined,
      country: req.query.country?.toString() || undefined,
      creatorId: req.query.creatorId?.toString() || undefined,
      minAed: num(req.query.minAed),
      maxAed: num(req.query.maxAed),
      minDays: num(req.query.minDays),
      maxDays: num(req.query.maxDays),
    };
    let list = store.journeys().filter((j) => matches(j, store, filter));
    if (req.query.sort === 'popular') list = [...list].sort((a, b) => b.likes - a.likes);
    else if (req.query.sort === 'budget') list = [...list].sort((a, b) => budgetAed(a) - budgetAed(b));
    else list = [...list].sort((a, b) => b.createdAt.localeCompare(a.createdAt));
    res.json({ journeys: list.map((j) => card(req, store, j, viewer)) });
  });

  r.get('/destinations', (req, res) => {
    res.json({ destinations: destinationsOf(req, store) });
  });

  r.get('/journeys/:id', (req, res) => {
    const journey = store.journey(req.params.id);
    if (!journey) throw new HttpError(404, 'Journey not found');
    const viewer = viewerOf(req, store);
    const related = store
      .journeys()
      .filter((j) => j.id !== journey.id)
      .map((j) => ({
        j,
        score: j.tags.filter((t) => journey.tags.includes(t)).length + (j.region === journey.region ? 3 : 0) + (j.country === journey.country ? 1 : 0),
      }))
      .filter((x) => x.score > 0)
      .sort((a, b) => b.score - a.score)
      .slice(0, 6)
      .map((x) => card(req, store, x.j, viewer));
    res.json({ journey: detail(req, store, journey, viewer), related });
  });

  r.post('/journeys', (req, res) => {
    const input = validateJourney(req.body ?? {}, store);
    const journey = store.addJourney(input);
    res.status(201).json({ journey: detail(req, store, journey, viewerOf(req, store)) });
  });

  r.post('/journeys/:id/save', (req, res) => {
    const { deviceId } = viewerOf(req, store);
    if (!deviceId) throw new HttpError(400, 'x-device-id header is required');
    if (!store.journey(req.params.id)) throw new HttpError(404, 'Journey not found');
    const saved = store.toggleSave(deviceId, req.params.id);
    res.json({ saved, saves: store.saveCount(req.params.id) });
  });

  r.post('/journeys/:id/like', (req, res) => {
    const { deviceId } = viewerOf(req, store);
    if (!deviceId) throw new HttpError(400, 'x-device-id header is required');
    if (!store.journey(req.params.id)) throw new HttpError(404, 'Journey not found');
    res.json(store.toggleLike(deviceId, req.params.id));
  });

  r.post('/journeys/:id/going', (req, res) => {
    const userId = requireUser(viewerOf(req, store));
    const journey = store.journey(req.params.id);
    if (!journey) throw new HttpError(404, 'Journey not found');
    const result = store.toggleGoing(userId, journey.id);
    if (result.going) {
      // Saying "I'm going" is intent: record it as an (unqualified) lead.
      const creator = store.creator(userId);
      const total = journey.budget.reduce((s, b) => s + b.amount, 0);
      const lead = { source: 'going', userId, name: creator?.name ?? '', handle: creator?.handle ?? null, phone: null, consent: false, planId: null, journeyId: journey.id, destination: journey.region, title: journey.title, budget: total, currency: journey.currency ?? 'AED', budgetAed: toAed(total, journey.currency ?? 'AED'), travelers: null, days: journey.durationDays, month: null, from: creator?.home ?? '', notes: '' };
      store.upsertLead({ ...lead, ...scoreLead(lead) });
    }
    res.json(result);
  });

  r.get('/me/saved', (req, res) => {
    const viewer = viewerOf(req, store);
    if (!viewer.deviceId) throw new HttpError(400, 'x-device-id header is required');
    const journeys = store.savedIds(viewer.deviceId).map((id) => store.journey(id)).filter(Boolean);
    res.json({ journeys: journeys.map((j) => card(req, store, j, viewer)) });
  });

  r.get('/me/going', (req, res) => {
    const viewer = viewerOf(req, store);
    const userId = requireUser(viewer);
    const journeys = store.goingIds(userId).map((id) => store.journey(id)).filter(Boolean);
    res.json({ journeys: journeys.map((j) => card(req, store, j, viewer)) });
  });

  return r;
}

/// Destinations, classified from the trips people have posted.
export function destinationsOf(req, store) {
  const groups = new Map();
  for (const j of store.journeys()) {
    const key = j.region.toLowerCase();
    const g = groups.get(key) ?? { name: j.region, country: j.country ?? '', count: 0, minAed: Infinity, cover: null, likes: -1 };
    g.count += 1;
    g.minAed = Math.min(g.minAed, budgetAed(j));
    if (j.likes > g.likes && j.coverPhoto) {
      g.likes = j.likes;
      g.cover = j.coverPhoto;
    }
    groups.set(key, g);
  }
  return [...groups.values()]
    .sort((a, b) => b.count - a.count || b.likes - a.likes)
    .map(({ likes, cover, ...g }) => ({ ...g, coverPhoto: cover ? { ...cover, url: cover.url.startsWith('/') ? `${req.protocol}://${req.get('host')}${cover.url}` : cover.url } : null }));
}

// ---- validation ---------------------------------------------------------------

const str = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');

function photoPath(url) {
  if (typeof url !== 'string' || !url) return null;
  // Uploaded files come back as absolute URLs; store them host-independent.
  const idx = url.indexOf('/static/');
  if (idx >= 0) return url.slice(idx);
  return /^https?:\/\//.test(url) ? url : null;
}

function fieldsOf(list, max = 12) {
  return (Array.isArray(list) ? list : [])
    .map((f) => ({ label: str(f?.label, 30), value: str(f?.value, 200) }))
    .filter((f) => f.label && f.value)
    .slice(0, max);
}

function expensesOf(list, stopId) {
  return (Array.isArray(list) ? list : [])
    .map((b) => ({
      category: BUDGET_CATEGORIES.includes(b?.category) ? b.category : 'other',
      label: str(b?.label, 80) || 'Expense',
      amount: Math.round(Number(b?.amount)),
      ...(stopId ? { stopId } : {}),
    }))
    .filter((b) => Number.isFinite(b.amount) && b.amount > 0 && b.amount < 100_000_000);
}

export function validateJourney(body, store) {
  const errors = {};
  const creator = store.creator(body.creatorId);
  if (!creator) errors.creatorId = 'Create your profile first.';

  const title = str(body.title, 80);
  if (title.length < 3) errors.title = 'Give your trip a title (3+ characters).';

  const rawStops = Array.isArray(body.stops) ? body.stops.slice(0, 30) : [];
  const stops = rawStops
    .map((s, i) => ({
      id: `s${i + 1}`,
      name: str(s.name, 60),
      day: Math.max(1, Math.min(60, Math.round(Number(s.day) || 1))),
      lat: Number(s.lat),
      lng: Number(s.lng),
      story: str(s.story, 1200),
      tip: str(s.tip, 300),
      fields: fieldsOf(s.fields),
      expenses: s.expenses,
      photos: (Array.isArray(s.photos) ? s.photos : [])
        .slice(0, 10)
        .map((p) => photoPath(p?.url ?? p))
        .filter(Boolean)
        .map((url) => ({ url, caption: str(s.name, 60), credit: { author: creator?.name ?? '', license: 'Shared on Travelgram', source: null } })),
    }))
    .filter((s) => s.name);
  if (stops.length < 1) errors.stops = 'Add at least one place.';
  if (stops.some((s) => !Number.isFinite(s.lat) || !Number.isFinite(s.lng) || Math.abs(s.lat) > 90 || Math.abs(s.lng) > 180)) {
    errors.stops = 'Every place needs a location. Pick it from the search results.';
  }

  const budget = [...expensesOf(body.budget), ...stops.flatMap((s) => expensesOf(s.expenses, s.id))];
  for (const s of stops) delete s.expenses;

  const travelers = Math.max(1, Math.min(50, Math.round(Number(body.travelers) || 1)));
  const lastDay = Math.max(1, ...stops.map((s) => s.day));
  const durationDays = Math.max(lastDay, Math.min(60, Math.round(Number(body.durationDays) || lastDay)));
  const currency = CURRENCIES.includes(body.currency) ? body.currency : 'AED';

  const tags = (Array.isArray(body.tags) ? body.tags : [])
    .map((t) => str(t, 24).toLowerCase())
    .filter(Boolean)
    .slice(0, 6);

  if (Object.keys(errors).length) throw new HttpError(400, 'Some details need another look.', errors);

  const allPhotos = stops.flatMap((s) => s.photos);
  const coverPath = photoPath(body.coverPhotoUrl);
  const coverPhoto = allPhotos.find((p) => p.url === coverPath) ?? allPhotos[0] ?? null;

  return {
    creatorId: creator.id,
    title,
    dek: str(body.dek, 200),
    region: str(body.region, 40) || stops[0].name,
    country: str(body.country, 40),
    currency,
    tags,
    bestMonths: (Array.isArray(body.bestMonths) ? body.bestMonths : []).map(Number).filter((m) => m >= 1 && m <= 12),
    durationDays,
    travelers,
    story: str(body.story, 4000),
    fields: fieldsOf(body.fields),
    coverPhoto,
    stops,
    budget,
  };
}
