"""End-to-end calls on a noisy line, against the real agent, Sarvam and Gemini.

A fake backend records what the agent reports; a fake "Plivo" streams mu-law
audio over the WebSocket. Run with:  pytest -m live
"""

import asyncio
import base64
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

import aiohttp
import numpy as np
import pytest
import websockets
from aiohttp import web
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT.parent / "backend" / ".env")
pytestmark = [pytest.mark.live, pytest.mark.skipif(not (os.getenv("SARVAM_API_KEY") and os.getenv("GEMINI_API_KEY")), reason="needs Sarvam + Gemini keys")]
KEY = "test-agent-key"


# ---- G.711 mu-law ------------------------------------------------------------------

def mulaw_decode(b: bytes) -> np.ndarray:
    u = ~np.frombuffer(b, dtype=np.uint8)
    sign, exp, mant = u & 0x80, (u >> 4) & 0x07, u & 0x0F
    mag = (((mant.astype(np.int32) << 3) + 0x84) << exp) - 0x84
    return np.where(sign != 0, -mag, mag).astype(np.int16)


def mulaw_encode(pcm: np.ndarray) -> bytes:
    x = pcm.astype(np.int32)
    sign = np.where(x < 0, 0x80, 0)
    x = np.minimum(np.abs(x), 32635) + 0x84
    exp = np.floor(np.log2(x)).astype(np.int32) - 7
    exp = np.clip(exp, 0, 7)
    mant = (x >> (exp + 3)) & 0x0F
    return (~(sign | (exp << 4) | mant) & 0xFF).astype(np.uint8).tobytes()


def noise(seconds: float, level: float, seed: int = 0) -> np.ndarray:
    """Street-ish noise: steady hiss plus random louder bursts (horns, clatter)."""
    rng = np.random.default_rng(seed)
    n = round(8000 * seconds)
    x = rng.normal(0, level, n)
    for _ in range(int(seconds)):
        s = rng.integers(0, max(1, n - 1600))
        x[s : s + 1600] += rng.normal(0, level * 3, 1600)
    return x


def mix(speech: np.ndarray, snr_db: float, pad_s: float = 1.0) -> np.ndarray:
    pad = np.zeros(int(8000 * pad_s))
    s = np.concatenate([pad, speech.astype(np.float64), pad])
    p_s = np.mean(speech.astype(np.float64) ** 2)
    level = np.sqrt(p_s / (10 ** (snr_db / 10)))
    return np.clip(s + noise(len(s) / 8000, level, seed=7), -32768, 32767).astype(np.int16)


async def say(text: str) -> np.ndarray:
    async with aiohttp.ClientSession() as http:
        async with http.post(
            "https://api.sarvam.ai/text-to-speech",
            headers={"api-subscription-key": os.environ["SARVAM_API_KEY"]},
            json={"text": text, "target_language_code": "ml-IN", "model": "bulbul:v3", "speaker": "rahul", "speech_sample_rate": 8000, "output_audio_codec": "mulaw"},
        ) as r:
            body = await r.json()
    return mulaw_decode(base64.b64decode(body["audios"][0]))


# ---- fixtures: fake backend + real agent ----------------------------------------------------

