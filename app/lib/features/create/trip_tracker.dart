import 'dart:async';

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
import '../../widgets/route_map.dart';
import 'draft.dart';

/// Create = track a trip as it happens, then post it.
class TripTracker extends StatefulWidget {
  const TripTracker({super.key, required this.onPosted});
  final void Function(Journey journey) onPosted;

  @override
  State<TripTracker> createState() => _TripTrackerState();
}

class _TripTrackerState extends State<TripTracker> {
  TripDraft? _trip = TripDraft.restore();
  Timer? _autosave;
  int _day = 1;

  @override
  void initState() {
    super.initState();
    _day = _trip?.days ?? 1;
  }

  @override
  void dispose() {
    _autosave?.cancel();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 500), () => _trip?.save());
  }

  Future<void> _addPlace() async {
    final place = await showModalBottomSheet<Place>(context: context, isScrollControlled: true, builder: (_) => const _PlaceSearchSheet());
    if (place == null || !mounted) return;
    final p = DraftPlace(name: place.name, region: place.region, country: place.country, lat: place.lat, lng: place.lng, day: _day);
    _trip!.places.add(p);
    _changed();
    await _edit(p);
  }

  Future<void> _edit(DraftPlace p) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaceEditor(trip: _trip!, place: p, onChanged: _changed)));
    _changed();
  }

  Future<void> _discard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard this trip?'),
        content: const Text('Places, photos and expenses you added will be removed from this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard', style: TextStyle(color: TG.like))),
        ],
      ),
    );
    if (ok == true) {
      await TripDraft.discard();
      setState(() => _trip = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    if (trip == null) {
      return _StartTrip(
        onStart: (t) {
          setState(() {
            _trip = t;
            _day = 1;
          });
          t.save();
        },
      );
    }
    final byDay = <int, List<DraftPlace>>{};
    for (final p in trip.places) {
      byDay.putIfAbsent(p.day, () => []).add(p);
    }
    final days = (byDay.keys.toList()..sort());
    final maxDay = days.isEmpty ? 1 : days.last;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(trip.title.isEmpty ? 'Trip to ${trip.destination}' : trip.title, style: TT.display(17, wght: 700)),
            Text('Tracking · ${trip.destination}', style: TT.ui(12, color: TG.muted)),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (v) => v == 'discard' ? _discard() : null,
            itemBuilder: (_) => const [PopupMenuItem(value: 'discard', child: Text('Discard trip'))],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(40, 38), backgroundColor: TG.accent),
              onPressed: trip.places.isEmpty
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PublishScreen(
                          trip: trip,
                          onChanged: _changed,
                          onPosted: (j) async {
                            await TripDraft.discard();
                            setState(() => _trip = null);
                            widget.onPosted(j);
                          },
                        ),
                      ),
                    ),
              child: const Text('Publish'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                _Stat(value: '${trip.places.length}', label: trip.places.length == 1 ? 'place' : 'places'),
                _Stat(value: money(trip.spent, trip.currency), label: 'spent'),
                _Stat(value: '${trip.photoUrls.length}', label: 'photos'),
                _Stat(value: '${trip.travelers}', label: trip.travelers == 1 ? 'traveller' : 'travellers'),
              ],
            ),
          ),
          if (trip.places.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: RouteMap(points: [for (final p in trip.places) RoutePoint(p.name, p.lat, p.lng, p.day)], height: 170, animate: false, compact: true),
              ),
            ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              children: [
                for (var d = 1; d <= maxDay + 1; d++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterPill(label: d > maxDay ? '+ Day $d' : 'Day $d', selected: _day == d, onTap: () => setState(() => _day = d)),
                  ),
              ],
            ),
          ),
          if (trip.places.isEmpty)
            const EmptyView(
              icon: Icons.add_location_alt_outlined,
              title: 'Add your first place',
              body: 'Search a place you visited or are at now. Add photos, what you spent and anything worth knowing.',
            ),
          for (final day in days) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text('Day $day', style: TT.label(12.5, color: TG.accent, wght: 700)),
            ),
            for (final p in byDay[day]!)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 56,
                    height: 56,
                    child: p.photos.isEmpty
                        ? const ColoredBox(color: TG.surface, child: Icon(Icons.photo_camera_outlined, color: TG.faint))
                        : (p.photos.first.bytes != null
                              ? Image.memory(p.photos.first.bytes!, fit: BoxFit.cover, cacheWidth: 150)
                              : TgImage(p.photos.first.url, cacheWidth: 60)),
                  ),
                ),
                title: Text(p.name, style: TT.ui(15, wght: 650)),
                subtitle: Text(
                  [
                    if (p.spent > 0) money(p.spent, trip.currency),
                    plural(p.photos.length, 'photo'),
                    if (p.fields.isNotEmpty) plural(p.fields.length, 'detail'),
                  ].join(' · '),
                  style: TT.ui(13, color: TG.muted),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, color: TG.faint),
                onTap: () => _edit(p),
              ),
          ],
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: TG.ink,
        foregroundColor: Colors.white,
        onPressed: _addPlace,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Text('Add place to Day $_day'),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      label: '$value $label',
      child: ExcludeSemantics(
        child: Column(
          children: [
            FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: TT.display(17, wght: 750))),
            Text(label, style: TT.ui(12, color: TG.muted)),
          ],
        ),
      ),
    ),
  );
}

