import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../data/models.dart';
import '../../theme/tg_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../home/post_card.dart';
import '../journey/journey_screen.dart';
import '../planner/planner_screen.dart';
import 'ammachi_art.dart';
import 'ammachi_controller.dart';
import 'call_screen.dart';

final _malayalam = RegExp(r'[ഀ-ൿ]');
bool isMalayalam(String s) => _malayalam.hasMatch(s);

/// Chat with Ammachi: type or talk, she answers in Malayalam (or English)
/// and points to real trips from the community.
class AmmachiScreen extends StatefulWidget {
  const AmmachiScreen({super.key, this.contextJourney, this.initialPrompt});

  final Journey? contextJourney;
  final String? initialPrompt; // sent as soon as the screen opens

  @override
  State<AmmachiScreen> createState() => _AmmachiScreenState();
}

class _AmmachiScreenState extends State<AmmachiScreen> {
  late final AmmachiController _c = AmmachiController(contextJourney: widget.contextJourney);
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChange);
    _c.init().then((_) {
      if (widget.initialPrompt != null && mounted) _c.send(widget.initialPrompt!);
    });
  }

  void _onChange() {
    final notice = _c.takeNotice();
    if (notice != null && mounted) showSnack(context, notice);
    // Keep the newest words in view while Ammachi talks.
    final count = _c.messages.length * 1000 + (_c.messages.isEmpty ? 0 : _c.messages.last.text.length ~/ 40 + _c.messages.last.citations.length);
    if (count != _lastCount) {
      _lastCount = count;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onChange);
    _c.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _submit([String? text]) {
    final t = text ?? _input.text;
    if (t.trim().isEmpty) return;
    _input.clear();
    _c.send(t);
  }

  Future<void> _call() async {
    await _c.stopSpeaking();
    if (mounted) await CallScreen.open(context, contextJourney: _c.contextJourney);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              _AvatarDot(mood: _c.mood, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Ammachi', style: TT.ui(16, wght: 700)),
                    Text(
                      _statusLine(),
                      style: TT.ui(12, color: TG.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            _LangToggle(lang: _c.lang, onChanged: _c.setLang),
            IconButton(
              tooltip: _c.voiceOn ? 'Turn voice off' : 'Turn voice on',
              onPressed: () => _c.setVoice(!_c.voiceOn),
              icon: Icon(_c.voiceOn ? Icons.volume_up_outlined : Icons.volume_off_outlined),
            ),
            IconButton(
              tooltip: 'Call Ammachi',
              onPressed: _call,
              style: IconButton.styleFrom(backgroundColor: TG.success, foregroundColor: Colors.white),
              icon: const Icon(Icons.call, size: 20),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            if (_c.contextJourney != null) _ContextChip(journey: _c.contextJourney!, onClear: _c.clearContext),
            Expanded(
              child: _c.messages.isEmpty
                  ? _Welcome(controller: _c, onPick: _submit, onCall: _call)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                      itemCount: _c.messages.length,
                      itemBuilder: (context, i) {
                        final m = _c.messages[i];
                        return m.fromUser ? _UserBubble(text: m.text) : _AmmachiBubble(message: m, controller: _c);
                      },
                    ),
            ),
            _Composer(controller: _c, input: _input, onSubmit: _submit),
          ],
        ),
      ),
    );
  }

  String _statusLine() {
    if (_c.listening) return _c.lang == 'en' ? 'Listening…' : 'കേൾക്കുന്നു…';
    if (_c.mood == AmmachiMood.thinking) return _c.lang == 'en' ? 'Thinking…' : 'ആലോചിക്കുന്നു…';
    if (_c.mood == AmmachiMood.speaking) return _c.lang == 'en' ? 'Speaking' : 'സംസാരിക്കുന്നു';
    final s = _c.status;
    if (s == null) return 'Travel assistant';
    return s.brain == 'gemini' ? 'Travel assistant · ${s.voice ? 'voice on' : 'text only'}' : 'Offline mode · community trips only';
  }
}

class _AvatarDot extends StatelessWidget {
  const _AvatarDot({required this.mood, this.size = 38});
  final AmmachiMood mood;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: TG.surface,
      shape: BoxShape.circle,
      border: Border.all(color: TG.line),
    ),
    child: ClipOval(
      child: OverflowBox(
        maxWidth: size * 1.45,
        maxHeight: size * 1.45,
        child: AmmachiAvatar(mood: mood, size: size * 1.45),
      ),
    ),
  );
}

