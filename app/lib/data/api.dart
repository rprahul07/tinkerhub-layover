import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;
import 'package:image_picker/image_picker.dart';

import 'models.dart';
import 'session.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status, this.details = const {}});
  final String message;
  final int? status;
  final Map<String, String> details;

  @override
  String toString() => message;
}

/// One event from Ammachi's stream.
sealed class AmmachiEvent {}

class AmmachiMeta extends AmmachiEvent {
  AmmachiMeta(this.mode, this.voice, this.reason);
  final String mode;
  final bool voice;
  final String? reason;
}

class AmmachiDelta extends AmmachiEvent {
  AmmachiDelta(this.text);
  final String text;
}

class AmmachiCite extends AmmachiEvent {
  AmmachiCite(this.journey);
  final Journey journey;
}

class AmmachiAudio extends AmmachiEvent {
  AmmachiAudio(this.index, this.url, this.text, {this.filler = false});
  final int index;
  final String? url;
  final String text;
  final bool filler; // "let me see, kunje…" while she thinks; not part of the answer
}

class AmmachiDone extends AmmachiEvent {
  AmmachiDone(this.text);
  final String text;
}

class AmmachiFailure extends AmmachiEvent {
  AmmachiFailure(this.message);
  final String message;
}

/// Filters for browsing trips.
class TripFilter {
  const TripFilter({this.q, this.destination, this.country, this.minAed, this.maxAed, this.minDays, this.maxDays, this.creatorId, this.sort});
  final String? q;
  final String? destination;
  final String? country;
  final int? minAed;
  final int? maxAed;
  final int? minDays;
  final int? maxDays;
  final String? creatorId;
  final String? sort;

  Map<String, String?> get query => {
    'q': q,
    'destination': destination,
    'country': country,
    'minAed': minAed?.toString(),
    'maxAed': maxAed?.toString(),
    'minDays': minDays?.toString(),
    'maxDays': maxDays?.toString(),
    'creatorId': creatorId,
    'sort': sort,
  };
}

class Api {
  Api(this.session, {http.Client? client}) : _client = client ?? http.Client();

  static late Api instance;

  final Session session;
  final http.Client _client;

  /// ngrok's free tier shows a warning page to browser-like clients unless this is set.
  static const tunnelHeaders = {'ngrok-skip-browser-warning': '1'};

