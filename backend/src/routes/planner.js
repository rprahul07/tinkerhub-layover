import { Router } from 'express';
import { formatMoney, toAed } from '../currency.js';
import { scoreLead } from '../leads.js';
import { buildPlan, normaliseRequest } from '../planner.js';
import { card, viewerOf } from '../present.js';
import { HttpError } from './journeys.js';

export function plannerRouter(store, { llm }) {
  const r = Router();

  const view = (req, plan) => {
    const viewer = viewerOf(req, store);
    return {
      ...plan,
      totalLabel: formatMoney(plan.total, plan.currency),
      budgetLabel: formatMoney(plan.request.budget, plan.request.currency),
      trips: plan.basedOn.map((id) => store.journey(id)).filter(Boolean).map((j) => card(req, store, j, viewer)),
    };
  };

  // "I have AED 1,000 and 2 days" → a plan from real trips.
  r.post('/planner', async (req, res) => {
    const { errors, request } = normaliseRequest(req.body);
    if (Object.keys(errors).length) throw new HttpError(400, 'Tell Ammachi a little more.', errors);
    const viewer = viewerOf(req, store);
    const plan = await buildPlan(store, llm, request);
    const saved = store.addPlan({ ...plan, userId: viewer.userId });
    res.status(201).json({ plan: view(req, saved) });
  });

  r.get('/plans/:id', (req, res) => {
    const plan = store.plan(req.params.id);
    if (!plan) throw new HttpError(404, 'Plan not found');
    res.json({ plan: view(req, plan) });
  });

  r.get('/me/plans', (req, res) => {
    const viewer = viewerOf(req, store);
    if (!viewer.userId) throw new HttpError(401, 'Create your profile first.');
    res.json({ plans: store.plansOf(viewer.userId).map((p) => view(req, p)) });
  });

  // "Confirm this plan / get it booked" → a lead for the dashboard.
  r.post('/leads', (req, res) => {
    const viewer = viewerOf(req, store);
    const b = req.body ?? {};
    const plan = b.planId ? store.plan(String(b.planId)) : null;
    const journey = b.journeyId ? store.journey(String(b.journeyId)) : null;
    if (!plan && !journey) throw new HttpError(400, 'Which plan or trip is this about?');
    const phone = String(b.phone ?? '').replace(/[^\d+]/g, '').slice(0, 16);
    if (b.consent === true && phone.length < 8) throw new HttpError(400, 'Check the phone number.', { phone: 'Enter a WhatsApp number with country code.' });
    const creator = viewer.userId ? store.creator(viewer.userId) : null;
    const currency = plan?.currency ?? (typeof b.currency === 'string' ? b.currency : 'AED');
    const budget = Number(b.budget) || plan?.request.budget || 0;
    const lead = {
      source: plan ? 'planner' : 'going',
      userId: viewer.userId,
      name: String(b.name ?? creator?.name ?? '').trim().slice(0, 60),
      handle: creator?.handle ?? null,
      phone: b.consent === true ? phone : null,
      consent: b.consent === true,
      planId: plan?.id ?? null,
      journeyId: journey?.id ?? plan?.basedOn?.[0] ?? null,
      destination: journey?.region ?? (plan ? store.journey(plan.basedOn[0])?.region : null) ?? null,
      title: plan?.title ?? journey?.title ?? '',
      budget,
      currency,
      budgetAed: toAed(budget, currency),
      travelers: Number(b.travelers) || plan?.request.travelers || null,
      days: plan?.request.days ?? journey?.durationDays ?? null,
      month: Math.round(Number(b.month)) || plan?.request.month || null,
      from: String(b.from ?? plan?.request.from ?? '').slice(0, 40),
      notes: String(b.notes ?? '').slice(0, 300),
    };
    const saved = store.upsertLead({ ...lead, ...scoreLead(lead) });
    res.status(201).json({ lead: { id: saved.id, score: saved.score, qualified: saved.qualified } });
  });

  return r;
}
