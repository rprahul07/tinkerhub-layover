import express from 'express';
import cors from 'cors';
import fs from 'node:fs';
import path from 'node:path';
import { config } from './config.js';
import { Store } from './store.js';
import { createGemini } from './ammachi/gemini.js';
import { SarvamTts } from './tts/sarvam.js';
import { VoiceLines } from './ammachi/voicelines.js';
import { journeysRouter, HttpError } from './routes/journeys.js';
import { creatorsRouter } from './routes/creators.js';
import { uploadsRouter } from './routes/uploads.js';
import { placesRouter } from './routes/places.js';
import { ammachiRouter } from './routes/ammachi.js';
import { plannerRouter } from './routes/planner.js';
import { dashboardKey, dashboardRouter } from './routes/dashboard.js';
import { documentsRouter } from './routes/documents.js';
import { bookingsRouter } from './routes/bookings.js';
import { voiceRouter } from './routes/voice.js';
import { createVoice } from './voice/plivo.js';
import { createProxyMiddleware } from 'http-proxy-middleware';

export function createApp(options = {}) {
  const store = options.store ?? new Store(config.dataDir);
  const llm = options.llm !== undefined ? options.llm : config.gemini.apiKey ? createGemini(config.gemini) : null;
  const tts = options.tts ?? new SarvamTts(config.sarvam, path.join(config.publicDir, 'tts'));
  const voiceLines = options.voiceLines ?? new VoiceLines(tts);

  const uploadsDir = options.uploadsDir ?? path.join(config.publicDir, 'uploads');
  // Identity documents are private: kept under data/ (never public/), served only via the key-protected dashboard.
  const docsDir = options.docsDir ?? path.join(config.dataDir, 'docs');

  const app = express();
  app.set('trust proxy', true);
  app.use(cors());
  app.use(express.json({ limit: '1mb' }));
  app.use('/static/uploads', express.static(uploadsDir, { maxAge: '7d', immutable: true }));
  app.use('/static', express.static(config.publicDir, { maxAge: '7d', immutable: true }));

  app.get('/api/health', (_req, res) => res.json({ ok: true, llm: llm ? llm.name : 'offline', tts: tts.enabled ? 'sarvam' : 'none' }));

  // For testing on a phone: open http://<laptop-ip>:4000/app to download the Android build.
  app.get('/app', (_req, res) => {
    const apk = path.join(config.publicDir, 'downloads', 'travelgram.apk');
    if (!fs.existsSync(apk)) {
      return res.status(404).type('text').send('No APK yet: run `flutter build apk --release` in app/ and copy it to backend/public/downloads/travelgram.apk');
    }
    res.download(apk, 'travelgram.apk');
  });
  app.use('/api', journeysRouter(store));
  app.use('/api', creatorsRouter(store));
  app.use('/api', uploadsRouter(uploadsDir));
  app.use('/api', placesRouter(store));
  app.use('/api', ammachiRouter(store, { llm, tts, voiceLines, callModel: options.callModel ?? config.gemini.callModel }));

  app.use('/api', plannerRouter(store, { llm }));
  const key = options.dashboardKey ?? dashboardKey(config.dataDir);
  const voice = options.voice ?? createVoice({ ...config.voice, agentKey: key }, store);
  app.use('/api', documentsRouter(store, { llm, voice, autoCallScore: config.voice.autoCallScore, allowSpecimens: options.allowSpecimens ?? config.voice.allowSpecimens, docsDir }));
  app.use('/api', bookingsRouter(store));
  app.use(voiceRouter(store, { llm, agentKey: key, publicUrl: config.voice.publicUrl }));
  // Plivo's audio stream → the Pipecat agent (same public tunnel).
  const agentProxy = createProxyMiddleware({ target: config.voice.agentUrl, ws: true, changeOrigin: true, pathFilter: '/voice/ws' });
  app.use(agentProxy);
  app.use('/dashboard', dashboardRouter(store, key, voice, docsDir));

  app.use('/api', (_req, _res, next) => next(new HttpError(404, 'No such endpoint')));

  // eslint-disable-next-line no-unused-vars
  app.use((err, _req, res, _next) => {
    const status = err.status ?? (err.code === 'LIMIT_FILE_SIZE' ? 413 : err.type === 'entity.parse.failed' ? 400 : 500);
    if (status >= 500) console.error(err);
    res.status(status).json({
      error: status >= 500 ? 'Something went wrong on our side.' : err.message,
      ...(err.details ? { details: err.details } : {}),
    });
  });

  return { app, store, voiceLines, dashboardKey: key, agentProxy, voice };
}
