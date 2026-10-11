import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travelgram/data/api.dart';
import 'package:travelgram/data/reactions.dart';
import 'package:travelgram/data/session.dart';
import 'package:travelgram/main.dart';

const me = {'id': 'c_me', 'name': 'Test Traveller', 'handle': 'test.traveller', 'home': 'Dubai', 'bio': '', 'hue': 30};
const sara = {'id': 'c_1', 'name': 'Sara Al Mansoori', 'handle': 'sara.trails', 'home': 'Abu Dhabi', 'bio': '', 'hue': 18, 'followers': 1200};

Map<String, dynamic> journey(String id, String title, {bool detailed = false}) => {
  'id': id,
  'title': title,
  'dek': 'A dek for $title.',
  'region': 'Hatta',
  'country': 'United Arab Emirates',
  'tags': ['mountains'],
  'bestMonths': [11, 12],
  'durationDays': 2,
  'travelers': 2,
  'stopCount': 2,
  'stopNames': ['Hatta Dam', 'Wadi Hub'],
  'currency': 'AED',
  'budgetTotal': 850,
  'budgetAed': 850,
  'perPersonPerDay': 212,
  'coverPhoto': null,
  'photos': [],
  'creator': sara,
  'likes': 10,
  'saves': 0,
  'goingCount': 3,
  'liked': false,
  'saved': false,
  'isGoing': false,
  'createdAt': '2026-10-01T00:00:00.000Z',
  if (detailed) ...{
    'story': 'Kayaks on green water.',
    'fields': [
      {'label': 'Visa', 'value': 'Not needed'},
    ],
    'stops': [
      {
        'id': 's1',
        'name': 'Hatta Dam',
        'day': 1,
        'lat': 24.8,
        'lng': 56.1,
        'story': 'Green water.',
        'tip': 'Go early.',
        'photos': [],
        'fields': [],
        'expenses': [
          {'category': 'activities', 'label': 'Kayak', 'amount': 120},
        ],
      },
      {'id': 's2', 'name': 'Wadi Hub', 'day': 2, 'lat': 24.79, 'lng': 56.12, 'story': '', 'tip': '', 'photos': [], 'fields': [], 'expenses': []},
    ],
    'budget': [
      {
        'category': 'activities',
        'amount': 120,
        'items': [
          {'category': 'activities', 'label': 'Kayak', 'amount': 120},
        ],
      },
    ],
  },
};

final requests = <String>[];

MockClient server() => MockClient.streaming((req, body) async {
  final path = req.url.path;
  requests.add('${req.method} $path');
  http.StreamedResponse json(Object o, [int status = 200]) =>
      http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(o))), status, headers: {'content-type': 'application/json'});

  switch ('${req.method} $path') {
    case 'GET /api/feed':
      return json({
        'tab': 'foryou',
        'journeys': [journey('j_hatta', 'Hatta on a budget')],
        'destinations': [
          {'name': 'Hatta', 'country': 'United Arab Emirates', 'count': 1, 'minAed': 850, 'coverPhoto': null},
        ],
        'suggested': [sara],
      });
    case 'GET /api/journeys/j_hatta':
      return json({'journey': journey('j_hatta', 'Hatta on a budget', detailed: true), 'related': []});
    case 'POST /api/journeys/j_hatta/going':
      return json({'going': true, 'goingCount': 4});
    case 'POST /api/creators/c_1/follow':
      return json({'following': true, 'followers': 1201});
    case 'POST /api/creators':
      return json({'creator': me});
    case 'GET /api/ammachi/status':
      return json({
        'llm': {'provider': 'offline', 'model': null},
        'tts': {'provider': 'none'},
      });
    case 'POST /api/ammachi/chat':
      final cite = jsonEncode({'journey': journey('j_hatta', 'Hatta on a budget')});
      final sse = [
        'event: meta\ndata: {"mode":"offline","voice":false}\n\n',
        'event: delta\ndata: {"text":"മലയും തണുപ്പും വേണോ കുഞ്ഞേ? "}\n\n',
        'event: cite\ndata: $cite\n\n',
        'event: delta\ndata: {"text":"Sara എഴുതിയ യാത്ര നോക്കൂ."}\n\n',
        'event: done\ndata: {"text":""}\n\n',
      ];
      return http.StreamedResponse(Stream.fromIterable(sse.map(utf8.encode)), 200, headers: {'content-type': 'text/event-stream'});
  }
  return json({'journeys': [], 'creators': [], 'destinations': [], 'plans': [], 'bookings': [], 'check': null});
});

Future<void> boot(WidgetTester tester, {bool signedIn = true}) async {
  SharedPreferences.setMockInitialValues(signedIn ? {'creator': jsonEncode(me)} : {});
  final session = await Session.init();
  Api.instance = Api(session, client: server());
  Reactions.instance = Reactions(Api.instance);
  tester.view.physicalSize = const Size(412 * 3, 892 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const TravelgramApp());
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUp(requests.clear);

  testWidgets('first launch asks for a profile, then shows the feed', (tester) async {
    await boot(tester, signedIn: false);
    expect(find.text('Trips worth copying.'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Test Traveller');
    await tester.enterText(find.widgetWithText(TextField, 'Mobile number'), '+971 50 123 4567');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    expect(requests, contains('POST /api/creators'));
    expect(find.text('Hatta on a budget'), findsWidgets);
  });

  testWidgets('feed shows trips with their creator, and Follow updates', (tester) async {
    await boot(tester);
    expect(requests, contains('GET /api/feed'));
    expect(find.text('Hatta on a budget'), findsWidgets);
    expect(find.text('Sara Al Mansoori'), findsWidgets);
    await tester.tap(find.bySemanticsLabel('Follow Sara Al Mansoori').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(requests, contains('POST /api/creators/c_1/follow'));
    expect(find.bySemanticsLabel('Following Sara Al Mansoori'), findsWidgets);
  });

  testWidgets('trip page shows places and expenses, and I’m going counts you in', (tester) async {
    await boot(tester);
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -350));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byType(PageView).first);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(seconds: 1));
    expect(requests, contains('GET /api/journeys/j_hatta'));
    expect(find.text('Hatta Dam', skipOffstage: false), findsWidgets);
    await tester.tap(find.widgetWithText(FilledButton, 'I’m going'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(requests, contains('POST /api/journeys/j_hatta/going'));
    expect(find.text('You’re going'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('Ammachi answers in Malayalam and credits the trip she cites', (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip('Chat with the AI consultant'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('ദുബായിൽ നിന്ന് 1000 ദിർഹത്തിന് ഒരു വീക്കെൻഡ്?'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(seconds: 1));
    expect(requests, contains('POST /api/ammachi/chat'));
    expect(find.textContaining('മലയും തണുപ്പും'), findsOneWidget);
    expect(find.text('by @sara.trails'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('the Desk tab gives the doc checker and trip planner their own space', (tester) async {
    await boot(tester);
    await tester.tap(find.bySemanticsLabel('Desk'));
    await tester.pump(const Duration(seconds: 1));
    expect(requests, contains('GET /api/me/documents'));
    expect(find.text('Smart document checker'), findsOneWidget);
    expect(find.text('Budget trip planner'), findsOneWidget);
    expect(find.text('Check my documents'), findsOneWidget);
    expect(find.byTooltip('Create a trip'), findsNothing); // Create lives on Home now
  });

  testWidgets('Create opens from the + on Home', (tester) async {
    await boot(tester);
    await tester.tap(find.byTooltip('Create a trip'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Track a trip'), findsOneWidget);
  });
}
