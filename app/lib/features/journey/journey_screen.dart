import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api.dart';
import '../../data/models.dart';
import '../../data/reactions.dart';
import '../../theme/tg_theme.dart';
import '../../util/format.dart';
import '../../widgets/budget.dart';
import '../../widgets/common.dart';
import '../../widgets/route_map.dart';
import '../ammachi/ammachi_art.dart';
import '../ammachi/ammachi_screen.dart';
import '../booking/booking_sheet.dart';
import '../documents/doc_check_screen.dart';
import '../home/post_card.dart';
import '../planner/planner_screen.dart';
import 'photo_viewer.dart';

Future<void> openJourney(BuildContext context, Journey journey) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => JourneyScreen(initial: journey)));

/// A trip: renders immediately from the card that was tapped, then fills in
/// the itinerary, route and budget once they load.
class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key, required this.initial});
  final Journey initial;

  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen> {
  late Journey _journey = widget.initial;
  List<Journey> _related = const [];
  String? _error;
  int _photo = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final (journey, related) = await Api.instance.journey(widget.initial.id);
      if (mounted) {
        setState(() {
          _journey = journey;
          _related = related;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _openMaps(Journey j) async {
    final s = j.stops;
    if (s.isEmpty) return;
    String ll(Stop x) => '${x.lat},${x.lng}';
    final uri = s.length == 1
        ? Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': ll(s.first)})
        : Uri.https('www.google.com', '/maps/dir/', {
            'api': '1',
            'origin': ll(s.first),
            'destination': ll(s.last),
            if (s.length > 2) 'waypoints': s.sublist(1, s.length - 1).map(ll).join('|'),
          });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) showSnack(context, 'Couldn’t open Maps.');
  }

  @override
  Widget build(BuildContext context) {
    final height = math.min(MediaQuery.sizeOf(context).height * 0.52, 520.0);
    return ListenableBuilder(
      listenable: Reactions.instance,
      builder: (context, _) {
        final j = Reactions.instance.apply(_journey);
        final photos = j.photos.isEmpty && j.coverPhoto != null ? [j.coverPhoto!] : j.photos;
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: height,
                backgroundColor: TG.bg,
                foregroundColor: TG.ink,
                leading: const _CircleBack(),
                actions: [
                  _CircleIcon(icon: Icons.ios_share_outlined, tooltip: 'Share', onTap: () => shareTrip(j)),
                  _CircleIcon(
                    icon: j.saved ? Icons.bookmark : Icons.bookmark_border,
                    tooltip: j.saved ? 'Remove from saved' : 'Save',
                    onTap: () => toggleWithSnack(context, () => Reactions.instance.toggleSave(j), done: 'Saved.'),
                  ),
                  const SizedBox(width: 8),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      PageView.builder(
                        itemCount: photos.length,
                        onPageChanged: (i) => setState(() => _photo = i),
                        itemBuilder: (context, i) => GestureDetector(
                          onTap: () => PhotoViewer.open(context, photos, i),
                          child: i == 0
                              ? Hero(tag: 'trip-${j.id}', child: TgImage(photos[i].url, cacheWidth: 900, semanticLabel: photos[i].caption))
                              : TgImage(photos[i].url, cacheWidth: 900, semanticLabel: photos[i].caption),
                        ),
                      ),
                      if (photos.length > 1)
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < photos.length; i++)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: const EdgeInsets.symmetric(horizontal: 3),
                                  width: i == _photo ? 18 : 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: i == _photo ? 1 : 0.6),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(child: _Header(journey: j)),
              if (_error != null && !_journey.isDetailed)
                SliverToBoxAdapter(child: ErrorView(message: _error!, onRetry: _load))
              else if (!_journey.isDetailed)
                const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: TG.accent))),
                )
              else
                ..._body(j),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _body(Journey j) {
    final days = <int, List<(int, Stop)>>{};
    for (var i = 0; i < j.stops.length; i++) {
      days.putIfAbsent(j.stops[i].day, () => []).add((i, j.stops[i]));
    }
    final allPhotos = [for (final s in j.stops) ...s.photos];
    final credits = {
      for (final p in allPhotos)
        if (p.credit != null && p.credit!.author.isNotEmpty && p.credit!.license != 'Shared on Travelgram') '${p.credit!.author} (${p.credit!.license})',
    };

    return [
      if (j.fields.isNotEmpty) SliverToBoxAdapter(child: _GoodToKnow(fields: j.fields)),
      if ((j.story ?? '').isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Text(j.story!, style: TT.ui(15.5, height: 1.6, color: TG.ink2)),
          ),
        ),
      const SliverToBoxAdapter(child: SectionTitle('Itinerary')),
      for (final entry in days.entries) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('Day ${entry.key}', style: TT.label(12.5, color: TG.accent, wght: 700)),
          ),
        ),
        for (final (i, stop) in entry.value)
          SliverToBoxAdapter(
            child: _PlaceCard(
              journey: j,
              stop: stop,
              number: i + 1,
              currency: j.currency,
              onPhoto: stop.photos.isEmpty ? null : () => PhotoViewer.open(context, allPhotos, allPhotos.indexOf(stop.photos.first)),
            ),
          ),
      ],
      SliverToBoxAdapter(
        child: SectionTitle('Route', action: j.stops.isEmpty ? null : 'Open in Maps', onAction: () => _openMaps(j)),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: RouteMap(points: [for (final s in j.stops) RoutePoint(s.name, s.lat, s.lng, s.day)], height: 260),
          ),
        ),
      ),
      if (j.budget.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionTitle('Budget')),
        SliverToBoxAdapter(
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: BudgetBreakdown(journey: j)),
        ),
      ],
      SliverToBoxAdapter(child: _AmmachiRow(journey: j)),
      if (credits.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Photos: ${credits.join(', ')}. Via Wikimedia Commons.', style: TT.ui(11.5, color: TG.faint, height: 1.5)),
          ),
        ),
      if (_related.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SectionTitle('More like this')),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _related.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => TripGridCard(journey: _related[i], width: 150),
            ),
          ),
        ),
      ],
      SliverToBoxAdapter(child: SizedBox(height: 40 + MediaQuery.paddingOf(context).bottom)),
    ];
  }
}

