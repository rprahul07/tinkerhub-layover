"""Travelgram visa & travel desk: an outbound AI voice agent.

Plivo dials a qualified lead (document score >= 70). When they answer, Plivo
streams the call audio to /voice/ws/{lead_id} (proxied by the Express backend),
and this Pipecat pipeline talks to them:

    Plivo audio -> Sarvam STT (Malayalam/English) -> Gemini -> Sarvam Bulbul TTS -> Plivo

It asks where they want to go, when, how many people and what they enjoy,
promises the best price, and posts the transcript back to the backend, which
scores conversion probability for the CRM.

Run:  .venv/Scripts/python bot.py   (port 8765)
"""

import asyncio
import base64
import json
import os
from pathlib import Path

import aiohttp
import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, Header, HTTPException, WebSocket
from loguru import logger

from pipecat.audio.filters.rnnoise_filter import RNNoiseFilter
from pipecat.frames.frames import InputAudioRawFrame, OutputAudioRawFrame, TTSSpeakFrame
from pipecat.pipeline.pipeline import Pipeline
from pipecat.pipeline.runner import PipelineRunner
from pipecat.pipeline.task import PipelineParams, PipelineTask
from pipecat.processors.aggregators.llm_context import LLMContext
from pipecat.processors.aggregators.llm_response_universal import LLMContextAggregatorPair, LLMUserAggregatorParams
from pipecat.runner.utils import parse_telephony_websocket
from pipecat.serializers.plivo import PlivoFrameSerializer
from pipecat.services.google.llm import GoogleLLMService
from pipecat.services.sarvam.stt import SarvamSTTService
from pipecat.services.sarvam.tts import SarvamTTSService
from pipecat.transcriptions.language import Language
from pipecat.transports.websocket.fastapi import FastAPIWebsocketParams, FastAPIWebsocketTransport

from capture import AudioMeter, GreetingGate, JunkTranscriptFilter, make_vad, trim_mulaw_silence, turn_strategies

BACKEND_DIR = Path(__file__).resolve().parent.parent / "backend"
load_dotenv(BACKEND_DIR / ".env")  # one .env for the whole project