  Uri _u(String path, [Map<String, String?> query = const {}]) {
    final q = {
      for (final e in query.entries)
        if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
    };
    return Uri.parse('${session.apiBase}/api$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'x-device-id': session.deviceId,
    if (session.creator != null) 'x-user-id': session.creator!.id,
    ...tunnelHeaders,
  };

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request, {Duration timeout = const Duration(seconds: 20)}) async {
    http.Response res;
    try {
      res = await request().timeout(timeout);
    } on TimeoutException {
      throw ApiException('The server is taking too long. Check your connection and try again.');
    } catch (_) {
      throw ApiException('Can’t reach Travelgram. Check your internet connection.');
    }
    Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Unexpected reply from the server (${res.statusCode}).', status: res.statusCode);
    }
    if (res.statusCode >= 400) {
      throw ApiException(
        body['error'] as String? ?? 'Something went wrong.',
        status: res.statusCode,
        details: (body['details'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ?? const {},
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> _get(String path, [Map<String, String?> q = const {}]) => _send(() => _client.get(_u(path, q), headers: _headers));

  Future<Map<String, dynamic>> _post(String path, [Object? body, Duration timeout = const Duration(seconds: 20)]) =>
      _send(() => _client.post(_u(path), headers: _headers, body: body == null ? null : jsonEncode(body)), timeout: timeout);

  List<Journey> _journeys(Map<String, dynamic> j) => (j['journeys'] as List).cast<Map<String, dynamic>>().map(Journey.fromJson).toList();

  // ---- trips -----------------------------------------------------------------------

  Future<Feed> feed({bool following = false}) async => Feed.fromJson(await _get('/feed', {'tab': following ? 'following' : 'foryou'}));

  Future<List<Journey>> journeys([TripFilter filter = const TripFilter()]) async => _journeys(await _get('/journeys', filter.query));

  Future<List<Destination>> destinations() async =>
      ((await _get('/destinations'))['destinations'] as List).cast<Map<String, dynamic>>().map(Destination.fromJson).toList();

  Future<(Journey, List<Journey>)> journey(String id) async {
    final j = await _get('/journeys/$id');
    return (Journey.fromJson(j['journey'] as Map<String, dynamic>), _journeys({'journeys': j['related']}));
  }

  Future<({bool saved, int saves})> toggleSave(String id) async {
    final j = await _post('/journeys/$id/save');
    return (saved: j['saved'] as bool, saves: (j['saves'] as num).toInt());
  }

  Future<({bool liked, int likes})> toggleLike(String id) async {
    final j = await _post('/journeys/$id/like');
    return (liked: j['liked'] as bool, likes: (j['likes'] as num).toInt());
  }

  Future<({bool going, int goingCount})> toggleGoing(String id) async {
    final j = await _post('/journeys/$id/going');
    return (going: j['going'] as bool, goingCount: (j['goingCount'] as num).toInt());
  }

  Future<List<Journey>> saved() async => _journeys(await _get('/me/saved'));
  Future<List<Journey>> going() async => _journeys(await _get('/me/going'));

  Future<Journey> createJourney(Map<String, dynamic> payload) async =>
      Journey.fromJson((await _post('/journeys', payload))['journey'] as Map<String, dynamic>);

  // ---- people ----------------------------------------------------------------------

  Future<Creator> createCreator({required String name, required String handle, String home = '', String bio = '', String phone = '', bool consent = false}) async {
    final j = await _post('/creators', {'name': name, 'handle': handle, 'home': home, 'bio': bio, 'phone': phone, 'consent': consent});
    return Creator.fromJson(j['creator'] as Map<String, dynamic>);
  }

  Future<List<Creator>> creators({String? q}) async =>
      ((await _get('/creators', {'q': q}))['creators'] as List).cast<Map<String, dynamic>>().map(Creator.fromJson).toList();

  Future<CreatorProfile> creator(String id) async => CreatorProfile.fromJson(await _get('/creators/$id'));

  Future<({bool following, int followers})> toggleFollow(String creatorId) async {
    final j = await _post('/creators/$creatorId/follow');
    return (following: j['following'] as bool, followers: (j['followers'] as num).toInt());
  }

  // ---- planner & leads -------------------------------------------------------------

  Future<TripPlan> plan({
    required int budget,
    required String currency,
    required int days,
    required int travelers,
    List<String> interests = const [],
    String from = '',
    int? month,
    required String lang,
  }) async {
    final j = await _post('/planner', {
      'budget': budget,
      'currency': currency,
      'days': days,
      'travelers': travelers,
      'interests': interests,
      'from': from,
      'month': month,
      'lang': lang,
    }, const Duration(seconds: 60));
    return TripPlan.fromJson(j['plan'] as Map<String, dynamic>);
  }

  Future<List<TripPlan>> myPlans() async =>
      ((await _get('/me/plans'))['plans'] as List).cast<Map<String, dynamic>>().map(TripPlan.fromJson).toList();

  Future<({int score, bool qualified})> sendLead({
    String? planId,
    String? journeyId,
    required String name,
    required String phone,
    required bool consent,
    int? month,
    int? travelers,
    String notes = '',
  }) async {
    final j = await _post('/leads', {
      'planId': planId,
      'journeyId': journeyId,
      'name': name,
      'phone': phone,
      'consent': consent,
      'month': month,
      'travelers': travelers,
      'notes': notes,
    });
    final lead = j['lead'] as Map<String, dynamic>;
    return (score: (lead['score'] as num).toInt(), qualified: lead['qualified'] as bool);
  }

  // ---- documents & bookings -------------------------------------------------------

  /// Sends up to four documents (id -> file) for a visa-readiness score.
  Future<DocCheck> checkDocuments(Map<String, XFile> files, {String destination = '', int? month, int travelers = 1, bool consent = true, String? journeyId}) async {
    final req = http.MultipartRequest('POST', _u('/documents/check'))
      ..headers['x-device-id'] = session.deviceId
      ..headers.addAll(tunnelHeaders)
      ..fields.addAll({
        'destination': destination,
        'month': month?.toString() ?? '',
        'travelers': '$travelers',
        'consent': '$consent',
        'lang': session.ammachiLang,
        'journeyId': ?journeyId,
      });
    if (session.creator != null) req.headers['x-user-id'] = session.creator!.id;
    for (final e in files.entries) {
      final bytes = await e.value.readAsBytes();
      final name = e.value.name.contains('.') ? e.value.name : '${e.value.name}.jpg';
      final lower = name.toLowerCase();
      final type = lower.endsWith('.pdf') ? MediaType('application', 'pdf') : MediaType('image', lower.endsWith('.png') ? 'png' : 'jpeg');
      req.files.add(http.MultipartFile.fromBytes(e.key, bytes, filename: name, contentType: type));
    }
    return DocCheck.fromJson(await _send(() async => http.Response.fromStream(await _client.send(req)), timeout: const Duration(seconds: 90)));
  }

  Future<DocCheck?> lastDocCheck() async {
    final j = (await _get('/me/documents'))['check'];
    return j == null ? null : DocCheck.fromJson(j as Map<String, dynamic>);
  }

  Future<Booking> book({required String journeyId, required String item, required String category, required int amount, required int guests, required String date}) async {
    final j = await _post('/bookings', {'journeyId': journeyId, 'item': item, 'category': category, 'amount': amount, 'guests': guests, 'date': date});
    return Booking.fromJson(j['booking'] as Map<String, dynamic>);
  }

  Future<List<Booking>> myBookings() async =>
      ((await _get('/me/bookings'))['bookings'] as List).cast<Map<String, dynamic>>().map(Booking.fromJson).toList();

  // ---- uploads & places --------------------------------------------------------------

  Future<String> uploadPhoto(XFile file) async {
    final req = http.MultipartRequest('POST', _u('/uploads'))
      ..headers['x-device-id'] = session.deviceId
      ..headers.addAll(tunnelHeaders);
    final bytes = await file.readAsBytes();
    final name = file.name.contains('.') ? file.name : '${file.name}.jpg';
    req.files.add(http.MultipartFile.fromBytes('photo', bytes, filename: name));
    final res = await _send(() async => http.Response.fromStream(await _client.send(req)), timeout: const Duration(seconds: 60));
    return res['url'] as String;
  }

  Future<List<Place>> places(String q) async {
    final j = await _get('/places', {'q': q});
    return (j['places'] as List).cast<Map<String, dynamic>>().map(Place.fromJson).toList();
  }

  // ---- Ammachi -------------------------------------------------------------------------

  Future<AmmachiStatus> ammachiStatus() async => AmmachiStatus.fromJson(await _get('/ammachi/status'));

  Future<String> speak(String text, String lang) async => (await _post('/tts', {'text': text, 'lang': lang}))['url'] as String;

  /// Streams Ammachi's reply as Server-Sent Events.
  Stream<AmmachiEvent> ammachi({
    required List<Map<String, String>> messages,
    required String lang,
    required bool voice,
    String? journeyId,
    String mode = 'chat',
  }) async* {
    final req = http.Request('POST', _u('/ammachi/chat'))
      ..headers.addAll(_headers)
      ..body = jsonEncode({'messages': messages, 'lang': lang, 'voice': voice, 'journeyId': journeyId, 'mode': mode});

    http.StreamedResponse res;
    try {
      res = await _client.send(req).timeout(const Duration(seconds: 25));
    } catch (_) {
      yield AmmachiFailure('Ammachi can’t hear you — check your internet connection.');
      return;
    }
    if (res.statusCode >= 400) {
      yield AmmachiFailure('Ammachi couldn’t answer that (${res.statusCode}).');
      return;
    }

    String? event;
    final data = StringBuffer();
    await for (final line in res.stream.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.startsWith('event:')) {
        event = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        data.write(line.substring(5).trim());
      } else if (line.isEmpty && event != null) {
        final parsed = _parse(event, data.toString());
        if (parsed != null) yield parsed;
        event = null;
        data.clear();
      }
    }
  }

  AmmachiEvent? _parse(String event, String raw) {
    final Map<String, dynamic> d;
    try {
      d = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    return switch (event) {
      'meta' => AmmachiMeta(d['mode'] as String? ?? 'offline', d['voice'] as bool? ?? false, d['reason'] as String?),
      'delta' => AmmachiDelta(d['text'] as String? ?? ''),
      'cite' => AmmachiCite(Journey.fromJson(d['journey'] as Map<String, dynamic>)),
      'audio' => AmmachiAudio((d['index'] as num).toInt(), d['url'] as String?, d['text'] as String? ?? '', filler: d['filler'] == true),
      'done' => AmmachiDone(d['text'] as String? ?? ''),
      'error' => AmmachiFailure(d['message'] as String? ?? 'Something went wrong.'),
      _ => null,
    };
  }
}
