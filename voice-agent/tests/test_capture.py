"""Unit tests for voice capture on noisy lines (no network)."""

import numpy as np
import pytest

from pipecat.audio.filters.rnnoise_filter import RNNoiseFilter
from pipecat.audio.vad.vad_analyzer import VADParams
from pipecat.frames.frames import InputAudioRawFrame, InterimTranscriptionFrame, TranscriptionFrame
from pipecat.tests.utils import run_test
from pipecat.turns.user_start.min_words_user_turn_start_strategy import MinWordsUserTurnStartStrategy

import bot
from capture import (
    INTERRUPT_MIN_WORDS,
    AudioMeter,
    GreetingGate,
    JunkTranscriptFilter,
    is_junk,
    trim_mulaw_silence,
    turn_strategies,
    vad_params,
)


def tx(text):
    return TranscriptionFrame(text=text, user_id="caller", timestamp="t")


# ---- junk transcripts -------------------------------------------------------------


@pytest.mark.parametrize("text", ["", None, "   ", ".", "...", "?!", "hmm", "Hmm.", "uh um", "mm mm", "ഹ്മ്", "<unk>", "[noise]", "(music)", "a", "ആ", "ss"])
def test_noise_transcripts_are_junk(text):
    assert is_junk(text)


@pytest.mark.parametrize("text", ["yes", "No", "ok", "ഹാ", "ശരി", "ഇല്ല", "Georgia", "ഡിസംബറിൽ ജോർജിയ", "two people", "hmm yes", "2"])
def test_real_answers_are_kept(text):
    assert not is_junk(text)


async def test_junk_filter_drops_only_noise():
    f = JunkTranscriptFilter()
    down, _ = await run_test(
        f,
        frames_to_send=[tx("hmm"), tx("ഡിസംബറിൽ ജോർജിയ"), InterimTranscriptionFrame(text="...", user_id="caller", timestamp="t"), tx("ഹാ")],
        expected_down_frames=[TranscriptionFrame, TranscriptionFrame],
    )
    assert [fr.text for fr in down] == ["ഡിസംബറിൽ ജോർജിയ", "ഹാ"]
    assert f.dropped == 2


# ---- greeting gate ----------------------------------------------------------------


async def test_greeting_gate_silences_caller_until_greeting_ends():
    now = [100.0]
    gate = GreetingGate(seconds=5, clock=lambda: now[0])
    loud = bytes([0x10, 0x7F] * 160)
    down, _ = await run_test(gate, frames_to_send=[InputAudioRawFrame(audio=loud, sample_rate=8000, num_channels=1)], expected_down_frames=[InputAudioRawFrame])
    assert down[0].audio == bytes(len(loud))  # muted while the greeting plays
    now[0] = 105.1
    assert gate.open
    down, _ = await run_test(gate, frames_to_send=[InputAudioRawFrame(audio=loud, sample_rate=8000, num_channels=1)], expected_down_frames=[InputAudioRawFrame])
    assert down[0].audio == loud  # then the caller is heard


def test_greeting_gate_without_greeting_is_open():
    assert GreetingGate(seconds=0).open


# ---- audio log ------------------------------------------------------------------------


async def test_audio_meter_counts_seconds():
    meter = AudioMeter(InputAudioRawFrame)
    one_second = bytes(8000 * 2)  # 16-bit mono at 8 kHz
    await run_test(meter, frames_to_send=[InputAudioRawFrame(audio=one_second, sample_rate=8000, num_channels=1)] * 3, expected_down_frames=[InputAudioRawFrame] * 3)
    assert meter.seconds == pytest.approx(3.0)


# ---- VAD / turn-taking -------------------------------------------------------------


def test_vad_is_stricter_than_defaults():
    p, d = vad_params(), VADParams()
    assert p.confidence > d.confidence
    assert p.start_secs > d.start_secs
    assert p.min_volume > d.min_volume


def test_turns_start_from_words_and_need_three_to_interrupt():
    s = turn_strategies()
    assert len(s.start) == 1 and isinstance(s.start[0], MinWordsUserTurnStartStrategy)
    assert INTERRUPT_MIN_WORDS == 3
    assert s.stop  # Pipecat's smart-turn stop strategy stays in place


# ---- noise suppression ----------------------------------------------------------------


def rms(pcm: bytes) -> float:
    a = np.frombuffer(pcm, dtype=np.int16).astype(np.float64)
    return float(np.sqrt(np.mean(a**2))) if a.size else 0.0


async def test_rnnoise_suppresses_steady_background_noise():
    rng = np.random.default_rng(1)
    noise = (rng.normal(0, 2500, 8000 * 3)).clip(-32768, 32767).astype(np.int16).tobytes()  # 3 s of hiss
    f = RNNoiseFilter()
    await f.start(8000)
    out = b""
    for i in range(0, len(noise), 320):  # 20 ms frames, like a phone stream
        out += await f.filter(noise[i : i + 320])
    await f.stop()
    tail_in, tail_out = rms(noise[len(noise) // 2 :]), rms(out[len(out) // 2 :])  # after it adapts
    assert tail_out < tail_in * 0.35, (tail_in, tail_out)


# ---- greeting audio + prompts ------------------------------------------------------------


def test_trim_mulaw_silence_keeps_short_lead_in():
    audio = bytes([0xFF] * 4000) + bytes([0x10, 0x90] * 100)
    out = trim_mulaw_silence(audio)
    assert len(out) == 400 + 200  # 50 ms lead-in + the speech
    assert trim_mulaw_silence(bytes([0xFF] * 100)) == b""
    assert trim_mulaw_silence(bytes([0x10] * 10)) == bytes([0x10] * 10)


def test_greeting_is_short_and_in_the_right_language():
    ml = bot.greeting({"name": "Rahul Raj", "lang": "ml"})
    en = bot.greeting({"name": "Rahul Raj", "lang": "en"})
    assert ml.startswith("നമസ്കാരം Rahul,") and "Travelgram" in ml and "AI consultant" in ml
    assert en.startswith("Hello Rahul,") and "AI consultant" in en
    for persona in ("അമ്മച്ചി", "Ammachi", "kunje", "കുഞ്ഞേ"):
        assert persona not in ml + en
    assert len(ml) < 140 and len(en) < 140


def test_call_details_carry_what_we_know():
    d = bot.call_details({"name": "Rahul", "docScore": 85, "destination": "Georgia", "month": 12, "travelers": 2, "lang": "ml"})
    assert "Georgia" in d and "December" in d and "2 people" in d and "85/100" in d and "Speak Malayalam" in d