BACKEND_URL = os.getenv("BACKEND_URL", f"http://127.0.0.1:{os.getenv('PORT', '4000')}")
MONTHS = ["", "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]

AGENT_RULES = """You are Ammachi, a warm, experienced travel advisor calling from the Travelgram Visa & Travel Desk in Dubai.
You are on an outbound PHONE CALL with a customer whose visa documents just passed our document checker, so they are ready to apply.
The first message gives the call details and the language to speak.

Goal of the call, ONE question at a time, in this order:
1. (Already done when the call starts: you greeted them, said their documents look ready and asked if it's a good time.)
2. Ask where they would like to go (confirm the destination if we already know it).
3. Ask their travel dates.
4. Ask how many people are travelling.
5. Ask what they enjoy (beach, desert, mountains, city, food, culture, shopping).
6. Close: thank them, say we will get them the BEST PRICE for visa, flights and hotels, and our team will send the quote on WhatsApp shortly. Then say goodbye.

Rules:
- Maximum two short sentences per turn. This is a phone call: no lists, no markdown, no emojis.
- In Malayalam, speak simple, friendly Gulf-Malayali Malayalam; English words like visa, hotel, flight are fine. Address them as kunje or by name.
- If they are busy or not interested, politely say we will WhatsApp them and say goodbye.
- Never ask for passport numbers, card details or other personal data.
- Never promise specific prices or guaranteed visa approval."""


def agent_key() -> str:
    key = os.getenv("DASHBOARD_KEY", "").strip()
    if key:
        return key
    return (BACKEND_DIR / "data" / "dashboard-key.txt").read_text().strip()


def greeting(lead: dict) -> str:
    """Scripted first line, so the caller hears a voice as soon as they answer."""
    name = (lead.get("name") or "").split(" ")[0]
    if lead.get("lang") == "en":
        return f"Hi {name}, Ammachi here from Travelgram Visa Desk. Your documents are ready! Got a minute?"
    return f"ഹലോ {name}, Travelgram Visa Desk-ൽ നിന്ന് അമ്മച്ചിയാ. Documents എല്ലാം ready ആണ്! ഒരു മിനിറ്റ് സംസാരിക്കാമോ?"


def call_details(lead: dict) -> str:
    known = []
    if lead.get("destination"):
        known.append(f"destination {lead['destination']}")
    if lead.get("month"):
        known.append(f"around {MONTHS[int(lead['month'])]}")
    if lead.get("travelers"):
        known.append(f"{lead['travelers']} people")
    return (
        f"(Call details. Customer: {lead.get('name') or 'unknown'}. Document score: {lead.get('docScore', '?')}/100. "
        f"Already known: {', '.join(known) or 'nothing yet'}. Speak {'English' if lead.get('lang') == 'en' else 'Malayalam'}. "
        "The customer just picked up and you have already greeted them. Continue from step 2 when they reply.)"
    )


def speaker() -> str:
    return os.getenv("SARVAM_AGENT_SPEAKER") or os.getenv("SARVAM_SPEAKER", "kavya")


async def synth_phone_audio(text: str, ml: bool) -> bytes:
    """The greeting as 8 kHz mu-law, ready to stream to Plivo the instant they answer."""
    async with aiohttp.ClientSession() as http:
        async with http.post(
            "https://api.sarvam.ai/text-to-speech",
            headers={"api-subscription-key": os.environ["SARVAM_API_KEY"]},
            json={
                "text": text,
                "target_language_code": "ml-IN" if ml else "en-IN",
                "model": os.getenv("SARVAM_TTS_MODEL", "bulbul:v3"),
                "speaker": speaker(),
                "pace": float(os.getenv("SARVAM_PACE", "1.0")),
                "speech_sample_rate": 8000,
                "output_audio_codec": "mulaw",
            },
            timeout=aiohttp.ClientTimeout(total=15),
        ) as r:
            body = await r.json()
    audio = base64.b64decode(body["audios"][0])
    if audio[:4] == b"RIFF" and b"data" in audio[:200]:
        audio = audio[audio.index(b"data") + 8 :]
    return trim_mulaw_silence(audio)  # she speaks the moment they answer


# lead id -> (lead, greeting text, greeting audio), prepared while the phone rings
_ringing: dict[str, tuple[dict, str, bytes]] = {}
_preparing: dict[str, asyncio.Task] = {}


def post_live(lead_id: str, role: str, text: str):
    """Streams each turn to the dashboard's live call view (fire and forget)."""

    async def send():
        try:
            async with aiohttp.ClientSession() as http:
                await http.post(f"{BACKEND_URL}/api/voice/live/{lead_id}", json={"role": role, "text": text}, headers={"x-agent-key": agent_key()})
        except Exception as e:
            logger.warning(f"Live update failed: {e}")

    if text and text.strip():
        asyncio.create_task(send())


def make_stt(ml: bool) -> SarvamSTTService:
    return SarvamSTTService(
        api_key=os.environ["SARVAM_API_KEY"],
        settings=SarvamSTTService.Settings(model="saaras:v3", language=Language.ML_IN if ml else Language.EN_IN),
    )


def build_kit() -> dict:
    """Everything slow to construct (Gemini client, VAD and turn models), built ahead of the call."""
    context = LLMContext([])
    return {
        "llm": GoogleLLMService(
            api_key=os.environ["GEMINI_API_KEY"],
            settings=GoogleLLMService.Settings(
                model=os.getenv("GEMINI_CALL_MODEL") or os.getenv("GEMINI_MODEL") or "gemini-flash-latest",
                system_instruction=AGENT_RULES,
                thinking=GoogleLLMService.ThinkingConfig(thinking_level=(os.getenv("GEMINI_THINKING_LEVEL") or "low").lower()),
            ),
        ),
        "stt_ml": make_stt(True),
        "context": context,
        "aggregators": LLMContextAggregatorPair(
            context, user_params=LLMUserAggregatorParams(vad_analyzer=make_vad(), user_turn_strategies=turn_strategies())
        ),
    }


_spare: dict | None = None


def take_kit() -> dict:
    global _spare
    kit, _spare = _spare or build_kit(), None
    return kit


async def fetch_lead(lead_id: str) -> dict:
    try:
        async with aiohttp.ClientSession() as http:
            async with http.get(f"{BACKEND_URL}/api/voice/lead/{lead_id}", headers={"x-agent-key": agent_key()}) as r:
                if r.status == 200:
                    return await r.json()
    except Exception as e:  # the call should still go ahead
        logger.warning(f"Could not load lead {lead_id}: {e}")
    return {"id": lead_id, "lang": "ml"}


def transcript_of(context: LLMContext) -> list[dict]:
    out = []
    for m in context.get_messages():
        role = m.get("role") if isinstance(m, dict) else None
        if role not in ("user", "assistant"):
            continue
        content = m.get("content")
        if isinstance(content, list):
            content = " ".join(p.get("text", "") for p in content if isinstance(p, dict))
        if content:
            out.append({"role": role, "text": str(content)})
    return out


app = FastAPI()


@app.on_event("startup")
async def warm_up():
    global _spare
    _spare = build_kit()
    logger.info("Voice agent ready")


@app.post("/prepare/{lead_id}")
async def prepare(lead_id: str, x_agent_key: str = Header(default="")):
    """Called by the backend as it dials, so the greeting is ready before pickup."""
    if x_agent_key != agent_key():
        raise HTTPException(401)
    async def render():
        lead = await fetch_lead(lead_id)
        text = greeting(lead)
        audio = await synth_phone_audio(text, lead.get("lang") != "en")
        _ringing[lead_id] = (lead, text, audio)
        logger.info(f"Greeting ready for lead {lead_id}: {len(audio) / 8000:.1f}s")
        return audio

    _preparing[lead_id] = asyncio.create_task(render())
    try:
        audio = await _preparing[lead_id]
    finally:
        _preparing.pop(lead_id, None)
    return {"ok": True, "seconds": round(len(audio) / 8000, 1)}


@app.get("/health")
async def health():
    return {"ok": True, "warm": _spare is not None}


@app.websocket("/voice/ws/{lead_id}")
async def call(websocket: WebSocket, lead_id: str):
    global _spare
    await websocket.accept()
    _, call_data = await parse_telephony_websocket(websocket)
    if lead_id in _preparing and lead_id not in _ringing:
        # Picked up before the greeting finished rendering: a short wait beats starting over.
        try:
            await asyncio.wait_for(asyncio.shield(_preparing[lead_id]), timeout=4)
        except Exception as e:
            logger.warning(f"Greeting not ready in time for {lead_id}: {e}")
    ready = _ringing.pop(lead_id, None)
    lead = ready[0] if ready else await fetch_lead(lead_id)
    ml = lead.get("lang") != "en"
    logger.info(f"Call connected for lead {lead_id} ({lead.get('name')}, {'ml' if ml else 'en'}), greeting {'pre-rendered' if ready else 'live'}")
    if ready:
        # Speak immediately; the pipeline connects to Sarvam/Gemini behind this.
        for i in range(0, len(ready[2]), 8000):
            await websocket.send_text(
                json.dumps(
                    {
                        "event": "playAudio",
                        "media": {"contentType": "audio/x-mulaw", "sampleRate": 8000, "payload": base64.b64encode(ready[2][i : i + 8000]).decode()},
                        "streamId": call_data["stream_id"],
                    }
                )
            )

    kit = take_kit()
    context, aggregators = kit["context"], kit["aggregators"]
    context.add_message({"role": "user", "content": call_details(lead)})
    if ready:
        context.add_message({"role": "assistant", "content": ready[1]})
        post_live(lead_id, "assistant", ready[1])

    serializer = PlivoFrameSerializer(
        stream_id=call_data["stream_id"],
        call_id=call_data.get("call_id"),
        auth_id=os.getenv("PLIVO_AUTH_ID"),
        auth_token=os.getenv("PLIVO_AUTH_TOKEN"),
        # Hang up the real call when the pipeline ends (needs Plivo credentials).
        params=PlivoFrameSerializer.InputParams(auto_hang_up=bool(os.getenv("PLIVO_AUTH_ID") and call_data.get("call_id"))),
    )
    transport = FastAPIWebsocketTransport(
        websocket=websocket,
        params=FastAPIWebsocketParams(
            audio_in_enabled=True,
            audio_in_filter=RNNoiseFilter(),  # strip background noise before VAD/STT
            audio_out_enabled=True,
            add_wav_header=False,
            serializer=serializer,
        ),
    )
    tts = SarvamTTSService(
        api_key=os.environ["SARVAM_API_KEY"],
        settings=SarvamTTSService.Settings(
            model=os.getenv("SARVAM_TTS_MODEL", "bulbul:v3"),
            voice=speaker(),
            language=Language.ML_IN if ml else Language.EN_IN,
        ),
    )
    stt = kit["stt_ml"] if ml else make_stt(False)

    heard, spoke = AudioMeter(InputAudioRawFrame), AudioMeter(OutputAudioRawFrame)
    greeting_seconds = len(ready[2]) / 8000 if ready else 0.0

    @aggregators.user().event_handler("on_user_turn_stopped")
    async def on_user_turn(_aggregator, _strategy, message):
        post_live(lead_id, "user", getattr(message, "content", "") or "")

    @aggregators.assistant().event_handler("on_assistant_turn_stopped")
    async def on_assistant_turn(_aggregator, message):
        post_live(lead_id, "assistant", getattr(message, "content", "") or "")

    gate, junk = GreetingGate(greeting_seconds), JunkTranscriptFilter()
    pipeline = Pipeline([transport.input(), heard, gate, stt, junk, aggregators.user(), kit["llm"], tts, spoke, transport.output(), aggregators.assistant()])
    task = PipelineTask(pipeline, params=PipelineParams(audio_in_sample_rate=8000, audio_out_sample_rate=8000, enable_metrics=True))

    @transport.event_handler("on_client_connected")
    async def on_connected(_transport, _ws):
        if not ready:
            await task.queue_frames([TTSSpeakFrame(greeting(lead))])

    @transport.event_handler("on_client_disconnected")
    async def on_disconnected(_transport, _ws):
        transcript = transcript_of(context)[1:]  # drop the call-details cue
        _ringing.pop(lead_id, None)
        audio = {"callerSeconds": round(heard.seconds, 1), "agentSeconds": round(spoke.seconds + greeting_seconds, 1)}
        audio["noiseDropped"] = junk.dropped
        logger.info(f"Call ended for lead {lead_id}: {len(transcript)} turns, heard {audio['callerSeconds']}s, spoke {audio['agentSeconds']}s, dropped {junk.dropped} noise transcripts")
        try:
            async with aiohttp.ClientSession() as http:
                await http.post(f"{BACKEND_URL}/api/voice/result/{lead_id}", json={"transcript": transcript, "audio": audio}, headers={"x-agent-key": agent_key()})
        except Exception as e:
            logger.error(f"Could not report call result: {e}")
        await task.cancel()

    try:
        await PipelineRunner(handle_sigint=False).run(task)
    finally:
        if _spare is None:
            _spare = build_kit()  # ready for the next call


if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=int(os.getenv("VOICE_AGENT_PORT", "8765")))
