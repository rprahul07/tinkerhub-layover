// The budget trip planner: "I have AED 1,000 and 2 days" → a day-by-day plan
// built only from real trips on Travelgram, with their real costs scaled to
// the user's group. Gemini writes it when available; otherwise a deterministic
// planner does. Either way the server checks every number and reference.
import { formatMoney, fromAed, toAed } from './currency.js';
import { budgetTotal } from './present.js';

const INTERESTS = ['desert', 'beach', 'mountains', 'city', 'culture', 'food', 'adventure', 'budget', 'family', 'couples'];

/// What one trip would cost this group, in AED: its cost per person per day,
/// times the user's travellers and days.
export function estimateAed(journey, { travelers, days }) {
  const totalAed = toAed(budgetTotal(journey), journey.currency ?? 'AED');
  const perPersonDay = totalAed / Math.max(1, journey.travelers) / Math.max(1, journey.durationDays);
  return Math.round(perPersonDay * travelers * days);
}

export function normaliseRequest(body = {}) {
  const currency = typeof body.currency === 'string' && body.currency.length === 3 ? body.currency.toUpperCase() : 'AED';
  const budget = Math.round(Number(body.budget));
  const errors = {};
  if (!Number.isFinite(budget) || budget <= 0) errors.budget = 'Tell us your budget.';
  const days = Math.max(1, Math.min(14, Math.round(Number(body.days) || 2)));
  const travelers = Math.max(1, Math.min(20, Math.round(Number(body.travelers) || 1)));
  const interests = (Array.isArray(body.interests) ? body.interests : []).filter((i) => INTERESTS.includes(i)).slice(0, 5);
  return {
    errors,
    request: {
      budget,
      currency,
      budgetAed: toAed(budget, currency),
      days,
      travelers,
      interests,
      from: String(body.from ?? '').trim().slice(0, 40),
      month: Math.max(0, Math.min(12, Math.round(Number(body.month) || 0))) || null,
      lang: body.lang === 'en' ? 'en' : 'ml',
    },
  };
}

/// Trips that could fit, best first.
export function candidates(store, req) {
  return store
    .journeys()
    .map((j) => {
      const est = estimateAed(j, req);
      let score = 0;
      for (const i of req.interests) if (j.tags.includes(i)) score += 3;
      score += est <= req.budgetAed ? 4 : est <= req.budgetAed * 1.2 ? 1 : -6;
      if (req.month && (j.bestMonths ?? []).includes(req.month)) score += 2;
      if (j.durationDays <= req.days + 1) score += 1;
      score += Math.min(j.likes, 3000) / 3000;
      return { journey: j, estAed: est, score };
    })
    .sort((a, b) => b.score - a.score);
}

const PLAN_SCHEMA = {
  type: 'object',
  properties: {
    title: { type: 'string' },
    summary: { type: 'string' },
    days: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          day: { type: 'integer' },
          title: { type: 'string' },
          items: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                place: { type: 'string' },
                journeyId: { type: 'string' },
                what: { type: 'string' },
                category: { type: 'string', enum: ['stay', 'transport', 'food', 'activities', 'other'] },
                costAed: { type: 'integer' },
              },
              required: ['place', 'journeyId', 'what', 'category', 'costAed'],
            },
          },
        },
        required: ['day', 'title', 'items'],
      },
    },
    tips: { type: 'array', items: { type: 'string' } },
  },
  required: ['title', 'summary', 'days'],
};

function describeForPlanner(store, { journey: j, estAed }) {
  const creator = store.creator(j.creatorId);
  const cur = j.currency ?? 'AED';
  const ratio = (cur === 'AED' ? 1 : toAed(1000, cur) / 1000).toFixed(4);
  const places = j.stops
    .map((s) => {
      const spent = j.budget.filter((b) => b.stopId === s.id).map((b) => `${b.category}: ${b.label} = ${b.amount} ${cur}`).join('; ');
      return `   - Day ${s.day}: ${s.name}${spent ? ` (${spent})` : ''}`;
    })
    .join('\n');
  const extra = j.budget.filter((b) => !b.stopId).map((b) => `${b.category}: ${b.label} = ${b.amount} ${cur}`).join('; ');
  return `[${j.id}] "${j.title}" by ${creator?.name} — ${j.region}, ${j.country}; ${j.durationDays} days for ${j.travelers}; costs in ${cur} (1 ${cur} = ${ratio} AED); est. for this group AED ${estAed}\n${places}${extra ? `\n   - Other: ${extra}` : ''}`;
}