class _CircleBack extends StatelessWidget {
  const _CircleBack();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back, size: 20), onPressed: () => Navigator.maybePop(context)),
    ),
  );
}

class _CircleIcon extends StatelessWidget {
  const _CircleIcon({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
    child: Material(
      color: Colors.white.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      child: IconButton(tooltip: tooltip, icon: Icon(icon, size: 20), onPressed: onTap),
    ),
  );
}

class _Header extends StatelessWidget {
  const _Header({required this.journey});
  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final j = journey;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Pressable(
                  semanticLabel: '${j.creator.name}, open profile',
                  onTap: () => openProfile(context, j.creator),
                  child: Row(
                    children: [
                      Avatar(j.creator, size: 40),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(j.creator.name, style: TT.ui(15, wght: 650), overflow: TextOverflow.ellipsis),
                            Text('@${j.creator.handle} · ${timeAgo(j.createdAt)}', style: TT.ui(12.5, color: TG.muted), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              FollowButton(j.creator, compact: true),
            ],
          ),
          const SizedBox(height: 16),
          Semantics(header: true, child: Text(j.title, style: TT.display(25, wght: 750))),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 16, color: TG.muted),
              const SizedBox(width: 4),
              Flexible(child: Text('${placeLine(j)} · Best ${seasonLabel(j.bestMonths)}', style: TT.ui(13.5, color: TG.muted))),
            ],
          ),
          const SizedBox(height: 12),
          Text(j.dek, style: TT.ui(15.5, color: TG.ink2, height: 1.5)),
          const SizedBox(height: 16),
          _Stats(journey: j),
          const SizedBox(height: 16),
          _Actions(journey: j),
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.journey});
  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final j = journey;
    final cells = [
      ('${j.durationDays}', j.durationDays == 1 ? 'day' : 'days'),
      ('${j.stopCount}', j.stopCount == 1 ? 'place' : 'places'),
      ('${j.travelers}', j.travelers == 1 ? 'traveller' : 'travellers'),
      (moneyShort(j.budgetTotal, j.currency), 'total'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: TG.surface, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (final (value, label) in cells)
            Expanded(
              child: Semantics(
                label: '$value $label',
                child: ExcludeSemantics(
                  child: Column(
                    children: [
                      Text(value, style: TT.display(17, wght: 750)),
                      const SizedBox(height: 2),
                      Text(label, style: TT.ui(12, color: TG.muted)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.journey});
  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final j = journey;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: j.isGoing ? TG.going : TG.ink),
                onPressed: () => toggleWithSnack(context, () => Reactions.instance.toggleGoing(j), done: 'Added to your trips.'),
                icon: Icon(j.isGoing ? Icons.check_rounded : Icons.flight_takeoff_rounded, size: 19),
                label: Text(j.isGoing ? 'You’re going' : 'I’m going'),
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: j.liked ? 'Unlike, ${j.likes} likes' : 'Like, ${j.likes} likes',
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(64, 50), padding: const EdgeInsets.symmetric(horizontal: 12)),
                onPressed: () => toggleWithSnack(context, () => Reactions.instance.toggleLike(j)),
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      Icon(j.liked ? Icons.favorite : Icons.favorite_border, color: j.liked ? TG.like : TG.ink, size: 20),
                      const SizedBox(width: 6),
                      Text(compactCount(j.likes)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '${compactCount(j.goingCount)} people are going',
                style: TT.ui(13, color: j.isGoing ? TG.going : TG.muted, wght: 550),
              ),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlannerScreen(
                    budget: j.budgetAed,
                    days: j.durationDays,
                    travelers: j.travelers,
                    interests: j.tags,
                  ),
                ),
              ),
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('Plan this for me'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DocCheckScreen(journey: j))),
          icon: const Icon(Icons.fact_check_outlined, size: 18),
          label: const Text('Check my visa documents'),
        ),
      ],
    );
  }
}

