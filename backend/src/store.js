// A tiny JSON-file database. Fine for a hackathon: everything lives in memory
// and is flushed to data/db.json (atomic rename) shortly after each write.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const EMPTY = () => ({ saves: {}, likes: {}, follows: {}, going: {}, plans: [], leads: [], bookings: [] });

export class Store {
  constructor(dataDir) {
    this.dataDir = dataDir;
    this.file = path.join(dataDir, 'db.json');
    this.seedFile = path.join(dataDir, 'seed.json');
    this.flushTimer = null;
    this.db = this.#load();
  }

  #load() {
    if (fs.existsSync(this.file)) return { ...EMPTY(), ...JSON.parse(fs.readFileSync(this.file, 'utf8')) };
    return { ...JSON.parse(fs.readFileSync(this.seedFile, 'utf8')), ...EMPTY() };
  }

  reset() {
    this.db = { ...JSON.parse(fs.readFileSync(this.seedFile, 'utf8')), ...EMPTY() };
    this.flushNow();
  }

  #scheduleFlush() {
    clearTimeout(this.flushTimer);
    this.flushTimer = setTimeout(() => this.flushNow(), 150);
  }

  flushNow() {
    clearTimeout(this.flushTimer);
    const tmp = `${this.file}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(this.db, null, 2));
    fs.renameSync(tmp, this.file);
  }

  // ---- creators (every user is a creator) ------------------------------------

  creators() {
    return this.db.creators;
  }

  creator(id) {
    return this.db.creators.find((c) => c.id === id) ?? null;
  }

  creatorByHandle(handle) {
    const h = handle.toLowerCase();
    return this.db.creators.find((c) => c.handle.toLowerCase() === h) ?? null;
  }

  addCreator({ name, handle, home = '', bio = '', phone = null, consent = false }) {
    const creator = {
      id: `c_${crypto.randomUUID().slice(0, 8)}`,
      name,
      handle,
      home,
      bio,
      hue: Math.floor(Math.random() * 360),
      followers: 0,
      following: 0,
      phone, // private: only the dashboard sees it
      consent,
      joinedAt: new Date().toISOString(),
    };
    this.db.creators.push(creator);
    this.#scheduleFlush();
    return creator;
  }

  // ---- follows ----------------------------------------------------------------

  followingIds(userId) {
    return this.db.follows[userId] ?? [];
  }

  isFollowing(userId, creatorId) {
    return Boolean(userId) && this.followingIds(userId).includes(creatorId);
  }

  followerCount(creatorId) {
    const base = this.creator(creatorId)?.followers ?? 0;
    return base + Object.values(this.db.follows).filter((ids) => ids.includes(creatorId)).length;
  }

  followingCount(userId) {
    return (this.creator(userId)?.following ?? 0) + this.followingIds(userId).length;
  }

  toggleFollow(userId, creatorId) {
    const ids = new Set(this.followingIds(userId));
    const following = !ids.has(creatorId);
    if (following) ids.add(creatorId);
    else ids.delete(creatorId);
    this.db.follows[userId] = [...ids];
    this.#scheduleFlush();
    return { following, followers: this.followerCount(creatorId) };
  }

  // ---- journeys -----------------------------------------------------------------

  journeys() {
    return this.db.journeys;
  }

  journey(id) {
    return this.db.journeys.find((j) => j.id === id) ?? null;
  }

  addJourney(journey) {
    const full = {
      ...journey,
      id: `j_${crypto.randomUUID().slice(0, 10)}`,
      likes: 0,
      going: 0,
      createdAt: new Date().toISOString(),
    };
    this.db.journeys.unshift(full);
    this.#scheduleFlush();
    return full;
  }

  // ---- "I'm going" ---------------------------------------------------------------

  goingIds(userId) {
    return this.db.going[userId] ?? [];
  }

  isGoing(userId, journeyId) {
    return Boolean(userId) && this.goingIds(userId).includes(journeyId);
  }

  goingCount(journeyId) {
    const base = this.journey(journeyId)?.going ?? 0;
    return base + Object.values(this.db.going).filter((ids) => ids.includes(journeyId)).length;
  }

  toggleGoing(userId, journeyId) {
    const ids = new Set(this.goingIds(userId));
    const going = !ids.has(journeyId);
    this.db.going[userId] = going ? [journeyId, ...[...ids].filter((i) => i !== journeyId)] : [...ids].filter((i) => i !== journeyId);
    this.#scheduleFlush();
    return { going, goingCount: this.goingCount(journeyId) };
  }

  // ---- budget plans & leads --------------------------------------------------

  addPlan(plan) {
    const full = { ...plan, id: `p_${crypto.randomUUID().slice(0, 10)}`, createdAt: new Date().toISOString() };
    this.db.plans.unshift(full);
    this.#scheduleFlush();
    return full;
  }

  plan(id) {
    return this.db.plans.find((p) => p.id === id) ?? null;
  }

  plansOf(userId) {
    return this.db.plans.filter((p) => p.userId === userId);
  }

  leads() {
    return this.db.leads;
  }

  lead(id) {
    return this.db.leads.find((l) => l.id === id) ?? null;
  }

  updateLead(id, patch) {
    const l = this.lead(id);
    if (!l) return null;
    Object.assign(l, patch, { updatedAt: new Date().toISOString() });
    this.#scheduleFlush();
    return l;
  }

  // ---- bookings (demo payments) ----------------------------------------------

  bookings() {
    return this.db.bookings;
  }

  addBooking(b) {
    const booking = { id: `b_${crypto.randomUUID().slice(0, 8)}`, ref: `TG-${crypto.randomBytes(3).toString('hex').toUpperCase()}`, createdAt: new Date().toISOString(), ...b };
    this.db.bookings.unshift(booking);
    this.#scheduleFlush();
    return booking;
  }

  /// One lead per person per plan/trip: a later, richer request replaces it.
  upsertLead(lead) {
    const key = (l) => `${l.userId ?? l.phone}|${l.planId ?? ''}|${l.journeyId ?? ''}`;
    const i = this.db.leads.findIndex((l) => key(l) === key(lead));
    const full = { ...(i >= 0 ? this.db.leads[i] : {}), ...lead, id: i >= 0 ? this.db.leads[i].id : `l_${crypto.randomUUID().slice(0, 10)}`, updatedAt: new Date().toISOString() };
    full.createdAt ??= full.updatedAt;
    if (i >= 0) this.db.leads.splice(i, 1);
    this.db.leads.unshift(full);
    this.#scheduleFlush();
    return full;
  }

  // ---- per-device saves & likes ---------------------------------------------

  savedIds(deviceId) {
    return this.db.saves[deviceId] ?? [];
  }

  isSaved(deviceId, journeyId) {
    return this.savedIds(deviceId).includes(journeyId);
  }

  saveCount(journeyId) {
    return Object.values(this.db.saves).filter((ids) => ids.includes(journeyId)).length;
  }

  toggleSave(deviceId, journeyId) {
    const ids = new Set(this.savedIds(deviceId));
    const saved = !ids.has(journeyId);
    if (saved) ids.add(journeyId);
    else ids.delete(journeyId);
    this.db.saves[deviceId] = saved ? [journeyId, ...[...ids].filter((i) => i !== journeyId)] : [...ids];
    this.#scheduleFlush();
    return saved;
  }

  isLiked(deviceId, journeyId) {
    return (this.db.likes[deviceId] ?? []).includes(journeyId);
  }

  toggleLike(deviceId, journeyId) {
    const journey = this.journey(journeyId);
    const ids = new Set(this.db.likes[deviceId] ?? []);
    const liked = !ids.has(journeyId);
    if (liked) ids.add(journeyId);
    else ids.delete(journeyId);
    this.db.likes[deviceId] = [...ids];
    journey.likes = Math.max(0, journey.likes + (liked ? 1 : -1));
    this.#scheduleFlush();
    return { liked, likes: journey.likes };
  }
}
