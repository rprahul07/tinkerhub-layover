// POST /api/ammachi/chat streams Server-Sent Events:
//   meta   {mode: 'gemini'|'offline', model, voice}
//   audio  {index:-1, url, text, filler:true}  an instant "let me see…" (voice only)
//   delta  {text}                         spoken text, markers removed
//   cite   {journey}                      a trip Ammachi recommended
//   audio  {index, url, text}             Bulbul MP3 for one sentence, in order
//   done   {text, citations}
//   error  {message}
import { Router } from 'express';
import { absolutize, card, viewerOf } from '../present.js';
import { catalogFor } from '../ammachi/catalog.js';
import { CitationSplitter, SentenceChunker, speakable } from '../ammachi/citations.js';
import { offlineReply, streamWords } from '../ammachi/offline.js';
import { systemInstruction } from '../ammachi/persona.js';
import { HttpError } from './journeys.js';

function cleanHistory(messages) {
  const turns = (Array.isArray(messages) ? messages : [])
    .filter((m) => m && typeof m.text === 'string' && m.text.trim())
    .slice(-12)
    .map((m) => ({ role: m.role === 'user' ? 'user' : 'model', text: m.text.trim().slice(0, 2000) }));
  // Merge consecutive turns from the same side and start with the user.
  const merged = [];
  for (const t of turns) {
    const prev = merged.at(-1);
    if (prev && prev.role === t.role) prev.text += `\n${t.text}`;
    else merged.push({ ...t });
  }
  while (merged.length && merged[0].role !== 'user') merged.shift();
  return merged;
}

export function ammachiRouter(store, { llm, tts, voiceLines, callModel }) {
  const r = Router();

  r.get('/ammachi/status', (req, res) => {
    const greeting = voiceLines?.ready
      ? { ml: absolutize(req, voiceLines.greeting('ml')), en: absolutize(req, voiceLines.greeting('en')) }
      : null;
    res.json({
      llm: llm ? { provider: llm.name, model: llm.model } : { provider: 'offline', model: null },
      tts: tts.enabled ? { provider: 'sarvam', model: tts.model, speaker: tts.speaker } : { provider: 'none' },
      greeting,
    });
  });

  // Speak an arbitrary line again (the replay button on a message).
  r.post('/tts', async (req, res) => {
    const text = speakable(String(req.body?.text ?? '')).slice(0, 2400);
    if (!text) throw new HttpError(400, 'Nothing to say.');
    if (!tts.enabled) throw new HttpError(503, 'Voice is not configured on the server (SARVAM_API_KEY).');
    const url = await tts.synthesize(text, req.body?.lang === 'en' ? 'en' : 'ml');
    res.json({ url: absolutize(req, url) });
  });

  r.post('/ammachi/chat', async (req, res) => {
    const history = cleanHistory(req.body?.messages);
    if (!history.length || history.at(-1).role !== 'user') throw new HttpError(400, 'Send at least one user message.');
    const lang = req.body?.lang === 'en' ? 'en' : 'ml';
    const mode = req.body?.mode === 'call' ? 'call' : 'chat';
    const wantVoice = req.body?.voice !== false && tts.enabled;
    const contextJourney = req.body?.journeyId ? store.journey(String(req.body.journeyId)) : null;
    const question = history.at(-1).text;
    const viewer = viewerOf(req, store);

    res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    });
    const send = (event, data) => {
      if (!res.writableEnded) res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
    };

    const abort = new AbortController();
    res.on('close', () => abort.abort());

    const splitter = new CitationSplitter();
    const chunker = new SentenceChunker();
    const cited = [];
    let spoken = '';
    let audioIndex = 0;
    let audioChain = Promise.resolve();
    let firstSentence = null; // the first sentence is voiced alone, so it's ready soonest

    const speak = (sentence) => {
      const clean = speakable(sentence);
      if (!wantVoice || !clean) return;
      const index = audioIndex++;
      const synth = () => tts.synthesize(clean, lang);
      const run = index === 0 ? synth() : firstSentence.then(synth, synth);
      if (index === 0) firstSentence = run.catch(() => {});
      const job = run.then(
        (url) => ({ url }),
        (err) => ({ error: err.message }),
      );
      // Events go out strictly in sentence order.
      audioChain = audioChain.then(async () => {
        const result = await job;
        if (result.url) send('audio', { index, url: absolutize(req, result.url), text: clean });
        else {
          console.warn('[ammachi] tts failed:', result.error);
          send('audio', { index, url: null, text: clean, error: 'voice_unavailable' });
        }
      });
    };

    const emit = (parts) => {
      for (const part of parts) {
        if (part.type === 'cite') {
          const journey = store.journey(part.id);
          if (journey && !cited.includes(journey.id)) {
            cited.push(journey.id);
            send('cite', { journey: card(req, store, journey, viewer) });
          }
        } else if (part.text) {
          spoken += part.text;
          send('delta', { text: part.text });
          chunker.push(part.text).forEach(speak);
        }
      }
    };

    const offlineStream = () => streamWords(offlineReply(store, { text: question, lang, contextJourneyId: contextJourney?.id }));

    let llmMode = llm ? 'gemini' : 'offline';
    send('meta', { mode: llmMode, model: llm ? (mode === 'call' && callModel) || llm.model : null, voice: wantVoice });

    // Say something right away while the model thinks.
    const filler = wantVoice && llm ? voiceLines?.filler(lang) : null;
    if (filler) send('audio', { index: -1, url: absolutize(req, filler.url), text: filler.text, filler: true });

    try {
      let source;
      if (llm) {
        const system = systemInstruction({
          lang,
          mode,
          catalog: catalogFor(store, history.filter((h) => h.role === 'user').map((h) => h.text).join(' '), { contextJourneyId: contextJourney?.id }),
          contextJourney,
        });
        source = llm.stream({ system, history, signal: abort.signal, modelOverride: mode === 'call' ? callModel : undefined });
      } else {
        source = offlineStream();
      }

      try {
        for await (const chunk of source) {
          if (abort.signal.aborted) break;
          emit(splitter.push(chunk));
        }
      } catch (err) {
        if (abort.signal.aborted) throw err;
        console.error('[ammachi] model error:', err?.message ?? err);
        if (spoken) throw err; // already mid-answer: report rather than restart
        // Nothing said yet: answer from the catalogue so the user isn't left hanging.
        llmMode = 'offline';
        send('meta', { mode: llmMode, model: null, voice: wantVoice, reason: 'model_unavailable' });
        for await (const chunk of offlineStream()) emit(splitter.push(chunk));
      }

      emit(splitter.flush());
      chunker.flush().forEach(speak);
      await audioChain;
      send('done', { text: spoken.trim(), citations: cited, mode: llmMode });
    } catch (err) {
      if (!abort.signal.aborted) {
        console.error('[ammachi] chat failed:', err);
        send('error', { message: 'The AI consultant could not finish that answer. Please ask again.' });
      }
    } finally {
      res.end();
    }
  });

  return r;
}
