import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../data/api.dart';
import '../data/models.dart';
import '../data/reactions.dart';
import '../data/session.dart';
import '../theme/tg_theme.dart';

/// Network photo with a neutral placeholder and a soft fade-in.
class TgImage extends StatelessWidget {
  const TgImage(this.url, {super.key, this.fit = BoxFit.cover, this.cacheWidth, this.semanticLabel});

  final String? url;
  final BoxFit fit;
  final int? cacheWidth;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (url == null) return const _Placeholder(failed: true);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Semantics(
      image: true,
      label: semanticLabel,
      child: CachedNetworkImage(
        imageUrl: url!,
        httpHeaders: Api.tunnelHeaders,
        fit: fit,
        memCacheWidth: cacheWidth == null ? null : (cacheWidth! * dpr).round(),
        fadeInDuration: const Duration(milliseconds: 220),
        placeholder: (_, _) => const _Placeholder(),
        errorWidget: (_, _, _) => const _Placeholder(failed: true),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.failed = false});
  final bool failed;

  @override
  Widget build(BuildContext context) => Container(
    color: TG.surface,
    alignment: Alignment.center,
    child: failed ? const Icon(Icons.image_not_supported_outlined, color: TG.faint) : null,
  );
}

/// Initials avatar, tinted by the creator's hue.
class Avatar extends StatelessWidget {
  const Avatar(this.creator, {super.key, this.size = 36});

  final Creator creator;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bg = HSLColor.fromAHSL(1, creator.hue.toDouble() % 360, 0.35, 0.88).toColor();
    final fg = HSLColor.fromAHSL(1, creator.hue.toDouble() % 360, 0.45, 0.30).toColor();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Text(creator.initials, style: TT.ui(size * 0.38, wght: 650, color: fg, height: 1)),
      ),
    );
  }
}

/// Follow / Following, kept in sync everywhere through [Reactions].
class FollowButton extends StatelessWidget {
  const FollowButton(this.creator, {super.key, this.compact = false});

  final Creator creator;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (Session.instance.creator?.id == creator.id) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Reactions.instance,
      builder: (context, _) {
        final c = Reactions.instance.applyCreator(creator);
        final on = c.isFollowing;
        final style = on
            ? OutlinedButton.styleFrom(
                minimumSize: Size(compact ? 84 : 104, compact ? 32 : 40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const StadiumBorder(),
                side: const BorderSide(color: TG.line),
                textStyle: TT.ui(13, wght: 600),
              )
            : OutlinedButton.styleFrom(
                minimumSize: Size(compact ? 84 : 104, compact ? 32 : 40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: const StadiumBorder(),
                backgroundColor: TG.ink,
                foregroundColor: Colors.white,
                side: const BorderSide(color: TG.ink),
                textStyle: TT.ui(13, wght: 600),
              );
        return Semantics(
          button: true,
          toggled: on,
          label: on ? 'Following ${c.name}' : 'Follow ${c.name}',
          child: OutlinedButton(
            style: style,
            onPressed: () async {
              HapticFeedback.selectionClick();
              try {
                await Reactions.instance.toggleFollow(c);
              } on ApiException catch (e) {
                if (context.mounted) showSnack(context, e.message);
              }
            },
            child: ExcludeSemantics(child: Text(on ? 'Following' : 'Follow')),
          ),
        );
      },
    );
  }
}

/// Scales down a touch when pressed.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, required this.onTap, this.semanticLabel});

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTapUp: (_) => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(scale: _down ? 0.98 : 1, duration: const Duration(milliseconds: 120), child: widget.child),
      ),
    );
  }
}

/// A rounded filter pill.
class FilterPill extends StatelessWidget {
  const FilterPill({super.key, required this.label, required this.selected, required this.onTap, this.icon});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? TG.ink : TG.bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? TG.ink : TG.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 16, color: selected ? Colors.white : TG.ink2), const SizedBox(width: 6)],
              ExcludeSemantics(child: Text(label, style: TT.ui(13, wght: 550, color: selected ? Colors.white : TG.ink))),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction, this.padding = const EdgeInsets.fromLTRB(16, 24, 8, 10)});

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Row(
      children: [
        Expanded(child: Semantics(header: true, child: Text(title, style: TT.display(18, wght: 700)))),
        if (action != null) TextButton(onPressed: onAction, child: Text(action!, style: TT.ui(13.5, wght: 600, color: TG.muted))),
      ],
    ),
  );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, required this.onRetry, this.dark = false});

  final String message;
  final VoidCallback onRetry;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final fg = dark ? Colors.white : TG.ink;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined, size: 40, color: dark ? Colors.white54 : TG.faint),
            const SizedBox(height: 14),
            Text('Couldn’t load this', style: TT.display(18, color: fg)),
            const SizedBox(height: 6),
            Text(message, style: TT.ui(14, color: dark ? Colors.white70 : TG.muted), textAlign: TextAlign.center),
            const SizedBox(height: 18),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({super.key, required this.icon, required this.title, required this.body, this.action});

  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(color: TG.surface, shape: BoxShape.circle),
          child: Icon(icon, color: TG.muted, size: 28),
        ),
        const SizedBox(height: 16),
        Text(title, style: TT.display(18), textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(body, style: TT.ui(14, color: TG.muted), textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 18), action!],
      ],
    ),
  );
}

/// A rectangle that shimmers while content loads.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 6});
  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(color: TG.surface, borderRadius: BorderRadius.circular(radius)),
  ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1300.ms, color: Colors.white.withValues(alpha: 0.6));
}

void showSnack(BuildContext context, String message, {String? action, VoidCallback? onAction}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: action == null ? null : SnackBarAction(label: action, textColor: const Color(0xFFFFB59E), onPressed: onAction ?? () {}),
      ),
    );
}
