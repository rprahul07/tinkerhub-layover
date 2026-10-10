// Plain data classes mirroring the Travelgram API.

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
int _i(Object? v) => (v as num?)?.toInt() ?? 0;
List<T> _list<T>(Object? v, T Function(Map<String, dynamic>) f) => (v as List? ?? const []).cast<Map<String, dynamic>>().map(f).toList();

class Creator {
  const Creator({
    required this.id,
    required this.name,
    required this.handle,
    this.home = '',
    this.bio = '',
    this.hue = 20,
    this.followers = 0,
    this.following = 0,
    this.trips = 0,
    this.isFollowing = false,
  });

  final String id;
  final String name;
  final String handle;
  final String home;
  final String bio;
  final int hue;
  final int followers;
  final int following;
  final int trips;
  final bool isFollowing;

  String get firstName => name.split(RegExp(r'\s+|&')).first.trim();
  String get initials {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty && p != '&').toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  Creator copyWith({bool? isFollowing, int? followers}) => Creator(
    id: id,
    name: name,
    handle: handle,
    home: home,
    bio: bio,
    hue: hue,
    followers: followers ?? this.followers,
    following: following,
    trips: trips,
    isFollowing: isFollowing ?? this.isFollowing,
  );

  factory Creator.fromJson(Map<String, dynamic> j) => Creator(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    handle: j['handle'] as String? ?? '',
    home: j['home'] as String? ?? '',
    bio: j['bio'] as String? ?? '',
    hue: _i(j['hue']),
    followers: _i(j['followers']),
    following: _i(j['following']),
    trips: _i(j['trips']),
    isFollowing: j['isFollowing'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'handle': handle, 'home': home, 'bio': bio, 'hue': hue};
}

class PhotoCredit {
  const PhotoCredit({required this.author, required this.license, this.source});
  final String author;
  final String license;
  final String? source;

  factory PhotoCredit.fromJson(Map<String, dynamic>? j) =>
      PhotoCredit(author: j?['author'] as String? ?? '', license: j?['license'] as String? ?? '', source: j?['source'] as String?);
}

class Photo {
  const Photo({required this.url, this.caption = '', this.credit});
  final String url;
  final String caption;
  final PhotoCredit? credit;

  factory Photo.fromJson(Map<String, dynamic> j) => Photo(
    url: j['url'] as String,
    caption: j['caption'] as String? ?? '',
    credit: j['credit'] == null ? null : PhotoCredit.fromJson(j['credit'] as Map<String, dynamic>),
  );
}

/// A free-form detail a creator added ("Entry fee: Free", "Visa: on arrival").
class Field {
  const Field(this.label, this.value);
  final String label;
  final String value;

  factory Field.fromJson(Map<String, dynamic> j) => Field(j['label'] as String? ?? '', j['value'] as String? ?? '');
  Map<String, dynamic> toJson() => {'label': label, 'value': value};
}

class Expense {
  const Expense({required this.category, required this.label, required this.amount});
  final String category;
  final String label;
  final int amount;

  factory Expense.fromJson(Map<String, dynamic> j) =>
      Expense(category: j['category'] as String? ?? 'other', label: j['label'] as String? ?? '', amount: _i(j['amount']));
  Map<String, dynamic> toJson() => {'category': category, 'label': label, 'amount': amount};
}

class Stop {
  const Stop({
    required this.id,
    required this.name,
    required this.day,
    required this.lat,
    required this.lng,
    this.story = '',
    this.tip = '',
    this.photos = const [],
    this.fields = const [],
    this.expenses = const [],
  });

  final String id;
  final String name;
  final int day;
  final double lat;
  final double lng;
  final String story;
  final String tip;
  final List<Photo> photos;
  final List<Field> fields;
  final List<Expense> expenses;

