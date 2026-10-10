import 'package:flutter/material.dart';

import '../../data/session.dart';
import '../../theme/tg_theme.dart';

/// Hidden setting (long-press the wordmark): which server the app talks to.
Future<void> showServerSheet(BuildContext context) async {
  final session = Session.instance;
  final controller = TextEditingController(text: session.apiBase);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Server address', style: TT.display(20)),
          const SizedBox(height: 6),
          Text('Point the app at a Travelgram backend, e.g. https://your-tunnel.ngrok-free.dev', style: TT.ui(13.5, color: TG.muted)),
          const SizedBox(height: 14),
          TextField(controller: controller, keyboardType: TextInputType.url, autocorrect: false),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton(
                onPressed: () async {
                  await session.setApiBase(null);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Reset'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () async {
                  await session.setApiBase(controller.text);
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
