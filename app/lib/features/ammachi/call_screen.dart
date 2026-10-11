import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../theme/tg_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../journey/journey_screen.dart';
import 'ammachi_art.dart';
import 'ammachi_controller.dart';
import 'ammachi_screen.dart' show isMalayalam;

/// A hands-free voice call with Ammachi: she greets, listens, answers out loud,
/// and listens again until you hang up.
class CallScreen extends StatefulWidget {
  const CallScreen({super.key, this.contextJourney});
  final Journey? contextJourney;

  static Future<void> open(BuildContext context, {Journey? contextJourney}) => Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, _, _) => CallScreen(contextJourney: contextJourney),
      transitionsBuilder: (_, a, _, child) => FadeTransition(
        opacity: a,
        child: SlideTransition(position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)), child: child),
      ),
    ),
  );

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with SingleTickerProviderStateMixin {
  late final AmmachiController _c = AmmachiController(contextJourney: widget.contextJourney);
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  Timer? _clock;
  bool _connecting = true;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _c.init().then((_) {
      if (!mounted) return;
      setState(() => _connecting = false);
      _c.startCall();
    });
  }

  void _onChange() {
    final n = _c.takeNotice();
    if (n != null && mounted) showSnack(context, n);
  }

  @override
  void dispose() {
    _clock?.cancel();
    _pulse.dispose();
    _c.removeListener(_onChange);
    _c.endCall();
    _c.dispose();
    super.dispose();
  }

  Future<void> _hangUp() async {
    HapticFeedback.heavyImpact();
    await _c.endCall();
    if (mounted) Navigator.of(context).pop();
  }

  String get _elapsed {
    final start = _c.callStartedAt;
    if (start == null) return '00:00';
    final s = DateTime.now().difference(start).inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  String _state() {
    final en = _c.lang == 'en';
    if (_connecting) return en ? 'Calling…' : 'വിളിക്കുന്നു…';
    if (_c.muted) return en ? 'Muted' : 'മ്യൂട്ട്';
    if (_c.listening) return en ? 'Listening' : 'കേൾക്കുന്നു';
    if (_c.mood == AmmachiMood.thinking) return en ? 'Thinking' : 'ആലോചിക്കുന്നു';
    if (_c.mood == AmmachiMood.speaking) return en ? 'Speaking' : 'സംസാരിക്കുന്നു';
    return _elapsed;
  }

  void _transcript() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TG.nightRaised,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: ListenableBuilder(
          listenable: _c,
          builder: (context, _) => _c.messages.isEmpty
              ? Center(child: Text('Nothing said yet', style: TT.ui(14, color: Colors.white60)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    for (final m in _c.messages)
                      if (m.text.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(m.fromUser ? 'You' : 'AI Consultant', style: TT.ui(12, wght: 650, color: m.fromUser ? Colors.white54 : const Color(0xFF7DD3FC))),
                              const SizedBox(height: 2),
                              Text(m.text.trim(), style: isMalayalam(m.text) ? TT.ml(15.5, color: Colors.white) : TT.ui(15, color: Colors.white)),
                            ],
                          ),
                        ),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) _c.endCall();
        },
        child: Scaffold(
          backgroundColor: TG.night,
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1E293B), Color(0xFF0B1120)]),
            ),
            child: SafeArea(
              child: ListenableBuilder(
                listenable: _c,
                builder: (context, _) {
                  final last = _c.messages.lastWhere((m) => !m.fromUser, orElse: () => ChatMessage.ammachi()..streaming = false);
                  final cites = last.citations;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                        child: Row(
                          children: [
                            IconButton(
                              tooltip: 'Minimise',
                              onPressed: _hangUp,
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70, size: 28),
                            ),
                            const Spacer(),
                            _Lang(lang: _c.lang, onTap: () => _c.setLang(_c.lang == 'en' ? 'ml' : 'en')),
                            const SizedBox(width: 8),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('AI Consultant', style: TT.display(26, color: Colors.white)),
                      const SizedBox(height: 4),
                      Semantics(
                        liveRegion: true,
                        child: Text(_state(), style: TT.ui(15, color: Colors.white60, wght: 500)),
                      ),
                      Expanded(
                        flex: 5,
                        child: Center(
                          child: _PulsingAvatar(pulse: _pulse, mood: _c.mood, level: _c.soundLevel, active: !_connecting && !_c.muted),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: SingleChildScrollView(
                            reverse: true,
                            child: Column(
                              children: [
                                if (_c.lastHeard.isNotEmpty || _c.partial.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      '“${_c.partial.isNotEmpty ? _c.partial : _c.lastHeard}”',
                                      textAlign: TextAlign.center,
                                      style: isMalayalam(_c.partial + _c.lastHeard) ? TT.ml(14, color: Colors.white54) : TT.ui(14, color: Colors.white54),
                                    ),
                                  ),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: Text(
                                    _c.caption,
                                    key: ValueKey(_c.caption),
                                    textAlign: TextAlign.center,
                                    style: isMalayalam(_c.caption) ? TT.ml(19, color: Colors.white, height: 1.55) : TT.ui(18.5, color: Colors.white, height: 1.45),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      if (cites.isNotEmpty)
                        SizedBox(
                          height: 78,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: cites.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 8),
                            itemBuilder: (context, i) => _CallTrip(journey: cites[i]),
                          ),
                        ),
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _RoundButton(
                              icon: _c.muted ? Icons.mic_off_rounded : Icons.mic_none_rounded,
                              label: _c.muted ? 'Unmute' : 'Mute',
                              on: _c.muted,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                _c.toggleMute();
                              },
                            ),
                            _RoundButton(icon: Icons.call_end_rounded, label: 'End', color: const Color(0xFFDC2626), size: 72, onTap: _hangUp),
                            _RoundButton(icon: Icons.subject_rounded, label: 'Transcript', onTap: _transcript),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PulsingAvatar extends StatelessWidget {
  const _PulsingAvatar({required this.pulse, required this.mood, required this.level, required this.active});
  final Animation<double> pulse;
  final AmmachiMood mood;
  final double level;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final ringColor = mood == AmmachiMood.listening ? const Color(0xFF34D399) : const Color(0xFF7DD3FC);
    final showRings = active && (mood == AmmachiMood.speaking || mood == AmmachiMood.listening);
    return LayoutBuilder(
      builder: (context, box) {
        final size = (box.biggest.shortestSide * 0.72).clamp(120.0, 220.0);
        return SizedBox.square(
          dimension: size * 1.4,
          child: AnimatedBuilder(
            animation: pulse,
            builder: (context, child) => Stack(
              alignment: Alignment.center,
              children: [
                if (showRings)
                  for (final offset in const [0.0, 0.5])
                    Builder(
                      builder: (_) {
                        final t = (pulse.value + offset) % 1;
                        final grow = mood == AmmachiMood.listening ? 0.15 + 0.25 * level : 0.3;
                        return Container(
                          width: size * (1 + grow * t),
                          height: size * (1 + grow * t),
                          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: ringColor.withValues(alpha: (1 - t) * 0.5), width: 2)),
                        );
                      },
                    ),
                child!,
              ],
            ),
            child: Container(
              width: size,
              height: size,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF1E293B)),
              child: ClipOval(child: OverflowBox(maxWidth: size * 1.35, maxHeight: size * 1.35, child: AmmachiAvatar(mood: mood, size: size * 1.35, soundLevel: level))),
            ),
          ),
        );
      },
    );
  }
}

class _Lang extends StatelessWidget {
  const _Lang({required this.lang, required this.onTap});
  final String lang;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: lang == 'en' ? 'Speaking English. Switch to Malayalam' : 'Speaking Malayalam. Switch to English',
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
        child: ExcludeSemantics(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.translate_rounded, size: 15, color: Colors.white70),
              const SizedBox(width: 6),
              Text(lang == 'en' ? 'English' : 'മലയാളം', style: lang == 'en' ? TT.ui(13, wght: 600, color: Colors.white) : TT.ml(13, wght: 600, color: Colors.white, height: 1.2)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CallTrip extends StatelessWidget {
  const _CallTrip({required this.journey});
  final Journey journey;

  @override
  Widget build(BuildContext context) => Pressable(
    semanticLabel: '${journey.title} by ${journey.creator.name}',
    onTap: () => openJourney(context, journey),
    child: Container(
      width: 250,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox.square(dimension: 60, child: TgImage(journey.coverPhoto?.url, cacheWidth: 70))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(journey.title, style: TT.ui(13.5, wght: 650, color: Colors.white), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${money(journey.budgetTotal, journey.currency)} · @${journey.creator.handle}', style: TT.ui(12, color: Colors.white60), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.label, required this.onTap, this.on = false, this.color, this.size = 60});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool on;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    toggled: color == null ? on : null,
    label: label,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color ?? (on ? Colors.white : Colors.white12),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(dimension: size, child: Icon(icon, color: color != null ? Colors.white : (on ? TG.night : Colors.white), size: size * 0.42)),
          ),
        ),
        const SizedBox(height: 8),
        ExcludeSemantics(child: Text(label, style: TT.ui(12.5, color: Colors.white70))),
      ],
    ),
  );
}
