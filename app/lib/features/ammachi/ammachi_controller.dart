import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../data/api.dart';
import '../../data/models.dart';
import '../../data/session.dart';
import 'ammachi_art.dart';

class ChatMessage {
  ChatMessage.user(this.text) : fromUser = true, streaming = false;
  ChatMessage.ammachi() : fromUser = false, text = '', streaming = true;

  final bool fromUser;
  String text;
  bool streaming;
  String? mode; // gemini | offline
  String? failure;
  final List<Journey> citations = [];
  final List<String> audio = [];
}

/// Runs a conversation with Ammachi: voice in (speech_to_text), streamed text
/// and journey citations out, and Sarvam Bulbul audio played in order.
class AmmachiController extends ChangeNotifier {
  AmmachiController({this.contextJourney});

  Journey? contextJourney;
  final messages = <ChatMessage>[];
  AmmachiStatus? status;

  AmmachiMood _mood = AmmachiMood.idle;
  AmmachiMood get mood => _mood;

  String partial = '';
  double soundLevel = 0;
  bool listening = false;
  String? notice; // a one-off hint for the UI (e.g. voice not available)

  // Call mode: hands-free turn-taking until the user hangs up.
  bool inCall = false;
  bool muted = false;
  DateTime? callStartedAt;
  String caption = ''; // what Ammachi is saying right now
  String lastHeard = ''; // what she last heard from the user
  int _quietTurns = 0;
  final _captions = <String, String>{};

  String get lang => Session.instance.ammachiLang;
  bool get voiceOn => Session.instance.ammachiVoice;
  bool get busy => messages.isNotEmpty && messages.last.streaming;

  final _stt = SpeechToText();
  bool? _sttReady;
  String? _sttLocale;

  final _player = AudioPlayer();
  final _queue = <String>[];
  bool _playing = false;
  StreamSubscription<AmmachiEvent>? _stream;
  StreamSubscription<PlayerState>? _playerSub;
  bool _disposed = false;

