// Edge v6 screens: Home, the Recovery / Sleep / Strain deep dives, Health,
// More and the + sheet. Long-tail features open the original screens.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../platform/app_icon.dart';
import '../state/app_state.dart';
import '../ui2/activity/day_strain.dart' show DayStrainDetail;
import '../ui2/profile/alarm.dart' show AlarmScreen;
import '../ui2/profile/band_notifications.dart' show BandNotifications;
import '../ui2/profile/data.dart' show DataScreen;
import '../ui2/profile/devices.dart' show MyDevices;
import '../ui2/profile/phone_import.dart' show PhoneImport;
import '../ui2/profile/profile.dart' show ProfileHome;
import '../ui2/profile/report_issue.dart' show ReportIssueScreen;
import '../ui2/profile/settings.dart' show MoreSettings;
import '../ui2/profile/step_calibration.dart' show StepCalibrationScreen;
import '../ui2/revision.dart';
import '../ui2/screens/beats.dart' show Beats;
import '../ui2/screens/calm_breathing.dart' show CalmBreathing;
import '../ui2/screens/circadian_detail.dart' show CircadianDetail;
import '../ui2/screens/detected_activities.dart' show DetectedActivitiesScreen;
import '../ui2/screens/ecg.dart' show EcgHomeScreen;
import '../ui2/screens/health_screen.dart' show HealthScreen;
import '../ui2/screens/journal_compose.dart' show JournalCompose;
import '../ui2/screens/naps.dart' show NapsScreen;
import '../ui2/screens/nutrition_screen.dart' show NutritionScreen;
import '../ui2/screens/readiness_detail.dart' show ReadinessDetail;
import '../ui2/screens/sleep_detail.dart' show SleepDetail;
import '../ui2/screens/wellness_screen.dart' show WellnessScreen;
import '../ui2/screens/what_changed.dart' show WhatChangedScreen;
import '../ui2/screens/workout_screen.dart' show WorkoutScreen;
import 'e6.dart';