def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@pytest.fixture(scope="module")
async def env():
    reports = {"live": [], "result": []}
    app = web.Application()

    async def lead(req):
        return web.json_response({"id": req.match_info["id"], "name": "Rahul", "lang": "ml", "docScore": 85, "destination": "", "travelers": None})

    async def live(req):
        reports["live"].append((req.match_info["id"], await req.json()))
        return web.json_response({"ok": True})

    async def result(req):
        reports["result"].append((req.match_info["id"], await req.json()))
        return web.json_response({"ok": True})

    app.router.add_get("/api/voice/lead/{id}", lead)
    app.router.add_post("/api/voice/live/{id}", live)
    app.router.add_post("/api/voice/result/{id}", result)
    runner = web.AppRunner(app)
    await runner.setup()
    backend_port, agent_port = free_port(), free_port()
    await web.TCPSite(runner, "127.0.0.1", backend_port).start()

    proc = subprocess.Popen(
        [sys.executable, "bot.py"],
        cwd=ROOT,
        env={**os.environ, "BACKEND_URL": f"http://127.0.0.1:{backend_port}", "VOICE_AGENT_PORT": str(agent_port), "DASHBOARD_KEY": KEY, "PLIVO_AUTH_ID": ""},
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    base = f"http://127.0.0.1:{agent_port}"
    async with aiohttp.ClientSession() as http:
        for _ in range(120):
            try:
                async with http.get(f"{base}/health") as r:
                    if (await r.json()).get("warm"):
                        break
            except aiohttp.ClientError:
                pass
            await asyncio.sleep(0.5)
    yield {"base": base, "ws": f"ws://127.0.0.1:{agent_port}", "reports": reports}
    proc.terminate()
    await runner.cleanup()


async def call(env, lead_id: str, caller_audio: np.ndarray, start_after_greeting: bool = True, hang_up_after: float = 14.0):
    """Places a fake Plivo call: greeting plays, then the caller's audio streams in real time."""
    async with aiohttp.ClientSession() as http:
        await http.post(f"{env['base']}/prepare/{lead_id}", headers={"x-agent-key": KEY})
    events = []
    first_audio = None
    async with websockets.connect(f"{env['ws']}/voice/ws/{lead_id}") as ws:
        t0 = time.monotonic()
        await ws.send(json.dumps({"event": "start", "start": {"streamId": "s-" + lead_id, "callId": "c-" + lead_id}}))

        async def reader():
            nonlocal first_audio
            async for m in ws:
                d = json.loads(m)
                events.append((time.monotonic() - t0, d.get("event")))
                if d.get("event") == "playAudio" and first_audio is None:
                    first_audio = time.monotonic() - t0

        rt = asyncio.create_task(reader())
        silence = mulaw_encode(np.zeros(160, dtype=np.int16))
        audio = mulaw_encode(caller_audio)
        # Caller audio starts at once (noise during the greeting is part of the test).
        sent, step, end = 0, 160, time.monotonic() + hang_up_after
        while time.monotonic() < end:
            chunk = audio[sent : sent + step] if sent < len(audio) else silence
            sent += step
            await ws.send(json.dumps({"event": "media", "media": {"payload": base64.b64encode(chunk).decode()}}))
            await asyncio.sleep(0.02)
        rt.cancel()
    for _ in range(40):  # wait for the agent's end-of-call report
        if any(i == lead_id for i, _ in env["reports"]["result"]):
            break
        await asyncio.sleep(0.25)
    live = [m for i, m in env["reports"]["live"] if i == lead_id]
    result = next(r for i, r in env["reports"]["result"] if i == lead_id)
    return {"events": events, "first_audio": first_audio, "live": live, "result": result}


# ---- the calls ---------------------------------------------------------------------------------

async def test_noise_only_line_does_not_trigger_the_agent(env):
    """20 s of street noise from the moment they pick up: no turns, greeting never cut off."""
    r = await call(env, "noise-only", noise(20, 900).astype(np.int16), hang_up_after=20)
    assert r["first_audio"] is not None and r["first_audio"] < 1.0, "greeting should play at once"
    assert not [m for m in r["live"] if m["role"] == "user"], f"noise became user turns: {r['live']}"
    assert not [e for _, e in r["events"] if e == "clearAudio"], "noise interrupted the greeting"
    replies = [m for m in r["live"] if m["role"] == "assistant"]
    assert len(replies) == 1, f"agent answered noise: {replies}"
    assert r["result"]["audio"]["callerSeconds"] > 10  # meter starts once the pipeline is up


async def test_answer_is_understood_through_noise(env):
    """A Malayalam answer at 10 dB SNR over street noise is transcribed and answered."""
    speech = await say("ഹാ, സമയമുണ്ട്. ഡിസംബറിൽ ജോർജിയയിലേക്ക് പോകണം, ഞങ്ങൾ രണ്ടുപേരുണ്ട്.")
    greeting_s = 10.5  # caller answers after the greeting
    lead_in = np.zeros(int(8000 * greeting_s), dtype=np.int16)
    noisy = np.concatenate([lead_in + noise(greeting_s, 300).astype(np.int16), mix(speech, snr_db=10)])
    r = await call(env, "noisy-answer", noisy, hang_up_after=greeting_s + len(speech) / 8000 + 22)
    heard = " ".join(m["text"] for m in r["live"] if m["role"] == "user")
    assert "ജോർജിയ" in heard or "ഡിസംബ" in heard, f"didn't catch the answer: {heard!r}"
    roles = [m["role"] for m in r["live"]]
    assert roles[0] == "assistant" and "user" in roles and roles[-1] == "assistant", roles
    assert r["result"]["transcript"], "transcript reported"
