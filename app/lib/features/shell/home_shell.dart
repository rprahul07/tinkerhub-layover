import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models.dart';
import '../../theme/tg_theme.dart';
import '../ammachi/ammachi_art.dart';
import '../ammachi/call_screen.dart';
import '../create/trip_tracker.dart';
import '../explore/explore_screen.dart';
import '../home/home_screen.dart';
import '../journey/journey_screen.dart';
import '../profile/profile_screen.dart';

/// Home · Explore · (Call Ammachi) · Create · Profile
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  final _visited = <int>{0};
  final _home = GlobalKey<HomeScreenState>();
  final _profile = GlobalKey<ProfileScreenState>();

  void _go(int i) {
    if (i == _index) return;
    HapticFeedback.selectionClick();
    setState(() {
      _index = i;
      _visited.add(i);
    });
    if (i == 3) _profile.currentState?.refresh();
  }

  Future<void> _onPosted(Journey journey) async {
    _go(0);
    await _home.currentState?.refresh();
    _profile.currentState?.refresh();
    if (mounted) await openJourney(context, journey);
  }

  Widget _tab(int i) {
    if (!_visited.contains(i)) return const SizedBox.shrink();
    final child = switch (i) {
      0 => HomeScreen(key: _home, onExplore: () => _go(1)),
      1 => const ExploreScreen(),
      2 => TripTracker(onPosted: _onPosted),
      _ => ProfileScreen(key: _profile, onCreate: () => _go(2)),
    };
    return TickerMode(enabled: i == _index, child: child);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: [for (var i = 0; i < 4; i++) _tab(i)]),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(color: TG.bg, border: Border(top: BorderSide(color: TG.line))),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 62,
            child: Row(
              children: [
                _NavItem(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Home', on: _index == 0, onTap: () => _go(0)),
                _NavItem(icon: Icons.explore_outlined, activeIcon: Icons.explore, label: 'Explore', on: _index == 1, onTap: () => _go(1)),
                const Expanded(child: _CallButton()),
                _NavItem(icon: Icons.add_box_outlined, activeIcon: Icons.add_box, label: 'Create', on: _index == 2, onTap: () => _go(2)),
                _NavItem(icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: 'Profile', on: _index == 3, onTap: () => _go(3)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.icon, required this.activeIcon, required this.label, required this.on, required this.onTap});
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      selected: on,
      button: true,
      label: label,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: ExcludeSemantics(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(on ? activeIcon : icon, color: on ? TG.ink : TG.muted, size: 25),
              const SizedBox(height: 2),
              Text(label, style: TT.ui(11, wght: on ? 650 : 500, color: on ? TG.ink : TG.muted)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The centre button: one tap to call Ammachi.
class _CallButton extends StatelessWidget {
  const _CallButton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Call Ammachi, your travel assistant',
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          CallScreen.open(context);
        },
        child: ExcludeSemantics(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: TG.surface, border: Border.all(color: TG.line)),
                    child: const ClipOval(
                      child: TickerMode(
                        enabled: false,
                        child: OverflowBox(maxWidth: 58, maxHeight: 58, child: AmmachiAvatar(mood: AmmachiMood.idle, size: 58)),
                      ),
                    ),
                  ),
                  Positioned(
                    right: -3,
                    bottom: -2,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(color: TG.success, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                      child: const Icon(Icons.call, size: 9, color: Colors.white),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text('Ammachi', style: TT.ui(11, wght: 600, color: TG.ink)),
            ],
          ),
        ),
      ),
    );
  }
}
