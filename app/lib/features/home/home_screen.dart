import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/models.dart';
import '../../theme/tg_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../ammachi/ammachi_screen.dart';
import '../explore/destination_screen.dart';
import '../explore/search_screen.dart';
import '../explore/server_sheet.dart';
import '../planner/planner_screen.dart';
import '../documents/doc_check_screen.dart';
import 'post_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onExplore, required this.onCreate});
  final VoidCallback onExplore;
  final VoidCallback onCreate;

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  bool _following = false;
  final _feeds = <bool, Feed>{};
  final _errors = <bool, String>{};
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load(false);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load(bool following) async {
    setState(() => _errors.remove(following));
    try {
      final feed = await Api.instance.feed(following: following);
      if (mounted) setState(() => _feeds[following] = feed);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errors[following] = e.message);
    }
  }

  /// After posting: show the new trip at the top.
  Future<void> refresh() async {
    await _load(_following);
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic);
  }

  void _switch(bool following) {
    setState(() => _following = following);
    if (!_feeds.containsKey(following)) _load(following);
  }

  @override
  Widget build(BuildContext context) {
    final feed = _feeds[_following];
    final error = _errors[_following];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: GestureDetector(
          onLongPress: () => showServerSheet(context),
          child: Text('Travelgram', style: TT.display(23, wght: 800, spacing: -0.04)),
        ),
        actions: [
          IconButton(
            tooltip: 'Create a trip',
            icon: const Icon(Icons.add_box_outlined),
            onPressed: widget.onCreate,
          ),
          IconButton(
            tooltip: 'Search',
            icon: const Icon(Icons.search_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchScreen())),
          ),
          IconButton(
            tooltip: 'Chat with the AI consultant',
            icon: const Icon(Icons.chat_bubble_outline_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AmmachiScreen())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: TG.accent,
        onRefresh: () => _load(_following),
        child: CustomScrollView(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _Tabs(following: _following, onChanged: _switch)),
            if (!_following) const SliverToBoxAdapter(child: PlannerBanner()),
            if (!_following) const SliverToBoxAdapter(child: _DocsBanner()),
            if (feed != null && feed.destinations.isNotEmpty && !_following)
              SliverToBoxAdapter(child: _DestinationChips(destinations: feed.destinations)),
            if (error != null && feed == null)
              SliverFillRemaining(hasScrollBody: false, child: ErrorView(message: error, onRetry: () => _load(_following)))
            else if (feed == null)
              const SliverToBoxAdapter(child: _FeedSkeleton())
            else if (feed.journeys.isEmpty && _following)
              SliverToBoxAdapter(child: _FollowSuggestions(creators: feed.suggested, onExplore: widget.onExplore))
            else
              SliverList.builder(itemCount: feed.journeys.length, itemBuilder: (context, i) => PostCard(journey: feed.journeys[i])),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.following, required this.onChanged});
  final bool following;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool value) {
      final on = following == value;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: InkWell(
            onTap: () => onChanged(value),
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? TG.ink : TG.line, width: on ? 2 : 1))),
              child: Text(label, style: TT.ui(14.5, wght: on ? 650 : 500, color: on ? TG.ink : TG.muted)),
            ),
          ),
        ),
      );
    }

    return Row(children: [tab('For you', false), tab('Following', true)]);
  }
}

/// The budget planner, front and centre: the reason to install the app.
class PlannerBanner extends StatelessWidget {
  const PlannerBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Pressable(
        semanticLabel: 'Plan a trip on your budget with the AI consultant',
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlannerScreen())),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          decoration: BoxDecoration(color: TG.ink, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Plan a trip on your budget', style: TT.display(17, wght: 700, color: Colors.white)),
                    const SizedBox(height: 4),
                    Text(
                      'Tell the AI consultant what you can spend. It builds a day-by-day plan from real trips and real prices.',
                      style: TT.ui(13.5, color: Colors.white70, height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [for (final s in ['AED 500 · 1 day', 'AED 1,500 · weekend', 'AED 5,000 · 5 days']) _Hint(s)],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(color: TG.accent, shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
    child: Text(text, style: TT.ui(12, wght: 550, color: Colors.white)),
  );
}

class _DestinationChips extends StatelessWidget {
  const _DestinationChips({required this.destinations});
  final List<Destination> destinations;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 58,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      itemCount: destinations.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, i) {
        final d = destinations[i];
        return FilterPill(
          label: d.name,
          icon: Icons.place_outlined,
          selected: false,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DestinationScreen(destination: d))),
        );
      },
    ),
  );
}

class _FollowSuggestions extends StatelessWidget {
  const _FollowSuggestions({required this.creators, required this.onExplore});
  final List<Creator> creators;
  final VoidCallback onExplore;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const EmptyView(
          icon: Icons.people_outline_rounded,
          title: 'Follow travellers you trust',
          body: 'Their new trips will show up here, newest first.',
        ),
        const SectionTitle('Suggested for you', padding: EdgeInsets.fromLTRB(16, 0, 16, 8)),
        for (final c in creators)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            leading: Avatar(c, size: 44),
            title: Text(c.name, style: TT.ui(15, wght: 650)),
            subtitle: Text('${c.home} · ${compactCount(c.followers)} followers', style: TT.ui(13, color: TG.muted)),
            trailing: FollowButton(c, compact: true),
            onTap: () => openProfile(context, c),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton(onPressed: onExplore, child: const Text('Explore trips')),
        ),
      ],
    );
  }
}

class _FeedSkeleton extends StatelessWidget {
  const _FeedSkeleton();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [Skeleton(width: 38, height: 38, radius: 19), SizedBox(width: 10), Skeleton(width: 140)]),
        SizedBox(height: 12),
        AspectRatio(aspectRatio: 4 / 5, child: Skeleton(height: double.infinity, radius: 0)),
        SizedBox(height: 12),
        Skeleton(width: 220, height: 18),
        SizedBox(height: 8),
        Skeleton(width: 180),
      ],
    ),
  );
}

class _DocsBanner extends StatelessWidget {
  const _DocsBanner();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    child: Material(
      color: TG.goingSoft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DocCheckScreen())),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              const Icon(Icons.fact_check_outlined, color: TG.going, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Visa ready? Get a free score', style: TT.ui(15, wght: 700)),
                    Text('Add 4 documents \u2014 the AI checks them in seconds.', style: TT.ui(13, color: TG.ink2)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: TG.going),
            ],
          ),
        ),
      ),
    ),
  );
}