class _GoodToKnow extends StatelessWidget {
  const _GoodToKnow({required this.fields});
  final List<Field> fields;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
    child: Container(
      decoration: BoxDecoration(border: Border.all(color: TG.line), borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 120, child: Text(fields[i].label, style: TT.ui(13.5, color: TG.muted))),
                  Expanded(child: Text(fields[i].value, style: TT.ui(13.5, wght: 550))),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _PlaceCard extends StatelessWidget {
  const _PlaceCard({required this.journey, required this.stop, required this.number, required this.currency, this.onPhoto});
  final Journey journey;
  final Stop stop;
  final int number;
  final String currency;
  final VoidCallback? onPhoto;

  @override
  Widget build(BuildContext context) {
    final s = stop;
    final spent = s.expenses.fold<int>(0, (t, e) => t + e.amount);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: TG.line), borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.photos.isNotEmpty)
              GestureDetector(
                onTap: onPhoto,
                child: AspectRatio(aspectRatio: 16 / 10, child: TgImage(s.photos.first.url, cacheWidth: 700, semanticLabel: s.name)),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(color: TG.ink, shape: BoxShape.circle),
                        child: Text('$number', style: TT.ui(12, wght: 700, color: Colors.white)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(s.name, style: TT.display(16.5, wght: 700))),
                      if (spent > 0) Text(money(spent, currency), style: TT.ui(14, wght: 650)),
                    ],
                  ),
                  if (s.story.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(s.story, style: TT.ui(14.5, color: TG.ink2, height: 1.55)),
                  ],
                  if (s.tip.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: TG.accentSoft, borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.lightbulb_outline_rounded, size: 17, color: TG.accent),
                          const SizedBox(width: 8),
                          Expanded(child: Text(s.tip, style: TT.ui(13.5, color: TG.ink2))),
                        ],
                      ),
                    ),
                  ],
                  if (s.fields.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final f in s.fields)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: TG.surface, borderRadius: BorderRadius.circular(8)),
                            child: Text('${f.label}: ${f.value}', style: TT.ui(12.5, wght: 550, color: TG.ink2)),
                          ),
                      ],
                    ),
                  ],
                  if (s.expenses.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (final e in s.expenses)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(TG.budgetIcons[e.category], size: 15, color: TG.muted),
                            const SizedBox(width: 8),
                            Expanded(child: Text(e.label, style: TT.ui(13, color: TG.muted))),
                            Text(money(e.amount, currency), style: TT.ui(13, color: TG.ink2, wght: 550)),
                            if (e.category != 'food' && e.category != 'other' && e.amount > 0) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 30,
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(52, 30),
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    backgroundColor: TG.success,
                                    textStyle: TT.ui(12.5, wght: 650),
                                  ),
                                  onPressed: () => showBookingSheet(context, journey: journey, stop: s, expense: e),
                                  child: const Text('Book'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AmmachiRow extends StatelessWidget {
  const _AmmachiRow({required this.journey});
  final Journey journey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: TG.surface, borderRadius: BorderRadius.circular(16)),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: const ClipOval(child: OverflowBox(maxWidth: 74, maxHeight: 74, child: AmmachiAvatar(mood: AmmachiMood.idle, size: 74))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('AI Consultant', style: TT.ui(15, wght: 650)),
                  Text('Hear a summary of this trip in Malayalam, or ask anything about it.', style: TT.ui(13, color: TG.muted)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(40, 38), backgroundColor: Colors.white),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AmmachiScreen(contextJourney: journey, initialPrompt: 'ഈ യാത്രയുടെ ഒരു ചുരുക്കം പറയാമോ?'),
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded, size: 18),
                        label: const Text('Listen'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => AmmachiScreen(contextJourney: journey))),
                        child: const Text('Ask'),
                      ),
                    ],
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
