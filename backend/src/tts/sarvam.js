// Sarvam AI Bulbul text-to-speech (REST: POST https://api.sarvam.ai/text-to-speech).
// Audio is cached on disk by content hash and served from /static/tts/.
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';

export class SarvamTts {
  constructor({ apiKey, model, speaker, pace }, outDir) {
    this.apiKey = apiKey;
    this.model = model;
    this.speaker = speaker;
    this.pace = pace;
    this.outDir = outDir;
    this.inflight = new Map();
  }

  get enabled() {
    return Boolean(this.apiKey);
  }

  // Returns the public path of an MP3 for `text`, synthesising it if needed.
  async synthesize(text, lang = 'ml') {
    const languageCode = lang === 'en' ? 'en-IN' : 'ml-IN';
    const key = crypto.createHash('sha1').update(`${this.model}|${this.speaker}|${this.pace}|${languageCode}|${text}`).digest('hex').slice(0, 20);
    const file = path.join(this.outDir, `${key}.mp3`);
    const publicPath = `/static/tts/${key}.mp3`;

    try {
      await fs.access(file);
      return publicPath;
    } catch {
      // not cached yet
    }
    if (this.inflight.has(key)) return this.inflight.get(key);

    const job = (async () => {
      const res = await fetch('https://api.sarvam.ai/text-to-speech', {
        method: 'POST',
        headers: { 'api-subscription-key': this.apiKey, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          text: text.slice(0, 2400),
          language_code: languageCode,
          model: this.model,
          speaker: this.speaker,
          pace: this.pace,
          output_audio_codec: 'mp3',
          speech_sample_rate: 24000,
        }),
        signal: AbortSignal.timeout(20000),
      });
      if (!res.ok) {
        const body = await res.text().catch(() => '');
        throw new Error(`Sarvam TTS ${res.status}: ${body.slice(0, 200)}`);
      }
      const json = await res.json();
      const audio = Buffer.from((json.audios ?? []).join(''), 'base64');
      if (!audio.length) throw new Error('Sarvam TTS returned no audio');
      await fs.mkdir(this.outDir, { recursive: true });
      await fs.writeFile(file, audio);
      return publicPath;
    })();

    this.inflight.set(key, job);
    try {
      return await job;
    } finally {
      this.inflight.delete(key);
    }
  }
}