  Future<void> init() async {
    _playerSub = _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _playing = false;
        _playNext();
      }
    });
    try {
      status = await Api.instance.ammachiStatus();
    } on ApiException {
      status = null;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _setMood(AmmachiMood m) {
    if (_mood != m) {
      _mood = m;
      _notify();
    }
  }

  Future<void> setLang(String l) async {
    await Session.instance.setAmmachiLang(l);
    _sttLocale = null;
    _notify();
  }

  Future<void> setVoice(bool on) async {
    await Session.instance.setAmmachiVoice(on);
    if (!on) await stopSpeaking();
    _notify();
  }

  void clearContext() {
    contextJourney = null;
    _notify();
  }

  // ---- call ---------------------------------------------------------------------

  Future<void> startCall() async {
    inCall = true;
    muted = false;
    callStartedAt = DateTime.now();
    _quietTurns = 0;
    _notify();
    if (status == null) await init();
    final greeting = lang == 'en' ? status?.greetingEn : status?.greetingMl;
    if (greeting != null && voiceOn) {
      _captions[greeting] = lang == 'en' ? 'Hello kunje, it’s Ammachi. So, where are we travelling this time?' : 'ഹലോ കുഞ്ഞേ, അമ്മച്ചിയാണ്. എങ്ങോട്ടാ ഈ പ്രാവശ്യം യാത്ര?';
      _enqueue(greeting); // she listens once the greeting finishes
    } else {
      caption = lang == 'en' ? 'Hello kunje, where are we travelling?' : 'ഹലോ കുഞ്ഞേ, എങ്ങോട്ടാ യാത്ര?';
      _listenSoon();
    }
  }

  Future<void> endCall() async {
    inCall = false;
    listening = false;
    await _stt.cancel();
    await _stream?.cancel();
    await stopSpeaking();
    _setMood(AmmachiMood.idle);
    _notify();
  }

  Future<void> toggleMute() async {
    muted = !muted;
    if (muted && listening) {
      listening = false;
      await _stt.cancel();
      _setMood(AmmachiMood.idle);
    } else if (!muted && !busy && !_playing) {
      _listenSoon();
    }
    _notify();
  }

  /// In a call, hand the turn back to the user once Ammachi is done talking.
  void _listenSoon() {
    if (!inCall || muted || _disposed) return;
    Future.delayed(const Duration(milliseconds: 350), () {
      if (inCall && !muted && !listening && !busy && !_playing && !_disposed) _startListening();
    });
  }

  // ---- sending ---------------------------------------------------------------

  Future<void> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty) return;
    await stopSpeaking();
    await _stream?.cancel();
    if (messages.isNotEmpty && messages.last.streaming) messages.last.streaming = false;

    messages.add(ChatMessage.user(text));
    final reply = ChatMessage.ammachi();
    messages.add(reply);
    partial = '';
    lastHeard = text;
    caption = '';
    _setMood(AmmachiMood.thinking);
    _notify();

    final history = messages
        .where((m) => m != reply && m.text.isNotEmpty)
        .map((m) => {'role': m.fromUser ? 'user' : 'ammachi', 'text': m.text})
        .toList();

    _stream = Api.instance
        .ammachi(messages: history, lang: lang, voice: voiceOn, journeyId: contextJourney?.id, mode: inCall ? 'call' : 'chat')
        .listen(
          (event) {
            switch (event) {
              case AmmachiMeta(:final mode):
                reply.mode = mode;
              case AmmachiDelta(:final text):
                reply.text += text;
                // Without a voice, she "speaks" through the text as it appears.
                if (!voiceOn || status?.voice != true) {
                  caption = reply.text.trim();
                  _setMood(AmmachiMood.idle);
                }
              case AmmachiCite(:final journey):
                reply.citations.add(journey);
              case AmmachiAudio(:final url, :final filler, :final text):
                if (url != null) {
                  if (!filler) reply.audio.add(url); // "Hear again" replays only the answer
                  _captions[url] = text;
                  if (voiceOn) _enqueue(url);
                }
              case AmmachiDone():
                reply.streaming = false;
                if (!_playing && _queue.isEmpty) {
                  _setMood(AmmachiMood.idle);
                  _listenSoon();
                }
              case AmmachiFailure(:final message):
                reply.failure = message;
                reply.streaming = false;
                caption = message;
                _setMood(AmmachiMood.idle);
                _listenSoon();
            }
            _notify();
          },
          onDone: () {
            if (reply.streaming) {
              reply.streaming = false;
              if (reply.text.isEmpty && reply.failure == null) reply.failure = 'Ammachi went quiet. Please ask again.';
              if (!_playing) {
                _setMood(AmmachiMood.idle);
                _listenSoon();
              }
              _notify();
            }
          },
        );
  }

  // ---- audio -----------------------------------------------------------------

  void _enqueue(String url) {
    _queue.add(url);
    _playNext();
  }

  Future<void> _playNext() async {
    if (_playing || _disposed) return;
    if (_queue.isEmpty) {
      if (!busy) {
        _setMood(AmmachiMood.idle);
        _listenSoon();
      }
      return;
    }
    _playing = true;
    final url = _queue.removeAt(0);
    if (_captions[url] != null) caption = _captions[url]!;
    _setMood(AmmachiMood.speaking);
    try {
      await _player.setUrl(url);
      await _player.play();
    } catch (e) {
      debugPrint('Ammachi audio failed: $e');
      _playing = false;
      unawaited(_playNext());
    }
  }

  Future<void> replay(ChatMessage m) async {
    await stopSpeaking();
    if (m.audio.isNotEmpty) {
      m.audio.forEach(_enqueue);
      return;
    }
    if (status?.voice != true) {
      notice = 'Ammachi’s voice isn’t set up on the server yet (SARVAM_API_KEY).';
      _notify();
      return;
    }
    try {
      _setMood(AmmachiMood.thinking);
      final url = await Api.instance.speak(m.text, lang);
      m.audio.add(url);
      _enqueue(url);
    } on ApiException catch (e) {
      notice = e.message;
      _setMood(AmmachiMood.idle);
    }
  }

  Future<void> stopSpeaking() async {
    _queue.clear();
    _playing = false;
    await _player.stop();
    if (_mood == AmmachiMood.speaking) _setMood(busy ? AmmachiMood.thinking : AmmachiMood.idle);
  }

  // ---- listening ---------------------------------------------------------------

  Future<bool> _ensureStt() async {
    if (_sttReady == true) return true;
    try {
      _sttReady = await _stt.initialize(onError: _onSttError, onStatus: _onSttStatus);
    } catch (e) {
      _sttReady = false;
    }
    return _sttReady!;
  }

  Future<String?> _localeFor(String lang) async {
    if (_sttLocale != null) return _sttLocale;
    final want = lang == 'en' ? 'en' : 'ml';
    try {
      final locales = await _stt.locales();
      final match = locales.where((l) => l.localeId.toLowerCase().replaceAll('-', '_').startsWith('${want}_')).toList();
      if (match.isNotEmpty) {
        _sttLocale = match.firstWhere((l) => l.localeId.toLowerCase().contains('in'), orElse: () => match.first).localeId;
        return _sttLocale;
      }
    } catch (_) {}
    // Platforms that don't list locales (e.g. the web) still accept the tag.
    return want == 'en' ? 'en-IN' : 'ml-IN';
  }

  Future<void> toggleListening() async {
    if (listening) {
      await _stt.stop();
      return;
    }
    await stopSpeaking();
    await _startListening();
  }

  Future<void> _startListening() async {
    if (!await _ensureStt()) {
      notice = 'Voice input isn’t available here. Allow the microphone, or type to Ammachi instead.';
      _notify();
      return;
    }
    final locale = await _localeFor(lang);
    partial = '';
    listening = true;
    _setMood(AmmachiMood.listening);
    _notify();
    await _stt.listen(
      onResult: _onResult,
      onSoundLevelChange: (level) {
        // Android reports roughly -2..10 dB; normalise to 0..1.
        soundLevel = ((level + 2) / 12).clamp(0.0, 1.0);
        _notify();
      },
      listenOptions: SpeechListenOptions(
        localeId: locale,
        partialResults: true,
        listenMode: ListenMode.dictation,
        pauseFor: Duration(milliseconds: inCall ? 1800 : 3000),
        listenFor: const Duration(seconds: 40),
        cancelOnError: true,
      ),
    );
  }

  void _onResult(SpeechRecognitionResult r) {
    partial = r.recognizedWords;
    if (r.finalResult) {
      listening = false;
      soundLevel = 0;
      final text = partial;
      partial = '';
      if (text.trim().isNotEmpty) {
        _quietTurns = 0;
        send(text);
      } else {
        _setMood(AmmachiMood.idle);
        _quietAgain();
      }
    }
    _notify();
  }

  /// Nothing heard: in a call, listen again a couple of times, then wait for a tap.
  void _quietAgain() {
    if (!inCall) return;
    if (++_quietTurns < 3) {
      _listenSoon();
    } else {
      muted = true;
      notice = lang == 'en' ? 'Ammachi is waiting. Tap the mic when you want to talk.' : 'അമ്മച്ചി കാത്തിരിക്കുന്നു. സംസാരിക്കാൻ മൈക്ക് തൊടൂ.';
      _notify();
    }
  }

  void _onSttStatus(String s) {
    if ((s == 'done' || s == 'notListening') && listening) {
      listening = false;
      soundLevel = 0;
      // If the recogniser stopped with words but no final result, send them.
      if (partial.trim().isNotEmpty) {
        final text = partial;
        partial = '';
        send(text);
      } else if (!busy) {
        _setMood(AmmachiMood.idle);
        _quietAgain();
      }
      _notify();
    }
  }

  void _onSttError(SpeechRecognitionError e) {
    listening = false;
    soundLevel = 0;
    final quiet = e.errorMsg == 'error_no_match' || e.errorMsg == 'error_speech_timeout';
    if (!quiet) {
      notice = lang == 'en'
          ? 'Ammachi couldn’t hear that (${e.errorMsg}). Try again or type.'
          : 'അമ്മച്ചിക്ക് കേൾക്കാൻ പറ്റിയില്ല. ഒന്നുകൂടി പറയൂ, അല്ലെങ്കിൽ ടൈപ്പ് ചെയ്യൂ.';
    }
    if (!busy) {
      _setMood(AmmachiMood.idle);
      if (quiet) _quietAgain();
    }
    _notify();
  }

  String? takeNotice() {
    final n = notice;
    notice = null;
    return n;
  }

  @override
  void dispose() {
    _disposed = true;
    _stream?.cancel();
    _playerSub?.cancel();
    _player.dispose();
    _stt.cancel();
    super.dispose();
  }
}
