import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api.dart';
import '../../data/models.dart';
import '../../data/session.dart';
import '../../theme/tg_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';

const _docs = [
  (id: 'passport', label: 'Passport', hint: 'Photo page, all corners visible', icon: Icons.badge_outlined),
  (id: 'residence', label: 'Residence visa / Emirates ID', hint: 'Front side', icon: Icons.credit_card_outlined),
  (id: 'bank', label: 'Bank statement', hint: 'Last 3 months, balance visible', icon: Icons.account_balance_outlined),
  (id: 'photo', label: 'Passport photo', hint: 'Plain light background', icon: Icons.face_outlined),
];

/// Visa readiness: four documents → a score. At 70+ the visa desk calls you.
class DocCheckScreen extends StatefulWidget {
  const DocCheckScreen({super.key, this.journey});
  final Journey? journey;

  @override
  State<DocCheckScreen> createState() => _DocCheckScreenState();
}

class _DocCheckScreenState extends State<DocCheckScreen> {
  final _files = <String, XFile>{};
  final _bytes = <String, Uint8List>{};
  final _picker = ImagePicker();
  late final _destination = TextEditingController(text: widget.journey == null ? '' : '${widget.journey!.region}, ${widget.journey!.country}');
  int _month = DateTime.now().month % 12 + 1;
  late int _travelers = widget.journey?.travelers ?? 1;
  bool _consent = Session.instance.creator != null;
  bool _checking = false;
  DocCheck? _result;

  @override
  void dispose() {
    _destination.dispose();
    super.dispose();
  }

  Future<void> _pick(String id) async {
    final source = kIsWeb
        ? ImageSource.gallery
        : await showModalBottomSheet<ImageSource>(
            context: context,
            builder: (context) => SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('Take a photo'), onTap: () => Navigator.pop(context, ImageSource.camera)),
                  ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
                ],
              ),
            ),
          );
    if (source == null) return;
    try {
      final f = await _picker.pickImage(source: source, maxWidth: 2000, imageQuality: 85);
      if (f == null) return;
      final b = await f.readAsBytes();
      setState(() {
        _files[id] = f;
        _bytes[id] = b;
        _result = null;
      });
    } on PlatformException catch (e) {
      if (mounted) showSnack(context, 'Couldn’t open the camera or photos (${e.code}).');
    }
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      final r = await Api.instance.checkDocuments(
        _files,
        destination: _destination.text.trim(),
        month: _month,
        travelers: _travelers,
        consent: _consent,
        journeyId: widget.journey?.id,
      );
      HapticFeedback.mediumImpact();
      setState(() => _result = r);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Visa document check')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text('Are you ready to apply?', style: TT.display(24, wght: 750)),
          const SizedBox(height: 6),
          Text(
            'Add up to four documents. We check them against the basic visa conditions and give you a readiness score. Your files are checked and then discarded — never stored.',
            style: TT.ui(14, color: TG.muted, height: 1.5),
          ),
          const SizedBox(height: 18),
          if (r != null) ...[_ResultCard(result: r), const SizedBox(height: 18)],
          for (final d in _docs) _DocSlot(doc: d, bytes: _bytes[d.id], check: r?.checks.where((c) => c.doc == d.id).firstOrNull, onTap: () => _pick(d.id)),
          const SizedBox(height: 12),
          TextField(controller: _destination, decoration: const InputDecoration(labelText: 'Where are you going?', hintText: 'Georgia, Oman, Schengen…', prefixIcon: Icon(Icons.flight_outlined))),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _month,
                  decoration: const InputDecoration(labelText: 'Travel month'),
                  items: [for (var m = 1; m <= 12; m++) DropdownMenuItem(value: m, child: Text(monthNames[m - 1]))],
                  onChanged: (v) => setState(() => _month = v ?? _month),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _travelers,
                  decoration: const InputDecoration(labelText: 'Travellers'),
                  items: [for (var n = 1; n <= 10; n++) DropdownMenuItem(value: n, child: Text('$n'))],
                  onChanged: (v) => setState(() => _travelers = v ?? _travelers),
                ),
              ),
            ],
          ),
          CheckboxListTile(
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text('If I’m ready, the visa desk can call me with the best price', style: TT.ui(13.5, color: TG.ink2)),
          ),
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TG.accent),
            onPressed: _files.isEmpty || _checking ? null : _check,
            child: _checking
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      const SizedBox(width: 10),
                      Text('Checking ${plural(_files.length, 'document')}…'),
                    ],
                  )
                : Text(_files.isEmpty ? 'Add a document to start' : 'Check my documents'),
          ),
        ],
      ),
    );
  }
}

class _DocSlot extends StatelessWidget {
  const _DocSlot({required this.doc, required this.bytes, required this.check, required this.onTap});
  final ({String id, String label, String hint, IconData icon}) doc;
  final Uint8List? bytes;
  final DocCheckItem? check;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (check?.status) {
      'ok' => (TG.success, Icons.check_circle_rounded),
      'warning' => (const Color(0xFFB45309), Icons.error_outline_rounded),
      'missing' => (TG.faint, Icons.remove_circle_outline_rounded),
      _ => (TG.faint, bytes == null ? Icons.add_circle_outline_rounded : Icons.check_rounded),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: TG.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: bytes == null ? ColoredBox(color: TG.bg, child: Icon(doc.icon, color: TG.muted)) : Image.memory(bytes!, fit: BoxFit.cover, cacheWidth: 150),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(doc.label, style: TT.ui(14.5, wght: 650)),
                      const SizedBox(height: 2),
                      Text(check?.note ?? (bytes == null ? doc.hint : 'Added — tap to replace'), style: TT.ui(12.5, color: check == null ? TG.muted : color, height: 1.35)),
                    ],
                  ),
                ),
                Icon(icon, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final DocCheck result;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final pass = r.score >= r.passScore;
    final color = pass ? TG.success : (r.score >= 40 ? const Color(0xFFB45309) : TG.like);
    final callLine = switch (r.callStatus) {
      'ringing' => 'Our visa desk is calling you now on your phone — pick up to get the best price.',
      'simulated' => 'You qualify! Our visa desk will call you shortly with the best price.',
      'failed' => 'You qualify! We couldn’t place the call right now — we’ll WhatsApp you instead.',
      _ => pass ? 'You qualify. Tick the box below to get a call with the best price.' : 'Fix the items marked below and check again to reach ${r.passScore}.',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox.square(
                dimension: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.expand(child: CircularProgressIndicator(value: r.score / 100, strokeWidth: 7, color: color, backgroundColor: TG.line)),
                    Text('${r.score}', style: TT.display(24, wght: 800, color: color)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pass ? 'Ready to apply' : 'Not ready yet', style: TT.display(18, wght: 750, color: color)),
                    const SizedBox(height: 4),
                    Text(r.summary, style: TT.ui(13.5, color: TG.ink2, height: 1.4)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(pass ? Icons.phone_in_talk_rounded : Icons.info_outline_rounded, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(callLine, style: TT.ui(13.5, wght: 600, color: TG.ink))),
            ],
          ),
          if (r.source == 'basic') ...[
            const SizedBox(height: 8),
            Text('AI review was unavailable, so this score only checks which documents are present.', style: TT.ui(12, color: TG.muted)),
          ],
        ],
      ),
    );
  }
}
