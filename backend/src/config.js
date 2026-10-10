import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

try {
  process.loadEnvFile(path.join(root, '.env'));
} catch {
  // No .env file: rely on the real environment.
}

const env = (key, fallback = '') => (process.env[key] ?? '').trim() || fallback;

export const config = {
  root,
  port: Number(env('PORT', '4000')),
  dataDir: env('DATA_DIR', path.join(root, 'data')),
  publicDir: path.join(root, 'public'),
  gemini: {
    apiKey: env('GEMINI_API_KEY'),
    // `gemini-flash-latest` is Google's alias for the current stable Flash model.
    model: env('GEMINI_MODEL', 'gemini-flash-latest'),
    // Optional faster model for voice calls (falls back to GEMINI_MODEL).
    callModel: env('GEMINI_CALL_MODEL'),
    thinkingLevel: env('GEMINI_THINKING_LEVEL', 'LOW'),
  },
  sarvam: {
    apiKey: env('SARVAM_API_KEY'),
    model: env('SARVAM_TTS_MODEL', 'bulbul:v3'),
    speaker: env('SARVAM_SPEAKER', 'kavitha'),
    pace: Number(env('SARVAM_PACE', '0.95')),
  },
  // Outbound AI calls: Plivo dials, the Pipecat agent (voice-agent/) talks.
  voice: {
    plivoAuthId: env('PLIVO_AUTH_ID'),
    plivoAuthToken: env('PLIVO_AUTH_TOKEN'),
    plivoFrom: env('PLIVO_FROM_NUMBER'),
    publicUrl: env('PUBLIC_URL').replace(/\/+$/, ''), // e.g. your ngrok https URL
    agentUrl: env('VOICE_AGENT_URL', 'http://127.0.0.1:8765'),
    autoCallScore: Number(env('AUTO_CALL_SCORE', '70')),
    allowSpecimens: env('DOC_CHECK_ALLOW_SPECIMENS') === 'true',
  },
};
