import 'dart:convert';
import 'dart:typed_data';

import '../../data/models.dart';
import '../../data/session.dart';

enum UploadState { uploading, done, failed }

class DraftPhoto {
  DraftPhoto({this.bytes, this.url, this.name = 'photo.jpg', this.state = UploadState.done});

  Uint8List? bytes; // local preview until the upload finishes
  String? url;
  String name;
  UploadState state;
}

/// One place on a trip being tracked: photos, spend, notes, details.
class DraftPlace {
  DraftPlace({
    required this.name,
    required this.lat,
    required this.lng,
    this.region = '',
    this.country = '',
    this.day = 1,
    this.story = '',
    this.tip = '',
    List<DraftPhoto>? photos,
    List<Expense>? expenses,
    List<Field>? fields,
  }) : photos = photos ?? [],
       expenses = expenses ?? [],
       fields = fields ?? [];

  String name;
  String region;
  String country;
  double lat;
  double lng;
  int day;
  String story;
  String tip;
  final List<DraftPhoto> photos;
  final List<Expense> expenses;
  final List<Field> fields;

  int get spent => expenses.fold(0, (s, e) => s + e.amount);
  List<String> get photoUrls => [for (final p in photos) if (p.url != null) p.url!];

  Map<String, dynamic> toJson() => {
    'name': name,
    'region': region,
    'country': country,
    'lat': lat,
    'lng': lng,
    'day': day,
    'story': story,
    'tip': tip,
    'photos': photoUrls,
    'expenses': [for (final e in expenses) e.toJson()],
    'fields': [for (final f in fields) f.toJson()],
  };

  factory DraftPlace.fromJson(Map<String, dynamic> j) => DraftPlace(
    name: j['name'] as String,
    region: j['region'] as String? ?? '',
    country: j['country'] as String? ?? '',
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    day: (j['day'] as num?)?.toInt() ?? 1,
    story: j['story'] as String? ?? '',
    tip: j['tip'] as String? ?? '',
    photos: [for (final u in (j['photos'] as List? ?? const []).cast<String>()) DraftPhoto(url: u)],
    expenses: (j['expenses'] as List? ?? const []).cast<Map<String, dynamic>>().map(Expense.fromJson).toList(),
    fields: (j['fields'] as List? ?? const []).cast<Map<String, dynamic>>().map(Field.fromJson).toList(),
  );
}

/// A trip being tracked. Autosaved, so it survives across the days of a trip.
class TripDraft {
  TripDraft({required this.title, required this.destination, this.country = '', this.currency = 'AED', this.travelers = 1});

  String title;
  String destination;
  String country;
  String currency;
  int travelers;
  String dek = '';
  String? coverUrl;
  final tags = <String>{};
  final places = <DraftPlace>[];
  final fields = <Field>[];

  int get days => places.isEmpty ? 1 : places.map((p) => p.day).reduce((a, b) => a > b ? a : b);
  int get spent => places.fold(0, (s, p) => s + p.spent);
  List<String> get photoUrls => [for (final p in places) ...p.photoUrls];
  bool get uploading => places.any((p) => p.photos.any((ph) => ph.state == UploadState.uploading));

  Map<String, dynamic> toJson() => {
    'title': title,
    'destination': destination,
    'country': country,
    'currency': currency,
    'travelers': travelers,
    'dek': dek,
    'coverUrl': coverUrl,
    'tags': tags.toList(),
    'places': [for (final p in places) p.toJson()],
    'fields': [for (final f in fields) f.toJson()],
  };

  static TripDraft? restore() {
    final raw = Session.instance.readDraft();
    if (raw == null) return null;
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      if (j['destination'] == null) return null; // an older draft format
      final d = TripDraft(
        title: j['title'] as String? ?? '',
        destination: j['destination'] as String,
        country: j['country'] as String? ?? '',
        currency: j['currency'] as String? ?? 'AED',
        travelers: (j['travelers'] as num?)?.toInt() ?? 1,
      )
        ..dek = j['dek'] as String? ?? ''
        ..coverUrl = j['coverUrl'] as String?;
      d.tags.addAll((j['tags'] as List? ?? const []).cast<String>());
      d.places.addAll((j['places'] as List? ?? const []).cast<Map<String, dynamic>>().map(DraftPlace.fromJson));
      d.fields.addAll((j['fields'] as List? ?? const []).cast<Map<String, dynamic>>().map(Field.fromJson));
      return d;
    } catch (_) {
      return null;
    }
  }

  Future<void> save() => Session.instance.writeDraft(jsonEncode(toJson()));
  static Future<void> discard() => Session.instance.writeDraft(null);

  /// The request body for POST /api/journeys.
  Map<String, dynamic> toPayload(String creatorId) {
    final urls = photoUrls;
    return {
      'creatorId': creatorId,
      'title': title.trim(),
      'dek': dek.trim(),
      'region': destination,
      'country': country,
      'currency': currency,
      'travelers': travelers,
      'durationDays': days,
      'tags': tags.toList(),
      'fields': [for (final f in fields) f.toJson()],
      'coverPhotoUrl': coverUrl ?? (urls.isEmpty ? null : urls.first),
      'stops': [
        for (final p in places)
          {
            'name': p.name,
            'lat': p.lat,
            'lng': p.lng,
            'day': p.day,
            'story': p.story.trim(),
            'tip': p.tip.trim(),
            'photos': [for (final u in p.photoUrls) {'url': u}],
            'expenses': [for (final e in p.expenses) e.toJson()],
            'fields': [for (final f in p.fields) f.toJson()],
          },
      ],
    };
  }
}