  factory Stop.fromJson(Map<String, dynamic> j) => Stop(
    id: j['id'] as String,
    name: j['name'] as String,
    day: _i(j['day']),
    lat: _d(j['lat']),
    lng: _d(j['lng']),
    story: j['story'] as String? ?? '',
    tip: j['tip'] as String? ?? '',
    photos: _list(j['photos'], Photo.fromJson),
    fields: _list(j['fields'], Field.fromJson),
    expenses: _list(j['expenses'], Expense.fromJson),
  );
}

class BudgetCategory {
  const BudgetCategory({required this.category, required this.amount, required this.items});
  final String category;
  final int amount;
  final List<Expense> items;

  factory BudgetCategory.fromJson(Map<String, dynamic> j) =>
      BudgetCategory(category: j['category'] as String, amount: _i(j['amount']), items: _list(j['items'], Expense.fromJson));
}

/// A trip. Feed cards carry the summary; [isDetailed] trips also carry the
/// story, places and budget.
class Journey {
  const Journey({
    required this.id,
    required this.title,
    required this.dek,
    required this.region,
    required this.country,
    required this.tags,
    required this.bestMonths,
    required this.durationDays,
    required this.travelers,
    required this.stopCount,
    required this.stopNames,
    required this.currency,
    required this.budgetTotal,
    required this.budgetAed,
    required this.perPersonPerDay,
    this.coverPhoto,
    this.photos = const [],
    required this.creator,
    required this.likes,
    required this.saves,
    required this.goingCount,
    required this.liked,
    required this.saved,
    required this.isGoing,
    required this.createdAt,
    this.story,
    this.pullQuote,
    this.fields = const [],
    this.stops = const [],
    this.budget = const [],
  });

  final String id;
  final String title;
  final String dek;
  final String region;
  final String country;
  final List<String> tags;
  final List<int> bestMonths;
  final int durationDays;
  final int travelers;
  final int stopCount;
  final List<String> stopNames;
  final String currency;
  final int budgetTotal;
  final int budgetAed;
  final int perPersonPerDay;
  final Photo? coverPhoto;
  final List<Photo> photos;
  final Creator creator;
  final int likes;
  final int saves;
  final int goingCount;
  final bool liked;
  final bool saved;
  final bool isGoing;
  final DateTime createdAt;

  final String? story;
  final String? pullQuote;
  final List<Field> fields;
  final List<Stop> stops;
  final List<BudgetCategory> budget;

  bool get isDetailed => story != null;

  Journey copyWith({bool? liked, int? likes, bool? saved, int? saves, bool? isGoing, int? goingCount, Creator? creator}) => Journey(
    id: id,
    title: title,
    dek: dek,
    region: region,
    country: country,
    tags: tags,
    bestMonths: bestMonths,
    durationDays: durationDays,
    travelers: travelers,
    stopCount: stopCount,
    stopNames: stopNames,
    currency: currency,
    budgetTotal: budgetTotal,
    budgetAed: budgetAed,
    perPersonPerDay: perPersonPerDay,
    coverPhoto: coverPhoto,
    photos: photos,
    creator: creator ?? this.creator,
    likes: likes ?? this.likes,
    saves: saves ?? this.saves,
    goingCount: goingCount ?? this.goingCount,
    liked: liked ?? this.liked,
    saved: saved ?? this.saved,
    isGoing: isGoing ?? this.isGoing,
    createdAt: createdAt,
    story: story,
    pullQuote: pullQuote,
    fields: fields,
    stops: stops,
    budget: budget,
  );

