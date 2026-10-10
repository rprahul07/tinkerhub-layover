import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/models.dart';
import '../../theme/tg_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../home/post_card.dart';
import 'destination_screen.dart';
import 'search_screen.dart';

const _durations = [('Weekend', 1, 2), ('3–5 days', 3, 5), ('A week+', 6, null)];

/// Browse by place, budget and trip length.
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  List<Destination>? _destinations;
  List<Creator>? _creators;
  String? _error;
  int? _budget; // index into budgetBrackets
  int? _duration; // index into _durations
  List<Journey>? _results;
  bool _loadingResults = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final (d, c) = (await Api.instance.destinations(), await Api.instance.creators());
      if (mounted) {
        setState(() {
          _destinations = d;
          _creators = c;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _filter() async {
    if (_budget == null && _duration == null) {
      setState(() => _results = null);
      return;
    }
    setState(() => _loadingResults = true);
    final b = _budget == null ? null : budgetBrackets[_budget!];
    final d = _duration == null ? null : _durations[_duration!];
    try {
      final results = await Api.instance.journeys(TripFilter(minAed: b?.min, maxAed: b?.max, minDays: d?.$2, maxDays: d?.$3, sort: 'budget'));
      if (mounted) setState(() => _results = results);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _loadingResults = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Explore', style: TT.display(22, wght: 750))),
      body: RefreshIndicator(
        color: TG.accent,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Semantics(
                  button: true,
                  label: 'Search places, trips and people',
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: TG.surface, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, color: TG.muted, size: 20),
                          const SizedBox(width: 10),
                          ExcludeSemantics(child: Text('Places, trips, people', style: TT.ui(15, color: TG.faint))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(child: _ChipRow(label: 'Budget', options: [for (final b in budgetBrackets) b.label], selected: _budget, onSelect: (i) {
              setState(() => _budget = _budget == i ? null : i);
              _filter();
            })),
            SliverToBoxAdapter(child: _ChipRow(label: 'Length', options: [for (final d in _durations) d.$1], selected: _duration, onSelect: (i) {
              setState(() => _duration = _duration == i ? null : i);
              _filter();
            })),
            if (_results != null || _loadingResults) ...[
              SliverToBoxAdapter(
                child: SectionTitle(
                  _loadingResults ? 'Searching…' : plural(_results!.length, 'trip'),
                  action: 'Clear',
                  onAction: () {
                    setState(() {
                      _budget = null;
                      _duration = null;
                      _results = null;
                    });
                  },
                ),
              ),
              if (_results != null && _results!.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyView(icon: Icons.travel_explore_rounded, title: 'No trips match yet', body: 'Try a wider budget or a different length.'),
                )
              else if (_results != null)
                SliverList.builder(itemCount: _results!.length, itemBuilder: (context, i) => TripTile(journey: _results![i])),
            ] else if (_error != null && _destinations == null)
              SliverFillRemaining(hasScrollBody: false, child: ErrorView(message: _error!, onRetry: _load))
            else if (_destinations == null)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: TG.accent))))
            else ...[
              const SliverToBoxAdapter(child: SectionTitle('Destinations')),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.82),
                  delegate: SliverChildBuilderDelegate((context, i) => _DestinationCard(destination: _destinations![i]), childCount: _destinations!.length),
                ),
              ),
              if (_creators != null && _creators!.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SectionTitle('Creators to follow')),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 196,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _creators!.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, i) => _CreatorCard(creator: _creators![i]),
                    ),
                  ),
                ),
              ],
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.label, required this.options, required this.selected, required this.onSelect});
  final String label;
  final List<String> options;
  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 52,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 10, top: 9),
          child: Text(label, style: TT.ui(13, wght: 600, color: TG.muted)),
        ),
        for (var i = 0; i < options.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterPill(label: options[i], selected: selected == i, onTap: () => onSelect(i)),
          ),
      ],
    ),
  );
}

class _DestinationCard extends StatelessWidget {
  const _DestinationCard({required this.destination});
  final Destination destination;

  @override
  Widget build(BuildContext context) {
    final d = destination;
    return Pressable(
      semanticLabel: '${d.name}, ${d.country}. ${plural(d.count, 'trip')}, from ${money(d.minAed, 'AED')}',
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DestinationScreen(destination: d))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            TgImage(d.coverPhoto?.url, cacheWidth: 260),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC000000)],
                  stops: [0.45, 1],
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(d.name, style: TT.display(17, wght: 700, color: Colors.white)),
                  Text(
                    '${plural(d.count, 'trip')} · from ${moneyShort(d.minAed, 'AED')}',
                    style: TT.ui(12.5, wght: 550, color: Colors.white.withValues(alpha: 0.85)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreatorCard extends StatelessWidget {
  const _CreatorCard({required this.creator});
  final Creator creator;

  @override
  Widget build(BuildContext context) => Container(
    width: 150,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(border: Border.all(color: TG.line), borderRadius: BorderRadius.circular(14)),
    child: Column(
      children: [
        GestureDetector(onTap: () => openProfile(context, creator), child: Avatar(creator, size: 56)),
        const SizedBox(height: 8),
        Text(creator.name, style: TT.ui(14, wght: 650), maxLines: 1, overflow: TextOverflow.ellipsis),
        Text('${compactCount(creator.followers)} followers', style: TT.ui(12, color: TG.muted)),
        const Spacer(),
        FollowButton(creator, compact: true),
      ],
    ),
  );
}