// ---- start --------------------------------------------------------------------

class _StartTrip extends StatefulWidget {
  const _StartTrip({required this.onStart});
  final ValueChanged<TripDraft> onStart;

  @override
  State<_StartTrip> createState() => _StartTripState();
}

class _StartTripState extends State<_StartTrip> {
  final _title = TextEditingController();
  Place? _destination;
  String _currency = 'AED';
  int _travelers = 1;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDestination() async {
    final place = await showModalBottomSheet<Place>(context: context, isScrollControlled: true, builder: (_) => const _PlaceSearchSheet(title: 'Where are you going?'));
    if (place != null) {
      setState(() {
        _destination = place;
        _currency = currencyForCountry(place.country);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Create', style: TT.display(22, wght: 750))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          Text('Track a trip', style: TT.display(26, wght: 750)),
          const SizedBox(height: 6),
          Text(
            'Add places as you go — photos, what you spent, anything worth knowing. Post it to your followers when you’re back.',
            style: TT.ui(15, color: TG.muted, height: 1.5),
          ),
          const SizedBox(height: 24),
          Semantics(
            button: true,
            label: _destination == null ? 'Choose destination' : 'Destination ${_destination!.name}',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: _pickDestination,
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Destination', prefixIcon: Icon(Icons.place_outlined)),
                child: Text(
                  _destination == null ? 'Search a city or place' : '${_destination!.name}${_destination!.country.isEmpty ? '' : ', ${_destination!.country}'}',
                  style: TT.ui(15, color: _destination == null ? TG.faint : TG.ink),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Trip name (optional)', hintText: 'Long weekend in the mountains'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _currency,
                  decoration: const InputDecoration(labelText: 'Currency'),
                  items: [for (final c in currencies) DropdownMenuItem(value: c, child: Text(c))],
                  onChanged: (v) => setState(() => _currency = v ?? 'AED'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Travellers', contentPadding: EdgeInsets.fromLTRB(16, 6, 4, 6)),
                  child: Row(
                    children: [
                      Expanded(child: Text('$_travelers', style: TT.ui(16, wght: 650))),
                      IconButton(
                        tooltip: 'Fewer travellers',
                        visualDensity: VisualDensity.compact,
                        onPressed: _travelers > 1 ? () => setState(() => _travelers--) : null,
                        icon: const Icon(Icons.remove, size: 18),
                      ),
                      IconButton(
                        tooltip: 'More travellers',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _travelers++),
                        icon: const Icon(Icons.add, size: 18),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _destination == null
                ? null
                : () => widget.onStart(
                    TripDraft(
                      title: _title.text.trim(),
                      destination: _destination!.name,
                      country: _destination!.country,
                      currency: _currency,
                      travelers: _travelers,
                    ),
                  ),
            child: const Text('Start tracking'),
          ),
        ],
      ),
    );
  }
}

// ---- place search ----------------------------------------------------------------

class _PlaceSearchSheet extends StatefulWidget {
  const _PlaceSearchSheet({this.title = 'Add a place'});
  final String title;

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Place> _results = const [];
  bool _loading = false;
  String? _error;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _search(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final seq = ++_seq;
      setState(() => _loading = true);
      try {
        final r = await Api.instance.places(q.trim());
        if (mounted && seq == _seq) {
          setState(() {
            _results = r;
            _error = null;
          });
        }
      } on ApiException catch (e) {
        if (mounted && seq == _seq) setState(() => _error = e.message);
      } finally {
        if (mounted && seq == _seq) setState(() => _loading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 10), child: Text(widget.title, style: TT.display(20, wght: 750))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _q,
                autofocus: true,
                onChanged: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search places — Jebel Jais, Muscat, Tbilisi…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _loading
                      ? const Padding(padding: EdgeInsets.all(14), child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                      : null,
                ),
              ),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!, style: TT.ui(13, color: TG.like))),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(top: 8),
                children: [
                  for (final p in _results)
                    ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(p.name, style: TT.ui(15, wght: 600)),
                      subtitle: Text([p.region, p.country].where((s) => s.isNotEmpty).join(', '), style: TT.ui(13, color: TG.muted)),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.pop(context, p);
                      },
                    ),
                  if (_results.isEmpty && _q.text.trim().length >= 2 && !_loading && _error == null)
                    Padding(padding: const EdgeInsets.all(20), child: Text('No places found. Try the nearest town.', style: TT.ui(14, color: TG.muted))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- place editor --------------------------------------------------------------------

const _detailPresets = ['Entry fee', 'Stay', 'Food tried', 'Transport', 'Best time', 'Rating', 'Visa', 'Bring'];

class PlaceEditor extends StatefulWidget {
  const PlaceEditor({super.key, required this.trip, required this.place, required this.onChanged});
  final TripDraft trip;
  final DraftPlace place;
  final VoidCallback onChanged;

  @override
  State<PlaceEditor> createState() => _PlaceEditorState();
}

class _PlaceEditorState extends State<PlaceEditor> {
  late final _story = TextEditingController(text: widget.place.story);
  late final _tip = TextEditingController(text: widget.place.tip);
  final _picker = ImagePicker();

  DraftPlace get p => widget.place;

  @override
  void dispose() {
    _story.dispose();
    _tip.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    widget.onChanged();
  }

  Future<void> _pick({bool camera = false}) async {
    try {
      final files = camera
          ? [?await _picker.pickImage(source: ImageSource.camera, maxWidth: 1800, imageQuality: 82)]
          : await _picker.pickMultiImage(maxWidth: 1800, imageQuality: 82, limit: 8);
      for (final f in files) {
        final photo = DraftPhoto(bytes: await f.readAsBytes(), name: f.name, state: UploadState.uploading);
        p.photos.add(photo);
        _changed();
        _upload(photo, f);
      }
    } on PlatformException catch (e) {
      if (mounted) showSnack(context, 'Couldn’t open your photos (${e.code}).');
    }
  }

  Future<void> _upload(DraftPhoto photo, XFile file) async {
    try {
      photo.url = await Api.instance.uploadPhoto(file);
      photo.state = UploadState.done;
    } on ApiException catch (e) {
      photo.state = UploadState.failed;
      if (mounted) {
        showSnack(context, 'A photo didn’t upload: ${e.message}', action: 'Retry', onAction: () {
          photo.state = UploadState.uploading;
          _changed();
          _upload(photo, file);
        });
      }
    }
    if (mounted) _changed();
  }

  Future<void> _addExpense() async {
    final e = await showModalBottomSheet<Expense>(context: context, isScrollControlled: true, builder: (_) => _ExpenseSheet(currency: widget.trip.currency));
    if (e != null) {
      p.expenses.add(e);
      _changed();
    }
  }

  Future<void> _addDetail([String? preset]) async {
    final f = await showModalBottomSheet<Field>(context: context, isScrollControlled: true, builder: (_) => _FieldSheet(label: preset));
    if (f != null) {
      p.fields.add(f);
      _changed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = widget.trip.currency;
    return Scaffold(
      appBar: AppBar(
        title: Text(p.name, style: TT.display(18, wght: 700)),
        actions: [
          IconButton(
            tooltip: 'Remove place',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () {
              widget.trip.places.remove(p);
              widget.onChanged();
              Navigator.pop(context);
            },
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Row(
            children: [
              const Icon(Icons.place_outlined, size: 16, color: TG.muted),
              const SizedBox(width: 4),
              Expanded(child: Text([p.region, p.country].where((s) => s.isNotEmpty).join(', '), style: TT.ui(13.5, color: TG.muted))),
              DropdownButton<int>(
                value: p.day,
                underline: const SizedBox.shrink(),
                items: [for (var d = 1; d <= widget.trip.days + 1; d++) DropdownMenuItem(value: d, child: Text('Day $d'))],
                onChanged: (v) {
                  p.day = v ?? p.day;
                  _changed();
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Photos', style: TT.ui(15, wght: 700)),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _AddTile(icon: Icons.add_photo_alternate_outlined, label: 'Gallery', onTap: _pick),
                if (!kIsWeb) _AddTile(icon: Icons.photo_camera_outlined, label: 'Camera', onTap: () => _pick(camera: true)),
                for (final (i, ph) in p.photos.indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 96,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ph.bytes != null ? Image.memory(ph.bytes!, fit: BoxFit.cover, cacheWidth: 250) : TgImage(ph.url, cacheWidth: 100),
                            if (ph.state == UploadState.uploading)
                              const ColoredBox(
                                color: Color(0x88000000),
                                child: Center(child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
                              ),
                            if (ph.state == UploadState.failed) const ColoredBox(color: Color(0xAAE11D48), child: Icon(Icons.error_outline, color: Colors.white)),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: IconButton(
                                tooltip: 'Remove photo',
                                visualDensity: VisualDensity.compact,
                                style: IconButton.styleFrom(backgroundColor: Colors.black45),
                                onPressed: () {
                                  p.photos.removeAt(i);
                                  _changed();
                                },
                                icon: const Icon(Icons.close, color: Colors.white, size: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _story,
            minLines: 2,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'What was it like?'),
            onChanged: (v) {
              p.story = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _tip,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Tip for the next person', prefixIcon: Icon(Icons.lightbulb_outline_rounded)),
            onChanged: (v) {
              p.tip = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: Text('Spent here', style: TT.ui(15, wght: 700))),
              Text(money(p.spent, cur), style: TT.ui(15, wght: 700)),
            ],
          ),
          for (final (i, e) in p.expenses.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: Icon(TG.budgetIcons[e.category], color: TG.budgetColors[e.category]),
              title: Text(e.label, style: TT.ui(14.5)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(money(e.amount, cur), style: TT.ui(14.5, wght: 600)),
                  IconButton(
                    tooltip: 'Remove expense',
                    icon: const Icon(Icons.close, size: 18, color: TG.faint),
                    onPressed: () {
                      p.expenses.removeAt(i);
                      _changed();
                    },
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: _addExpense, icon: const Icon(Icons.add, size: 18), label: const Text('Add expense')),
          ),
          const SizedBox(height: 12),
          Text('Details', style: TT.ui(15, wght: 700)),
          const SizedBox(height: 4),
          Text('Anything worth knowing — add your own fields.', style: TT.ui(13, color: TG.muted)),
          for (final (i, f) in p.fields.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(f.label, style: TT.ui(13, color: TG.muted)),
              subtitle: Text(f.value, style: TT.ui(14.5, color: TG.ink)),
              trailing: IconButton(
                tooltip: 'Remove ${f.label}',
                icon: const Icon(Icons.close, size: 18, color: TG.faint),
                onPressed: () {
                  p.fields.removeAt(i);
                  _changed();
                },
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in _detailPresets.where((d) => !p.fields.any((f) => f.label == d)))
                FilterPill(label: '+ $preset', selected: false, onTap: () => _addDetail(preset)),
              FilterPill(label: '+ Custom', selected: false, onTap: _addDetail),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Semantics(
      button: true,
      label: 'Add photo from $label',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          width: 96,
          decoration: BoxDecoration(color: TG.surface, borderRadius: BorderRadius.circular(12)),
          child: ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Icon(icon, color: TG.ink2), const SizedBox(height: 4), Text(label, style: TT.ui(12, wght: 600))],
            ),
          ),
        ),
      ),
    ),
  );
}

class _ExpenseSheet extends StatefulWidget {
  const _ExpenseSheet({required this.currency});
  final String currency;

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  final _amount = TextEditingController();
  final _label = TextEditingController();
  String _category = 'activities';

  @override
  void dispose() {
    _amount.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Add expense', style: TT.display(20, wght: 750)),
        const SizedBox(height: 14),
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(8)],
          style: TT.display(22, wght: 700),
          decoration: InputDecoration(labelText: 'Amount', prefixText: '${widget.currency} '),
        ),
        const SizedBox(height: 10),
        TextField(controller: _label, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'What for?', hintText: 'Tickets, taxi, lunch…')),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in TG.budgetLabels.keys)
              FilterPill(label: TG.budgetLabels[c]!, icon: TG.budgetIcons[c], selected: _category == c, onTap: () => setState(() => _category = c)),
          ],
        ),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: _amount,
          builder: (context, _) => FilledButton(
            onPressed: (int.tryParse(_amount.text) ?? 0) <= 0
                ? null
                : () => Navigator.pop(
                    context,
                    Expense(category: _category, label: _label.text.trim().isEmpty ? TG.budgetLabels[_category]! : _label.text.trim(), amount: int.parse(_amount.text)),
                  ),
            child: const Text('Add'),
          ),
        ),
      ],
    ),
  );
}

class _FieldSheet extends StatefulWidget {
  const _FieldSheet({this.label});
  final String? label;

  @override
  State<_FieldSheet> createState() => _FieldSheetState();
}

class _FieldSheetState extends State<_FieldSheet> {
  late final _label = TextEditingController(text: widget.label ?? '');
  final _value = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label ?? 'Add a detail', style: TT.display(20, wght: 750)),
        const SizedBox(height: 14),
        if (widget.label == null) ...[
          TextField(controller: _label, autofocus: true, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(labelText: 'Label', hintText: 'Parking, Wi-Fi, Dress code…')),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _value,
          autofocus: widget.label != null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Value'),
        ),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: Listenable.merge([_label, _value]),
          builder: (context, _) => FilledButton(
            onPressed: _label.text.trim().isEmpty || _value.text.trim().isEmpty ? null : () => Navigator.pop(context, Field(_label.text.trim(), _value.text.trim())),
            child: const Text('Add'),
          ),
        ),
      ],
    ),
  );
}

