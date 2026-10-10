import { Router } from 'express';
import { card, creatorView, viewerOf } from '../present.js';
import { HttpError } from './journeys.js';

export function creatorsRouter(store) {
  const r = Router();

  // Everyone on Travelgram is a creator. Profile creation is the sign-up.
  r.post('/creators', (req, res) => {
    const name = String(req.body?.name ?? '').trim().slice(0, 40);
    const handle = String(req.body?.handle ?? '')
      .trim()
      .replace(/^@/, '')
      .toLowerCase()
      .slice(0, 24);
    const errors = {};
    if (name.length < 2) errors.name = 'Tell us your name.';
    if (!/^[a-z0-9._]{3,24}$/.test(handle)) errors.handle = 'Use 3–24 letters, numbers, dots or underscores.';
    else if (store.creatorByHandle(handle)) errors.handle = `@${handle} is taken. Try another.`;
    const phone = String(req.body?.phone ?? '').replace(/[^\d+]/g, '').slice(0, 16);
    if (phone.replace(/\D/g, '').length < 8) errors.phone = 'Enter your mobile number with country code.';
    if (Object.keys(errors).length) throw new HttpError(400, 'Check your profile details.', errors);
    const creator = store.addCreator({
      name,
      handle,
      home: String(req.body?.home ?? '').trim().slice(0, 40),
      bio: String(req.body?.bio ?? '').trim().slice(0, 140),
      phone: phone.startsWith('+') ? phone : `+${phone}`,
      consent: req.body?.consent === true,
    });
    res.status(201).json({ creator: creatorView(store, creator, { userId: creator.id }) });
  });

  // People to follow, or search by name/handle.
  r.get('/creators', (req, res) => {
    const viewer = viewerOf(req, store);
    const q = String(req.query.q ?? '').trim().toLowerCase();
    const list = store
      .creators()
      .filter((c) => c.id !== viewer.userId)
      .filter((c) => !q || `${c.name} ${c.handle} ${c.home}`.toLowerCase().includes(q))
      .sort((a, b) => store.followerCount(b.id) - store.followerCount(a.id))
      .slice(0, 30)
      .map((c) => creatorView(store, c, viewer));
    res.json({ creators: list });
  });

  r.get('/creators/:id', (req, res) => {
    const creator = store.creator(req.params.id);
    if (!creator) throw new HttpError(404, 'Traveller not found');
    const viewer = viewerOf(req, store);
    const journeys = store
      .journeys()
      .filter((j) => j.creatorId === creator.id)
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt));
    res.json({
      creator: creatorView(store, creator, viewer),
      stats: {
        journeys: journeys.length,
        likes: journeys.reduce((s, j) => s + j.likes, 0),
        days: journeys.reduce((s, j) => s + j.durationDays, 0),
        countries: new Set(journeys.map((j) => j.country).filter(Boolean)).size,
      },
      journeys: journeys.map((j) => card(req, store, j, viewer)),
    });
  });

  r.post('/creators/:id/follow', (req, res) => {
    const viewer = viewerOf(req, store);
    if (!viewer.userId) throw new HttpError(401, 'Create your profile first.');
    if (!store.creator(req.params.id)) throw new HttpError(404, 'Traveller not found');
    if (req.params.id === viewer.userId) throw new HttpError(400, "You can't follow yourself.");
    res.json(store.toggleFollow(viewer.userId, req.params.id));
  });

  return r;
}
