import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/api.dart';
import '../../data/models.dart';
import '../../data/reactions.dart';
import '../../theme/tg_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../journey/journey_screen.dart';
import '../profile/profile_screen.dart';

String tripMeta(Journey j) => '${plural(j.durationDays, 'day')} · ${plural(j.stopCount, 'place')} · ${money(j.budgetTotal, j.currency)} for ${j.travelers}';

String placeLine(Journey j) => j.country.isEmpty || j.country == j.region ? j.region : '${j.region}, ${j.country == 'United Arab Emirates' ? 'UAE' : j.country}';

/// Rebuilds when likes/saves/going/follows change anywhere in the app.
class ReactiveJourney extends StatelessWidget {
  const ReactiveJourney({super.key, required this.journey, required this.builder});
  final Journey journey;
  final Widget Function(BuildContext context, Journey j) builder;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: Reactions.instance, builder: (context, _) => builder(context, Reactions.instance.apply(journey)));
}

Future<void> toggleWithSnack(BuildContext context, Future<Object?> Function() action, {String? done}) async {
  HapticFeedback.selectionClick();
  try {
    final result = await action();
    if (done != null && result == true && context.mounted) showSnack(context, done);
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, e.message);
  }
}

void shareTrip(Journey j) {
  SharePlus.instance.share(
    ShareParams(
      subject: '${j.title} — on Travelgram',
      text: '“${j.title}” by ${j.creator.name} on Travelgram\n${j.dek}\n${tripMeta(j)}',
    ),
  );
}

void openProfile(BuildContext context, Creator c) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileScreen(creatorId: c.id, initial: c)));

/// A trip post in the feed.
class PostCard extends StatefulWidget {
  const PostCard({super.key, required this.journey});
  final Journey journey;

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    return ReactiveJourney(
      journey: widget.journey,
      builder: (context, j) {
        final photos = j.photos.isEmpty && j.coverPhoto != null ? [j.coverPhoto!] : j.photos;
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Pressable(
                        semanticLabel: '${j.creator.name}, open profile',
                        onTap: () => openProfile(context, j.creator),
                        child: Row(
                          children: [
                            Avatar(j.creator, size: 38),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(j.creator.name, style: TT.ui(14.5, wght: 650), overflow: TextOverflow.ellipsis),
                                  Text('${placeLine(j)} · ${timeAgo(j.createdAt)}', style: TT.ui(12.5, color: TG.muted), overflow: TextOverflow.ellipsis),
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
              ),
              GestureDetector(
                onTap: () => openJourney(context, j),
                onDoubleTap: () {
                  if (!j.liked) toggleWithSnack(context, () => Reactions.instance.toggleLike(j));
                },
                child: AspectRatio(
                  aspectRatio: 4 / 5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      PageView.builder(
                        itemCount: photos.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (context, i) => i == 0
                            ? Hero(tag: 'trip-${j.id}', child: TgImage(photos[i].url, cacheWidth: 600, semanticLabel: photos[i].caption))
                            : TgImage(photos[i].url, cacheWidth: 600, semanticLabel: photos[i].caption),
                      ),
                      if (photos.length > 1)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                            decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(12)),
                            child: Text('${_page + 1}/${photos.length}', style: TT.ui(12, wght: 600, color: Colors.white)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
                child: Row(
                  children: [
                    _Action(
                      icon: j.liked ? Icons.favorite : Icons.favorite_border,
                      color: j.liked ? TG.like : TG.ink,
                      label: compactCount(j.likes),
                      semantics: j.liked ? 'Unlike, ${j.likes} likes' : 'Like, ${j.likes} likes',
                      onTap: () => toggleWithSnack(context, () => Reactions.instance.toggleLike(j)),
                    ),
                    _Action(
                      icon: j.isGoing ? Icons.flight_takeoff : Icons.flight_takeoff_outlined,
                      color: j.isGoing ? TG.going : TG.ink,
                      label: j.isGoing ? 'Going · ${compactCount(j.goingCount)}' : '${compactCount(j.goingCount)} going',
                      semantics: j.isGoing ? 'You’re going. ${j.goingCount} going' : 'I’m going. ${j.goingCount} going',
                      onTap: () => toggleWithSnack(context, () => Reactions.instance.toggleGoing(j), done: 'Added to your trips.'),
                    ),
                    const Spacer(),
                    IconButton(tooltip: 'Share', onPressed: () => shareTrip(j), icon: const Icon(Icons.ios_share_outlined, size: 22)),
                    IconButton(
                      tooltip: j.saved ? 'Remove from saved' : 'Save',
                      onPressed: () => toggleWithSnack(context, () => Reactions.instance.toggleSave(j), done: 'Saved.'),
                      icon: Icon(j.saved ? Icons.bookmark : Icons.bookmark_border, size: 24),
                    ),
                  ],
                ),
              ),
              Pressable(
                semanticLabel: 'Open ${j.title}',
                onTap: () => openJourney(context, j),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(j.title, style: TT.display(17, wght: 700)),
                      const SizedBox(height: 3),
                      Text(tripMeta(j), style: TT.ui(13.5, wght: 550, color: TG.ink2)),
                      const SizedBox(height: 6),
                      Text(j.dek, style: TT.ui(14, color: TG.muted, height: 1.45), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.color, required this.label, required this.semantics, required this.onTap});
  final IconData icon;
  final Color color;
  final String label;
  final String semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semantics,
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 23, color: color),
              const SizedBox(width: 6),
              Text(label, style: TT.ui(13.5, wght: 600, color: color == TG.ink ? TG.ink2 : color)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A compact row for lists (search results, destinations).
class TripTile extends StatelessWidget {
  const TripTile({super.key, required this.journey});
  final Journey journey;

  @override
  Widget build(BuildContext context) => ReactiveJourney(
    journey: journey,
    builder: (context, j) => Pressable(
      semanticLabel: '${j.title} by ${j.creator.name}. ${tripMeta(j)}',
      onTap: () => openJourney(context, j),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(width: 88, height: 88, child: TgImage(j.coverPhoto?.url, cacheWidth: 100)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(j.title, style: TT.ui(15, wght: 650), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Text(placeLine(j), style: TT.ui(13, color: TG.muted)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(money(j.budgetTotal, j.currency), style: TT.ui(13.5, wght: 650)),
                      Text(' · ${plural(j.durationDays, 'day')} · by ${j.creator.firstName}', style: TT.ui(13, color: TG.muted)),
                    ],
                  ),
                ],
              ),
            ),
            if (j.isGoing) const Icon(Icons.flight_takeoff, size: 18, color: TG.going),
          ],
        ),
      ),
    ),
  );
}

/// A photo-first card for grids (profiles, rails).
class TripGridCard extends StatelessWidget {
  const TripGridCard({super.key, required this.journey, this.width});
  final Journey journey;
  final double? width;

  @override
  Widget build(BuildContext context) => Pressable(
    semanticLabel: '${journey.title}. ${tripMeta(journey)}',
    onTap: () => openJourney(context, journey),
    child: SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 4 / 5,
            child: ClipRRect(borderRadius: BorderRadius.circular(12), child: TgImage(journey.coverPhoto?.url, cacheWidth: 260)),
          ),
          const SizedBox(height: 8),
          Text(journey.title, style: TT.ui(14, wght: 650, height: 1.25), maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text('${money(journey.budgetTotal, journey.currency)} · ${plural(journey.durationDays, 'day')}', style: TT.ui(12.5, color: TG.muted)),
        ],
      ),
    ),
  );
}
