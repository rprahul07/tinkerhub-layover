import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Per-install state: an anonymous device id (for saves and likes), the
/// traveller profile once created, and which server to talk to.
class Session extends ChangeNotifier {
  Session._(this._prefs);

  static late Session instance;

  final SharedPreferences _prefs;

  static Future<Session> init() async {
    final prefs = await SharedPreferences.getInstance();
    instance = Session._(prefs);
    if (prefs.getString(_kDevice) == null) {
      final rnd = Random.secure();
      await prefs.setString(_kDevice, List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join());
    }
    return instance;
  }

  static const _kDevice = 'device_id';
  static const _kCreator = 'creator';
  static const _kServer = 'server_url';
  static const _kLang = 'ammachi_lang';
  static const _kVoice = 'ammachi_voice';

  String get deviceId => _prefs.getString(_kDevice)!;

  /// The API server. Overridable at build time (--dart-define=API_BASE=...) and
  /// at runtime from the hidden settings sheet (long-press the masthead).
  String get apiBase {
    final saved = _prefs.getString(_kServer);
    if (saved != null && saved.isNotEmpty) return saved;
    const fromDefine = String.fromEnvironment('API_BASE');
    if (fromDefine.isNotEmpty) return fromDefine;
    if (kIsWeb) return '${Uri.base.scheme}://${Uri.base.host}:4000';
    if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:4000'; // emulator → host
    return 'http://localhost:4000';
  }

  Future<void> setApiBase(String? url) async {
    final clean = url?.trim().replaceAll(RegExp(r'/+$'), '');
    if (clean == null || clean.isEmpty) {
      await _prefs.remove(_kServer);
    } else {
      await _prefs.setString(_kServer, clean);
    }
    notifyListeners();
  }

  Creator? get creator {
    final raw = _prefs.getString(_kCreator);
    return raw == null ? null : Creator.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> setCreator(Creator c) async {
    await _prefs.setString(_kCreator, jsonEncode(c.toJson()));
    notifyListeners();
  }

  String get ammachiLang => _prefs.getString(_kLang) ?? 'ml';
  Future<void> setAmmachiLang(String lang) async {
    await _prefs.setString(_kLang, lang);
    notifyListeners();
  }

  bool get ammachiVoice => _prefs.getBool(_kVoice) ?? true;
  Future<void> setAmmachiVoice(bool on) async {
    await _prefs.setBool(_kVoice, on);
    notifyListeners();
  }

  String? readDraft() => _prefs.getString('draft');
  Future<void> writeDraft(String? json) => json == null ? _prefs.remove('draft') : _prefs.setString('draft', json);
}
