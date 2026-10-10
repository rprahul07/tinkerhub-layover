import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../../data/api.dart';
import '../../data/models.dart';
import '../../data/session.dart';
import '../../theme/tg_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../ammachi/ammachi_art.dart';
import '../home/post_card.dart';

const _interests = ['desert', 'beach', 'mountains', 'city', 'culture', 'food', 'adventure', 'family', 'couples'];

/// "I have AED 1,000 and 2 days" → a real plan.
class PlannerScreen extends StatefulWidget {
  const PlannerScreen({super.key, this.budget, this.days, this.travelers, this.interests = const []});

  final int? budget; // AED
  final int? days;
  final int? travelers;
  final List<String> interests;

  @override
  State<PlannerScreen> createState() => _PlannerScreenState();
}

class _PlannerScreenState extends State<PlannerScreen> {
  late final _budget = TextEditingController(text: widget.budget == null ? '' : '${widget.budget}');
  late final _from = TextEditingController(text: Session.instance.creator?.home ?? '');
  String _currency = 'AED';
  late int _days = widget.days ?? 2;
  late int _travelers = widget.travelers ?? 2;
  late final Set<String> _picked = {...widget.interests.where(_interests.contains)};
  int? _month;
  bool _busy = false;

  @override
  void dispose() {
    _budget.dispose();
    _from.dispose();
    super.dispose();
  }

  Future<void> _plan() async {
    final budget = int.tryParse(_budget.text.replaceAll(',', ''));
    if (budget == null || budget <= 0) {
      showSnack(context, 'Enter your budget first.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final plan = await Api.instance.plan(
        budget: budget,
        currency: _currency,
        days: _days,
        travelers: _travelers,
        interests: _picked.toList(),
        from: _from.text.trim(),
        month: _month,
        lang: Session.instance.ammachiLang,
      );
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlanScreen(plan: plan)));
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Plan with Ammachi')),
      body: _busy
          ? const _Planning()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text('What can you spend?', style: TT.display(24, wght: 750)),
                const SizedBox(height: 4),
                Text('Ammachi builds a day-by-day plan from trips people actually took, with what they actually paid.', style: TT.ui(14.5, color: TG.muted)),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _budget,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)],
                        style: TT.display(24, wght: 700),
                        decoration: const InputDecoration(labelText: 'Total budget'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 104,
                      child: DropdownButtonFormField<String>(
                        initialValue: _currency,
                        items: [for (final c in currencies) DropdownMenuItem(value: c, child: Text(c))],
                        onChanged: (v) => setState(() => _currency = v ?? 'AED'),
                        decoration: const InputDecoration(labelText: 'Currency'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _Stepper(label: 'Days', value: _days, min: 1, max: 14, onChanged: (v) => setState(() => _days = v)),
                _Stepper(label: 'Travellers', value: _travelers, min: 1, max: 20, onChanged: (v) => setState(() => _travelers = v)),
                const SizedBox(height: 12),
                Text('What do you enjoy?', style: TT.ui(14, wght: 650)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final i in _interests)
                      FilterPill(
                        label: i[0].toUpperCase() + i.substring(1),
                        selected: _picked.contains(i),
                        onTap: () => setState(() => _picked.contains(i) ? _picked.remove(i) : _picked.add(i)),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text('When (optional)', style: TT.ui(14, wght: 650)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: 12,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, i) => FilterPill(
                      label: monthShort[i],
                      selected: _month == i + 1,
                      onTap: () => setState(() => _month = _month == i + 1 ? null : i + 1),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                TextField(controller: _from, decoration: const InputDecoration(labelText: 'Starting from', hintText: 'Dubai')),
                const SizedBox(height: 24),
                FilledButton.icon(onPressed: _plan, icon: const Icon(Icons.auto_awesome, size: 18), label: const Text('Build my plan')),
              ],
            ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, required this.min, required this.max, required this.onChanged});
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label, style: TT.ui(15, wght: 600))),
        IconButton.outlined(
          tooltip: 'Fewer $label'.toLowerCase(),
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove, size: 18),
        ),
        SizedBox(width: 40, child: Text('$value', textAlign: TextAlign.center, style: TT.display(18, wght: 700))),
        IconButton.outlined(
          tooltip: 'More $label'.toLowerCase(),
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add, size: 18),
        ),
      ],
    ),
  );
}