/// Loads [E6Data] and reloads when new data is derived.
mixin _E6Load<T extends StatefulWidget> on State<T>, RevisionReload<T> {
  E6Data? data;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => reload());
  }

  @override
  void reload() {
    final repo = context.read<AppState>().repo;
    if (repo == null) return;
    final token = beginRead(#e6);
    E6Data.load(repo)
        .then((d) {
          if (stillNewest(#e6, token)) setState(() => data = d);
        })
        .catchError((Object _) {});
  }
}

/// Bottom space so the last card clears the tab bar.
const double _kTabClearance = 130;

// ─── Home ──────────────────────────────────────────────────────────────────

class E6Home extends StatefulWidget {
  const E6Home({super.key});
  @override
  State<E6Home> createState() => _E6HomeState();
}

class _E6HomeState extends State<E6Home> with RevisionReload, _E6Load {
  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final d = data;
    final battery = app.device.batteryPct;
    final name = d?.home.name;
    final next = app.fajrAlarmNext;
    final fajr = app.fajrPrayerNext;
    final rec = d?.recovery;
    final strain = d?.strain;
    return RefreshIndicator(
      onRefresh: () async => reload(),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          MediaQuery.paddingOf(c).top + 8,
          16,
          _kTabClearance,
        ),
        children: [
          Row(
            children: [
              Semantics(
                button: true,
                label: 'Profile',
                child: InkWell(
                  onTap: () => e6Push(c, const ProfileHome()),
                  customBorder: const CircleBorder(),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFF3A4247),
                    child: Text(
                      (name == null || name.isEmpty)
                          ? 'E'
                          : name.characters.first.toUpperCase(),
                      style: E6T.body,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Text('TODAY', style: E6T.cap(15)),
              const Spacer(),
              InkWell(
                onTap: () => e6Push(c, const MyDevices()),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      Icon(
                        app.isConnected
                            ? Icons.battery_std_rounded
                            : Icons.bluetooth_disabled_rounded,
                        size: 18,
                        color: app.isConnected ? E6C.ink : E6C.ink2,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        battery == null ? '—' : '${battery.round()}%',
                        style: E6T.num(16),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _dial(
                c,
                'Sleep',
                d?.sleepPct,
                E6C.sleep,
                '%',
                () => d == null ? null : e6Push(c, E6SleepScreen(data: d)),
              ),
              _dial(
                c,
                'Recovery',
                rec,
                E6C.recovery(rec),
                '%',
                () => d == null ? null : e6Push(c, E6RecoveryScreen(data: d)),
              ),
              _dial(
                c,
                'Strain',
                strain,
                E6C.strain,
                '',
                () => d == null ? null : e6Push(c, E6StrainScreen(data: d)),
                max: 21,
                digits: 1,
              ),
            ],
          ),
          const SizedBox(height: 10),
          const E6Section('My day'),
          E6Card(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                E6Row(
                  leading: E6Chip(e6Hm(d?.sleepMin), fill: E6C.sleep),
                  title: 'Sleep',
                  sub: d?.needMin == null
                      ? 'Last night'
                      : 'Needed ${e6Hm(d!.needMin)}',
                  onTap: d == null
                      ? null
                      : () => e6Push(c, E6SleepScreen(data: d)),
                ),
                E6Row(
                  leading: E6Chip(
                    next == null
                        ? 'Off'
                        : e6TimeOf(next).replaceAll(RegExp(r' [AP]M'), ''),
                    outline: E6C.ink,
                  ),
                  title: 'Fajr buzz',
                  sub: next == null
                      ? 'Turn it on in Alarm'
                      : fajr == null
                      ? 'Next ${e6TimeOf(next)}'
                      : 'Fajr ${e6TimeOf(fajr)}, buzz ${e6TimeOf(next)}',
                  onTap: () => e6Push(c, const AlarmScreen()),
                ),
                E6Row(
                  leading: E6Chip(e6Num(strain, digits: 1), fill: E6C.strain),
                  title: 'Activities',
                  sub: 'Workouts and detected activity',
                  onTap: () => e6Push(c, const DetectedActivitiesScreen()),
                ),
                E6Row(
                  divider: false,
                  title: 'Start activity',
                  leading: const Icon(Icons.add, color: E6C.ink),
                  onTap: () => e6Push(c, const WorkoutScreen()),
                ),
              ],
            ),
          ),
          const E6Section('My plan'),
          E6Card(
            child: Column(
              children: [
                _plan(
                  'Strain target',
                  d?.targetLow == null
                      ? '—'
                      : '${e6Num(d!.targetLow, digits: 1)}–${e6Num(d.targetHigh, digits: 1)}',
                  (strain == null || d?.targetHigh == null)
                      ? 0
                      : (strain / d!.targetHigh!).clamp(0, 1).toDouble(),
                  E6C.strain,
                ),
                const SizedBox(height: 14),
                _plan(
                  'Asleep by',
                  e6Clock(d?.home.bedtime.value),
                  d?.sleepPct == null ? 0 : (d!.sleepPct! / 100).toDouble(),
                  E6C.sleep,
                ),
              ],
            ),
          ),
          const E6Section('My dashboard'),
          _grid([
            _tile(c, 'HRV', e6Num(d?.hrv), 'ms'),
            _tile(c, 'Resting heart rate', e6Num(d?.home.rhr.value), 'bpm'),
            _tile(c, 'Steps', e6Num(d?.home.steps.value), ''),
            _tile(c, 'Respiratory rate', e6Num(d?.resp, digits: 1), 'rpm'),
          ]),
        ],
      ),
    );
  }

  Widget _dial(
    BuildContext c,
    String label,
    num? v,
    Color color,
    String unit,
    VoidCallback? onTap, {
    double max = 100,
    int digits = 0,
  }) {
    return Semantics(
      button: true,
      label: '$label ${e6Num(v, digits: digits)}',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Column(
          children: [
            E6Dial(
              size: 108,
              fraction: v == null ? 0 : v / max,
              color: color,
              value: e6Num(v, digits: digits),
              unit: v == null ? '' : unit,
            ),
            const SizedBox(height: 12),
            Text(label.toUpperCase(), style: E6T.cap(13)),
          ],
        ),
      ),
    );
  }

  Widget _plan(String label, String value, double f, Color color) => Column(
    children: [
      Row(
        children: [
          Expanded(child: Text(label, style: E6T.body.copyWith(fontSize: 15))),
          Text(value, style: E6T.num(16)),
        ],
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: f,
          minHeight: 6,
          color: color,
          backgroundColor: E6C.track,
        ),
      ),
    ],
  );

  Widget _tile(BuildContext c, String label, String value, String unit) =>
      E6Card(
        onTap: () => e6Push(c, const HealthScreen()),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: E6T.small.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: value, style: E6T.num(26)),
                  if (unit.isNotEmpty && value != '—')
                    TextSpan(
                      text: ' $unit',
                      style: E6T.num(14, color: E6C.ink2),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
}

