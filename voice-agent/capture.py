"""Voice capture on noisy phone lines.

Phone calls arrive with traffic, fans, TV and line hiss. Left alone, that noise
starts "user turns", interrupts Ammachi mid-sentence (which also clears the
greeting already queued on Plivo) and gets transcribed into nonsense that the
LLM then answers. The defences, in pipeline order:

1. RNNoise on the caller's audio (transport input filter).
2. GreetingGate: the caller is muted (silence passed on) while the pre-rendered
   greeting plays, so noise can't cut it off.
3. Stricter Silero VAD: louder, more confident, longer speech before it counts.
4. Turns start from words, not sound: one word while Ammachi is quiet, three
   words to interrupt her while she speaks.
5. JunkTranscriptFilter: transcripts that are only noise ("hmm", ".", "<unk>")
   never reach the LLM.
"""

import re
import time

from pipecat.audio.vad.silero import SileroVADAnalyzer
from pipecat.audio.vad.vad_analyzer import VADParams
from pipecat.frames.frames import InputAudioRawFrame, InterimTranscriptionFrame, TranscriptionFrame
from pipecat.processors.frame_processor import FrameDirection, FrameProcessor
from pipecat.turns.user_start.min_words_user_turn_start_strategy import MinWordsUserTurnStartStrategy
from pipecat.turns.user_turn_strategies import UserTurnStrategies

# Words needed to interrupt Ammachi while she is talking (a cough or "hmm" won't).
INTERRUPT_MIN_WORDS = 3

# Sounds STT emits for noise, breathing and fillers. Real one-word answers
# ("yes", "ok", "ഹാ", "ശരി", "ഇല്ല") are deliberately NOT here.
_FILLERS = {
    "hmm", "hm", "mm", "mmm", "uh", "um", "umm", "uhh", "ah", "aah", "eh", "er", "erm", "huh", "oh",
    "ഹ്മ്", "ഹ്മ്മ്", "മ്", "മ്മ്", "ഉം", "ആഹ്", "ഏഹ്", "ഓ",
}
_TAGS = re.compile(r"<[^>]*>|\[[^\]]*\]|\([^)]*\)")  # <unk>, [noise], (music)
_NOT_WORD = re.compile(r"[^\wഀ-ൿ]+")


def is_junk(text: str | None) -> bool:
    """True when a transcript carries no words worth answering."""
    if not text:
        return True
    words = [w for w in (_NOT_WORD.sub(" ", _TAGS.sub(" ", text)).lower().split()) if w]
    if not words:
        return True
    if all(w in _FILLERS for w in words):
        return True
    # A single character repeated or alone ("a", "ആ", "ss") is line noise.
    # Digits are real answers ("2" people).
    w = words[0]
    return len(words) == 1 and not w.isdigit() and len(set(w)) == 1 and len(w) <= 3


def vad_params() -> VADParams:
    """Stricter than Pipecat's defaults (0.7 / 0.2 s / 0.6): phone noise is loud and bursty."""
    return VADParams(confidence=0.8, start_secs=0.3, stop_secs=0.2, min_volume=0.65)


def make_vad() -> SileroVADAnalyzer:
    return SileroVADAnalyzer(params=vad_params())


def turn_strategies() -> UserTurnStrategies:
    """Turns start from transcribed words (not raw sound); stopping keeps Pipecat's smart-turn default."""
    return UserTurnStrategies(start=[MinWordsUserTurnStartStrategy(min_words=INTERRUPT_MIN_WORDS)])


class JunkTranscriptFilter(FrameProcessor):
    """Drops transcripts that are only noise, so they never start a turn or reach the LLM."""

    def __init__(self):
        super().__init__()
        self.dropped = 0

    async def process_frame(self, frame, direction: FrameDirection):
        await super().process_frame(frame, direction)
        if isinstance(frame, (TranscriptionFrame, InterimTranscriptionFrame)) and is_junk(frame.text):
            self.dropped += 1
            return
        await self.push_frame(frame, direction)


class GreetingGate(FrameProcessor):
    """Passes silence instead of caller audio until the pre-rendered greeting has played."""

    def __init__(self, seconds: float, clock=time.monotonic):
        super().__init__()
        self._clock = clock
        self._until = clock() + max(0.0, seconds)

    @property
    def open(self) -> bool:
        return self._clock() >= self._until

    async def process_frame(self, frame, direction: FrameDirection):
        await super().process_frame(frame, direction)
        if isinstance(frame, InputAudioRawFrame) and not self.open:
            frame = InputAudioRawFrame(audio=bytes(len(frame.audio)), sample_rate=frame.sample_rate, num_channels=frame.num_channels)
        await self.push_frame(frame, direction)


class AudioMeter(FrameProcessor):
    """Counts seconds of audio of one kind passing through: the call's audio log."""

    def __init__(self, kind: type):
        super().__init__()
        self.kind = kind
        self.seconds = 0.0

    async def process_frame(self, frame, direction: FrameDirection):
        await super().process_frame(frame, direction)
        if isinstance(frame, self.kind) and frame.sample_rate:
            self.seconds += len(frame.audio) / 2 / frame.sample_rate / max(1, frame.num_channels)
        await self.push_frame(frame, direction)


# mu-law bytes that are (near) silence: 0xFF/0x7F are zero, the next few are tiny.
_MULAW_QUIET = {0xFF, 0x7F, 0xFE, 0x7E, 0xFD, 0x7D}


def trim_mulaw_silence(audio: bytes, keep_ms: int = 50, rate: int = 8000) -> bytes:
    """Removes leading silence from 8 kHz mu-law audio, keeping a short natural lead-in."""
    i = 0
    while i < len(audio) and audio[i] in _MULAW_QUIET:
        i += 1
    if i == len(audio):
        return b""
    return audio[max(0, i - keep_ms * rate // 1000) :]
