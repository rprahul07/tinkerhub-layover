// Lead qualification. A lead is someone with real intent to travel: they built
// and confirmed a budget plan, or said "I'm going" on a trip. The score says
// how ready they are to be contacted; contact details are only kept with consent.

export function scoreLead(lead) {
  const reasons = [];
  let score = 0;
  const add = (points, why) => {
    score += points;
    reasons.push(why);
  };
  if (lead.source === 'planner') add(25, 'Confirmed a budget plan');
  else if (lead.source === 'going') add(10, 'Tapped "I\'m going"');
  else if (lead.source === 'ammachi') add(15, 'Asked the AI consultant to plan');
  if (lead.budgetAed > 0) add(15, 'Has a budget');
  if (lead.month) add(15, 'Knows when');
  if (lead.travelers > 0) add(10, 'Knows group size');
  if (lead.destination) add(10, 'Knows where');
  const contactable = Boolean(lead.phone) && lead.consent === true;
  if (contactable) add(25, 'Can be contacted');
  score = Math.min(100, score);
  return { score, qualified: contactable && score >= 70, reasons };
}

export const STAGES = ['High probability', 'Called', 'Calling', 'Qualified', 'Contactable', 'Interested'];

export function stageOf(lead) {
  if (lead.outcome?.probability === 'high') return 'High probability';
  if (['completed', 'simulated'].includes(lead.call?.status)) return 'Called';
  if (['ringing', 'in_progress'].includes(lead.call?.status)) return 'Calling';
  if (lead.qualified) return 'Qualified';
  if (lead.phone && lead.consent) return 'Contactable';
  return 'Interested';
}
