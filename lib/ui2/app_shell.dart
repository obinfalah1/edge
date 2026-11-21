// The four-tab shell.
//
// Today · Sleep · Activity · Health. Stable: the contents personalise, the
// mental map does not. Each domain owns an accent, so colour tells you where
// you are before the label does. Profile is not a tab; every tab's header
// carries the avatar into it.
//
// There is no fifth tab, and the type system is what says so — [ShellDomain]
// is a closed enum and [AppShell] takes a builder keyed by it, so "just add a
// tab for X" is a change to this file with a reviewer attached, not something
// a screen can do on its own. Anything that feels like another destination is
// a section or a pushed screen inside the domain that owns it.

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../l10n/app_localizations.dart';
import 'grammar.dart';
import 'theme.dart';

/// The four primary destinations, in bar order.
enum ShellDomain {
  today('Today', LucideIcons.house, C.domHome),
  sleep('Sleep', LucideIcons.moon, C.domSleep),
  activity('Activity', LucideIcons.dumbbell, C.domMove),
  health('Health', LucideIcons.heartPulse, C.domHealth);

  const ShellDomain(this.label, this.icon, this.accent);

  final String label;
  final IconData icon;

  /// [label] in the user's language. Own keys rather than the screen titles,
  /// so two tabs can never end up with the same translated word.
  String title(BuildContext c) {
    final l = AppLocalizations.of(c);
    return switch (this) {
          ShellDomain.today => l?.tabToday,
          ShellDomain.sleep => l?.tabSleep,
          ShellDomain.activity => l?.tabActivity,
          ShellDomain.health => l?.tabHealth,
        } ??
        label;
  }

  /// The domain's pigment. Use `P.of(context).on(accent)` for text and
  /// `.fill(accent)` for a filled surface — the raw value is not AA-safe.
  final Color accent;
}

// There is no `Domain` InheritedWidget. There was one, promising that a screen
// "and anything it pushes" could pick up its accent without threading it — but
// nothing ever read it, and a pushed route could not have: `MaterialApp.home`
// is the gate, so `Navigator.of` pushes above the shell entirely. Screens take
// their accent as a parameter, which is honest about where it comes from.

class AppShell extends StatefulWidget {
  /// Builds the body of one domain. Called lazily — a tab is not built until
  /// it is first selected, then kept alive by the [IndexedStack].
  final Widget Function(BuildContext context, ShellDomain domain) builder;

  final ShellDomain initial;

  /// Notified on every tab change, including a re-tap of the current tab
  /// (which domains conventionally use to scroll to top) and a return via Back.
  final void Function(ShellDomain domain)? onSelect;

  /// Pinned between the domain and the tab bar, above every tab. This is not
  /// a general slot — it exists for state that is RUNNING and is not on
  /// screen, which today means a minimised workout. A domain's own content
  /// belongs inside the domain.
  final Widget? banner;

  /// External selection control. When provided, the shell follows changes to
  /// it and switches tabs WITHOUT being recreated, so a programmatic jump
  /// (a notification deep link) keeps every visited tab's state — scroll
  /// position included — alive in the [IndexedStack].
  final ValueNotifier<ShellDomain>? selection;

