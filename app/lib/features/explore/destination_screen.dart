import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/models.dart';
import '../../theme/tg_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../home/post_card.dart';

/// Every trip people posted for one destination, filterable by budget.
class DestinationScreen extends StatefulWidget {
  const DestinationScreen({super.key, required this.destination});
  final Destination destination;

  @override
  State<DestinationScreen> createState() => _DestinationScreenState();
}

class _DestinationScreenState extends State<DestinationScreen> {
  List<Journey>? _trips;
  String? _error;
  int? _budget;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    final b = _budget == null ? null : budgetBrackets[_budget!];
    try {
      final trips = await Api.instance.journeys(TripFilter(destination: widget.destination.name, minAed: b?.min, maxAed: b?.max, sort: 'popular'));
      if (mounted) setState(() => _trips = trips);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.destination;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 240,
            foregroundColor: Colors.white,
            backgroundColor: TG.ink,
            title: Text(d.name, style: TT.display(18, wght: 700, color: Colors.white)),
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  TgImage(d.coverPhoto?.url, cacheWidth: 600),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x66000000), Colors.transparent, Color(0xB3000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    bottom: 16,
                    child: Text(
                      '${d.country} · ${plural(d.count, 'trip')} · from ${money(d.minAed, 'AED')}',
                      style: TT.ui(14, wght: 550, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                itemCount: budgetBrackets.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => FilterPill(
                  label: budgetBrackets[i].label,
                  selected: _budget == i,
                  onTap: () {
                    setState(() => _budget = _budget == i ? null : i);
                    _load();
                  },
                ),
              ),
            ),
          ),
          if (_error != null && _trips == null)
            SliverFillRemaining(hasScrollBody: false, child: ErrorView(message: _error!, onRetry: _load))
          else if (_trips == null)
            const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: TG.accent))))
          else if (_trips!.isEmpty)
            const SliverToBoxAdapter(child: EmptyView(icon: Icons.filter_alt_off_outlined, title: 'No trips in this budget', body: 'Try another budget range.'))
          else
            SliverList.builder(itemCount: _trips!.length, itemBuilder: (context, i) => PostCard(journey: _trips![i])),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}
