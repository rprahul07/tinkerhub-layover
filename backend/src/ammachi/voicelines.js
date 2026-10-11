// Short lines the AI consultant can say instantly: a greeting when a call connects, and
// a "let me see…" filler while Gemini thinks. They are synthesised once at
// startup (and cached on disk by the TTS client), so they play in ~1 second.

const LINES = {
  greeting: {
    ml: 'നമസ്കാരം, ഞാൻ Travelgram-ന്റെ AI travel consultant ആണ്. എങ്ങോട്ടാണ് യാത്ര പ്ലാൻ ചെയ്യുന്നത്?',
    en: "Hello, this is Travelgram's AI travel consultant. Where are you planning to travel?",
  },
  fillers: {
    ml: ['ശരി, ഒരു നിമിഷം നോക്കട്ടെ.', 'മനസ്സിലായി, ഒന്ന് പരിശോധിക്കട്ടെ.', 'ഒരു നിമിഷം, ഞാൻ നോക്കാം.'],
    en: ['Sure, one moment please.', 'Understood, let me check.', 'Just a moment while I look that up.'],
  },
};

export class VoiceLines {
  constructor(tts) {
    this.tts = tts;
    this.urls = { greeting: {}, fillers: { ml: [], en: [] } };
    this.ready = false;
  }

  async prewarm() {
    if (!this.tts.enabled) return;
    try {
      for (const lang of ['ml', 'en']) {
        this.urls.greeting[lang] = await this.tts.synthesize(LINES.greeting[lang], lang);
        for (const line of LINES.fillers[lang]) {
          this.urls.fillers[lang].push({ url: await this.tts.synthesize(line, lang), text: line });
        }
      }
      this.ready = true;
    } catch (err) {
      console.warn('[ammachi] could not prepare voice lines:', err.message);
    }
  }

  greeting(lang) {
    return this.urls.greeting[lang === 'en' ? 'en' : 'ml'] ?? null;
  }

  filler(lang) {
    const list = this.urls.fillers[lang === 'en' ? 'en' : 'ml'];
    return list.length ? list[Math.floor(Math.random() * list.length)] : null;
  }
}