class _Planning extends StatelessWidget {
  const _Planning();

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: const BoxDecoration(color: TG.surface, shape: BoxShape.circle),
          child: const ClipOval(child: OverflowBox(maxWidth: 170, maxHeight: 170, child: AmmachiAvatar(mood: AmmachiMood.thinking, size: 170))),
        ),
        const SizedBox(height: 18),
        Text('Ammachi is planning…', style: TT.display(19)),
        const SizedBox(height: 4),
        Text('Matching your budget against real trips.', style: TT.ui(14, color: TG.muted)),
        const SizedBox(height: 20),
        const SizedBox(width: 140, child: LinearProgressIndicator(color: TG.accent, backgroundColor: TG.surface)),
      ],
    ),
  );
}

/// The finished plan: fit against budget, Ammachi's take, days, sources.
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, required this.plan});
  final TripPlan plan;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  final _player = AudioPlayer();
  bool _speaking = false;
  bool _requested = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _listen() async {
    final p = widget.plan;
    if (_speaking) {
      await _player.stop();
      setState(() => _speaking = false);
      return;
    }
    setState(() => _speaking = true);
    try {
      final url = await Api.instance.speak(p.summary, Session.instance.ammachiLang);
      await _player.setUrl(url);
      await _player.play();
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.plan;
    final over = p.totalAed - p.budgetAed;
    final malayalam = RegExp(r'[ഀ-ൿ]').hasMatch(p.summary);
    return Scaffold(
      appBar: AppBar(title: const Text('Your plan')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
        children: [
          Text(p.title, style: TT.display(24, wght: 750)),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(money(p.totalAed, 'AED'), style: TT.display(22, wght: 750)),
              Text('  of ${p.budgetLabel}', style: TT.ui(14, color: TG.muted)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: p.fits ? TG.goingSoft : TG.accentSoft, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  p.fits ? 'Within budget' : 'Over by ${money(over, 'AED')}',
                  style: TT.ui(12.5, wght: 650, color: p.fits ? TG.going : TG.accent),
                ),
              ),
            ],
          ),
          Text('${plural(p.dayCount, 'day')} · ${plural(p.travelers, 'traveller')}', style: TT.ui(13.5, color: TG.muted)),
          if (p.summary.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: TG.surface, borderRadius: BorderRadius.circular(16)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                    child: ClipOval(
                      child: OverflowBox(
                        maxWidth: 58,
                        maxHeight: 58,
                        child: AmmachiAvatar(mood: _speaking ? AmmachiMood.speaking : AmmachiMood.idle, size: 58),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.summary, style: malayalam ? TT.ml(15) : TT.ui(15, height: 1.5)),
                        const SizedBox(height: 4),
                        TextButton.icon(
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(40, 32)),
                          onPressed: _listen,
                          icon: Icon(_speaking ? Icons.stop_rounded : Icons.volume_up_outlined, size: 18),
                          label: Text(_speaking ? 'Stop' : 'Listen'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          for (final d in p.days) ...[
            const SizedBox(height: 20),
            Text('Day ${d.day} · ${d.title}', style: TT.ui(15.5, wght: 700)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(border: Border.all(color: TG.line), borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  for (var i = 0; i < d.items.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(TG.budgetIcons[d.items[i].category] ?? Icons.place_outlined, size: 20, color: TG.budgetColors[d.items[i].category] ?? TG.muted),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d.items[i].place, style: TT.ui(14.5, wght: 650)),
                                if (d.items[i].what.isNotEmpty) Text(d.items[i].what, style: TT.ui(13, color: TG.muted)),
                              ],
                            ),
                          ),
                          Text(money(d.items[i].costAed, 'AED'), style: TT.ui(14, wght: 600)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (p.tips.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Tips', style: TT.ui(15.5, wght: 700)),
            for (final t in p.tips)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(padding: EdgeInsets.only(top: 3), child: Icon(Icons.check_circle_outline, size: 16, color: TG.going)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(t, style: RegExp(r'[ഀ-ൿ]').hasMatch(t) ? TT.ml(14) : TT.ui(14))),
                  ],
                ),
              ),
          ],
          if (p.trips.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Built from these trips', style: TT.ui(15.5, wght: 700)),
            const SizedBox(height: 4),
            for (final j in p.trips) TripTile(journey: j),
          ],
          const SizedBox(height: 8),
          Text(
            p.source == 'gemini' ? 'Planned by Ammachi (Gemini) from community trips. Prices are what travellers paid.' : 'Planned from community trips (offline mode).',
            style: TT.ui(12, color: TG.faint),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _requested ? TG.going : TG.accent),
            onPressed: _requested
                ? null
                : () async {
                    final sent = await showLeadSheet(context, planId: p.id, travelers: p.travelers);
                    if (sent && mounted) setState(() => _requested = true);
                  },
            icon: Icon(_requested ? Icons.check_rounded : Icons.support_agent_rounded, size: 20),
            label: Text(_requested ? 'Request sent' : 'Get this trip booked'),
          ),
        ),
      ),
    );
  }
}