  const AppShell({
    super.key,
    required this.builder,
    this.initial = ShellDomain.today,
    this.onSelect,
    this.banner,
    this.selection,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late ShellDomain _current = widget.initial;
  late final Set<ShellDomain> _built = {widget.initial};
  // Tabs are kept alive, not pushed onto the Navigator. Keep their history
  // here so Android Back can return to the previous tab. A restored tab or
  // cold-launch deep link has Today as its way back into the app.
  late final List<ShellDomain> _history = [
    if (widget.initial != ShellDomain.today) ShellDomain.today,
  ];

  @override
  void initState() {
    super.initState();
    widget.selection?.addListener(_followSelection);
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selection != oldWidget.selection) {
      oldWidget.selection?.removeListener(_followSelection);
      widget.selection?.addListener(_followSelection);
      // Reconcile with the new notifier's current value. didUpdateWidget
      // runs during the build phase, so the onSelect callback is deferred
      // to after the frame — it may setState on the parent.
      final s = widget.selection;
      if (s != null && s.value != _current) {
        final d = s.value;
        _select(d, notify: false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Discard the callback if the shell was unmounted, the notifier
          // was swapped, or the selection moved on since scheduling —
          // reporting the stale domain would write it back via onSelect.
          if (mounted && widget.selection == s && s.value == d) {
            widget.onSelect?.call(d);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    widget.selection?.removeListener(_followSelection);
    super.dispose();
  }

  void _followSelection() {
    final s = widget.selection;
    if (s == null) return;
    if (s.value != _current) _select(s.value);
  }

  void _select(ShellDomain d, {bool notify = true}) {
    setState(() {
      // Each tab at most once, most recent last, so switching back and forth
      // between two tabs does not add a Back press per switch. Today stays in
      // as the way back into the app even while it is the tab on screen.
      if (d != _current) {
        _history.remove(_current);
        // Leaving Today puts it back at the bottom, never on top: it is the
        // last stop before Back leaves the app.
        if (_current == ShellDomain.today) {
          _history.insert(0, _current);
        } else {
          _history.add(_current);
        }
        if (d != ShellDomain.today) _history.remove(d);
      }
      _current = d;
      _built.add(d);
    });
    if (notify) widget.onSelect?.call(d);
  }

  void _back() {
    if (_history.isEmpty) return;
    setState(() {
      _current = _history.removeLast();
      _built.add(_current);
    });
    widget.onSelect?.call(_current);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return PopScope<Object?>(
      canPop: _history.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: p.bg,
        // The glass pill floats over the content, which scrolls under it.
        extendBody: glassOf(c) || p.metro,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Expanded(
                child: IndexedStack(
                  index: _current.index,
                  children: [
                    // An unvisited tab is an empty box, not a built screen — the
                    // old shell built all forty screens' worth of state on launch.
                    for (final d in ShellDomain.values)
                      if (_built.contains(d))
                        widget.builder(c, d)
                      else
                        const SizedBox.shrink(),
                  ],
                ),
              ),
              if (widget.banner != null) widget.banner!,
            ],
          ),
        ),
        bottomNavigationBar: glassOf(c)
            ? _GlassPillBar(current: _current, onTap: _select)
            : p.metro
                ? _InstBar(current: _current, onTap: _select)
                : _TabBar(current: _current, onTap: _select),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  final ShellDomain current;
  final ValueChanged<ShellDomain> onTap;

  const _TabBar({required this.current, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      decoration: BoxDecoration(
        color: p.card,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: SafeArea(
        top: false,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final d in ShellDomain.values)
                Expanded(
                  child: _Tab(
                    domain: d,
                    on: d == current,
                    onTap: () => onTap(d),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Instrument's tab bar: a solid docked plate with a hairline above it. The
/// selected tab is marked by a short lapis index at the top edge that slides
/// to the tab you pick, like the pointer on a scale.
class _InstBar extends StatelessWidget {
  final ShellDomain current;
  final ValueChanged<ShellDomain> onTap;

  const _InstBar({required this.current, required this.onTap});

  /// Line's own tab icons: Today is the day as a line with a stop on it.
  static IconData _icon(ShellDomain d) => switch (d) {
        ShellDomain.today => LucideIcons.chartNoAxesGantt,
        ShellDomain.sleep => LucideIcons.moon,
        ShellDomain.activity => LucideIcons.activity,
        ShellDomain.health => LucideIcons.heart,
      };

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    // Line: the iOS tab bar. A translucent bar the page scrolls under, a
    // hairline on top, and the selected tab in gold.
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: p.card.withValues(alpha: .86),
            border: Border(top: BorderSide(color: p.line, width: .5)),
          ),
          child: SafeArea(
            top: false,
            child: Row(children: [
              for (final d in ShellDomain.values)
                Expanded(
                  child: Semantics(
                    selected: d == current,
                    child: Pressable(
                      semanticLabel: d.title(c),
                      onTap: () {
                        if (d != current) HapticFeedback.selectionClick();
                        onTap(d);
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(top: S.x2, bottom: S.x1),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(_icon(d),
                              size: 24,
                              color: d == current ? p.on(p.tint) : p.ink3),
                          const SizedBox(height: 2),
                          Text(d.title(c),
                              style: F.over.copyWith(
                                  color: d == current ? p.on(p.tint) : p.ink3,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Liquid Glass tab bar: a floating capsule that blurs what scrolls under it,
/// with a translucent fill, a bright rim and the selected tab in a lens.
class _GlassPillBar extends StatelessWidget {
  final ShellDomain current;
  final ValueChanged<ShellDomain> onTap;

  const _GlassPillBar({required this.current, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    // A full capsule, as Apple's own iOS 26 tab bars (App Store, Music).
    const radius = BorderRadius.all(Radius.circular(32));
    final bottom = MediaQuery.paddingOf(c).bottom;
    // Min height: the bottom bar slot hands down loose constraints, and the
    // blur layer would otherwise take the whole screen.
    return Column(mainAxisSize: MainAxisSize.min, children: [Padding(
      padding: EdgeInsets.fromLTRB(S.x5, 0, S.x5, bottom > 0 ? bottom - 8 : S.x3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: p.shadow.withValues(alpha: p.dark ? .5 : .10),
              blurRadius: 18,
              spreadRadius: -6,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            // Light blur, like Apple's: what is behind stays readable and colourful.
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: CustomPaint(
              foregroundPainter: GlassRim(p.dark, radius: radius),
              child: Container(
                // A floor, not a fixed height: larger text grows the pill.
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  borderRadius: radius,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: p.dark
                        ? GlassTok.pillDark
                        : GlassTok.pillLight,
                  ),
                ),
                // One lens for the whole bar that slides (with a little
                // overshoot, like liquid) to the tab you pick.
                child: LayoutBuilder(builder: (c, box) {
                  final n = ShellDomain.values.length;
                  final w = box.maxWidth / n;
                  const lensRadius = BorderRadius.all(Radius.circular(28));
                  return Stack(children: [
                    AnimatedPositioned(
                      duration: motion(c, Motion.slow),
                      curve: Curves.easeOutBack,
                      left: current.index * w + 2,
                      width: w - 4,
                      top: 0,
                      bottom: 0,
                      child: CustomPaint(
                        foregroundPainter: GlassRim(p.dark,
                            radius: lensRadius),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: lensRadius,
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                p.dark ? GlassTok.lensDark : GlassTok.lensLight,
                                p.wash(p.tint),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Row(children: [
                      for (final d in ShellDomain.values)
                        Expanded(
                          child: _Tab(
                            domain: d,
                            on: d == current,
                            onTap: () {
                              if (d != current) HapticFeedback.selectionClick();
                              onTap(d);
                            },
                            lens: true,
                          ),
                        ),
                    ]),
                  ]);
                }),
              ),
            ),
          ),
        ),
      ),
    )]);
  }
}

class _Tab extends StatelessWidget {
  final ShellDomain domain;
  final bool on;
  final VoidCallback onTap;

  /// In the glass pill the selected tab sits in a clear lens instead of a
  /// tinted chip around the icon.
  final bool lens;

  const _Tab(
      {required this.domain,
      required this.on,
      required this.onTap,
      this.lens = false});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    // iOS 26: unselected items in the label colour, the selected one tinted.
    // Under glass the selected tab takes the theme's tint.
    final ink = on
        ? p.on(lens || p.metro ? p.tint : domain.accent)
        : (lens ? p.ink : p.ink3);
    // On the clear glass bar, a soft halo keeps icons and labels readable
    // over whatever scrolls beneath (Apple does this with vibrancy).
    final halo = lens
        ? [
            Shadow(
                color: p.dark ? GlassTok.haloDark : GlassTok.haloLight,
                blurRadius: 4),
          ]
        : null;
    final label = domain.title(c);
    return Semantics(
      selected: on,
      child: Pressable(
        onTap: onTap,
        semanticLabel: label,
        child: AnimatedContainer(
          duration: motion(c, Motion.base),
          // In the pill the selected tab is a rounded rectangle the full width
          // of its slot (not a circle hugging the label).
          width: lens ? double.infinity : null,
          margin: lens ? const EdgeInsets.symmetric(horizontal: 2) : null,
          padding: EdgeInsets.symmetric(vertical: lens ? 5 : 6, horizontal: 2),
          // The selected tab's own soft capsule, as in Apple's iOS 26 bars.
          // The lens is drawn once by the bar and slides between tabs.
          decoration: null,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
            AnimatedContainer(
              duration: motion(c, Motion.base),
              padding: EdgeInsets.symmetric(
                horizontal: on ? S.x3 : 0,
                vertical: S.x1,
              ),
              decoration: BoxDecoration(
                color: on && !lens && !p.metro
                    ? p.wash(domain.accent)
                    : const Color(0x00000000),
                borderRadius: R.rPill,
              ),
              child: Icon(domain.icon,
                  size: lens ? 22 : 20, color: ink, shadows: halo),
            ),
              const SizedBox(height: 3),
              Text(
                label,
                textAlign: TextAlign.center,
              style: F.over.copyWith(
                color: ink,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                shadows: halo,
              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
