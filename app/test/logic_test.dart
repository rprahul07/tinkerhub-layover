import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:travelgram/data/models.dart';
import 'package:travelgram/data/session.dart';
import 'package:travelgram/features/create/draft.dart';
import 'package:travelgram/util/format.dart';

void main() {
  test('money formats each currency the way people read it', () {
    expect(money(1200, 'AED'), 'AED 1,200');
    expect(money(1234567, 'INR'), '₹12,34,567');
    expect(money(855, 'USD'), '\$855');
    expect(money(133, 'OMR'), 'OMR 133');
    expect(moneyShort(1500, 'AED'), 'AED 1.5k');
  });

  test('currency follows the destination country', () {
    expect(currencyForCountry('United Arab Emirates'), 'AED');
    expect(currencyForCountry('Oman'), 'OMR');
    expect(currencyForCountry('Georgia'), 'GEL');
    expect(currencyForCountry('Japan'), 'USD');
  });

  test('plural and season labels', () {
    expect(plural(1, 'day'), '1 day');
    expect(plural(3, 'country', 'countries'), '3 countries');
    expect(seasonLabel([11, 12, 1, 2]), 'Nov–Feb');
    expect(seasonLabel([]), 'Any time');
  });

  test('a tracked trip becomes a journey payload with expenses and custom fields', () async {
    SharedPreferences.setMockInitialValues({});
    await Session.init();
    final trip = TripDraft(title: 'Hatta weekend', destination: 'Hatta', country: 'United Arab Emirates', travelers: 2);
    trip.places.add(
      DraftPlace(
        name: 'Hatta Dam',
        lat: 24.8,
        lng: 56.1,
        day: 1,
        story: 'Kayaks on green water.',
        photos: [DraftPhoto(url: '/static/uploads/a.jpg')],
        expenses: [const Expense(category: 'activities', label: 'Kayak', amount: 60)],
        fields: [const Field('Entry fee', 'Free')],
      ),
    );
    trip.places.add(
      DraftPlace(name: 'Hatta Wadi Hub', lat: 24.79, lng: 56.12, day: 2, expenses: [const Expense(category: 'food', label: 'Lunch', amount: 90)]),
    );
    expect(trip.days, 2);
    expect(trip.spent, 150);

    final p = trip.toPayload('c_me');
    expect(p['creatorId'], 'c_me');
    expect(p['currency'], 'AED');
    expect(p['durationDays'], 2);
    expect(p['coverPhotoUrl'], '/static/uploads/a.jpg');
    final stops = p['stops'] as List;
    expect(stops, hasLength(2));
    expect((stops[0] as Map)['expenses'], [
      {'category': 'activities', 'label': 'Kayak', 'amount': 60},
    ]);
    expect((stops[0] as Map)['fields'], [
      {'label': 'Entry fee', 'value': 'Free'},
    ]);

    await trip.save();
    final restored = TripDraft.restore()!;
    expect(restored.places.first.expenses.single.amount, 60);
    expect(restored.places.first.photoUrls, ['/static/uploads/a.jpg']);
  });

  test('journey JSON with going and currency parses', () {
    final j = Journey.fromJson({
      'id': 'j1',
      'title': 'Liwa nights',
      'currency': 'AED',
      'budgetTotal': 900,
      'budgetAed': 900,
      'goingCount': 4,
      'isGoing': true,
      'creator': {'id': 'c1', 'name': 'Sara Al Mansoori', 'handle': 'sara'},
    });
    expect(j.goingCount, 4);
    expect(j.isGoing, isTrue);
    expect(j.creator.initials, 'SM');
  });
}
