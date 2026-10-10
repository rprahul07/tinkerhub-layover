import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/api.dart';
import '../../data/models.dart';
import '../../theme/tg_theme.dart';
import '../../util/format.dart';
import '../../widgets/common.dart';
import '../home/post_card.dart';

/// Search trips and people.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Journey>? _trips;
  List<Creator>? _people;
  bool _loading = false;
  String? _error;
  int _seq = 0;

  static const _ideas = ['Dubai', 'desert', 'Oman', 'hiking', 'Georgia', 'beach', 'family'];

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () => _search(q));
  }

  Future<void> _search(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _trips = null;
        _people = null;
      });
      return;
    }
    final seq = ++_seq;
    setState(() => _loading = true);
    try {
      final (trips, people) = (await Api.instance.journeys(TripFilter(q: query)), await Api.instance.creators(q: query));
      if (mounted && seq == _seq) {
        setState(() {
          _trips = trips;
          _people = people;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted && seq == _seq) setState(() => _error = e.message);
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trips = _trips;
    final people = _people ?? const <Creator>[];
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _search,
          decoration: InputDecoration(
            hintText: 'Places, trips, people',
            isDense: true,
            suffixIcon: _loading
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                : null,
          ),
        ),
        actions: const [SizedBox(width: 12)],
      ),
      body: _error != null
          ? ErrorView(message: _error!, onRetry: () => _search(_controller.text))
          : trips == null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Popular searches', style: TT.ui(13, wght: 600, color: TG.muted)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final idea in _ideas)
                      FilterPill(
                        label: idea,
                        selected: false,
                        onTap: () {
                          _controller.text = idea;
                          _search(idea);
                        },
                      ),
                  ],
                ),
              ],
            )
          : trips.isEmpty && people.isEmpty
          ? EmptyView(icon: Icons.search_off_rounded, title: 'Nothing for “${_controller.text.trim()}”', body: 'Try a city, a country or a kind of trip.')
          : ListView(
              children: [
                if (people.isNotEmpty) ...[
                  const SectionTitle('People', padding: EdgeInsets.fromLTRB(16, 12, 16, 4)),
                  for (final c in people.take(4))
                    ListTile(
                      leading: Avatar(c, size: 40),
                      title: Text(c.name, style: TT.ui(15, wght: 650)),
                      subtitle: Text('@${c.handle} · ${compactCount(c.followers)} followers', style: TT.ui(13, color: TG.muted)),
                      trailing: FollowButton(c, compact: true),
                      onTap: () => openProfile(context, c),
                    ),
                ],
                if (trips.isNotEmpty) ...[
                  SectionTitle(plural(trips.length, 'trip'), padding: const EdgeInsets.fromLTRB(16, 16, 16, 4)),
                  for (final j in trips) TripTile(journey: j),
                ],
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