class _LangToggle extends StatelessWidget {
  const _LangToggle({required this.lang, required this.onChanged});
  final String lang;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(String value, String label, TextStyle style) {
      final on = lang == value;
      return Semantics(
        selected: on,
        button: true,
        label: value == 'ml' ? 'Malayalam' : 'English',
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onChanged(value);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 32),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(color: on ? TG.ink : Colors.transparent, borderRadius: BorderRadius.circular(8)),
            child: ExcludeSemantics(
              child: Text(label, style: style.copyWith(color: on ? Colors.white : TG.muted)),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: TG.surface, borderRadius: BorderRadius.circular(11)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [seg('ml', 'മല', TT.ml(13, wght: 600, height: 1.2)), seg('en', 'EN', TT.ui(12.5, wght: 650))]),
    );
  }
}

class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.journey, required this.onClear});
  final Journey journey;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
    padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
    decoration: BoxDecoration(color: TG.surface, borderRadius: BorderRadius.circular(12)),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox.square(dimension: 36, child: TgImage(journey.coverPhoto?.url, cacheWidth: 40)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Talking about', style: TT.ui(11.5, color: TG.muted)),
              Text(journey.title, style: TT.ui(13.5, wght: 650), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Talk about anything',
          onPressed: onClear,
          icon: const Icon(Icons.close, size: 18, color: TG.muted),
        ),
      ],
    ),
  );
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.controller, required this.onPick, required this.onCall});
  final AmmachiController controller;
  final ValueChanged<String> onPick;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final en = controller.lang == 'en';
    final journey = controller.contextJourney;
    final ideas = journey != null
        ? (en
              ? ['Tell me this trip like a story', 'Can I do this cheaper?', 'What should I pack?']
              : ['ഈ യാത്ര ഒരു കഥ പോലെ പറഞ്ഞുതരാമോ?', 'ഇത് കുറഞ്ഞ ചിലവിൽ ചെയ്യാൻ പറ്റുമോ?', 'എന്തൊക്കെ കൊണ്ടുപോകണം?'])
        : (en
              ? ['A weekend from Dubai under AED 1,000', 'Somewhere cool to escape the heat', 'Desert camp for a family of four']
              : ['ദുബായിൽ നിന്ന് 1000 ദിർഹത്തിന് ഒരു വീക്കെൻഡ്?', 'ചൂടിൽ നിന്ന് രക്ഷപ്പെടാൻ ഒരു തണുത്ത സ്ഥലം', 'നാലുപേരുള്ള കുടുംബത്തിന് ഡെസേർട്ട് ക്യാമ്പ്']);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      children: [
        Center(
          child: Container(
            width: 132,
            height: 132,
            decoration: const BoxDecoration(color: TG.surface, shape: BoxShape.circle),
            child: ClipOval(
              child: OverflowBox(maxWidth: 180, maxHeight: 180, child: AmmachiAvatar(mood: controller.mood, size: 180)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(en ? 'Hi, I’m Ammachi' : 'ഹലോ കുഞ്ഞേ, അമ്മച്ചിയാണ്', textAlign: TextAlign.center, style: en ? TT.display(22) : TT.ml(21, wght: 650, height: 1.4)),
        const SizedBox(height: 6),
        Text(
          'Ask about any trip, get a plan that fits your budget, or hear a journey told in Malayalam. Every suggestion comes from a real traveller’s trip.',
          textAlign: TextAlign.center,
          style: TT.ui(14, color: TG.muted, height: 1.5),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: TG.success, minimumSize: const Size(48, 44)),
                onPressed: onCall,
                icon: const Icon(Icons.call, size: 18),
                label: const Text('Call her'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PlannerScreen())),
                icon: const Icon(Icons.savings_outlined, size: 18),
                label: const Text('Plan a trip', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(en ? 'Try asking' : 'ചോദിച്ചു നോക്കൂ', style: TT.ui(13, wght: 650, color: TG.muted)),
        const SizedBox(height: 8),
        for (final (i, idea) in ideas.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: TG.surface,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onPick(idea),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(child: Text(idea, style: isMalayalam(idea) ? TT.ml(14.5, height: 1.45) : TT.ui(14.5))),
                      const Icon(Icons.north_east_rounded, size: 16, color: TG.faint),
                    ],
                  ),
                ),
              ),
            ),
          ).animate().fadeIn(delay: (80 * i).ms, duration: 250.ms).slideY(begin: 0.15, end: 0),
      ],
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerRight,
    child: Container(
      margin: const EdgeInsets.only(left: 56, bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: TG.ink,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: Text(
        text,
        style: isMalayalam(text) ? TT.ml(15, color: Colors.white, height: 1.5) : TT.ui(15, color: Colors.white),
      ),
    ),
  );
}

