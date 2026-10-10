import 'package:flutter/material.dart';

import '../data/models.dart';
import '../theme/tg_theme.dart';
import '../util/format.dart';

/// Proportional, colour-coded bar of where the money went; grows in on mount.
class BudgetBar extends StatelessWidget {
  const BudgetBar({super.key, required this.parts, this.height = 10});

  /// category → amount
  final Map<String, int> parts;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = parts.values.fold<int>(0, (s, v) => s + v);
    if (total == 0) return Container(height: height, decoration: BoxDecoration(color: TG.surface, borderRadius: BorderRadius.circular(height)));
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, t, _) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              for (final e in parts.entries)
                if (e.value > 0)
                  Flexible(
                    flex: (e.value * 1000 ~/ total).clamp(1, 1000),
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: t,
                      child: Container(margin: const EdgeInsets.only(right: 2), color: TG.budgetColors[e.key] ?? TG.muted),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The trip's budget: bar, category rows with their items, totals.
class BudgetBreakdown extends StatelessWidget {
  const BudgetBreakdown({super.key, required this.journey});
  final Journey journey;

  @override
  Widget build(BuildContext context) {
    final j = journey;
    return Semantics(
      label: 'Budget ${money(j.budgetTotal, j.currency)} for ${plural(j.travelers, 'traveller')}. '
          '${j.budget.map((c) => '${TG.budgetLabels[c.category]} ${money(c.amount, j.currency)}').join(', ')}.',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(border: Border.all(color: TG.line), borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Total spent', style: TT.ui(13, color: TG.muted)),
                        Text(money(j.budgetTotal, j.currency), style: TT.display(26, wght: 750)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${money(j.perPersonPerDay, j.currency)} / person / day', style: TT.ui(13, wght: 600)),
                      if (j.currency != 'AED') Text('≈ ${money(j.budgetAed, 'AED')}', style: TT.ui(12.5, color: TG.muted)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              BudgetBar(parts: {for (final c in j.budget) c.category: c.amount}),
              const SizedBox(height: 10),
              for (final c in j.budget)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: TG.budgetColors[c.category], borderRadius: BorderRadius.circular(3))),
                          const SizedBox(width: 8),
                          Expanded(child: Text(TG.budgetLabels[c.category] ?? c.category, style: TT.ui(14.5, wght: 600))),
                          Text(money(c.amount, j.currency), style: TT.ui(14.5, wght: 650)),
                        ],
                      ),
                      for (final item in c.items)
                        Padding(
                          padding: const EdgeInsets.only(left: 18, top: 4),
                          child: Row(
                            children: [
                              Expanded(child: Text(item.label, style: TT.ui(13, color: TG.muted))),
                              Text(money(item.amount, j.currency), style: TT.ui(13, color: TG.muted)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
