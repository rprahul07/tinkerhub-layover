import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tg_theme.dart';
import '../util/format.dart';

class RoutePoint {
  const RoutePoint(this.name, this.lat, this.lng, this.day);
  final String name;
  final double lat;
  final double lng;
  final int day;
}

/// The route, drawn like an ink sketch on a paper map: a graticule, a compass,
/// numbered stop stamps and a line that draws itself in.
class RouteMap extends StatefulWidget {
  const RouteMap({super.key, required this.points, this.height = 300, this.animate = true, this.compact = false});

  final List<RoutePoint> points;
  final double height;
  final bool animate;
  final bool compact;

  double get totalKm {
    double km = 0;
    for (var i = 1; i < points.length; i++) {
      km += distanceKm(points[i - 1].lat, points[i - 1].lng, points[i].lat, points[i].lng);
    }
    return km;
  }

  @override
  State<RouteMap> createState() => _RouteMapState();
}

class _RouteMapState extends State<RouteMap> with TickerProviderStateMixin {
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: 900 + 350 * widget.points.length),
  );
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void initState() {
    super.initState();
    if (widget.animate) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _draw.forward();
      });
    } else {
      _draw.value = 1;
    }
  }

  @override
  void didUpdateWidget(RouteMap old) {
    super.didUpdateWidget(old);
    if (old.points.length != widget.points.length) _draw.value = 1;
  }

  @override
  void dispose() {
    _draw.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final names = widget.points.map((p) => p.name).join(', then ');
    return Semantics(
      label: widget.points.isEmpty
          ? 'Route map, no stops yet'
          : 'Route map: $names. About ${widget.totalKm.round()} kilometres as the crow flies.',
      child: SizedBox(
        height: widget.height,
        // Two layers: the map only repaints while the ink is drawing; the
        // pulse at the destination repaints on its own, cheaply.
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: AnimatedBuilder(
                animation: _draw,
                builder: (context, _) => CustomPaint(
                  painter: _RoutePainter(
                    points: widget.points,
                    progress: Curves.easeInOutCubic.transform(_draw.value),
                    compact: widget.compact,
                    km: widget.totalKm,
                  ),
                ),
              ),
            ),
            if (widget.points.length > 1)
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_draw, _pulse]),
                  builder: (context, _) => CustomPaint(
                    painter: _draw.value < 1 ? null : _PulsePainter(points: widget.points, compact: widget.compact, pulse: _pulse.value),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Fits the stops into the box (equirectangular, longitude squashed by latitude).
List<Offset> projectRoute(List<RoutePoint> points, Size size, bool compact) {
  final pad = EdgeInsets.fromLTRB(compact ? 36 : 54, 40, compact ? 36 : 54, compact ? 32 : 46);
  final lats = points.map((p) => p.lat);
  final lngs = points.map((p) => p.lng);
  final minLat = lats.reduce(math.min), maxLat = lats.reduce(math.max);
  final minLng = lngs.reduce(math.min), maxLng = lngs.reduce(math.max);
  final midLat = (minLat + maxLat) / 2;
  final k = math.cos(midLat * math.pi / 180);
  final spanX = math.max((maxLng - minLng) * k, 0.004);
  final spanY = math.max(maxLat - minLat, 0.004);
  final w = size.width - pad.horizontal;
  final h = size.height - pad.vertical;
  final scale = math.min(w / spanX, h / spanY);
  final offX = pad.left + (w - spanX * scale) / 2;
  final offY = pad.top + (h - spanY * scale) / 2;
  return points.map((p) {
    final x = offX + ((p.lng - minLng) * k) * scale + (maxLng == minLng ? spanX * scale / 2 : 0);
    final y = offY + (maxLat - p.lat) * scale + (maxLat == minLat ? spanY * scale / 2 : 0);
    return Offset(x, y);
  }).toList();
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.points, required this.compact, required this.pulse});
  final List<RoutePoint> points;
  final bool compact;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final end = projectRoute(points, size, compact).last;
    canvas.drawCircle(
      end,
      12.5 + 10 * pulse,
      Paint()
        ..color = TG.accent.withValues(alpha: 0.35 * (1 - pulse))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.pulse != pulse || old.points != points;
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({required this.points, required this.progress, required this.compact, required this.km});

  final List<RoutePoint> points;
  final double progress;
  final bool compact;
  final double km;

  static const _dayInk = [TG.accent, Color(0xFF1D4ED8), TG.going, Color(0xFFA16207), Color(0xFF7C3AED)];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Paper with a faint blue-grey graticule, like a survey sheet.
    canvas.drawRect(rect, Paint()..color = TG.surface);
    final grid = Paint()
      ..color = TG.line.withValues(alpha: 0.9)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 28) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    _compass(canvas, Offset(size.width - 34, 34), 18);

    if (points.isEmpty) {
      _label(canvas, 'Add stops to draw your route', Offset(size.width / 2, size.height / 2), center: true, faint: true);
      return;
    }

    final projected = _project(size);

    // The route: a smooth curve through the stops, drawn progressively.
    final path = _smooth(projected);
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (s, m) => s + m.length);
    final shown = Path();
    var remaining = total * progress;
    Offset? tip;
    for (final m in metrics) {
      final take = math.min(remaining, m.length);
      if (take > 0) {
        shown.addPath(m.extractPath(0, take), Offset.zero);
        tip = m.getTangentForOffset(take)?.position;
      }
      remaining -= take;
    }
    canvas.drawPath(
      shown,
      Paint()
        ..color = TG.accent.withValues(alpha: 0.16)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // Dashed ink line on top.
    final ink = Paint()
      ..color = TG.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (final m in shown.computeMetrics()) {
      for (double d = 0; d < m.length; d += 11) {
        canvas.drawPath(m.extractPath(d, math.min(d + 7, m.length)), ink);
      }
    }

    // Stops appear as the line reaches them.
    final reached = <int>{};
    if (points.length == 1 || progress >= 1) {
      reached.addAll(List.generate(points.length, (i) => i));
    } else {
      // Approximate: stop i is reached when progress passes its share of the path.
      for (var i = 0; i < points.length; i++) {
        if (progress >= i / (points.length - 1) - 0.001) reached.add(i);
      }
    }

    // Stops a few kilometres apart would sit on top of each other, so
    // consecutive stops that land close together share one marker ("1–3").
    final groups = <List<int>>[];
    for (var i = 0; i < projected.length; i++) {
      if (groups.isNotEmpty && (projected[i] - projected[groups.last.first]).distance < 30) {
        groups.last.add(i);
      } else {
        groups.add([i]);
      }
    }

    final placed = <Rect>[Rect.fromCircle(center: Offset(size.width - 34, 34), radius: 26)];
    for (final g in groups) {
      final shown = g.where(reached.contains).toList();
      if (shown.isEmpty) continue;
      final p = projected[g.first];
      final color = _dayInk[(points[g.first].day - 1) % _dayInk.length];
      final text = shown.length == 1 ? '${shown.first + 1}' : '${shown.first + 1}–${shown.last + 1}';
      final num = TextPainter(
        text: TextSpan(text: text, style: TT.ui(11, wght: 700, color: color)),
        textDirection: TextDirection.ltr,
      )..layout();
      final marker = RRect.fromRectAndRadius(
        Rect.fromCenter(center: p, width: math.max(25, num.width + 14), height: 25),
        const Radius.circular(12.5),
      );
      canvas.drawRRect(marker.shift(const Offset(0, 1.5)), Paint()..color = TG.ink.withValues(alpha: 0.18));
      canvas.drawRRect(marker, Paint()..color = Colors.white);
      canvas.drawRRect(
        marker,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4,
      );
      num.paint(canvas, p - Offset(num.width / 2, num.height / 2));
      placed.add(marker.outerRect);
    }

    // Labels go beside their marker, on whichever side has room, and are
    // skipped rather than drawn over another label.
    if (!compact || groups.length <= 5) {
      for (final g in groups) {
        final shown = g.where(reached.contains).toList();
        if (shown.isEmpty) continue;
        final p = projected[g.first];
        final name = shown.length == 1 ? points[shown.first].name : '${points[shown.first].name} +${shown.length - 1}';
        final halfWidth = shown.length == 1 ? 12.5 : 22.0;
        final preferLeft = p.dx > size.width * 0.6;
        for (final left in [preferLeft, !preferLeft]) {
          final anchor = p + Offset(left ? -(halfWidth + 6) : halfWidth + 6, 0);
          final box = _labelBox(name, anchor, alignRight: left);
          if (box.left < 2 || box.right > size.width - 2 || placed.any((r) => r.overlaps(box))) continue;
          _label(canvas, name, anchor, alignRight: left);
          placed.add(box);
          break;
        }
      }
    }

    // A dot riding the tip of the ink while it draws.
    if (tip != null && progress < 1) {
      canvas.drawCircle(tip, 4, Paint()..color = TG.accent);
    }

    if (!compact && projected.length > 1) {
      _label(canvas, '≈ ${km.round()} KM AS THE CROW FLIES', Offset(14, size.height - 20), faint: true, mono: true);
    }
  }

  List<Offset> _project(Size size) => projectRoute(points, size, compact);

  // Catmull-Rom through the points, with a little hand-drawn wobble.
  Path _smooth(List<Offset> pts) {
    final path = Path();
    if (pts.isEmpty) return path;
    path.moveTo(pts.first.dx, pts.first.dy);
    for (var i = 0; i < pts.length - 1; i++) {
      final p0 = i == 0 ? pts[i] : pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i + 2 < pts.length ? pts[i + 2] : p2;
      final wobble = Offset(-(p2.dy - p1.dy), p2.dx - p1.dx) * 0.08 * (i.isEven ? 1 : -1);
      final c1 = p1 + (p2 - p0) / 6 + wobble;
      final c2 = p2 - (p3 - p1) / 6 + wobble;
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    return path;
  }

  void _compass(Canvas canvas, Offset c, double r) {
    final p = Paint()
      ..color = TG.ink.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(c, r, p);
    final needle = Path()
      ..moveTo(c.dx, c.dy - r + 2)
      ..lineTo(c.dx + 4, c.dy)
      ..lineTo(c.dx, c.dy + r - 2)
      ..lineTo(c.dx - 4, c.dy)
      ..close();
    canvas.drawPath(needle, Paint()..color = TG.ink.withValues(alpha: 0.12));
    canvas.drawPath(
      Path()
        ..moveTo(c.dx, c.dy - r + 2)
        ..lineTo(c.dx + 4, c.dy)
        ..lineTo(c.dx - 4, c.dy)
        ..close(),
      Paint()..color = TG.accent,
    );
    final n = TextPainter(
      text: TextSpan(
        text: 'N',
        style: TT.ui(9, wght: 700, color: TG.ink),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    n.paint(canvas, Offset(c.dx - n.width / 2, c.dy - r - n.height - 1));
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at, {
    bool alignRight = false,
    bool center = false,
    bool faint = false,
    bool mono = false,
  }) {
    final tp = _labelPainter(text, faint: faint, mono: mono);
    final dx = center ? at.dx - tp.width / 2 : (alignRight ? at.dx - tp.width : at.dx);
    final box = Rect.fromLTWH(dx - 4, at.dy - tp.height / 2 - 2, tp.width + 8, tp.height + 4);
    if (!faint) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(2)),
        Paint()..color = TG.surface.withValues(alpha: 0.92),
      );
    }
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  TextPainter _labelPainter(String text, {bool faint = false, bool mono = false}) => TextPainter(
    text: TextSpan(
      text: text,
      style: mono ? TT.label(9.5) : TT.ui(11.5, wght: 600, color: faint ? TG.faint : TG.ink),
    ),
    textDirection: TextDirection.ltr,
    maxLines: mono ? 1 : 2,
    ellipsis: '…',
  )..layout(maxWidth: mono ? 320 : 130);

  /// Where [_label] would draw [text], for collision checks.
  Rect _labelBox(String text, Offset at, {bool alignRight = false}) {
    final tp = _labelPainter(text);
    final dx = alignRight ? at.dx - tp.width : at.dx;
    return Rect.fromLTWH(dx - 4, at.dy - tp.height / 2 - 2, tp.width + 8, tp.height + 4);
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.progress != progress || old.points != points || old.km != km;
}
