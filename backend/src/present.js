// Shapes stored records into API responses. Photo paths are stored relative
// (/static/...) and expanded against the request host, so the same data works
// from an emulator (10.0.2.2), a phone on the LAN, an ngrok tunnel, or the web.
import { toAed } from './currency.js';

export const BUDGET_CATEGORIES = ['stay', 'transport', 'food', 'activities', 'other'];

export function baseUrl(req) {
  return `${req.protocol}://${req.get('host')}`;
}

export function absolutize(req, url) {
  if (!url) return url;
  return url.startsWith('/') ? `${baseUrl(req)}${url}` : url;
}

const photo = (req, p) => (p ? { ...p, url: absolutize(req, p.url) } : null);

export function budgetTotal(journey) {
  return journey.budget.reduce((sum, item) => sum + item.amount, 0);
}

export function budgetAed(journey) {
  return toAed(budgetTotal(journey), journey.currency ?? 'AED');
}

/// The viewer's identity: device (saves, likes) and user (follows, going).
export function viewerOf(req, store) {
  const userId = req.get('x-user-id') || null;
  return {
    deviceId: req.get('x-device-id')?.slice(0, 64) || null,
    userId: userId && store.creator(userId) ? userId : null,
  };
}

export function creatorView(store, creator, viewer) {
  if (!creator) return { id: 'unknown', name: 'Unknown traveller', handle: 'unknown', hue: 0, followers: 0, following: 0, isFollowing: false };
  const { id, name, handle, home, bio, hue } = creator;
  return {
    id,
    name,
    handle,
    home,
    bio,
    hue,
    followers: store.followerCount(id),
    following: store.followingCount(id),
    trips: store.journeys().filter((j) => j.creatorId === id).length,
    isFollowing: store.isFollowing(viewer?.userId, id),
  };
}

export function card(req, store, journey, viewer) {
  const total = budgetTotal(journey);
  const photos = journey.stops.flatMap((s) => s.photos).slice(0, 6);
  const cover = journey.coverPhoto ?? photos[0] ?? null;
  return {
    id: journey.id,
    title: journey.title,
    dek: journey.dek,
    region: journey.region,
    country: journey.country ?? '',
    tags: journey.tags,
    bestMonths: journey.bestMonths ?? [],
    durationDays: journey.durationDays,
    travelers: journey.travelers,
    stopCount: journey.stops.length,
    stopNames: journey.stops.map((s) => s.name),
    currency: journey.currency ?? 'AED',
    budgetTotal: total,
    budgetAed: budgetAed(journey),
    perPersonPerDay: Math.round(total / Math.max(1, journey.travelers) / Math.max(1, journey.durationDays)),
    coverPhoto: photo(req, cover),
    photos: [cover, ...photos.filter((p) => p.url !== cover?.url)].filter(Boolean).slice(0, 6).map((p) => photo(req, p)),
    creator: creatorView(store, store.creator(journey.creatorId), viewer),
    likes: journey.likes,
    saves: store.saveCount(journey.id),
    goingCount: store.goingCount(journey.id),
    liked: viewer?.deviceId ? store.isLiked(viewer.deviceId, journey.id) : false,
    saved: viewer?.deviceId ? store.isSaved(viewer.deviceId, journey.id) : false,
    isGoing: store.isGoing(viewer?.userId, journey.id),
    createdAt: journey.createdAt,
  };
}

export function detail(req, store, journey, viewer) {
  return {
    ...card(req, store, journey, viewer),
    story: journey.story ?? '',
    pullQuote: journey.pullQuote ?? null,
    fields: journey.fields ?? [],
    stops: journey.stops.map((s) => ({
      ...s,
      fields: s.fields ?? [],
      expenses: journey.budget.filter((b) => b.stopId === s.id),
      photos: s.photos.map((p) => photo(req, p)),
    })),
    budget: BUDGET_CATEGORIES.map((category) => {
      const items = journey.budget.filter((b) => b.category === category);
      return { category, amount: items.reduce((s, b) => s + b.amount, 0), items };
    }).filter((c) => c.amount > 0),
  };
}

// ---- filtering / search ------------------------------------------------------

export function matches(journey, store, f) {
  if (f.creatorId && journey.creatorId !== f.creatorId) return false;
  if (f.creatorIds && !f.creatorIds.includes(journey.creatorId)) return false;
  if (f.tag && !journey.tags.includes(f.tag)) return false;
  if (f.destination && journey.region.toLowerCase() !== f.destination.toLowerCase()) return false;
  if (f.country && (journey.country ?? '').toLowerCase() !== f.country.toLowerCase()) return false;
  const aed = budgetAed(journey);
  if (f.minAed !== undefined && aed < f.minAed) return false;
  if (f.maxAed !== undefined && aed > f.maxAed) return false;
  if (f.minDays !== undefined && journey.durationDays < f.minDays) return false;
  if (f.maxDays !== undefined && journey.durationDays > f.maxDays) return false;
  if (f.q) {
    const creator = store.creator(journey.creatorId);
    const haystack = [
      journey.title,
      journey.dek,
      journey.region,
      journey.country,
      journey.tags.join(' '),
      journey.stops.map((s) => s.name).join(' '),
      creator?.name,
      creator?.handle,
    ]
      .join(' ')
      .toLowerCase();
    const terms = f.q.toLowerCase().split(/\s+/).filter(Boolean);
    if (!terms.every((t) => haystack.includes(t))) return false;
  }
  return true;
}

/// "For you": fresh posts first, then what people engage with.
export function forYouScore(journey, store) {
  const ageDays = (Date.now() - Date.parse(journey.createdAt)) / 86400000;
  // Brand-new posts lead for their first day; then freshness fades over a month.
  const freshness = (ageDays < 1 ? 100 : 0) + Math.max(0, 30 - ageDays) * 2;
  return freshness + Math.log10(journey.likes + 1) * 10 + Math.log10(store.goingCount(journey.id) + 1) * 8;
}