// ---- publish ----------------------------------------------------------------------------

const _tagOptions = ['desert', 'beach', 'mountains', 'city', 'culture', 'food', 'adventure', 'budget', 'family', 'couples', 'solo', 'friends'];

class PublishScreen extends StatefulWidget {
  const PublishScreen({super.key, required this.trip, required this.onChanged, required this.onPosted});
  final TripDraft trip;
  final VoidCallback onChanged;
  final Future<void> Function(Journey) onPosted;

  @override
  State<PublishScreen> createState() => _PublishScreenState();
}

class _PublishScreenState extends State<PublishScreen> {
  late final _title = TextEditingController(text: widget.trip.title);
  late final _dek = TextEditingController(text: widget.trip.dek);
  bool _posting = false;

  TripDraft get t => widget.trip;

  @override
  void dispose() {
    _title.dispose();
    _dek.dispose();
    super.dispose();
  }

  Future<void> _post() async {
    final me = Session.instance.creator;
    if (me == null) return;
    t.title = _title.text.trim();
    t.dek = _dek.text.trim();
    setState(() => _posting = true);
    try {
      final journey = await Api.instance.createJourney(t.toPayload(me.id));
      if (!mounted) return;
      Navigator.pop(context);
      await widget.onPosted(journey);
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.details.values.isNotEmpty ? e.details.values.first : e.message);
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final urls = t.photoUrls;
    final cover = t.coverUrl ?? (urls.isEmpty ? null : urls.first);
    return Scaffold(
      appBar: AppBar(title: const Text('Publish trip')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (urls.isNotEmpty) ...[
            Text('Cover photo', style: TT.ui(15, wght: 700)),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: urls.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final on = urls[i] == cover;
                  return Semantics(
                    selected: on,
                    button: true,
                    label: 'Photo ${i + 1}${on ? ', cover' : ''}',
                    child: GestureDetector(
                      onTap: () {
                        setState(() => t.coverUrl = urls[i]);
                        widget.onChanged();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 88,
                        padding: EdgeInsets.all(on ? 3 : 0),
                        decoration: BoxDecoration(color: on ? TG.accent : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                        child: ClipRRect(borderRadius: BorderRadius.circular(10), child: TgImage(urls[i], cacheWidth: 90)),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
          TextField(controller: _title, textCapitalization: TextCapitalization.sentences, maxLength: 80, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 4),
          TextField(
            controller: _dek,
            minLines: 2,
            maxLines: 4,
            maxLength: 200,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Short description'),
          ),
          const SizedBox(height: 8),
          Text('Tags', style: TT.ui(15, wght: 700)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in _tagOptions)
                FilterPill(
                  label: tag[0].toUpperCase() + tag.substring(1),
                  selected: t.tags.contains(tag),
                  onTap: () {
                    setState(() => t.tags.contains(tag) ? t.tags.remove(tag) : t.tags.add(tag));
                    widget.onChanged();
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: TG.surface, borderRadius: BorderRadius.circular(14)),
            child: Text(
              '${plural(t.places.length, 'place')} · ${plural(t.days, 'day')} · ${money(t.spent, t.currency)} spent · ${plural(urls.length, 'photo')}',
              style: TT.ui(14, wght: 600),
            ),
          ),
          const SizedBox(height: 20),
          ListenableBuilder(
            listenable: _title,
            builder: (context, _) => FilledButton(
              style: FilledButton.styleFrom(backgroundColor: TG.accent),
              onPressed: _posting || t.uploading || _title.text.trim().length < 3 ? null : _post,
              child: _posting
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(t.uploading ? 'Waiting for photos…' : (_title.text.trim().length < 3 ? 'Add a title' : 'Post to Travelgram')),
            ),
          ),
        ],
      ),
    );
  }
}