  factory Journey.fromJson(Map<String, dynamic> j) => Journey(
    id: j['id'] as String,
    title: j['title'] as String,
    dek: j['dek'] as String? ?? '',
    region: j['region'] as String? ?? '',
    country: j['country'] as String? ?? '',
    tags: (j['tags'] as List? ?? const []).cast<String>(),
    bestMonths: (j['bestMonths'] as List? ?? const []).map((e) => (e as num).toInt()).toList(),
    durationDays: _i(j['durationDays']),
    travelers: _i(j['travelers']),
    stopCount: _i(j['stopCount']),
    stopNames: (j['stopNames'] as List? ?? const []).cast<String>(),
    currency: j['currency'] as String? ?? 'AED',
    budgetTotal: _i(j['budgetTotal']),
    budgetAed: _i(j['budgetAed']),
    perPersonPerDay: _i(j['perPersonPerDay']),
    coverPhoto: j['coverPhoto'] == null ? null : Photo.fromJson(j['coverPhoto'] as Map<String, dynamic>),
    photos: _list(j['photos'], Photo.fromJson),
    creator: Creator.fromJson(j['creator'] as Map<String, dynamic>),
    likes: _i(j['likes']),
    saves: _i(j['saves']),
    goingCount: _i(j['goingCount']),
    liked: j['liked'] as bool? ?? false,
    saved: j['saved'] as bool? ?? false,
    isGoing: j['isGoing'] as bool? ?? false,
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    story: j['story'] as String?,
    pullQuote: j['pullQuote'] as String?,
    fields: _list(j['fields'], Field.fromJson),
    stops: _list(j['stops'], Stop.fromJson),
    budget: _list(j['budget'], BudgetCategory.fromJson),
  );
}

class Destination {
  const Destination({required this.name, required this.country, required this.count, required this.minAed, this.coverPhoto});
  final String name;
  final String country;
  final int count;
  final int minAed;
  final Photo? coverPhoto;

  factory Destination.fromJson(Map<String, dynamic> j) => Destination(
    name: j['name'] as String,
    country: j['country'] as String? ?? '',
    count: _i(j['count']),
    minAed: _i(j['minAed']),
    coverPhoto: j['coverPhoto'] == null ? null : Photo.fromJson(j['coverPhoto'] as Map<String, dynamic>),
  );
}

class Feed {
  const Feed({required this.journeys, required this.destinations, required this.suggested});
  final List<Journey> journeys;
  final List<Destination> destinations;
  final List<Creator> suggested;

  factory Feed.fromJson(Map<String, dynamic> j) => Feed(
    journeys: _list(j['journeys'], Journey.fromJson),
    destinations: _list(j['destinations'], Destination.fromJson),
    suggested: _list(j['suggested'], Creator.fromJson),
  );
}

class Place {
  const Place({required this.name, required this.region, required this.country, required this.lat, required this.lng});
  final String name;
  final String region;
  final String country;
  final double lat;
  final double lng;

  factory Place.fromJson(Map<String, dynamic> j) => Place(
    name: j['name'] as String,
    region: j['region'] as String? ?? '',
    country: j['country'] as String? ?? '',
    lat: _d(j['lat']),
    lng: _d(j['lng']),
  );
}

class CreatorProfile {
  const CreatorProfile({required this.creator, required this.journeys, required this.countries});
  final Creator creator;
  final List<Journey> journeys;
  final int countries;

  factory CreatorProfile.fromJson(Map<String, dynamic> j) => CreatorProfile(
    creator: Creator.fromJson(j['creator'] as Map<String, dynamic>),
    journeys: _list(j['journeys'], Journey.fromJson),
    countries: _i((j['stats'] as Map?)?['countries']),
  );
}

class PlanItem {
  const PlanItem({required this.place, required this.journeyId, required this.what, required this.category, required this.costAed});
  final String place;
  final String journeyId;
  final String what;
  final String category;
  final int costAed;

  factory PlanItem.fromJson(Map<String, dynamic> j) => PlanItem(
    place: j['place'] as String? ?? '',
    journeyId: j['journeyId'] as String? ?? '',
    what: j['what'] as String? ?? '',
    category: j['category'] as String? ?? 'other',
    costAed: _i(j['costAed']),
  );
}

class PlanDay {
  const PlanDay({required this.day, required this.title, required this.items});
  final int day;
  final String title;
  final List<PlanItem> items;

  factory PlanDay.fromJson(Map<String, dynamic> j) =>
      PlanDay(day: _i(j['day']), title: j['title'] as String? ?? '', items: _list(j['items'], PlanItem.fromJson));
}

/// A budget plan Ammachi built from real trips.
class TripPlan {
  const TripPlan({
    required this.id,
    required this.title,
    required this.summary,
    required this.tips,
    required this.days,
    required this.totalAed,
    required this.totalLabel,
    required this.budgetLabel,
    required this.budgetAed,
    required this.fits,
    required this.travelers,
    required this.dayCount,
    required this.trips,
    required this.source,
  });

