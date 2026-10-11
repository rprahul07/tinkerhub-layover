import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/models.dart';
import '../../theme/tg_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../ammachi/call_screen.dart';
import '../documents/doc_check_screen.dart';
import '../planner/planner_screen.dart';

/// The travel desk: the two tools that turn browsing into a trip —
/// the smart visa document checker and the budget trip planner.
class DeskScreen extends StatefulWidget {
  const DeskScreen({super.key});

  @override
  State<DeskScreen> createState() => DeskScreenState();
}

class DeskScreenState extends State<DeskScreen> {
  DocCheck? _lastCheck;
  List<TripPlan>? _plans;
  List<Booking>? _bookings;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final r = await Future.wait([Api.instance.lastDocCheck(), Api.instance.myPlans(), Api.instance.myBookings()]);
      if (!mounted) return;
      setState(() {
        _lastCheck = r[0] as DocCheck?;
        _plans = r[1] as List<TripPlan>;
        _bookings = r[2] as List<Booking>;
      });
    } on ApiException {
      if (mounted) setState(() => _plans ??= const []);
    }
  }

  Future<void> _open(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    refresh();
  }

  @override
  Widget build(BuildContext context) {
    final plans = _plans;
    final bookings = _bookings ?? const <Booking>[];
    return Scaffold(
      appBar: AppBar(title: Text('Travel desk', style: TT.display(22, wght: 750))),
      body: RefreshIndicator(
        color: TG.accent,
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Text('Get visa-ready and plan on a budget — free.', style: TT.ui(14.5, color: TG.muted)),
            const SizedBox(height: 16),
            _ToolCard(
              color: TG.going,
              soft: TG.goingSoft,
              icon: Icons.fact_check_outlined,
              title: 'Smart document checker',
              body: 'Add up to 4 documents and get a visa-readiness score in seconds. Score 70+ and our visa desk calls you with the best price.',
              cta: _lastCheck == null ? 'Check my documents' : 'Check again',
              onTap: () => _open(const DocCheckScreen()),
              footer: _lastCheck == null ? null : _LastCheck(check: _lastCheck!),
            ),
            const SizedBox(height: 14),
            _ToolCard(
              color: TG.accent,
              soft: TG.accentSoft,
              icon: Icons.savings_outlined,
              title: 'Budget trip planner',
              body: 'Tell the AI consultant what you can spend. It builds a day-by-day plan from real trips and real prices in the community.',
              cta: 'Plan a trip',
              onTap: () => _open(const PlannerScreen()),
              footer: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (label, budget, days) in const [('AED 500 · 1 day', 500, 1), ('AED 1,500 · weekend', 1500, 2), ('AED 5,000 · 5 days', 5000, 5)])
                    FilterPill(label: label, selected: false, onTap: () => _open(PlannerScreen(budget: budget, days: days))),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Material(
              color: TG.surface,
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                leading: const CircleAvatar(backgroundColor: TG.success, child: Icon(Icons.call, color: Colors.white, size: 20)),
                title: Text('Rather talk it through?', style: TT.ui(15, wght: 650)),
                subtitle: Text('Call the AI consultant — Malayalam or English', style: TT.ui(13, color: TG.muted)),
                trailing: const Icon(Icons.chevron_right_rounded, color: TG.faint),
                onTap: () => CallScreen.open(context),
              ),
            ),
            if (plans != null && plans.isNotEmpty) ...[
              const SectionTitle('Your plans', padding: EdgeInsets.fromLTRB(0, 24, 0, 6)),
              for (final p in plans.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: TG.accentSoft, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.savings_outlined, color: TG.accent),
                  ),
                  title: Text(p.title, style: TT.ui(14.5, wght: 650), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${plural(p.dayCount, 'day')} · ${plural(p.travelers, 'traveller')} · ${p.totalLabel}', style: TT.ui(13, color: TG.muted)),
                  trailing: const Icon(Icons.chevron_right_rounded, color: TG.faint),
                  onTap: () => _open(PlanScreen(plan: p)),
                ),
            ],
            if (bookings.isNotEmpty) ...[
              const SectionTitle('Your bookings', padding: EdgeInsets.fromLTRB(0, 24, 0, 6)),
              for (final b in bookings.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: TG.goingSoft, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.confirmation_number_outlined, color: TG.going),
                  ),
                  title: Text(b.item, style: TT.ui(14.5, wght: 650), maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${b.date} · ${plural(b.guests, 'guest')} · ${b.totalLabel}', style: TT.ui(13, color: TG.muted)),
                  trailing: Text(b.ref, style: TT.ui(12, wght: 650, color: TG.ink2)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.color,
    required this.soft,
    required this.icon,
    required this.title,
    required this.body,
    required this.cta,
    required this.onTap,
    this.footer,
  });
  final Color color;
  final Color soft;
  final IconData icon;
  final String title;
  final String body;
  final String cta;
  final VoidCallback onTap;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: TG.bg, borderRadius: BorderRadius.circular(18), border: Border.all(color: TG.line)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: TT.display(18, wght: 750))),
          ],
        ),
        const SizedBox(height: 10),
        Text(body, style: TT.ui(14, color: TG.ink2, height: 1.45)),
        if (footer != null) ...[const SizedBox(height: 12), footer!],
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(style: FilledButton.styleFrom(backgroundColor: color), onPressed: onTap, child: Text(cta)),
        ),
      ],
    ),
  );
}

class _LastCheck extends StatelessWidget {
  const _LastCheck({required this.check});
  final DocCheck check;

  @override
  Widget build(BuildContext context) {
    final pass = check.score >= check.passScore;
    final color = pass ? TG.success : const Color(0xFFB45309);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Text('${check.score}', style: TT.display(26, wght: 800, color: color)),
          Text(' /100', style: TT.ui(13, color: TG.muted)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              pass
                  ? (check.callStatus == 'ringing' || check.callStatus == 'completed' ? 'Ready to apply · our visa desk has called you' : 'Ready to apply · expect a call from our visa desk')
                  : 'Not ready yet · ${check.checks.where((c) => c.status != 'ok').length} documents need attention',
              style: TT.ui(13, wght: 600, color: TG.ink),
            ),
          ),
        ],
      ),
    );
  }
}
