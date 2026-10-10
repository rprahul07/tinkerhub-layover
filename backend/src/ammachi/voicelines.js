// Short lines Ammachi can say instantly: a greeting when a call connects, and
// a "let me see…" filler while Gemini thinks. They are synthesised once at
// startup (and cached on disk by the TTS client), so they play in ~1 second.

const LINES = {
  greeting: {
    ml: 'ഹലോ കുഞ്ഞേ, അമ്മച്ചിയാണ്. എങ്ങോട്ടാ ഈ പ്രാവശ്യം യാത്ര?',
    en: "Hello kunje, it's Ammachi. So, where are we travelling this time?",
  },
  fillers: {
    ml: ['ഹ്മ്, അമ്മച്ചി ഒന്ന് നോക്കട്ടെ.', 'ശരി കുഞ്ഞേ, ഒരു നിമിഷം.', 'ആഹാ, കൊള്ളാമല്ലോ. നോക്കട്ടെ.'],
    en: ['Hmm, let Ammachi have a look.', 'Alright kunje, one moment.', 'Oh, lovely. Let me see.'],
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