/// Collects contact details with explicit consent, then sends the lead.
Future<bool> showLeadSheet(BuildContext context, {String? planId, String? journeyId, int? travelers}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _LeadSheet(planId: planId, journeyId: journeyId, travelers: travelers),
  );
  return result ?? false;
}

class _LeadSheet extends StatefulWidget {
  const _LeadSheet({this.planId, this.journeyId, this.travelers});
  final String? planId;
  final String? journeyId;
  final int? travelers;

  @override
  State<_LeadSheet> createState() => _LeadSheetState();
}

class _LeadSheetState extends State<_LeadSheet> {
  late final _name = TextEditingController(text: Session.instance.creator?.name ?? '');
  final _phone = TextEditingController(text: '+971 ');
  final _notes = TextEditingController();
  int? _month;
  bool _consent = false;
  bool _sending = false;
  String? _phoneError;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _phoneError = null;
    });
    try {
      await Api.instance.sendLead(
        planId: widget.planId,
        journeyId: widget.journeyId,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        consent: _consent,
        month: _month,
        travelers: widget.travelers,
        notes: _notes.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      showSnack(context, 'Sent. A Travelgram travel partner will message you on WhatsApp.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _phoneError = e.details['phone'] ?? e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Get this trip booked', style: TT.display(20, wght: 750)),
            const SizedBox(height: 4),
            Text('A Travelgram travel partner will price it and message you. No payment now.', style: TT.ui(13.5, color: TG.muted)),
            const SizedBox(height: 16),
            TextField(controller: _name, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 10),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: 'WhatsApp number', errorText: _phoneError),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _month,
              decoration: const InputDecoration(labelText: 'When are you travelling?'),
              items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(monthNames[m - 1]))],
              onChanged: (v) => setState(() => _month = v),
            ),
            const SizedBox(height: 10),
            TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Anything else? (optional)')),
            const SizedBox(height: 6),
            CheckboxListTile(
              value: _consent,
              onChanged: (v) => setState(() => _consent = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('Travelgram’s travel partners may contact me on WhatsApp about this trip.', style: TT.ui(13.5)),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _sending || !_consent || _name.text.trim().length < 2 ? null : _send,
              child: _sending
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Send request'),
            ),
          ],
        ),
      ),
    );
  }
}
