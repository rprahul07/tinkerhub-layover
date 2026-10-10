import 'dart:math' as math;

const monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const monthShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// Indian digit grouping: 1234567 → 12,34,567.
String groupIndian(int n) {
  final neg = n < 0;
  final s = n.abs().toString();
  if (s.length <= 3) return '${neg ? '-' : ''}$s';
  final last3 = s.substring(s.length - 3);
  var rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${neg ? '-' : ''}${parts.join(',')},$last3';
}

/// Standard grouping: 1234567 → 1,234,567.
String groupThousands(int n) {
  final s = n.abs().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return n < 0 ? '-$s' : s;
}

const _symbols = {'INR': '₹', 'USD': '\$', 'EUR': '€', 'GBP': '£'};

/// "AED 1,200", "₹12,000", "$855", "OMR 133".
String money(int amount, String currency) {
  final digits = currency == 'INR' ? groupIndian(amount) : groupThousands(amount);
  final symbol = _symbols[currency];
  return symbol != null ? '$symbol$digits' : '$currency $digits';
}

/// "AED 1.2k" for tight spaces.
String moneyShort(int amount, String currency) {
  String n;
  if (amount >= 100000 && currency == 'INR') {
    n = '${(amount / 100000).toStringAsFixed(amount % 100000 == 0 ? 0 : 1)}L';
  } else if (amount >= 1000) {
    n = '${(amount / 1000).toStringAsFixed(amount % 1000 == 0 || amount >= 10000 ? 0 : 1)}k';
  } else {
    n = '$amount';
  }
  final symbol = _symbols[currency];
  return symbol != null ? '$symbol$n' : '$currency $n';
}

String compactCount(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k' : '$n';

String plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  if (d.inDays < 60) return '${d.inDays ~/ 7}w';
  return '${monthShort[t.month - 1]} ${t.year}';
}

/// "Jun–Sep" style season ranges from a list of month numbers.
String seasonLabel(List<int> months) {
  if (months.isEmpty) return 'Any time';
  if (months.length >= 12) return 'All year';
  final sorted = [...months]..sort();
  final start = sorted.firstWhere((m) => !sorted.contains(m == 1 ? 12 : m - 1), orElse: () => sorted.first);
  var end = start;
  while (sorted.contains(end == 12 ? 1 : end + 1) && (end == 12 ? 1 : end + 1) != start) {
    end = end == 12 ? 1 : end + 1;
  }
  return start == end ? monthShort[start - 1] : '${monthShort[start - 1]}–${monthShort[end - 1]}';
}

/// Budget brackets for browsing, in AED.
class BudgetBracket {
  const BudgetBracket(this.label, this.min, this.max);
  final String label;
  final int? min;
  final int? max;
}

const budgetBrackets = [
  BudgetBracket('Under AED 1k', null, 1000),
  BudgetBracket('AED 1–3k', 1000, 3000),
  BudgetBracket('AED 3–6k', 3000, 6000),
  BudgetBracket('AED 6k+', 6000, null),
];

/// Currencies people pick when tracking or planning.
const currencies = ['AED', 'USD', 'INR', 'OMR', 'SAR', 'QAR', 'EUR', 'GBP', 'GEL'];

String currencyForCountry(String country) => switch (country) {
  'United Arab Emirates' || 'UAE' => 'AED',
  'Oman' => 'OMR',
  'India' => 'INR',
  'Saudi Arabia' => 'SAR',
  'Qatar' => 'QAR',
  'Georgia' => 'GEL',
  'United Kingdom' => 'GBP',
  'France' || 'Germany' || 'Italy' || 'Spain' => 'EUR',
  '' => 'AED',
  _ => 'USD',
};

/// Haversine distance in km.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}
