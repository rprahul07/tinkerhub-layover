import 'dart:math' as math;

import 'package:flutter/material.dart';

enum AmmachiMood { idle, listening, thinking, speaking }

/// The AI consultant's mark: a calm, professional headset badge. It breathes
/// softly when idle, shows a listening ring that follows the caller's voice,
/// a turning arc while thinking, and gentle waves while speaking.
class AmmachiAvatar extends StatefulWidget {
  const AmmachiAvatar({super.key, required this.mood, this.size = 200, this.soundLevel = 0});

  final AmmachiMood mood;
  final double size;
  final double soundLevel; // 0..1 while listening

  @override
  State<AmmachiAvatar> createState() => _AmmachiAvatarState();
}

class _AmmachiAvatarState extends State<AmmachiAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (widget.mood) {
      AmmachiMood.idle => 'AI consultant',
      AmmachiMood.listening => 'AI consultant is listening',
      AmmachiMood.thinking => 'AI consultant is thinking',
      AmmachiMood.speaking => 'AI consultant is speaking',
    };
    return Semantics(
      label: label,
      image: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _clock,
            builder: (context, _) => CustomPaint(painter: _AgentPainter(mood: widget.mood, t: _clock.value, level: widget.soundLevel)),
          ),
        ),
      ),
    );
  }
}

class _AgentPainter extends CustomPainter {
  _AgentPainter({required this.mood, required this.t, required this.level});
  final AmmachiMood mood;
  final double t; // 0..1, loops every 3 s
  final double level;

  static const _deep = Color(0xFF1E293B);
  static const _mid = Color(0xFF334155);
  static const _accent = Color(0xFF38BDF8);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final breathe = mood == AmmachiMood.idle ? 1 + 0.012 * math.sin(t * 2 * math.pi) : 1.0;

    // Badge.
    canvas.drawCircle(
      c,
      r * 0.92 * breathe,
      Paint()..shader = const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_mid, _deep]).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Headset: band, ear cups and microphone boom.
    final ink = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.075;
    final band = Rect.fromCircle(center: c.translate(0, r * 0.04), radius: r * 0.36);
    canvas.drawArc(band, math.pi * 1.05, math.pi * 0.9, false, ink);
    final cup = Paint()..color = Colors.white;
    for (final dx in [-1.0, 1.0]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromCenter(center: c.translate(dx * r * 0.36, r * 0.12), width: r * 0.16, height: r * 0.3), Radius.circular(r * 0.06)),
        cup,
      );
    }
    final boom = Path()
      ..moveTo(c.dx + r * 0.36, c.dy + r * 0.26)
      ..quadraticBezierTo(c.dx + r * 0.33, c.dy + r * 0.46, c.dx + r * 0.08, c.dy + r * 0.46);
    canvas.drawPath(boom, ink..strokeWidth = r * 0.05);
    canvas.drawCircle(c.translate(r * 0.05, r * 0.46), r * 0.055, Paint()..color = mood == AmmachiMood.speaking ? _accent : Colors.white);

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = r * 0.03;
    switch (mood) {
      case AmmachiMood.listening:
        // A ring that grows with the caller's voice.
        final grow = 0.62 + 0.06 * level.clamp(0.0, 1.0); // stays inside the cropped badge
        canvas.drawCircle(c, r * grow, ring..color = _accent.withValues(alpha: 0.85));
      case AmmachiMood.thinking:
        // A turning arc.
        canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.64), t * 2 * math.pi, math.pi * 0.6, false, ring..color = _accent);
      case AmmachiMood.speaking:
        // Three soft bars under the microphone, like a voice meter.
        final bar = Paint()..color = _accent;
        for (var i = 0; i < 3; i++) {
          final h = r * (0.06 + 0.07 * (0.5 + 0.5 * math.sin((t * 4 + i * 0.33) * 2 * math.pi)));
          canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromCenter(center: c.translate((i - 1) * r * 0.1, r * 0.6), width: r * 0.06, height: h), Radius.circular(r * 0.03)),
            bar,
          );
        }
      case AmmachiMood.idle:
        break;
    }
  }

  @override
  bool shouldRepaint(_AgentPainter old) => old.t != t || old.mood != mood || old.level != level;
}
