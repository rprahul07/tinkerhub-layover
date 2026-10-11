# Travelgram voice agent (Plivo + Pipecat)

Outbound AI calls to qualified leads (document score ≥ 70 with call consent).

```
Plivo call → /voice/answer (Express) → <Stream> wss://PUBLIC_URL/voice/ws/:leadId
          → Express proxies to this agent (port 8765)
          → Sarvam STT → Gemini → Sarvam Bulbul TTS → back to the caller
On hang-up → transcript → backend → Gemini extracts destination/date/people/probability → CRM
```

## Run

```
cd voice-agent
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements.txt
.venv/Scripts/python bot.py
```

It reads keys from `backend/.env` (GEMINI_API_KEY, SARVAM_API_KEY, PLIVO_*).

## Real phone calls

In `backend/.env` set `PLIVO_AUTH_ID`, `PLIVO_AUTH_TOKEN`, `PLIVO_FROM_NUMBER` (a Plivo number that can dial the UAE/India) and `PUBLIC_URL` (the public https URL of your server or tunnel), then restart the backend. Without them calls are **simulated**: leads still show "Call simulated" in the CRM, and the dashboard says so.

Optional: `GEMINI_CALL_MODEL` (a faster model for calls), `SARVAM_AGENT_SPEAKER` (voice).

## Noise handling

Phone lines are noisy, so `capture.py` guards the conversation:
- RNNoise suppression on caller audio
- the caller is muted while the pre-rendered greeting plays
- stricter Silero VAD
- turns start from words, not sound (3 words to interrupt the agent, 1 word when it is quiet)
- a filter that drops noise-only transcripts

## Tests

```
.venv/Scripts/python -m pip install -r requirements-dev.txt
.venv/Scripts/python -m pytest -m "not live"   # unit tests, no network
.venv/Scripts/python -m pytest -m live         # 2 end-to-end calls with real Sarvam + Gemini (uses credits)
```
