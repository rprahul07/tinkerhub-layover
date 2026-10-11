import os from 'node:os';
import { config } from './config.js';
import { createApp } from './app.js';

const { app, store, voiceLines, dashboardKey, agentProxy, voice } = createApp();
// The AI consultant's greeting and "let me see…" fillers, ready before the first call.
voiceLines.prewarm().then(() => voiceLines.ready && console.log('  AI consultant voice lines ready'));

const server = app.listen(config.port, '0.0.0.0', () => {
  const lan = Object.values(os.networkInterfaces())
    .flat()
    .find((i) => i && i.family === 'IPv4' && !i.internal)?.address;
  console.log(`Travelgram API on http://localhost:${config.port}${lan ? `  (phone on same Wi-Fi: http://${lan}:${config.port})` : ''}`);
  console.log(`  AI consultant brain: ${config.gemini.apiKey ? `Gemini (${config.gemini.model})` : 'offline mode — set GEMINI_API_KEY in backend/.env'}`);
  console.log(`  Leads dashboard: http://localhost:${config.port}/dashboard?key=${dashboardKey}`);
  console.log(`  AI calls: ${voice.configured ? 'Plivo → Pipecat agent' : 'simulated — set PLIVO_* in backend/.env and run voice-agent/'}`);
  console.log(`  AI consultant voice: ${config.sarvam.apiKey ? `Sarvam ${config.sarvam.model} (${config.sarvam.speaker})` : 'off — set SARVAM_API_KEY in backend/.env'}`);
});

server.on('upgrade', agentProxy.upgrade);

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    store.flushNow();
    server.close(() => process.exit(0));
  });
}
