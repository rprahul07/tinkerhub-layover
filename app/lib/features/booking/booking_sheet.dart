import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/api.dart';
import '../../data/models.dart';
import '../../theme/tg_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';

/// Book a stay, activity or ride from a trip's itinerary. Payment is a demo.
Future<void> showBookingSheet(BuildContext context, {required Journey journey, required Stop stop, required Expense expense}) =>
    showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (_) => _BookingSheet(journey: journey, stop: stop, expense: expense));

class _BookingSheet extends StatefulWidget {
  const _BookingSheet({required this.journey, required this.stop, required this.expense});
  final Journey journey;
  final Stop stop;
  final Expense expense;

  @override
  State<_BookingSheet> createState() => _BookingSheetState();
}

class _BookingSheetState extends State<_BookingSheet> {
  DateTime _date = DateTime.now().add(const Duration(days: 14));
  late int _guests = widget.journey.travelers.clamp(1, 10);
  bool _paying = false;
  Booking? _done;

  bool get _perStay => widget.expense.category == 'stay';
  int get _total => widget.expense.amount * (_perStay ? 1 : _guests);
  String get _cur => widget.journey.currency;

  Future<void> _pay() async {
    setState(() => _paying = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 900)); // the demo "card processor"
      final b = await Api.instance.book(
        journeyId: widget.journey.id,
        item: '${widget.expense.label} · ${widget.stop.name}',
        category: widget.expense.category,
        amount: widget.expense.amount,
        guests: _guests,
        date: _date.toIso8601String().substring(0, 10),
      );
      HapticFeedback.heavyImpact();
      setState(() => _done = b);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.expense;
    final done = _done;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: done != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_rounded, color: TG.success, size: 56),
                const SizedBox(height: 10),
                Text('Booked!', style: TT.display(22, wght: 750)),
                const SizedBox(height: 4),
                Text('${done.item}\n${done.date} · ${plural(done.guests, 'guest')} · ${done.totalLabel}', textAlign: TextAlign.center, style: TT.ui(14, color: TG.muted, height: 1.5)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: TG.surface, borderRadius: BorderRadius.circular(10)),
                  child: Text('Booking ref ${done.ref}', style: TT.ui(15, wght: 700)),
                ),
                const SizedBox(height: 16),
                SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(color: TG.budgetColors[e.category]!.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Icon(TG.budgetIcons[e.category], color: TG.budgetColors[e.category]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.label, style: TT.display(18, wght: 700)),
                          Text('${widget.stop.name} · as on @${widget.journey.creator.handle}’s trip', style: TT.ui(13, color: TG.muted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)));
                          if (d != null) setState(() => _date = d);
                        },
                        icon: const Icon(Icons.calendar_today_outlined, size: 18),
                        label: Text('${_date.day} ${monthShort[_date.month - 1]} ${_date.year}'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
                        child: Row(
                          children: [
                            IconButton(tooltip: 'Fewer guests', onPressed: _guests > 1 ? () => setState(() => _guests--) : null, icon: const Icon(Icons.remove, size: 18)),
                            Expanded(child: Text(plural(_guests, 'guest'), textAlign: TextAlign.center, style: TT.ui(14, wght: 600))),
                            IconButton(tooltip: 'More guests', onPressed: _guests < 10 ? () => setState(() => _guests++) : null, icon: const Icon(Icons.add, size: 18)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Text(_perStay ? 'Total' : '${money(e.amount, _cur)} × $_guests', style: TT.ui(14, color: TG.muted))),
                    Text(money(_total, _cur), style: TT.display(22, wght: 800)),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: TG.surface, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Icon(Icons.credit_card_rounded, color: TG.muted),
                      const SizedBox(width: 10),
                      Expanded(child: Text('Demo card •••• 4242', style: TT.ui(14, wght: 600))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
                        child: Text('DEMO', style: TT.ui(11, wght: 700, color: const Color(0xFF92400E))),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text('Demo payment — no money is charged.', style: TT.ui(12, color: TG.muted), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: TG.success),
                  onPressed: _paying ? null : _pay,
                  child: _paying
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text('Pay ${money(_total, _cur)}'),
                ),
              ],
            ),
    );
  }
}