/// Checks a plan, keeps only real trip references, recomputes totals.
function finalise(store, req, draft, source) {
  const used = new Set();
  const days = (draft.days ?? []).slice(0, req.days + 1).map((d, i) => ({
    day: i + 1,
    title: String(d.title ?? `Day ${i + 1}`).slice(0, 80),
    items: (d.items ?? [])
      .filter((it) => store.journey(it.journeyId))
      .slice(0, 8)
      .map((it) => {
        used.add(it.journeyId);
        return {
          place: String(it.place).slice(0, 60),
          journeyId: it.journeyId,
          what: String(it.what ?? '').slice(0, 200),
          category: ['stay', 'transport', 'food', 'activities', 'other'].includes(it.category) ? it.category : 'other',
          costAed: Math.max(0, Math.round(Number(it.costAed) || 0)),
        };
      }),
  })).filter((d) => d.items.length);
  const totalAed = days.reduce((s, d) => s + d.items.reduce((t, it) => t + it.costAed, 0), 0);
  return {
    title: String(draft.title ?? 'Your trip').slice(0, 80),
    summary: String(draft.summary ?? '').slice(0, 600),
    tips: (draft.tips ?? []).map((t) => String(t).slice(0, 160)).slice(0, 4),
    days,
    request: req,
    totalAed,
    total: fromAed(totalAed, req.currency),
    currency: req.currency,
    fits: totalAed <= req.budgetAed,
    basedOn: [...used],
    source,
  };
}

/// A plan without a language model: the best-fitting trip, scaled to the group.
export function deterministicPlan(store, req) {
  const [best] = candidates(store, req);
  if (!best) return finalise(store, req, { title: 'No trips yet', summary: '', days: [] }, 'catalogue');
  const j = best.journey;
  const cur = j.currency ?? 'AED';
  const scale = req.travelers / Math.max(1, j.travelers);
  const dayScale = req.days / Math.max(1, j.durationDays);
  const days = [];
  for (let d = 1; d <= req.days; d++) {
    const srcDay = Math.min(j.durationDays, Math.ceil(d / Math.max(dayScale, 0.0001)) || d);
    const stops = j.stops.filter((s) => s.day === Math.min(srcDay, j.durationDays));
    days.push({
      day: d,
      title: stops.map((s) => s.name).slice(0, 2).join(' & ') || j.region,
      items: stops.map((s) => {
        const spentAed = j.budget.filter((b) => b.stopId === s.id).reduce((t, b) => t + toAed(b.amount, cur), 0);
        return { place: s.name, journeyId: j.id, what: s.story.split('. ')[0], category: 'activities', costAed: Math.round(spentAed * scale) };
      }),
    });
  }
  // Trip-level costs (stays, flights) spread over the plan.
  const extraAed = j.budget.filter((b) => !b.stopId).reduce((t, b) => t + toAed(b.amount, cur), 0) * scale * Math.min(1, dayScale);
  if (extraAed > 0 && days[0]) days[0].items.push({ place: j.region, journeyId: j.id, what: 'Stay and getting there', category: 'stay', costAed: Math.round(extraAed) });
  const creator = store.creator(j.creatorId)?.name ?? 'a traveller';
  const summary =
    req.lang === 'en'
      ? `Kunje, for ${formatMoney(req.budget, req.currency)} I'd follow ${creator}'s "${j.title}". It comes to about ${formatMoney(best.estAed, 'AED')} for ${req.travelers}.`
      : `കുഞ്ഞേ, ${formatMoney(req.budget, req.currency)} കൊണ്ട് ${creator} എഴുതിയ "${j.title}" പോലെ പോകാം. ${req.travelers} പേർക്ക് ഏകദേശം ${formatMoney(best.estAed, 'AED')} ആകും.`;
  return finalise(store, req, { title: j.title, summary, days, tips: (j.fields ?? []).map((f) => `${f.label}: ${f.value}`) }, 'catalogue');
}

export async function buildPlan(store, llm, req) {
  if (!llm?.json) return deterministicPlan(store, req);
  const top = candidates(store, req).slice(0, 6);
  const catalogue = top.map((c) => describeForPlanner(store, c)).join('\n');
  const system = `You are Ammachi, a Malayali grandmother in Dubai who plans trips for the Travelgram community. You build plans ONLY from the trips below: use their places and their real costs (convert to AED with the given rate, and scale per person and per day to this group). Never invent places or prices. Keep within the budget if at all possible; if impossible, get as close as you can and say so. Each item must carry the journeyId of the trip it comes from. Include stay and transport costs where the trips had them.
Write "title" in English. Write "summary" (2 short sentences, warm, spoken style, crediting the creators by name) and "tips" in ${req.lang === 'en' ? 'English' : 'Malayalam script (place names may stay in English)'}.

Trips:
${catalogue}`;
  const prompt = `Plan: ${req.days} day(s), ${req.travelers} traveller(s), budget ${req.budget} ${req.currency} (= AED ${req.budgetAed})${req.from ? `, starting from ${req.from}` : ''}${req.interests.length ? `, interests: ${req.interests.join(', ')}` : ''}${req.month ? `, travelling in month ${req.month}` : ''}.`;
  try {
    const draft = await llm.json({ system, prompt, schema: PLAN_SCHEMA });
    const plan = finalise(store, req, draft, 'gemini');
    return plan.days.length ? plan : deterministicPlan(store, req);
  } catch (err) {
    console.warn('[planner] gemini failed, using catalogue plan:', err.message);
    return deterministicPlan(store, req);
  }
}