  final String id;
  final String title;
  final String summary;
  final List<String> tips;
  final List<PlanDay> days;
  final int totalAed;
  final String totalLabel;
  final String budgetLabel;
  final int budgetAed;
  final bool fits;
  final int travelers;
  final int dayCount;
  final List<Journey> trips;
  final String source; // gemini | catalogue

  factory TripPlan.fromJson(Map<String, dynamic> j) {
    final req = j['request'] as Map<String, dynamic>? ?? const {};
    return TripPlan(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      summary: j['summary'] as String? ?? '',
      tips: (j['tips'] as List? ?? const []).cast<String>(),
      days: _list(j['days'], PlanDay.fromJson),
      totalAed: _i(j['totalAed']),
      totalLabel: j['totalLabel'] as String? ?? '',
      budgetLabel: j['budgetLabel'] as String? ?? '',
      budgetAed: _i(req['budgetAed']),
      fits: j['fits'] as bool? ?? true,
      travelers: _i(req['travelers']),
      dayCount: _i(req['days']),
      trips: _list(j['trips'], Journey.fromJson),
      source: j['source'] as String? ?? 'catalogue',
    );
  }
}

class AmmachiStatus {
  const AmmachiStatus({required this.brain, this.model, required this.voice, this.greetingMl, this.greetingEn});
  final String brain; // gemini | offline
  final String? model;
  final bool voice;
  final String? greetingMl;
  final String? greetingEn;

  factory AmmachiStatus.fromJson(Map<String, dynamic> j) => AmmachiStatus(
    brain: (j['llm'] as Map?)?['provider'] as String? ?? 'offline',
    model: (j['llm'] as Map?)?['model'] as String?,
    voice: (j['tts'] as Map?)?['provider'] == 'sarvam',
    greetingMl: (j['greeting'] as Map?)?['ml'] as String?,
    greetingEn: (j['greeting'] as Map?)?['en'] as String?,
  );
}

class DocCheckItem {
  const DocCheckItem({required this.doc, required this.status, required this.note});
  final String doc; // passport | residence | bank | photo
  final String status; // ok | warning | missing
  final String note;

  factory DocCheckItem.fromJson(Map<String, dynamic> j) =>
      DocCheckItem(doc: j['doc'] as String? ?? '', status: j['status'] as String? ?? 'missing', note: j['note'] as String? ?? '');
}

/// The visa-readiness score for a set of documents.
class DocCheck {
  const DocCheck({required this.score, required this.passScore, required this.summary, required this.checks, required this.qualified, required this.callStatus, required this.source});
  final int score;
  final int passScore;
  final String summary;
  final List<DocCheckItem> checks;
  final bool qualified;
  final String callStatus; // simulated | ringing | failed | not_triggered
  final String source; // ai | basic

  factory DocCheck.fromJson(Map<String, dynamic> j) => DocCheck(
    score: _i(j['score']),
    passScore: _i(j['passScore']) == 0 ? 70 : _i(j['passScore']),
    summary: j['summary'] as String? ?? '',
    checks: _list(j['checks'], DocCheckItem.fromJson),
    qualified: j['qualified'] as bool? ?? false,
    callStatus: (j['call'] as Map?)?['status'] as String? ?? 'not_triggered',
    source: j['source'] as String? ?? 'basic',
  );
}

class Booking {
  const Booking({required this.ref, required this.item, required this.journeyTitle, required this.date, required this.guests, required this.totalLabel});
  final String ref;
  final String item;
  final String journeyTitle;
  final String date;
  final int guests;
  final String totalLabel;

  factory Booking.fromJson(Map<String, dynamic> j) => Booking(
    ref: j['ref'] as String? ?? '',
    item: j['item'] as String? ?? '',
    journeyTitle: j['journeyTitle'] as String? ?? '',
    date: j['date'] as String? ?? '',
    guests: _i(j['guests']),
    totalLabel: j['totalLabel'] as String? ?? '',
  );
}