// ─── Deep dives ────────────────────────────────────────────────────────────

/// Page frame for a pushed v6 screen: background, back button, title.
class E6Page extends StatelessWidget {
  final String title;
  final String? sub;
  final List<Widget> children;
  final Widget? action;
  const E6Page({
    super.key,
    required this.title,
    this.sub,
    required this.children,
    this.action,
  });

  @override
  Widget build(BuildContext c) {
    return ValueListenableBuilder<bool>(
      valueListenable: E6Prefs.glass,
      builder: (c, glass, _) => Scaffold(
        backgroundColor: E6C.base,
        body: DecoratedBox(
          decoration: e6Background(glass),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              MediaQuery.paddingOf(c).top + 8,
              16,
              40,
            ),
            children: [
              Row(
                children: [
                  E6RoundButton(
                    icon: Icons.chevron_left_rounded,
                    label: 'Back',
                    onTap: () => Navigator.of(c).maybePop(),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(title.toUpperCase(), style: E6T.cap(16)),
                        if (sub != null) Text(sub!, style: E6T.small),
                      ],
                    ),
                  ),
                  action ?? const SizedBox(width: 44),
                ],
              ),
              const SizedBox(height: 14),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

Widget _stat(String label, String value, {String unit = '', Color? color}) =>
    E6Card(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: E6T.small),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: E6T.num(26, color: color ?? E6C.ink),
                ),
                if (unit.isNotEmpty && value != '—')
                  TextSpan(
                    text: ' $unit',
                    style: E6T.num(14, color: E6C.ink2),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

/// Two tiles per row, each row as tall as its tallest tile, so a long label
/// or a large text size wraps instead of overflowing.
Widget _grid(List<Widget> tiles, {int columns = 2}) => Column(
  children: [
    for (var i = 0; i < tiles.length; i += columns)
      Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var j = i; j < i + columns; j++) ...[
                if (j > i) const SizedBox(width: 8),
                Expanded(child: j < tiles.length ? tiles[j] : const SizedBox()),
              ],
            ],
          ),
        ),
      ),
  ],
);

Widget _moreButton(BuildContext c, String label, Widget screen) => Padding(
  padding: const EdgeInsets.only(top: 14),
  child: E6Card(
    onTap: () => e6Push(c, screen),
    child: Row(
      children: [
        Expanded(child: Text(label, style: E6T.body)),
        const Icon(Icons.chevron_right, color: E6C.ink2),
      ],
    ),
  ),
);

class E6RecoveryScreen extends StatelessWidget {
  final E6Data data;
  const E6RecoveryScreen({super.key, required this.data});

