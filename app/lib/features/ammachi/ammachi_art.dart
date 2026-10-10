import 'dart:math' as math;

import 'package:flutter/material.dart';


enum AmmachiMood { idle, listening, thinking, speaking }

/// Ammachi's portrait, drawn in code: silver bun, round gold spectacles and a
/// gold-bordered mundu. She breathes, blinks, looks up while thinking and talks.
class AmmachiAvatar extends StatefulWidget {
  const AmmachiAvatar({super.key, required this.mood, this.size = 200, this.soundLevel = 0});

  final AmmachiMood mood;
  final double size;
  final double soundLevel; // 0..1 while listening

  @override
  State<AmmachiAvatar> createState() => _AmmachiAvatarState();
}

class _AmmachiAvatarState extends State<AmmachiAvatar> with TickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 60))..repeat();
  // Each Ammachi blinks on her own rhythm, driven by the clock (no timers, so
  // she stops entirely when her tab is hidden).
  final _blinkOffset = math.Random().nextDouble() * 4;
  double _gazeX = 0, _gazeY = 0;
  double _tilt = 0;
  double _level = 0;

  double _blinkAt(double t) {
    final phase = (t + _blinkOffset) % 4.3;
    const length = 0.16;
    return phase < length ? math.sin(phase / length * math.pi) : 0;
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: switch (widget.mood) {
        AmmachiMood.idle => 'Ammachi, smiling',
        AmmachiMood.listening => 'Ammachi is listening',
        AmmachiMood.thinking => 'Ammachi is thinking',
        AmmachiMood.speaking => 'Ammachi is speaking',
      },
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: AnimatedBuilder(
            animation: _clock,
            builder: (context, _) {
              final t = _clock.value * 60; // seconds
              final mood = widget.mood;
              // Ease gaze, tilt and sound level towards their targets each frame.
              final targetGx = mood == AmmachiMood.thinking ? 0.6 : (mood == AmmachiMood.listening ? 0 : math.sin(t * 0.4) * 0.25);
              final targetGy = mood == AmmachiMood.thinking ? -0.8 : 0.0;
              final targetTilt = mood == AmmachiMood.listening ? -0.07 : (mood == AmmachiMood.thinking ? 0.05 : math.sin(t * 0.5) * 0.015);
              _gazeX += (targetGx - _gazeX) * 0.08;
              _gazeY += (targetGy - _gazeY) * 0.08;
              _tilt += (targetTilt - _tilt) * 0.06;
              _level += (widget.soundLevel - _level) * 0.25;

              final mouth = mood == AmmachiMood.speaking
                  ? (0.35 + 0.35 * math.sin(t * 17) + 0.25 * math.sin(t * 7.3 + 1) + 0.15 * math.sin(t * 29)).clamp(0.0, 1.0)
                  : 0.0;
              return CustomPaint(
                painter: _AmmachiPainter(
                  breath: math.sin(t * 1.6) * 0.5 + 0.5,
                  blink: _blinkAt(t),
                  mouth: mouth,
                  gaze: Offset(_gazeX, _gazeY),
                  tilt: _tilt,
                  listening: mood == AmmachiMood.listening ? 1 : 0,
                  level: _level,
                  time: t,
                  smiling: mood == AmmachiMood.idle,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _AmmachiPainter extends CustomPainter {
  _AmmachiPainter({
    required this.breath,
    required this.blink,
    required this.mouth,
    required this.gaze,
    required this.tilt,
    required this.listening,
    required this.level,
    required this.time,
    required this.smiling,
  });

  final double breath, blink, mouth, tilt, listening, level, time;
  final Offset gaze;
  final bool smiling;

  static const skin = Color(0xFFB9784F);
  static const skinLight = Color(0xFFCB8C62);
  static const skinShade = Color(0xFF99603C);
  static const hair = Color(0xFFE9E4DA);
  static const hairShade = Color(0xFFBDB4A6);
  static const mundu = Color(0xFFF6EEDC);
  static const blouse = Color(0xFF1F4B3A);
  static const gold = Color(0xFFD4A63C);
  static const goldDeep = Color(0xFF9A7120);
  static const line = Color(0xFF3B2418);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    Offset p(double x, double y) => Offset(x * s, y * s);
    Rect r(double cx, double cy, double w, double h) => Rect.fromCenter(center: p(cx, cy), width: w * s, height: h * s);

    final lift = breath * s * 0.006;

    // ---- shoulders: green blouse, kasavu mundu draped over the left shoulder
    canvas.save();
    canvas.translate(0, -lift * 0.5);
    final shoulders = Path()
      ..moveTo(s * 0.12, s * 1.0)
      ..cubicTo(s * 0.14, s * 0.82, s * 0.30, s * 0.76, s * 0.5, s * 0.76)
      ..cubicTo(s * 0.70, s * 0.76, s * 0.86, s * 0.82, s * 0.88, s * 1.0)
      ..close();
    canvas.drawPath(shoulders, Paint()..color = blouse);
    // neck
    canvas.drawRRect(RRect.fromRectAndRadius(r(0.5, 0.73, 0.13, 0.12), Radius.circular(s * 0.05)), Paint()..color = skinShade);
    // gold chain
    canvas.drawArc(
      r(0.5, 0.74, 0.17, 0.12),
      0.2,
      math.pi - 0.4,
      false,
      Paint()
        ..color = gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.008,
    );
    // mundu drape: cream cloth sweeping from the left shoulder across the chest
    final drape = Path()
      ..moveTo(s * 0.17, s * 1.0)
      ..cubicTo(s * 0.20, s * 0.86, s * 0.28, s * 0.79, s * 0.37, s * 0.78)
      ..cubicTo(s * 0.47, s * 0.86, s * 0.60, s * 0.94, s * 0.68, s * 1.0)
      ..close();
    canvas.drawPath(drape, Paint()..color = mundu);
    // the kasavu: a gold band along the drape's edge
    final band = Path()
      ..moveTo(s * 0.37, s * 0.78)
      ..cubicTo(s * 0.47, s * 0.86, s * 0.60, s * 0.94, s * 0.68, s * 1.0);
    canvas.drawPath(
      band,
      Paint()
        ..color = gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.032,
    );
    canvas.drawPath(
      band.shift(Offset(-s * 0.022, s * 0.012)),
      Paint()
        ..color = goldDeep
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.005,
    );
    canvas.restore();

    // ---- head (tilts and bobs)
    canvas.save();
    canvas.translate(s * 0.5, s * 0.5 - lift);
    canvas.rotate(tilt);
    canvas.translate(-s * 0.5, -s * 0.5);

    // bun
    canvas.drawCircle(p(0.5, 0.17), s * 0.105, Paint()..color = hair);
    // the coil of the bun
    canvas.drawArc(
      r(0.5, 0.165, 0.12, 0.10),
      0.4,
      4.2,
      false,
      Paint()
        ..color = hairShade.withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.007,
    );

    // ears + kammal (gold ear studs with a tiny drop)
    for (final side in [-1.0, 1.0]) {
      final ear = p(0.5 + side * 0.255, 0.50);
      canvas.drawOval(Rect.fromCenter(center: ear, width: s * 0.07, height: s * 0.11), Paint()..color = skinShade);
      final stud = ear + Offset(0, s * 0.055);
      canvas.drawCircle(stud, s * 0.022, Paint()..color = gold);
      canvas.drawCircle(stud + Offset(0, s * 0.035 + math.sin(time * 2 + side) * s * 0.003), s * 0.012, Paint()..color = gold);
    }

    // face
    final face = r(0.5, 0.49, 0.50, 0.56);
    canvas.drawOval(
      face,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(-0.25, -0.35),
          radius: 0.9,
          colors: [skinLight, skin, skinShade],
          stops: [0, 0.6, 1],
        ).createShader(face),
    );

    // hair cap with a centre parting, framing the forehead
    final cap = Path()
      ..moveTo(s * 0.245, s * 0.47)
      ..cubicTo(s * 0.23, s * 0.25, s * 0.38, s * 0.19, s * 0.5, s * 0.20)
      ..cubicTo(s * 0.62, s * 0.19, s * 0.77, s * 0.25, s * 0.755, s * 0.47)
      ..cubicTo(s * 0.73, s * 0.36, s * 0.64, s * 0.30, s * 0.5, s * 0.31)
      ..cubicTo(s * 0.36, s * 0.30, s * 0.27, s * 0.36, s * 0.245, s * 0.47)
      ..close();
    canvas.drawPath(cap, Paint()..color = hair);
    final strands = Paint()
      ..color = hairShade
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.006
      ..strokeCap = StrokeCap.round;
    // A few combed strands sweeping back from the parting, kept inside the hair.
    for (final side in [-1.0, 1.0]) {
      for (final k in [0.0, 1.0]) {
        final start = p(0.5 + side * (0.04 + k * 0.06), 0.30 - k * 0.005);
        final end = p(0.5 + side * (0.15 + k * 0.07), 0.25 + k * 0.035);
        final ctrl = p(0.5 + side * (0.10 + k * 0.05), 0.235 + k * 0.01);
        canvas.drawPath(Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy), strands);
      }
    }

    // cheeks
    for (final side in [-1.0, 1.0]) {
      canvas.drawCircle(p(0.5 + side * 0.14, 0.585), s * 0.05, Paint()..color = const Color(0xFFD9775B).withValues(alpha: 0.35));
    }

    // eyes
    final ink = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.012
      ..strokeCap = StrokeCap.round;
    for (final side in [-1.0, 1.0]) {
      final c = p(0.5 + side * 0.105, 0.48);
      if (blink > 0.5) {
        canvas.drawLine(c - Offset(s * 0.03, 0), c + Offset(s * 0.03, 0), ink);
      } else if (smiling) {
        // contented, crinkled eyes
        canvas.drawArc(
          Rect.fromCenter(center: c + Offset(0, s * 0.012), width: s * 0.065, height: s * 0.05),
          math.pi * 1.1,
          math.pi * 0.8,
          false,
          ink,
        );
      } else {
        final open = 1 - blink * 2;
        canvas.drawOval(Rect.fromCenter(center: c, width: s * 0.06, height: s * 0.05 * open), Paint()..color = const Color(0xFFFFF8EC));
        canvas.drawCircle(c + Offset(gaze.dx * s * 0.012, gaze.dy * s * 0.01), s * 0.017 * open.clamp(0.3, 1), Paint()..color = line);
        canvas.drawCircle(
          c + Offset(gaze.dx * s * 0.012 + s * 0.006, gaze.dy * s * 0.01 - s * 0.006),
          s * 0.005,
          Paint()..color = Colors.white,
        );
      }
      // laugh lines
      canvas.drawArc(
        Rect.fromCenter(center: c + Offset(side * s * 0.055, s * 0.01), width: s * 0.03, height: s * 0.05),
        side > 0 ? -0.6 : math.pi - 0.6 + 1.2,
        0.0 + (side > 0 ? 1.2 : -1.2),
        false,
        Paint()
          ..color = skinShade
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.005,
      );
    }

    // round gold spectacles
    final rim = Paint()
      ..color = gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.011;
    for (final side in [-1.0, 1.0]) {
      final c = p(0.5 + side * 0.105, 0.485);
      canvas.drawCircle(c, s * 0.068, Paint()..color = Colors.white.withValues(alpha: 0.10));
      canvas.drawCircle(c, s * 0.068, rim);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: s * 0.05),
        -2.4,
        0.7,
        false,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.006,
      );
    }
    canvas.drawArc(r(0.5, 0.49, 0.07, 0.05), math.pi * 1.15, math.pi * 0.7, false, rim);
    canvas.drawLine(p(0.327, 0.475), p(0.255, 0.46), rim);
    canvas.drawLine(p(0.673, 0.475), p(0.745, 0.46), rim);

    // eyebrows (silver), raised while thinking
    final browLift = gaze.dy < -0.3 ? s * 0.012 : 0.0;
    for (final side in [-1.0, 1.0]) {
      canvas.drawArc(
        Rect.fromCenter(center: p(0.5 + side * 0.105, 0.405) - Offset(0, browLift), width: s * 0.08, height: s * 0.035),
        math.pi * 1.15,
        math.pi * 0.7,
        false,
        Paint()
          ..color = hairShade
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.014
          ..strokeCap = StrokeCap.round,
      );
    }

    // nose
    canvas.drawArc(
      r(0.5, 0.555, 0.05, 0.05),
      0.3,
      2.2,
      false,
      Paint()
        ..color = skinShade
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.01
        ..strokeCap = StrokeCap.round,
    );

    // mouth: a smile, or open while talking
    final mc = p(0.5, 0.645);
    if (mouth > 0.05) {
      final h = s * (0.018 + 0.05 * mouth);
      final w = s * (0.095 - 0.015 * mouth);
      final rect = Rect.fromCenter(center: mc + Offset(0, h * 0.2), width: w, height: h);
      canvas.drawOval(rect, Paint()..color = const Color(0xFF5A2A20));
      canvas.drawOval(
        Rect.fromCenter(center: rect.bottomCenter - Offset(0, h * 0.28), width: w * 0.55, height: h * 0.38),
        Paint()..color = const Color(0xFFC0605A),
      );
    } else {
      canvas.drawArc(Rect.fromCenter(center: mc - Offset(0, s * 0.02), width: s * 0.12, height: s * 0.07), 0.25, math.pi - 0.5, false, ink);
    }
    // smile lines
    for (final side in [-1.0, 1.0]) {
      canvas.drawArc(
        Rect.fromCenter(center: mc + Offset(side * s * 0.085, -s * 0.03), width: s * 0.04, height: s * 0.08),
        side > 0 ? -0.9 : math.pi - 0.9 + 1.4,
        side > 0 ? 1.4 : -1.4,
        false,
        Paint()
          ..color = skinShade
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.006,
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_AmmachiPainter old) => true;
}
