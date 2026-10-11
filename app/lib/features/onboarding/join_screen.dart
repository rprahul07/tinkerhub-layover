import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/session.dart';
import '../../theme/tg_theme.dart';
import '../explore/server_sheet.dart';

/// First launch: a profile is the sign-up. Name, handle, home city.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _name = TextEditingController();
  final _handle = TextEditingController();
  final _home = TextEditingController(text: 'Dubai');
  final _phone = TextEditingController(text: '+971 ');
  bool _consent = true;
  bool _handleEdited = false;
  bool _saving = false;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _name.dispose();
    _handle.dispose();
    _home.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _suggestHandle(String name) {
    if (_handleEdited) return;
    _handle.text = name.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '.').replaceAll(RegExp(r'^\.|\.$'), '');
  }

  Future<void> _join() async {
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      final creator = await Api.instance.createCreator(
        name: _name.text.trim(),
        handle: _handle.text.trim(),
        home: _home.text.trim(),
        phone: _phone.text.trim(),
        consent: _consent,
      );
      await Session.instance.setCreator(creator);
    } on ApiException catch (e) {
      if (mounted) setState(() => _errors = e.details.isEmpty ? {'name': e.message} : e.details);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
          children: [
            GestureDetector(
              onLongPress: () => showServerSheet(context),
              child: Text('Travelgram', style: TT.display(30, wght: 800, spacing: -0.04)),
            ),
            const SizedBox(height: 28),
            Text('Trips worth copying.', style: TT.display(34, wght: 750, height: 1.08)),
            const SizedBox(height: 10),
            Text(
              'Real itineraries with real budgets, posted by travellers you can follow. Plan your own with our AI travel consultant.',
              style: TT.ui(16, color: TG.muted, height: 1.5),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              onChanged: _suggestHandle,
              decoration: InputDecoration(labelText: 'Your name', errorText: _errors['name']),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _handle,
              autocorrect: false,
              onChanged: (_) => _handleEdited = true,
              decoration: InputDecoration(labelText: 'Username', prefixText: '@', errorText: _errors['handle']),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _home,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Home city'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumber],
              decoration: InputDecoration(labelText: 'Mobile number', prefixIcon: const Icon(Icons.phone_outlined), errorText: _errors['phone']),
            ),
            CheckboxListTile(
              value: _consent,
              onChanged: (v) => setState(() => _consent = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text('Travelgram’s visa & travel desk may call or WhatsApp me about my trips', style: TT.ui(13.5, color: TG.ink2)),
            ),
            const SizedBox(height: 12),
            ListenableBuilder(
              listenable: Listenable.merge([_name, _handle, _phone]),
              builder: (context, _) => FilledButton(
                onPressed: _saving || _name.text.trim().length < 2 || _handle.text.trim().length < 3 || _phone.text.replaceAll(RegExp(r'\D'), '').length < 8 ? null : _join,
                child: _saving
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Continue'),
              ),
            ),
            const SizedBox(height: 14),
            Text('No password needed for the demo. Your profile lives on this device.', style: TT.ui(12.5, color: TG.faint), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
