import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/models.dart';
import '../../data/reactions.dart';
import '../../data/session.dart';
import '../../theme/tg_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../explore/server_sheet.dart';
import '../home/post_card.dart';
import '../planner/planner_screen.dart';

/// A creator's profile. Without [creatorId] it's the signed-in user's own,
/// with Trips · Going · Saved · Plans.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.creatorId, this.initial, this.onCreate});
  final String? creatorId;
  final Creator? initial;
  final VoidCallback? onCreate;

  @override
  State<ProfileScreen> createState() => ProfileScreenState();
}

class ProfileScreenState extends State<ProfileScreen> {
  CreatorProfile? _profile;
  List<Journey>? _going;
  List<Journey>? _saved;
  List<TripPlan>? _plans;
  String? _error;
  int _tab = 0;
  int _seenVersion = -1;

  String? get _id => widget.creatorId ?? Session.instance.creator?.id;
  bool get _mine => widget.creatorId == null || widget.creatorId == Session.instance.creator?.id;

  @override
  void initState() {
    super.initState();
    refresh();
    if (_mine) Reactions.instance.addListener(_onReactions);
  }

  @override
  void dispose() {
    Reactions.instance.removeListener(_onReactions);
    super.dispose();
  }

  /// Going/saved lists change when you tap elsewhere; reload them lazily.
  void _onReactions() {
    if (Reactions.instance.version != _seenVersion && mounted) _loadLists();
  }