  @override
  Widget build(BuildContext c) {
    final r = data.recovery;
    final color = E6C.recovery(r);
    final line = r == null
        ? 'Recovery is not scored yet. Wear the band tonight.'
        : r >= 67
        ? 'You’re primed to take on strain today.'
        : r >= 34
        ? 'You’re maintaining. Keep strain moderate.'
        : 'Your body needs rest today.';
    return E6Page(
      title: 'Recovery',
      sub: 'Today',
      children: [
        Center(
          child: E6Dial(
            size: 196,
            stroke: 9,
            fraction: r == null ? 0 : r / 100,
            color: color,
            value: e6Num(r),
            unit: r == null ? '' : '%',
            fontSize: 64,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          line,
          textAlign: TextAlign.center,
          style: E6T.body.copyWith(fontSize: 17),
        ),
        const E6Section('What drove it'),
        E6Card(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              E6Row(
                title: 'Heart rate variability',
                trailing: Text('${e6Num(data.hrv)} ms', style: E6T.num(22)),
              ),
              E6Row(
                title: 'Resting heart rate',
                trailing: Text(
                  '${e6Num(data.home.rhr.value)} bpm',
                  style: E6T.num(22),
                ),
              ),
              E6Row(
                title: 'Respiratory rate',
                trailing: Text(
                  '${e6Num(data.resp, digits: 1)} rpm',
                  style: E6T.num(22),
                ),
              ),
              E6Row(
                divider: false,
                title: 'Sleep performance',
                trailing: Text('${e6Num(data.sleepPct)}%', style: E6T.num(22)),
              ),
            ],
          ),
        ),
        if (data.recovery30.isNotEmpty) ...[
          const E6Section('Last 30 days'),
          E6Card(
            child: SizedBox(
              height: 110,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (final v in data.recovery30)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: FractionallySizedBox(
                          heightFactor: (v / 100).clamp(0.03, 1).toDouble(),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: E6C.recovery(v),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        _moreButton(c, 'Full breakdown', const ReadinessDetail()),
      ],
    );
  }
}

class E6SleepScreen extends StatelessWidget {
  final E6Data data;
  const E6SleepScreen({super.key, required this.data});

  @override
  Widget build(BuildContext c) {
    final st = data.home.sleepStages;
    final stages = <(String, int?, Color)>[
      ('Awake', st?.awake, E6C.ink2),
      ('Light', st?.light, E6C.sleep),
      ('Deep', st?.deep, E6C.deep),
      ('REM', st?.rem, E6C.rem),
    ];
    final total = stages.fold<int>(0, (a, s) => a + (s.$2 ?? 0));
    return E6Page(
      title: 'Sleep',
      sub: 'Last night',
      children: [
        Row(
          children: [
            E6Dial(
              size: 150,
              stroke: 8,
              fraction: (data.sleepPct ?? 0) / 100,
              color: E6C.sleep,
              value: e6Num(data.sleepPct),
              unit: data.sleepPct == null ? '' : '%',
              fontSize: 46,
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('HOURS OF SLEEP', style: E6T.cap(13, color: E6C.ink2)),
                Text(e6Hm(data.sleepMin), style: E6T.num(30)),
                const SizedBox(height: 10),
                Text('SLEEP NEEDED', style: E6T.cap(13, color: E6C.ink2)),
                Text(e6Hm(data.needMin), style: E6T.num(30, color: E6C.ink2)),
              ],
            ),
          ],
        ),
        const E6Section('Stages'),
        E6Card(
          child: total == 0
              ? const Text(
                  'Stages show once the night has scored.',
                  style: E6T.sub,
                )
              : Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 18,
                        child: Row(
                          children: [
                            for (final s in stages)
                              if ((s.$2 ?? 0) > 0)
                                Expanded(
                                  flex: s.$2!,
                                  child: ColoredBox(color: s.$3),
                                ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        for (final s in stages)
                          Expanded(
                            child: Column(
                              children: [
                                Text(e6Hm(s.$2), style: E6T.num(19)),
                                Text(s.$1, style: E6T.small),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        _grid([
          _stat('Efficiency', e6Num(data.efficiency), unit: '%'),
          _stat(
            'Asleep by tonight',
            e6Clock(data.home.bedtime.value),
            color: E6C.sleep,
          ),
        ]),
        _moreButton(c, 'Full sleep details', const SleepDetail()),
        _moreButton(c, 'Naps', const NapsScreen()),
        _moreButton(c, 'Body clock', const CircadianDetail()),
      ],
    );
  }
}

class E6StrainScreen extends StatelessWidget {
  final E6Data data;
  const E6StrainScreen({super.key, required this.data});

  @override
  Widget build(BuildContext c) {
    final s = data.strain;
    final lo = data.targetLow, hi = data.targetHigh;
    return E6Page(
      title: 'Strain',
      sub: 'Today',
      action: E6RoundButton(
        icon: Icons.add,
        label: 'Start activity',
        onTap: () => e6Push(c, const WorkoutScreen()),
      ),
      children: [
        Center(
          child: E6Dial(
            size: 196,
            stroke: 9,
            fraction: s == null ? 0 : s / 21,
            color: E6C.strain,
            value: e6Num(s, digits: 1),
            fontSize: 62,
            caption: 'of 21',
            bandFrom: lo == null ? null : lo / 21,
            bandTo: hi == null ? null : hi / 21,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          lo == null
              ? 'Your target shows once recovery is scored.'
              : 'Target today ${e6Num(lo, digits: 1)} to ${e6Num(hi, digits: 1)}',
          textAlign: TextAlign.center,
          style: E6T.body,
        ),
        const SizedBox(height: 8),
        _grid([
          _stat('Calories', e6Num(data.home.calories.value)),
          _stat('Steps', e6Num(data.home.steps.value)),
        ]),
        _moreButton(c, 'Activities', const DetectedActivitiesScreen()),
        _moreButton(c, 'Full breakdown', const DayStrainDetail()),
      ],
    );
  }
}

// ─── Health tab ────────────────────────────────────────────────────────────

class E6Health extends StatefulWidget {
  const E6Health({super.key});
  @override
  State<E6Health> createState() => _E6HealthState();
}

class _E6HealthState extends State<E6Health> with RevisionReload, _E6Load {
  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final d = data;
    final hr = app.device.liveHr;
    final temp = d?.skinTempDev;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(c).top + 8,
        16,
        _kTabClearance,
      ),
      children: [
        SizedBox(
          height: 44,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('HEALTH', style: E6T.cap(24)),
          ),
        ),
        const SizedBox(height: 8),
        E6Card(
          onTap: () => e6Push(c, const Beats()),
          child: Row(
            children: [
              const Icon(Icons.favorite_rounded, color: E6C.heart),
              const SizedBox(width: 10),
              Text('HEART RATE, LIVE', style: E6T.cap(13, color: E6C.ink2)),
              const Spacer(),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: hr == null ? '—' : '$hr',
                      style: E6T.num(40),
                    ),
                    TextSpan(
                      text: ' bpm',
                      style: E6T.num(16, color: E6C.ink2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const E6Section('Health monitor'),
        _grid([
          _stat('HRV', e6Num(d?.hrv), unit: 'ms'),
          _stat('Resting heart rate', e6Num(d?.home.rhr.value), unit: 'bpm'),
          _stat('Respiratory rate', e6Num(d?.resp, digits: 1), unit: 'rpm'),
          _stat('Blood oxygen', e6Num(d?.spo2), unit: '%'),
          _stat(
            'Skin temperature',
            temp == null
                ? '—'
                : '${temp >= 0 ? '+' : ''}${temp.toStringAsFixed(1)}',
            unit: '°C',
          ),
          _stat('Stress', e6Num(d?.stress, digits: 1)),
        ]),
        const E6Section('Tools'),
        _grid(columns: 4, [
          _tool(
            c,
            'ECG',
            Icons.monitor_heart_outlined,
            E6C.heart,
            const EcgHomeScreen(),
          ),
          _tool(
            c,
            'Heartbeats',
            Icons.favorite_border,
            E6C.heart,
            const Beats(),
          ),
          _tool(c, 'Breathe', Icons.air, E6C.sleep, const CalmBreathing()),
          _tool(
            c,
            'Wellness',
            Icons.spa_outlined,
            E6C.rec,
            const WellnessScreen(),
          ),
          _tool(
            c,
            'Nutrition',
            Icons.restaurant_outlined,
            E6C.mid,
            const NutritionScreen(page: true),
          ),
          _tool(
            c,
            'Journal',
            Icons.edit_outlined,
            E6C.strain,
            const JournalCompose(),
          ),
          _tool(
            c,
            'What changed',
            Icons.change_history,
            E6C.sleep,
            const WhatChangedScreen(),
          ),
          _tool(
            c,
            'All data',
            Icons.insights_outlined,
            E6C.ink2,
            const HealthScreen(),
          ),
        ]),
      ],
    );
  }

  Widget _tool(
    BuildContext c,
    String label,
    IconData icon,
    Color color,
    Widget screen,
  ) => E6Card(
    padding: const EdgeInsets.all(6),
    onTap: () => e6Push(c, screen),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 6),
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 6),
        Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: E6T.small.copyWith(
            color: E6C.ink,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

// ─── More tab ──────────────────────────────────────────────────────────────

class E6More extends StatelessWidget {
  const E6More({super.key});

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final battery = app.device.batteryPct;
    Widget group(String title, List<(String, IconData, Widget)> items) =>
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            E6Section(title),
            E6Card(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++)
                    E6Row(
                      leading: Icon(items[i].$2, color: E6C.ink2, size: 20),
                      title: items[i].$1,
                      divider: i < items.length - 1,
                      onTap: () => e6Push(c, items[i].$3),
                    ),
                ],
              ),
            ),
          ],
        );
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(c).top + 8,
        16,
        _kTabClearance,
      ),
      children: [
        E6Card(
          onTap: () => e6Push(c, const ProfileHome()),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 24,
                backgroundColor: Color(0xFF3A4247),
                child: Icon(Icons.person_outline, color: E6C.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Profile',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: E6C.ink,
                      ),
                    ),
                    Text(
                      app.isConnected
                          ? 'Band connected${battery == null ? '' : ', battery ${battery.round()}%'}'
                          : 'Band not connected',
                      style: E6T.sub,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: E6C.ink2),
            ],
          ),
        ),
        const E6Section('Look'),
        ValueListenableBuilder<bool>(
          valueListenable: E6Prefs.glass,
          builder: (c, glass, _) => E6Card(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                for (final (label, value) in const [
                  ('Classic', false),
                  ('Liquid Glass', true),
                ])
                  Expanded(
                    child: Semantics(
                      selected: glass == value,
                      button: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => E6Prefs.setGlass(value),
                        child: Container(
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: glass == value
                                ? const Color(0x29FFFFFF)
                                : null,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            label,
                            style: E6T.body.copyWith(fontSize: 15),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const _E6IconPicker(),
        group('Band', [
          ('My devices', Icons.watch_outlined, const MyDevices()),
          ('Alarm and Fajr buzz', Icons.alarm, const AlarmScreen()),
          (
            'Band notifications',
            Icons.notifications_none,
            const BandNotifications(),
          ),
          ('Step calibration', Icons.straighten, const StepCalibrationScreen()),
        ]),
        group('Your data', [
          ('Export and backup', Icons.download_outlined, const DataScreen()),
          ('Import from phone', Icons.phone_iphone, const PhoneImport()),
          ('Report a problem', Icons.flag_outlined, const ReportIssueScreen()),
        ]),
        group('App', [
          ('Settings', Icons.settings_outlined, const MoreSettings()),
        ]),
        Padding(
          padding: const EdgeInsets.only(top: 18),
          child: TextButton(
            onPressed: () async {
              await E6Prefs.setOn(false);
              if (c.mounted) {
                ScaffoldMessenger.of(c).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'The previous design comes back the next time you open Edge.',
                    ),
                  ),
                );
              }
            },
            child: const Text(
              'Use the previous design',
              style: TextStyle(color: E6C.ink2),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── + sheet ───────────────────────────────────────────────────────────────

Future<void> showE6ActionSheet(BuildContext c) {
  return showModalBottomSheet<void>(
    context: c,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x99000000),
    isScrollControlled: true,
    builder: (sheet) => ValueListenableBuilder<bool>(
      valueListenable: E6Prefs.glass,
      builder: (sheet, glass, _) {
        void open(Widget w) {
          Navigator.of(sheet).pop();
          unawaited(e6Push(c, w));
        }

        final options = <(String, String, IconData, Color, VoidCallback)>[
          (
            'Start activity',
            'Run, walk, gym and more',
            Icons.play_arrow_rounded,
            E6C.strain,
            () => open(const WorkoutScreen()),
          ),
          (
            'Journal',
            'How yesterday went',
            Icons.edit_outlined,
            const Color(0x24FFFFFF),
            () => open(const JournalCompose()),
          ),
          (
            'Breathe',
            'Slows your heart',
            Icons.air,
            E6C.sleep,
            () => open(const CalmBreathing()),
          ),
          (
            'Take an ECG',
            '30 second reading',
            Icons.monitor_heart_outlined,
            E6C.heart,
            () => open(const EcgHomeScreen()),
          ),
          (
            'Fajr buzz',
            'Settings and test',
            Icons.alarm,
            const Color(0x24FFFFFF),
            () => open(const AlarmScreen()),
          ),
          (
            'Log food',
            'Or scan a barcode',
            Icons.restaurant_outlined,
            E6C.mid,
            () => open(const NutritionScreen(page: true)),
          ),
        ];
        final body = Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            10,
            18,
            MediaQuery.paddingOf(sheet).bottom + 18,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0x4DFFFFFF),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text('START', style: E6T.cap(18))),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(sheet).pop(),
                    icon: const Icon(Icons.close, color: E6C.ink),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _grid([
                for (final o in options)
                  E6Card(
                    onTap: o.$5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: o.$4,
                          child: Icon(o.$3, color: E6C.ink, size: 20),
                        ),
                        const SizedBox(height: 14),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.$1, style: E6T.body),
                            Text(
                              o.$2,
                              style: E6T.small,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ]),
              const SizedBox(height: 12),
              const Text(
                'Band timer: say or type to Siri, “Remind me in 20 minutes with Edge.”',
                style: E6T.sub,
              ),
            ],
          ),
        );
        const radius = BorderRadius.vertical(top: Radius.circular(36));
        return glass
            ? E6Glass(radius: radius, strong: true, child: body)
            : DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1F22),
                  borderRadius: radius,
                ),
                child: body,
              );
      },
    ),
  );
}

