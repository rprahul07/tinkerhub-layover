// Used when GEMINI_API_KEY is not configured (or Gemini fails before speaking).
// No language model: the consultant picks trips with the same retrieval Gemini gets
// and fills in short templates. The app labels these replies as offline.
import { priceOf, rank } from './catalog.js';

const TOPICS = ['desert', 'beach', 'mountains', 'city', 'culture', 'food', 'budget', 'monsoon'];

const OPENERS = {
  ml: {
    desert: 'മരുഭൂമി യാത്രയ്ക്ക് നല്ല ഒരു ഓപ്ഷൻ ഇതാ.',
    beach: 'ബീച്ച് യാത്രയ്ക്ക് ഇത് പരിഗണിക്കാം.',
    mountains: 'മലയോര യാത്രയ്ക്ക് നല്ല ഒരു ഓപ്ഷൻ ഇതാ.',
    city: 'സിറ്റി യാത്രയ്ക്ക് ഇത് നോക്കാം.',
    culture: 'ചരിത്രവും സംസ്കാരവും കാണാൻ ഇത് നല്ലതാണ്.',
    food: 'ഭക്ഷണത്തിന് പ്രാധാന്യമുള്ള ഒരു യാത്ര ഇതാ.',
    budget: 'കുറഞ്ഞ ബജറ്റിൽ ഇത് പരിഗണിക്കാം.',
    monsoon: 'മഴക്കാല യാത്രയ്ക്ക് ഒരു ഓപ്ഷൻ ഇതാ.',
    default: 'നിങ്ങൾക്ക് അനുയോജ്യമായ ഒരു യാത്ര ഇതാ.',
  },
  en: {
    desert: 'For a desert trip, here is a good option.',
    beach: 'For the beach, I would suggest this.',
    mountains: 'For the mountains, here is a good option.',
    city: 'For a city break, consider this.',
    culture: 'For history and culture, this is a strong choice.',
    food: 'For a food-focused trip, here is one.',
    budget: 'On a tight budget, consider this.',
    monsoon: 'For the rainy season, here is an option.',
    default: 'Here is a trip that should suit you.',
  },
};

const CLOSERS = {
  ml: 'കൂടുതൽ വിവരങ്ങൾ വേണമെങ്കിൽ ചോദിക്കൂ.',
  en: 'Let me know if you would like more details.',
};

export function offlineReply(store, { text, lang, contextJourneyId }) {
  const L = lang === 'en' ? 'en' : 'ml';
  const ranked = rank(store, text, { contextJourneyId });
  const [first, second] = ranked;
  const topic = TOPICS.find((t) => first?.intent.tags.includes(t)) ?? 'default';

  const line = (r, lead) => {
    const j = r.journey;
    const creator = store.creator(j.creatorId)?.name ?? 'a traveller';
    const days = j.durationDays;
    return L === 'en'
      ? `${lead ? 'Look at' : 'Or'} “${j.title}” [[journey:${j.id}]] by ${creator}: ${days} day${days > 1 ? 's' : ''}, about ${priceOf(j)} all in.`
      : `${creator} എഴുതിയ “${j.title}” [[journey:${j.id}]] ${lead ? 'നോക്കൂ' : 'ഉം നല്ലതാണ്'}. ${days} ദിവസം, ആകെ ഏകദേശം ${priceOf(j)}.`;
  };

  const parts = [OPENERS[L][topic]];
  if (first) parts.push(line(first, true));
  if (second && second.score > 1) parts.push(line(second, false));
  parts.push(CLOSERS[L]);
  return parts.join(' ');
}

// Streams a finished string in word-sized pieces so the client renders it
// through the same path as a live model.
export async function* streamWords(text, delayMs = 18) {
  for (const piece of text.match(/\S+\s*/g) ?? []) {
    yield piece;
    if (delayMs) await new Promise((r) => setTimeout(r, delayMs));
  }
}