  Future<void> refresh() async {
    final id = _id;
    if (id == null) return;
    try {
      final p = await Api.instance.creator(id);
      if (!mounted) return;
      setState(() {
        _profile = p;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
    if (_mine) await _loadLists();
  }

  Future<void> _loadLists() async {
    _seenVersion = Reactions.instance.version;
    try {
      final results = await Future.wait([Api.instance.going(), Api.instance.saved(), Api.instance.myPlans()]);
      if (!mounted) return;
      setState(() {
        _going = results[0] as List<Journey>;
        _saved = results[1] as List<Journey>;
        _plans = results[2] as List<TripPlan>;
      });
    } on ApiException {
      // The profile still shows; the tabs show their empty state.
    }
  }

  @override
  Widget build(BuildContext context) {
    final creator = _profile?.creator ?? widget.initial ?? (_mine ? Session.instance.creator : null);
    final tabs = _mine ? const ['Trips', 'Going', 'Saved', 'Plans'] : const ['Trips'];
    return Scaffold(
      appBar: AppBar(
        title: Text(creator == null ? '' : '@${creator.handle}', style: TT.display(17, wght: 700)),
        actions: [
          if (_mine)
            IconButton(tooltip: 'Server settings', icon: const Icon(Icons.settings_outlined), onPressed: () => showServerSheet(context)),
        ],
      ),
      body: RefreshIndicator(
        color: TG.accent,
        onRefresh: refresh,
        child: CustomScrollView(
          slivers: [
            if (creator != null) SliverToBoxAdapter(child: _Header(creator: creator, profile: _profile, mine: _mine, onCreate: widget.onCreate)),
            if (_error != null && _profile == null)
              SliverFillRemaining(hasScrollBody: false, child: ErrorView(message: _error!, onRetry: refresh))
            else ...[
              if (tabs.length > 1)
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabsHeader(
                    tabs: tabs,
                    selected: _tab,
                    counts: [_profile?.journeys.length, _going?.length, _saved?.length, _plans?.length],
                    onTap: (i) => setState(() => _tab = i),
                  ),
                ),
              ..._body(),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _body() {
    if (_tab == 3) {
      final plans = _plans;
      if (plans == null) return [const SliverToBoxAdapter(child: _GridSkeleton())];
      if (plans.isEmpty) {
        return [
          SliverToBoxAdapter(
            child: EmptyView(
              icon: Icons.savings_outlined,
              title: 'No plans yet',
              body: 'Tell the AI consultant your budget and it’ll build a trip from real ones in the community.',
              action: FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlannerScreen())),
                child: const Text('Plan a trip'),
              ),
            ),
          ),
        ];
      }
      return [
        SliverList.separated(
          itemCount: plans.length,
          separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
          itemBuilder: (context, i) {
            final p = plans[i];
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: TG.accentSoft, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.savings_outlined, color: TG.accent),
              ),
              title: Text(p.title, style: TT.ui(15, wght: 650), maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text('${plural(p.dayCount, 'day')} · ${plural(p.travelers, 'traveller')} · ${p.totalLabel}', style: TT.ui(13, color: TG.muted)),
              trailing: const Icon(Icons.chevron_right_rounded, color: TG.faint),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlanScreen(plan: p))),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ];
    }

    final (list, empty) = switch (_tab) {
      1 => (
        _going,
        const EmptyView(
          icon: Icons.flight_takeoff,
          title: 'Nowhere yet',
          body: 'Tap “I’m going” on a trip you want to do. It’ll be waiting here, with everything you need.',
        ),
      ),
      2 => (_saved, const EmptyView(icon: Icons.bookmark_border_rounded, title: 'Nothing saved', body: 'Save trips to come back to them later.')),
      _ => (
        _profile?.journeys,
        EmptyView(
          icon: Icons.map_outlined,
          title: _mine ? 'Post your first trip' : 'No trips yet',
          body: _mine ? 'Track the places, photos and money as you travel, then share it.' : 'When they post a trip, it shows up here.',
          action: _mine && widget.onCreate != null ? FilledButton(onPressed: widget.onCreate, child: const Text('Track a trip')) : null,
        ),
      ),
    };
    if (list == null) return [const SliverToBoxAdapter(child: _GridSkeleton())];
    if (list.isEmpty) return [SliverToBoxAdapter(child: empty)];
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 220, mainAxisSpacing: 16, crossAxisSpacing: 12, childAspectRatio: 0.62),
          delegate: SliverChildBuilderDelegate((context, i) => TripGridCard(journey: list[i]), childCount: list.length),
        ),
      ),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.creator, required this.profile, required this.mine, this.onCreate});
  final Creator creator;
  final CreatorProfile? profile;
  final bool mine;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Reactions.instance,
      builder: (context, _) {
        final c = Reactions.instance.applyCreator(creator);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(c, size: 76),
                  const SizedBox(width: 20),
                  _Count(value: profile?.journeys.length ?? c.trips, label: 'Trips'),
                  _Count(value: c.followers, label: 'Followers'),
                  _Count(value: c.following, label: 'Following'),
                ],
              ),
              const SizedBox(height: 12),
              Text(c.name, style: TT.display(18, wght: 700)),
              if (c.home.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.place_outlined, size: 15, color: TG.muted),
                    const SizedBox(width: 3),
                    Text(c.home, style: TT.ui(13.5, color: TG.muted)),
                    if ((profile?.countries ?? 0) > 0) Text(' · ${plural(profile!.countries, 'country', 'countries')}', style: TT.ui(13.5, color: TG.muted)),
                  ],
                ),
              ],
              if (c.bio.isNotEmpty) ...[const SizedBox(height: 8), Text(c.bio, style: TT.ui(14.5, height: 1.45))],
              const SizedBox(height: 14),
              if (mine)
                Row(
                  children: [
                    if (onCreate != null)
                      Expanded(
                        child: FilledButton.icon(onPressed: onCreate, icon: const Icon(Icons.add, size: 18), label: const Text('Track a trip')),
                      ),
                    if (onCreate != null) const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(48, 50)),
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlannerScreen())),
                        icon: const Icon(Icons.savings_outlined, size: 18),
                        label: const Text('Plan on a budget'),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(width: double.infinity, child: FollowButton(c)),
            ],
          ),
        );
      },
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      label: '$value $label',
      child: ExcludeSemantics(
        child: Column(
          children: [
            Text(compactCount(value), style: TT.display(18, wght: 750)),
            const SizedBox(height: 2),
            Text(label, style: TT.ui(12.5, color: TG.muted)),
          ],
        ),
      ),
    ),
  );
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader({required this.tabs, required this.selected, required this.counts, required this.onTap});
  final List<String> tabs;
  final int selected;
  final List<int?> counts;
  final ValueChanged<int> onTap;

  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
    color: TG.bg,
    child: Row(
      children: [
        for (final (i, t) in tabs.indexed)
          Expanded(
            child: Semantics(
              selected: i == selected,
              button: true,
              label: '$t${counts[i] == null ? '' : ', ${counts[i]}'}',
              child: InkWell(
                onTap: () => onTap(i),
                child: ExcludeSemantics(
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: i == selected ? TG.ink : TG.line, width: i == selected ? 2 : 1)),
                    ),
                    child: Text(t, style: TT.ui(14, wght: i == selected ? 700 : 500, color: i == selected ? TG.ink : TG.muted)),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  @override
  bool shouldRebuild(_TabsHeader old) => old.selected != selected || old.counts.toString() != counts.toString() || old.tabs != tabs;
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        for (var i = 0; i < 2; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [AspectRatio(aspectRatio: 4 / 5, child: Skeleton(radius: 12)), SizedBox(height: 8), Skeleton(width: 120)],
            ),
          ),
        ],
      ],
    ),
  );
}
