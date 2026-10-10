// Used when GEMINI_API_KEY is not configured (or Gemini fails before speaking).
// No language model: Ammachi picks trips with the same retrieval Gemini gets
// and fills in warm templates. The app labels these replies as offline.
import { priceOf, rank } from './catalog.js';

const TOPICS = ['desert', 'beach', 'mountains', 'city', 'culture', 'food', 'budget', 'monsoon'];

const OPENERS = {
  ml: {
    desert: 'മരുഭൂമിയിൽ ഒരു രാത്രിയാണോ മോഹം? കേട്ടോ കുഞ്ഞേ.',
    beach: 'കടൽ കാണണോ കുഞ്ഞേ? എങ്കിൽ ഇതാ.',
    mountains: 'മല കയറാനാണോ മോഹം? തണുപ്പുള്ള ഒരു വഴി പറയാം.',
    city: 'നഗരം ചുറ്റിക്കാണാനാണോ? അമ്മച്ചിക്ക് പറ്റിയ ഒന്നുണ്ട്.',
    culture: 'പഴയ കാര്യങ്ങൾ കാണാനാണോ ഇഷ്ടം? നല്ലത്, കുഞ്ഞേ.',
    food: 'വയറു നിറയ്ക്കാനുള്ള യാത്രയാണോ? എങ്കിൽ കേട്ടോ.',
    budget: 'കുറഞ്ഞ ചെലവിൽ പോകണോ? നല്ല കാര്യം, കുഞ്ഞേ.',
    monsoon: 'മഴ കാണാനാണോ കുഞ്ഞേ? അമ്മച്ചിക്ക് പറ്റിയ ഒന്നുണ്ട്.',
    default: 'ശരി കുഞ്ഞേ, അമ്മച്ചി ഒന്ന് നോക്കട്ടെ.',
  },
  en: {
    desert: 'A night in the desert, is it? Listen, kunje.',
    beach: 'You want the sea, kunje? Then here.',
    mountains: 'Up into the mountains, is it? Let me tell you a cool one.',
    city: 'Want to roam the city? Ammachi has a good one.',
    culture: 'Old forts and museums? Very good, kunje.',
    food: 'A trip for the stomach! Then listen carefully.',
    budget: 'Travelling light on money? Very sensible, kunje.',
    monsoon: 'You want the rain, kunje? Ammachi has just the thing.',
    default: 'Alright kunje, let Ammachi have a look.',
  },
};

const CLOSERS = {
  ml: 'സൂക്ഷിച്ച് പോയി വാ കുഞ്ഞേ.',
  en: 'Go carefully and come back with stories, kunje.',
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