class _AmmachiBubble extends StatelessWidget {
  const _AmmachiBubble({required this.message, required this.controller});
  final ChatMessage message;
  final AmmachiController controller;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final text = m.text.trim();
    return Padding(
      padding: const EdgeInsets.only(right: 24, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: const BoxDecoration(
              color: TG.surface,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: text.isEmpty && m.failure == null
                ? const _Dots()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (text.isNotEmpty) Text(text, style: isMalayalam(text) ? TT.ml(16, height: 1.65) : TT.ui(15.5, height: 1.5)),
                      if (m.failure != null) ...[if (text.isNotEmpty) const SizedBox(height: 6), Text(m.failure!, style: TT.ui(13.5, color: TG.like))],
                    ],
                  ),
          ),
          for (final j in m.citations) _CitedTrip(journey: j),
          if (!m.streaming && text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: TG.muted, minimumSize: const Size(40, 34), padding: const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: () => controller.replay(m),
                    icon: const Icon(Icons.volume_up_outlined, size: 16),
                    label: Text('Listen', style: TT.ui(12.5, wght: 600, color: TG.muted)),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(foregroundColor: TG.muted, minimumSize: const Size(40, 34), padding: const EdgeInsets.symmetric(horizontal: 8)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: text));
                      showSnack(context, 'Copied');
                    },
                    icon: const Icon(Icons.copy_rounded, size: 15),
                    label: Text('Copy', style: TT.ui(12.5, wght: 600, color: TG.muted)),
                  ),
                  if (m.mode == 'offline')
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Tooltip(
                        message: 'The AI model wasn’t reachable, so this answer comes straight from community trips.',
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: TG.surfaceHigh, borderRadius: BorderRadius.circular(6)),
                          child: Text('Offline', style: TT.ui(11, wght: 650, color: TG.muted)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A trip Ammachi mentioned, credited to its creator.
class _CitedTrip extends StatelessWidget {
  const _CitedTrip({required this.journey});
  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final j = journey;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Pressable(
        semanticLabel: '${j.title} by ${j.creator.name}. ${tripMeta(j)}',
        onTap: () => openJourney(context, j),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: TG.bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: TG.line),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox.square(dimension: 60, child: TgImage(j.coverPhoto?.url, cacheWidth: 70)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(j.title, style: TT.ui(14, wght: 650), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      '${money(j.budgetTotal, j.currency)} · ${plural(j.durationDays, 'day')} · ${placeLine(j)}',
                      style: TT.ui(12.5, color: TG.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Avatar(j.creator, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'by @${j.creator.handle}',
                            style: TT.ui(12, wght: 600, color: TG.ink2),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: TG.faint),
            ],
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Ammachi is thinking',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            decoration: const BoxDecoration(color: TG.faint, shape: BoxShape.circle),
          ).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(delay: (150 * i).ms, duration: 450.ms).scaleXY(begin: 0.7, end: 1, duration: 450.ms),
      ],
    ),
  );
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.input, required this.onSubmit});
  final AmmachiController controller;
  final TextEditingController input;
  final ValueChanged<String?> onSubmit;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final en = c.lang == 'en';
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: TG.bg,
        border: Border(top: BorderSide(color: TG.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: c.listening
                    ? Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(color: TG.accentSoft, borderRadius: BorderRadius.circular(24)),
                        child: Text(
                          c.partial.isEmpty ? (en ? 'Listening… speak now' : 'കേൾക്കുന്നു… പറഞ്ഞോളൂ') : c.partial,
                          style: isMalayalam(c.partial) || (!en && c.partial.isEmpty) ? TT.ml(15, color: TG.ink2, height: 1.4) : TT.ui(15, color: TG.ink2),
                        ),
                      )
                    : TextField(
                        controller: input,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: onSubmit,
                        style: TT.ui(15),
                        decoration: InputDecoration(
                          hintText: en ? 'Ask Ammachi…' : 'അമ്മച്ചിയോട് ചോദിക്കൂ…',
                          hintStyle: en ? TT.ui(15, color: TG.faint) : TT.ml(15, color: TG.faint, height: 1.3),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: const BorderSide(color: TG.line),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              ListenableBuilder(
                listenable: input,
                builder: (context, _) {
                  final typing = input.text.trim().isNotEmpty && !c.listening;
                  if (typing) {
                    return IconButton.filled(
                      tooltip: 'Send',
                      style: IconButton.styleFrom(backgroundColor: TG.ink, minimumSize: const Size(48, 48)),
                      onPressed: () => onSubmit(null),
                      icon: const Icon(Icons.arrow_upward_rounded),
                    );
                  }
                  return Semantics(
                    button: true,
                    toggled: c.listening,
                    label: c.listening ? 'Stop listening' : 'Talk to Ammachi',
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        c.toggleListening();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.listening ? TG.accent : TG.surface,
                          boxShadow: c.listening
                              ? [BoxShadow(color: TG.accent.withValues(alpha: 0.35), blurRadius: 6 + 18 * c.soundLevel, spreadRadius: 6 * c.soundLevel)]
                              : null,
                        ),
                        child: ExcludeSemantics(
                          child: Icon(c.listening ? Icons.stop_rounded : Icons.mic_none_rounded, color: c.listening ? Colors.white : TG.ink),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