/// The home-screen icon: Orbit, Orbit Glass or Orbit Tinted. iOS owns the
/// choice and asks the user to confirm each change.
class _E6IconPicker extends StatefulWidget {
  const _E6IconPicker();
  @override
  State<_E6IconPicker> createState() => _E6IconPickerState();
}

class _E6IconPickerState extends State<_E6IconPicker> {
  bool _available = false;
  AppIconChoice _current = AppIconChoice.orbit;

  @override
  void initState() {
    super.initState();
    AppIcon.available().then((a) async {
      final cur = a ? await AppIcon.current() : AppIconChoice.orbit;
      if (mounted)
        setState(() {
          _available = a;
          _current = cur;
        });
    });
  }

  Future<void> _pick(AppIconChoice c) async {
    if (c == _current) return;
    final ok = await AppIcon.set(c);
    if (!mounted) return;
    if (ok) setState(() => _current = c);
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The icon could not be changed. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext c) {
    if (!_available) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const E6Section('App icon'),
        E6Card(
          child: Row(
            children: [
              for (final choice in AppIconChoice.values)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: choice == _current,
                    label: choice.label,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _pick(choice),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: choice == _current
                                      ? E6C.ink
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.asset(
                                  choice.asset,
                                  width: 60,
                                  height: 60,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              choice.label,
                              style: E6T.small.copyWith(
                                color: choice == _current ? E6C.ink : E6C.ink2,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
