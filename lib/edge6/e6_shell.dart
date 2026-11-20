// Edge v6 shell: Home, Health, Coach, More, with the + button for starting
// things. Classic shows a bottom bar with a white + in the middle; Liquid
// Glass shows a floating glass bar and a separate glass + button.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../ui2/screens/coach.dart' show CoachScreen;
import '../ui2/screens/workout_screen.dart' show WorkoutScreen;
import 'e6.dart';
import 'e6_screens.dart';

class E6Shell extends StatefulWidget {
  const E6Shell({super.key});
  @override
  State<E6Shell> createState() => _E6ShellState();
}

class _E6ShellState extends State<E6Shell> {
  int _tab = 0;
  final Set<int> _built = {0};

  static const _tabs = <(String, IconData, IconData)>[
    ('Home', Icons.home_outlined, Icons.home_rounded),
    ('Health', Icons.favorite_border_rounded, Icons.favorite_rounded),
    ('Coach', Icons.auto_awesome_outlined, Icons.auto_awesome),
    ('More', Icons.menu_rounded, Icons.menu_rounded),
  ];

  Widget _page(int i) => switch (i) {
    0 => const E6Home(),
    1 => const E6Health(),
    2 => const CoachScreen(),
    _ => const E6More(),
  };

  void _select(int i) => setState(() {
    _tab = i;
    _built.add(i);
  });

  @override
  Widget build(BuildContext context) {
    final live = context.select<AppState, bool>((a) => a.activeWorkout != null);
    return ValueListenableBuilder<bool>(
      valueListenable: E6Prefs.glass,
      builder: (c, glass, _) => Theme(
        data: Theme.of(c).copyWith(
          scaffoldBackgroundColor: E6C.base,
          colorScheme: Theme.of(c).colorScheme.copyWith(primary: E6C.ink),
        ),
        child: Scaffold(
          backgroundColor: E6C.base,
          extendBody: true,
          body: DecoratedBox(
            decoration: e6Background(glass),
            child: IndexedStack(
              index: _tab,
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  _built.contains(i) ? _page(i) : const SizedBox.shrink(),
              ],
            ),
          ),
          bottomNavigationBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (live)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: E6Card(
                    strong: true,
                    onTap: () => e6Push(c, const WorkoutScreen()),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.fiber_manual_record,
                          color: E6C.low,
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('Activity running', style: E6T.body),
                        ),
                        Text('OPEN', style: E6T.cap(13)),
                      ],
                    ),
                  ),
                ),
              glass ? _glassBar(c) : _classicBar(c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabButton(int i, {bool pill = false}) {
    final on = i == _tab;
    final t = _tabs[i];
    return Semantics(
      selected: on,
      button: true,
      label: t.$1,
      child: InkWell(
        onTap: () => _select(i),
        borderRadius: BorderRadius.circular(27),
        child: Container(
          height: 54,
          decoration: pill && on
              ? BoxDecoration(
                  color: const Color(0x29FFFFFF),
                  borderRadius: BorderRadius.circular(27),
                )
              : null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(on ? t.$3 : t.$2, color: on ? E6C.ink : E6C.ink2, size: 23),
              const SizedBox(height: 2),
              Text(
                t.$1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: on ? E6C.ink : E6C.ink2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _plus(BuildContext c, {required bool glass}) {
    final icon = Icon(
      Icons.add_rounded,
      size: 28,
      color: glass ? E6C.ink : E6C.base,
    );
    final btn = SizedBox(
      width: glass ? 64 : 54,
      height: glass ? 64 : 54,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () => showE6ActionSheet(c),
          child: icon,
        ),
      ),
    );
    return Semantics(
      button: true,
      label: 'Start activity, journal or Fajr buzz',
      child: glass
          ? E6Glass(radius: BorderRadius.circular(32), strong: true, child: btn)
          : DecoratedBox(
              decoration: const BoxDecoration(
                color: E6C.ink,
                shape: BoxShape.circle,
              ),
              child: btn,
            ),
    );
  }

  Widget _classicBar(BuildContext c) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x000D1012), Color(0xF00D1012), E6C.base],
        stops: [0, 0.3, 1],
      ),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
        child: Row(
          children: [
            Expanded(child: _tabButton(0)),
            Expanded(child: _tabButton(1)),
            Expanded(child: Center(child: _plus(c, glass: false))),
            Expanded(child: _tabButton(2)),
            Expanded(child: _tabButton(3)),
          ],
        ),
      ),
    ),
  );

  Widget _glassBar(BuildContext c) => SafeArea(
    top: false,
    minimum: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: E6Glass(
              radius: BorderRadius.circular(32),
              strong: true,
              child: SizedBox(
                height: 64,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: Row(
                    children: [
                      for (var i = 0; i < _tabs.length; i++)
                        Expanded(child: _tabButton(i, pill: true)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _plus(c, glass: true),
        ],
      ),
    ),
  );
}
