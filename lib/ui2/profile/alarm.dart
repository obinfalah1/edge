// The band alarm.
//
// This screen exists because the alarm is the one thing in the app that keeps
// working when the app does not. It is armed on the STRAP's own real-time
// clock, so it survives the app being killed, the phone rebooting, and the
// phone being out of range entirely. The rebuild shipped with no alarm UI at
// all while `AppState` still restored `alarm_epoch` on launch and still ran the
// confirmation state machine — which means an alarm armed on an older build
// went on firing every morning with nothing anywhere to see it or stop it.
//
// The honesty problem is confirmation. Writing SET_ALARM to the band is not
// evidence that the band latched it; the strap says so separately, by emitting
// event 56, and it might never arrive. And after a relaunch there is no live
// confirmation at all — only the epoch we wrote down. Three different states,
// and the screen says which one it is rather than drawing a confident green
// tick over all three.
//
// A single next-occurrence time picker used to live here. It is gone: the
// weekly schedule below is now the ONLY thing that arms the band (AppState
// computes the next enabled occurrence on every connect/sync), so a second,
// independent "set one alarm" affordance would just be a second source of
// truth that the schedule engine silently overwrites on the next sync.

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/day_label.dart' show calendarDaysBetween;
import '../../l10n/app_localizations.dart';
import '../../l10n/display_text.dart';
import '../../state/alarm_schedule.dart';
import '../../state/app_state.dart';
import '../../state/clock_format.dart' show formatClock;
import '../../state/fajr_alarm.dart' show FajrAlarmSettings;
import '../../state/prayer_buzz.dart' show Prayer, PrayerBuzzSettings;
import '../screens/home_screen.dart' show go, weekdayShortName;
import '../screens/metric_detail.dart' show detailLinkRow;
import '../ui2.dart';
import 'profile.dart' show SetRow, settingsGroup;

/// What we actually know about the armed alarm.
enum AlarmArmState {
  /// Nothing armed.
  none,

  /// Written to the band; its confirmation event may still be in flight.
  pending,

  /// The band emitted ALARM_SET — it latched.
  confirmed,

  /// Armed, but unconfirmed: either the band never acknowledged the write, or
  /// this is an alarm from a previous run of the app and there is no live
  /// confirmation to read. Both mean the same thing to the user — we cannot
  /// promise it will fire — so they share one state rather than being dressed
  /// up as two.
  unknown,
}

/// The armed instant and what we know about it. Shared by this screen and
/// Home's door so the two can never disagree. Reading it arms nothing.
(DateTime?, AlarmArmState) alarmArmOf(AppState app) {
  final epoch = app.alarmEpoch;
  if (epoch == null) return (null, AlarmArmState.none);
  return (
    DateTime.fromMillisecondsSinceEpoch(epoch * 1000),
    app.alarmConfirmed
        ? AlarmArmState.confirmed
        : app.alarmPending
            ? AlarmArmState.pending
            : AlarmArmState.unknown,
  );
}

/// Home's door onto the alarm: the next armed day and time plus its state,
/// or "Set an alarm". A plain [detailLinkRow], not a card. An epoch already
/// behind [now] fired or was missed while the link was down (only a live
/// event or the next connect clears it), so it says so instead of passing a
/// spent alarm off as the next one.
Widget alarmDoor(BuildContext c, DateTime? at, AlarmArmState state,
        {DateTime? now}) =>
    _AlarmTick.wrap(at, now, (n) {
      final l = AppLocalizations.of(c);
      final String sub;
      if (at == null) {
        sub = l?.alarmSetAnAlarm ?? 'Set an alarm';
      } else {
        final what = at.isAfter(n)
            ? AlarmScreenView._localizedStateLabel(c, state)
            : (l?.alarmInThePast ??
                'In the past — it has already fired or been missed');
        sub = calm(P.of(c), '${AlarmScreenView._dayAndTime(c, at)} · $what');
      }
      return detailLinkRow(c, LucideIcons.alarmClock,
          l?.alarmNavTitle ?? 'Alarm', sub, () => go(c, const AlarmScreen()));
    });

/// The same facts as [alarmDoor], as an "At a glance" tile: the armed time
/// (or "Not set") and, under it, which day and what we know about it. The
/// icon takes the state's colour, so an unconfirmed alarm is not drawn in the
/// same calm tone as a confirmed one.
Widget alarmGlanceCard(BuildContext c, DateTime? at, AlarmArmState state,
        {DateTime? now}) =>
    _AlarmTick.wrap(at, now, (n) {
      final l = AppLocalizations.of(c);
      return SignalCard(
        LucideIcons.alarmClock,
        AlarmScreenView._stateColor(state),
        l?.alarmNavTitle ?? 'Alarm',
        at == null
            ? (l?.alarmStateNotSet ?? 'Not set')
            : AlarmScreenView._hhmm(at),
        sub: at == null
            ? (l?.alarmSetAnAlarm ?? 'Set an alarm')
            : at.isAfter(n)
                ? calm(P.of(c), '${AlarmScreenView._whichDay(c, at, n)} · '
                    '${AlarmScreenView._localizedStateLabel(c, state)}')
                : (l?.alarmGlanceInThePast ?? 'Fired or missed'),
        onTap: () => go(c, const AlarmScreen()),
      );
    });

/// The same alarm as [alarmGlanceCard], as a list row (Line and Glass).
Widget alarmGlanceRow(BuildContext c, DateTime? at, AlarmArmState state,
        {DateTime? now, String? title}) =>
    _AlarmTick.wrap(at, now, (n) {
      final l = AppLocalizations.of(c);
      final (fig, ap) = splitClock(at == null ? '' : AlarmScreenView._hhmm(at));
      final label = AlarmScreenView._localizedStateLabel(c, state);
      return ListRow(
        icon: LucideIcons.alarmClock,
        title: title ?? (l?.alarmNavTitle ?? 'Alarm'),
        sub: at == null
            ? (l?.alarmSetAnAlarm ?? 'Set an alarm')
            : at.isAfter(n)
                ? '${AlarmScreenView._whichDay(c, at, n)}, ${label.toLowerCase()}'
                    '${state == AlarmArmState.confirmed ? ' on the band' : ''}'
                : (l?.alarmGlanceInThePast ?? 'Fired or missed'),
        value: at == null ? (l?.alarmStateNotSet ?? 'Not set') : fig,
        unit: ap,
        onTap: () => go(c, const AlarmScreen()),
      );
    });

/// Rebuilds [build] at the two moments its text goes stale on its own: when
/// the armed alarm passes (upcoming → fired or missed) and at local midnight
/// (Tomorrow → Later today). Home rebuilds only on new data or a changed
/// alarm, so with the band out of range nothing else would — and the row
/// went on calling an alarm that had already passed the next one.
class _AlarmTick extends StatefulWidget {
  final DateTime? at;
  final Widget Function(DateTime now) build;

  const _AlarmTick(this.at, this.build);

  /// A pinned [now] (tests, goldens) is a frozen clock: nothing to wait for.
  static Widget wrap(DateTime? at, DateTime? now,
          Widget Function(DateTime now) build) =>
      now != null ? build(now) : _AlarmTick(at, build);

  @override
  State<_AlarmTick> createState() => _AlarmTickState();
}

class _AlarmTickState extends State<_AlarmTick> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_AlarmTick old) {
    super.didUpdateWidget(old);
    if (old.at != widget.at) _schedule();
  }

  // Scheduled here rather than in build, so a Home rebuild on new data does
  // not throw away and re-create the timer every time.
  void _schedule() {
    final now = clock.now();
    final midnight = DateTime(now.year, now.month, now.day + 1);
    final at = widget.at;
    final next =
        at != null && at.isAfter(now) && at.isBefore(midnight) ? at : midnight;
    _t?.cancel();
    _t = Timer(next.difference(now), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  Widget build(BuildContext c) => widget.build(clock.now());

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }
}

class AlarmScreen extends StatelessWidget {
  const AlarmScreen({super.key});

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final (armedAt, state) = alarmArmOf(app);
    // setScheduleDay saves the row even when the band never got it (offline,
    // write failed, strap rejected the arm); surface that as a failure so the
    // screen doesn't say "sent" while the band still holds the old time.
    final notOnBand = uiText(c,
        "Saved, but the band hasn't taken it yet — it's sent again on the next sync");
    // The Fajr alarm is a personal addition: its copy is English only.
    const noTimes = "Couldn't get prayer times — check the internet connection";
    const stockPattern =
        'The band refused the custom pattern — the test (and Fajr) use its standard alarm buzz';
    Future<void> onBand(Future<bool> write) async {
      if (!await write) throw Exception(notOnBand);
    }
    return AlarmScreenView(
      armedAt: armedAt,
      state: state,
      firedAt: app.alarmFiredAt,
      connected: app.isConnected,
      schedule: app.alarmSchedule,
      onToggleDay: (weekday, enabled) =>
          onBand(app.setScheduleDay(weekday: weekday, enabled: enabled)),
      onSetDayTime: (weekday, hour, minute) => onBand(
          app.setScheduleDay(weekday: weekday, hour: hour, minute: minute)),
      onSetSmartWindow: (weekday, minutes) => onBand(
          app.setScheduleDay(weekday: weekday, smartWindowMinutes: minutes)),
      onTest: app.testAlarmBuzz,
      onCancel: app.disableAlarm,
      fajr: app.fajrAlarm,
      fajrNext: app.fajrAlarmNext,
      fajrPrayer: app.fajrPrayerNext,
      fajrSource: app.fajrLocationSource,
      onSetFajr: ({enabled, offsetMinutes, buzzCount, pauseSteps}) async {
        final onBandNow = await app.setFajrAlarm(
            enabled: enabled,
            offsetMinutes: offsetMinutes,
            buzzCount: buzzCount,
            pauseSteps: pauseSteps);
        if (!onBandNow) throw Exception(notOnBand);
      },
      onRefreshFajr: () async {
        if (!await app.refreshFajrTimes()) throw Exception(noTimes);
      },
      onTestFajr: () async {
        if (await app.testFajrAlarm()) throw Exception(stockPattern);
      },
      prayer: app.prayerBuzz,
      prayerNext: app.prayerBuzzNext,
      prayerToday: app.prayerTimesToday,
      onSetPrayer: ({toggle, offsetMinutes, buzzCount}) async {
        final onBandNow = await app.setPrayerBuzz(
            toggle: toggle, offsetMinutes: offsetMinutes, buzzCount: buzzCount);
        if (!onBandNow) throw Exception(notOnBand);
      },
    );
  }
}

/// Fajr alarm copy: a personal addition, English only, so it stays out of
/// the translated-literal helpers.
String _fajrText(String s) => s;

/// A pause setting as the strap plays it: steps of 240 ms.
String _pauseLabel(int steps) =>
    '${(steps * FajrAlarmSettings.pauseStepMs / 1000).toStringAsFixed(2)} s';

class AlarmScreenView extends StatelessWidget {
  final DateTime? armedAt;
  final AlarmArmState state;
  final bool connected;

  /// When the band last fired the alarm, shown for the rest of that day.
  final DateTime? firedAt;

  /// Injectable clock. "Tomorrow" vs "Later today" is relative, so a golden of
  /// this screen is otherwise a function of when the suite happens to run.
  final DateTime? now;

  /// Always exactly 7 entries in weekday order — see
  /// `fillDefaultAlarmSchedule` in state/alarm_schedule.dart, which is what
  /// [AppState.alarmSchedule] guarantees.
  final List<AlarmScheduleEntry> schedule;

  /// All four talk to the band or its schedule and all throw when it is not
  /// connected or the band did not take the write — the screen reports the
  /// failure rather than pretending it worked.
  final Future<void> Function(int weekday, bool enabled)? onToggleDay;
  final Future<void> Function(int weekday, int hour, int minute)?
      onSetDayTime;
  final Future<void> Function(int weekday, int minutes)? onSetSmartWindow;
  final Future<void> Function()? onTest, onCancel;

  /// The Fajr alarm (fajr_alarm.dart): its settings, the next buzz time and
  /// the Fajr behind it, and where the prayer times are for.
  final FajrAlarmSettings? fajr;
  final DateTime? fajrNext, fajrPrayer;
  final String? fajrSource;
  final Future<void> Function({
    bool? enabled,
    int? offsetMinutes,
    int? buzzCount,
    int? pauseSteps,
  })? onSetFajr;
  final Future<void> Function()? onRefreshFajr, onTestFajr;

  /// Prayer buzzes (prayer_buzz.dart): Dhuhr, Asr, Maghrib and Isha, each
  /// with its own switch; separate from the Fajr alarm.
  final PrayerBuzzSettings? prayer;
  final ({DateTime at, Prayer prayer})? prayerNext;
  final Map<Prayer, DateTime> prayerToday;
  final Future<void> Function({
    Prayer? toggle,
    int? offsetMinutes,
    int? buzzCount,
  })? onSetPrayer;

  const AlarmScreenView({
    super.key,
    this.armedAt,
    this.state = AlarmArmState.none,
    this.connected = false,
    this.firedAt,
    this.now,
    this.schedule = const [],
    this.onToggleDay,
    this.onSetDayTime,
    this.onSetSmartWindow,
    this.onTest,
    this.onCancel,
    this.fajr,
    this.fajrNext,
    this.fajrPrayer,
    this.fajrSource,
    this.onSetFajr,
    this.onRefreshFajr,
    this.onTestFajr,
    this.prayer,
    this.prayerNext,
    this.prayerToday = const {},
    this.onSetPrayer,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final at = armedAt;
    final fired = firedAt;
    final anyDayEnabled = schedule.any((d) => d.enabled);
    if (p.metro || p.glass) return _refined(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(l?.alarmNavTitle ?? 'Alarm',
                sub: l?.alarmNavSub ?? 'Wakes you on the band, not the phone'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                if (fired != null &&
                    calendarDaysBetween(fired, now ?? DateTime.now()) == 0) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Pill(
                        l?.alarmFiredAt(_hhmm(fired)) ??
                            'Fired at ${_hhmm(fired)}', C.green,
                        icon: LucideIcons.alarmClockCheck),
                  ),
                  const SizedBox(height: S.x3),
                ],
                if (at != null && p.metro) ...[
                  // Line: the next alarm on a signage panel, the time in
                  // large figures, the band's confirmation in gold.
                  Container(
                    padding: const EdgeInsets.all(S.x4),
                    decoration: const BoxDecoration(
                        color: LineTok.sign, borderRadius: R.rMetro),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Next alarm',
                              style: F.cap.copyWith(color: LineTok.signMute)),
                          const SizedBox(height: S.x1),
                          Text(_hhmm(at),
                              style: F.n48.copyWith(
                                  color: LineTok.signInk,
                                  fontFamily: LineTok.display,
                                  fontWeight: FontWeight.w300)),
                          Text(
                              '${_whichDay(c, at, now ?? DateTime.now())}, '
                              '${_localizedStateLabel(c, state).toLowerCase()}',
                              style: F.cap.copyWith(
                                  color: state == AlarmArmState.confirmed
                                      ? LineTok.lapis
                                      : LineTok.signMute)),
                        ]),
                  ),
                  if (_stateDetail(c, state) case final detail?) ...[
                    const SizedBox(height: S.x3),
                    StatusCard(_stateHeadline(c, state), detail,
                        icon: _stateIcon(state)),
                  ],
                  const SizedBox(height: S.x4),
                ] else if (at != null) ...[
                  Surface(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l?.alarmNextLabel ?? 'NEXT',
                              style: F.over.copyWith(color: p.ink3)),
                          const SizedBox(height: S.x1),
                          Text(_dayAndTime(c, at),
                              style: F.n48.copyWith(color: p.ink)),
                          Text(_whichDay(c, at, now ?? DateTime.now()),
                              style: F.cap.copyWith(color: p.ink2)),
                          const SizedBox(height: S.x3),
                          Pill(_localizedStateLabel(c, state), _stateColor(state),
                              icon: _stateIcon(state)),
                        ]),
                  ),
                  if (_stateDetail(c, state) case final detail?) ...[
                    const SizedBox(height: S.x3),
                    StatusCard(_stateHeadline(c, state), detail,
                        icon: _stateIcon(state)),
                  ],
                  const SizedBox(height: S.x4),
                ],
                if (fajr != null) ...[
                  _fajrGroup(c, fajr!),
                  const SizedBox(height: S.x3),
                ],
                if (prayer != null) ...[
                  _prayerGroup(c, prayer!),
                  const SizedBox(height: S.x3),
                ],
                if (!connected)
                  StatusCard(
                    l?.alarmNotConnectedTitle ?? 'The band is not connected',
                    l?.alarmNotConnectedBody ??
                        'Changing, testing or cancelling the alarm needs a live connection. An alarm that is already set still works; it lives on the band.',
                    icon: LucideIcons.bluetoothOff,
                  )
                else ...[
                  settingsGroup(c, l?.alarmScheduleGroup ?? 'Weekly schedule', [
                    for (final day in schedule) ...[
                      SetRow(
                          LucideIcons.calendarDays,
                          C.orange,
                          _weekdayLabel(c, day.weekday),
                          value: day.enabled
                              ? (l?.stateOn ?? 'On')
                              : (l?.stateOff ?? 'Off'),
                          chevron: false,
                          onTap: () => _run(
                              c,
                              onToggleDay == null
                                  ? null
                                  : () => onToggleDay!(
                                      day.weekday, !day.enabled),
                              null)),
                      if (day.enabled) ...[
                        SetRow(LucideIcons.clock, C.blue,
                            l?.alarmWakeTimeRowTitle ?? 'Wake time',
                            value: _hhmmOf(day.hour, day.minute),
                            chevron: false,
                            onTap: () => _pickDayTime(c, day)),
                        SetRow(LucideIcons.moon, C.purple, 'Smart wake',
                            value: day.smartWindowMinutes == 0
                                ? (l?.stateOff ?? 'Off')
                                : '${day.smartWindowMinutes} min early',
                            chevron: false,
                            onTap: () => _pickSmartWindow(c, day)),
                      ],
                    ],
                  ]),
                  const SizedBox(height: S.x3),
                  if (at != null) ...[
                    BigButton(l?.alarmTestTheBuzz ?? 'Test the buzz',
                        icon: LucideIcons.vibrate,
                        color: C.blue,
                        soft: true,
                        onTap: () => _run(
                            c, onTest, l?.alarmBuzzingTheBand ?? 'Buzz sent to the band')),
                    const SizedBox(height: S.x3),
                  ],
                  if (at != null || anyDayEnabled)
                    BigButton(l?.alarmCancelTheAlarm ?? 'Cancel the alarm',
                        icon: LucideIcons.bellOff,
                        color: C.red,
                        soft: true,
                        onTap: () => _run(
                            c, onCancel, l?.alarmCancelled ?? 'Alarm cancelled')),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── Line and Liquid Glass ────────────────────────────────────────────────
  //
  // The same settings and the same calls, laid out for a glance: one card
  // with the next alarm and whether the band has it, the Fajr numbers as
  // plain rows, the four prayers as switches, the week as seven day buttons
  // with a row only for each day that is on, and both tests together at the
  // bottom where the thumb is.

  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];

  Widget _refined(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final at = armedAt;
    final fired = firedAt;
    final f = fajr;
    final anyDayEnabled = schedule.any((d) => d.enabled);
    final n = now ?? DateTime.now();
    final isFajr = at != null &&
        f != null &&
        f.enabled &&
        fajrNext != null &&
        fajrNext!.difference(at).inMinutes.abs() < 1;
    Widget section(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(S.x1, S.x5, S.x1, S.x2),
          child: Text(t,
              style: F.t2.copyWith(
                  color: p.ink,
                  fontFamily: p.metro ? LineTok.display : null,
                  fontWeight: p.metro ? FontWeight.w500 : FontWeight.w700)),
        );
    Widget caption(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x2, 0),
          child: Text(t, style: F.cap.copyWith(color: p.ink3)),
        );
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(l?.alarmNavTitle ?? 'Alarm'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(S.x1, 0, S.x1, S.x3),
                  child: Text('The band buzzes on its own clock, phone locked or not.',
                      style: F.cap.copyWith(color: p.ink3)),
                ),
                if (fired != null && calendarDaysBetween(fired, n) == 0) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Pill(
                        l?.alarmFiredAt(_hhmm(fired)) ?? 'Fired at ${_hhmm(fired)}',
                        C.green,
                        icon: LucideIcons.alarmClockCheck),
                  ),
                  const SizedBox(height: S.x3),
                ],
                if (at != null) _hero(c, at, n, isFajr),
                if (at != null && state != AlarmArmState.confirmed)
                  if (_stateDetail(c, state) case final detail?) ...[
                    const SizedBox(height: S.x3),
                    StatusCard(_stateHeadline(c, state), detail, icon: _stateIcon(state)),
                  ],
                if (f != null) ...[
                  section(_fajrText('Fajr alarm')),
                  _fajrRows(c, f, showNext: !isFajr),
                ],
                if (prayer != null) ...[
                  section('Prayer buzzes'),
                  _prayerRows(c, prayer!),
                  if (fajrSource != null && fajrSource != 'none')
                    caption('Times for ${_whereText().toLowerCase()}, UAE calculation.'),
                ],
                if (!connected) ...[
                  const SizedBox(height: S.x4),
                  StatusCard(
                    l?.alarmNotConnectedTitle ?? 'The band is not connected',
                    l?.alarmNotConnectedBody ??
                        'Changing, testing or cancelling the alarm needs a live connection. An alarm that is already set still works; it lives on the band.',
                    icon: LucideIcons.bluetoothOff,
                  ),
                ] else ...[
                  section('Weekly alarm'),
                  _weekRows(c),
                  caption('Tap a day to turn its alarm on or off.'),
                  if ((f != null && f.enabled) || at != null || anyDayEnabled) ...[
                    section('Check it works'),
                    if (f != null && f.enabled)
                      PrimaryButton(_fajrText('Test the Fajr buzz in 1 minute'),
                          icon: LucideIcons.vibrate,
                          onTap: () => _run(c, onTestFajr,
                              _fajrText('Test alarm set — the band buzzes in about a minute'))),
                    if (at != null) ...[
                      const SizedBox(height: S.x3),
                      SecondaryButton('Test the alarm buzz',
                          onTap: () => _run(
                              c, onTest, l?.alarmBuzzingTheBand ?? 'Buzz sent to the band')),
                    ],
                    if (at != null || anyDayEnabled) ...[
                      const SizedBox(height: S.x2),
                      Center(
                        child: TextButton(
                          style: TextButton.styleFrom(
                              foregroundColor: p.on(C.red),
                              minimumSize: const Size(0, 44)),
                          onPressed: () => _confirmCancel(c),
                          child: Text(l?.alarmCancelTheAlarm ?? 'Cancel the alarm',
                              style: F.body.copyWith(fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ],
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  /// The next alarm: the time large, where it comes from, and whether the
  /// band has it. Line sets it on the signage panel; Glass on a glass card.
  Widget _hero(BuildContext c, DateTime at, DateTime n, bool isFajr) {
    final p = P.of(c);
    final onSign = p.metro;
    final ink = onSign ? LineTok.signInk : p.ink;
    final mute = onSign ? LineTok.signMute : p.ink3;
    final (fig, ap) = splitClock(_hhmm(at));
    final from = isFajr && fajrPrayer != null
        ? 'Fajr ${_hhmm(fajrPrayer!)}, plus ${fajr!.offsetMinutes} min'
        : _weekdayNames[(at.weekday - 1) % 7];
    final ok = state == AlarmArmState.confirmed;
    final stateColor = ok
        ? (onSign ? C.signGreen : p.on(C.green))
        : (onSign ? LineTok.signMute : p.ink3);
    final stateText = ok ? 'Confirmed on the band' : _localizedStateLabel(c, state);
    final body = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Next alarm, ${_whichDay(c, at, n).toLowerCase()}', style: F.cap.copyWith(color: mute)),
      const SizedBox(height: S.x1),
      Text.rich(TextSpan(children: [
        TextSpan(
            text: fig,
            style: F.n48.copyWith(
                color: ink,
                fontFamily: p.metro ? LineTok.display : null,
                fontWeight: FontWeight.w300)),
        if (ap.isNotEmpty) TextSpan(text: ' $ap', style: F.head.copyWith(color: mute)),
      ])),
      const SizedBox(height: S.x2),
      Wrap(
          spacing: S.x3,
          runSpacing: S.x1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(from, style: F.cap.copyWith(color: onSign ? LineTok.signMute : p.ink2)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(ok ? LucideIcons.check : _stateIcon(state), size: 16, color: stateColor),
              const SizedBox(width: 4),
              Flexible(
                child: Text(stateText,
                    style: F.cap.copyWith(color: stateColor, fontWeight: FontWeight.w600)),
              ),
            ]),
          ]),
    ]);
    return Semantics(
      container: true,
      label: 'Next alarm ${_whichDay(c, at, n)} at ${_hhmm(at)}, $from, $stateText',
      child: ExcludeSemantics(
        child: onSign
            ? Container(
                padding: const EdgeInsets.all(S.x5),
                decoration: const BoxDecoration(color: LineTok.sign, borderRadius: R.rMetro),
                child: body)
            : Surface(pad: const EdgeInsets.all(S.x5), child: body),
      ),
    );
  }

  String _whereText() => switch (fajrSource) {
        'gps' => _fajrText('Your location'),
        'last' => _fajrText('Your last location'),
        'sharjah' => _fajrText('Sharjah (no location yet)'),
        _ => _fajrText('Not fetched yet'),
      };

  Widget _prayerBadge(BuildContext c, String letter, bool on) {
    final p = P.of(c);
    if (p.glass) {
      return rowLead(
          c,
          switch (letter) {
            'F' => LucideIcons.sunrise,
            'M' || 'I' => LucideIcons.moon,
            _ => LucideIcons.sun,
          },
          color: on ? C.prayer : p.ink3);
    }
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: on ? LineTok.lapis : p.card2, borderRadius: R.rMd),
      child: Text(letter,
          style: F.body.copyWith(
              color: on ? LineTok.sign : p.ink3,
              fontFamily: LineTok.display,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _fajrRows(BuildContext c, FajrAlarmSettings f, {required bool showNext}) {
    Future<void> set({bool? on, int? off, int? n, int? gap}) async {
      if (onSetFajr == null) return;
      await onSetFajr!(enabled: on, offsetMinutes: off, buzzCount: n, pauseSteps: gap);
    }
    void toggle() {
      selectHaptic();
      _run(c, () => set(on: !f.enabled),
          f.enabled ? _fajrText('Fajr alarm off') : _fajrText('Fajr alarm on — sent to the band'));
    }
    final buzz = fajrNext;
    return RowGroup([
      ListRow(
        leading: _prayerBadge(c, 'F', f.enabled),
        title: _fajrText('Fajr alarm'),
        sub: 'Every day, from your prayer times',
        trailing: Switch.adaptive(value: f.enabled, onChanged: onSetFajr == null ? null : (_) => toggle()),
        chevron: false,
        onTap: onSetFajr == null ? null : toggle,
      ),
      if (f.enabled) ...[
        if (showNext)
          ListRow(
              title: 'Next Fajr buzz',
              detail: buzz == null
                  ? _fajrText('Fetching prayer times…')
                  : '${_whichDay(c, buzz, now ?? DateTime.now())}, ${_hhmm(buzz)}'),
        ListRow(
            title: _fajrText('Minutes after Fajr'),
            detail: '${f.offsetMinutes} min',
            onTap: () => _pickNumber(c, _fajrText('Minutes after Fajr'),
                const [0, 5, 10, 15, 20, 25, 30, 45, 60, 90, 120], (m) => '$m min', (m) => set(off: m))),
        ListRow(
            title: _fajrText('Buzzes'),
            detail: '${f.buzzCount}',
            onTap: () => _pickNumber(c, _fajrText('Buzzes'),
                [for (var i = 1; i <= 10; i++) i, 15, 20], (n) => '$n', (n) => set(n: n))),
        ListRow(
            title: 'Gap between buzzes',
            detail: '${(f.pauseSteps * FajrAlarmSettings.pauseStepMs / 1000).toStringAsFixed(1)} s',
            onTap: () => _pickNumber(c, 'Gap between buzzes',
                [for (var i = 1; i <= FajrAlarmSettings.maxPause; i++) i], _pauseLabel, (g) => set(gap: g))),
        ListRow(
            title: _fajrText('Prayer times for'),
            detail: _whereText(),
            onTap: () => _run(c, onRefreshFajr, _fajrText('Prayer times updated'))),
      ],
    ]);
  }

  Widget _prayerRows(BuildContext c, PrayerBuzzSettings s) {
    Future<void> set({Prayer? toggle, int? off, int? n}) async {
      if (onSetPrayer == null) return;
      await onSetPrayer!(toggle: toggle, offsetMinutes: off, buzzCount: n);
    }
    void toggle(Prayer pr) {
      selectHaptic();
      final on = !s.isOn(pr);
      _run(c, () => set(toggle: pr), on ? '${pr.api} buzz on' : '${pr.api} buzz off');
    }
    return RowGroup([
      for (final pr in Prayer.values)
        ListRow(
          leading: _prayerBadge(c, pr.api.substring(0, 1), s.isOn(pr)),
          title: pr.label(false),
          sub: prayerToday[pr] == null ? null : _hhmm(prayerToday[pr]!),
          trailing: Switch.adaptive(
              value: s.isOn(pr), onChanged: onSetPrayer == null ? null : (_) => toggle(pr)),
          chevron: false,
          onTap: onSetPrayer == null ? null : () => toggle(pr),
        ),
      if (s.anyOn) ...[
        ListRow(
            title: 'Minutes after the adhan',
            detail: '${s.offsetMinutes} min',
            onTap: () => _pickNumber(c, 'Minutes after the adhan',
                const [0, 5, 10, 15, 20, 30, 45, 60], (m) => '$m min', (m) => set(off: m))),
        ListRow(
            title: 'Buzzes',
            detail: '${s.buzzCount}',
            onTap: () => _pickNumber(c, 'Buzzes', [for (var i = 1; i <= 10; i++) i], (n) => '$n',
                (n) => set(n: n))),
      ],
    ]);
  }

  Widget _weekRows(BuildContext c) {
    final p = P.of(c);
    final on = p.metro ? LineTok.lapis : p.fill(p.tint);
    final onInk = p.metro ? LineTok.sign : p.inkOnFill;
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final days = Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (final day in schedule)
          Pressable(
            semanticLabel:
                '${_weekdayNames[day.weekday % 7]} alarm, ${day.enabled ? 'on' : 'off'}',
            onTap: onToggleDay == null
                ? null
                : () {
                    selectHaptic();
                    _run(c, () => onToggleDay!(day.weekday, !day.enabled), null);
                  },
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: day.enabled ? on : p.card2),
              child: Text(letters[day.weekday % 7],
                  style: F.body.copyWith(
                      color: day.enabled ? onInk : p.ink2,
                      fontWeight: FontWeight.w600,
                      fontFamily: p.metro ? LineTok.display : null)),
            ),
          ),
      ]),
    );
    return RowGroup([
      days,
      for (final day in schedule)
        if (day.enabled)
          Builder(builder: (c) {
            final (fig, ap) = splitClock(_hhmmOf(day.hour, day.minute));
            return ListRow(
              title: _weekdayNames[day.weekday % 7],
              sub: day.smartWindowMinutes == 0
                  ? 'Smart wake off'
                  : 'Smart wake ${day.smartWindowMinutes} min early',
              value: fig,
              unit: ap,
              onTap: () => _dayOptions(c, day),
            );
          }),
    ]);
  }

  /// A day's two settings, as an iOS action sheet: its wake time and its
  /// smart wake window.
  Future<void> _dayOptions(BuildContext c, AlarmScheduleEntry day) async {
    final pick = await showModalBottomSheet<int>(
      context: c,
      backgroundColor: P.of(c).cardSolid,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              title: Text('Change the wake time (${_hhmmOf(day.hour, day.minute)})'),
              onTap: () => Navigator.pop(ctx, 0)),
          ListTile(
              title: Text(day.smartWindowMinutes == 0
                  ? 'Smart wake: off'
                  : 'Smart wake: ${day.smartWindowMinutes} min early'),
              onTap: () => Navigator.pop(ctx, 1)),
        ]),
      ),
    );
    if (pick == null || !c.mounted) return;
    if (pick == 0 && onSetDayTime != null) await _pickDayTime(c, day);
    if (pick == 1 && onSetSmartWindow != null && c.mounted) await _pickSmartWindow(c, day);
  }

  Future<void> _confirmCancel(BuildContext c) async {
    final l = AppLocalizations.of(c);
    final yes = await showAdaptiveDialog<bool>(
      context: c,
      builder: (ctx) => AlertDialog.adaptive(
        title: const Text('Cancel the alarm?'),
        content: const Text('The band will not buzz until you set an alarm again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l?.alarmCancelTheAlarm ?? 'Cancel the alarm',
                  style: TextStyle(color: P.of(ctx).on(C.red)))),
        ],
      ),
    );
    if (yes == true && c.mounted) {
      await _run(c, onCancel, l?.alarmCancelled ?? 'Alarm cancelled');
    }
  }

  /// The Fajr alarm group: on/off, the next Fajr and buzz time, the three
  /// numbers, the location the times are for, and a one-minute test.
  Widget _fajrGroup(BuildContext c, FajrAlarmSettings f) {
    final l = AppLocalizations.of(c);
    final prayer = fajrPrayer;
    final buzz = fajrNext;
    final when = buzz == null
        ? _fajrText('Fetching prayer times…')
        : calm(P.of(c), '${_whichDay(c, buzz, now ?? DateTime.now())} · '
            '${_fajrText('Fajr')} ${prayer == null ? '' : _hhmm(prayer)} → '
            '${_fajrText('buzz')} ${_hhmm(buzz)}');
    final where = switch (fajrSource) {
      'gps' => _fajrText('Your location'),
      'last' => _fajrText('Your last location'),
      'sharjah' => _fajrText('Sharjah (no location yet)'),
      _ => _fajrText('Not fetched yet'),
    };
    Future<void> set({bool? on, int? off, int? n, int? gap}) async {
      if (onSetFajr == null) return;
      await onSetFajr!(
          enabled: on, offsetMinutes: off, buzzCount: n, pauseSteps: gap);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      settingsGroup(c, _fajrText('Fajr alarm'), [
        SetRow(LucideIcons.sunrise, C.yellow, _fajrText('Fajr alarm'),
            value: f.enabled ? (l?.stateOn ?? 'On') : (l?.stateOff ?? 'Off'),
            chevron: false,
            badge: 'F',
            badgeOn: f.enabled,
            onTap: () => _run(c, () => set(on: !f.enabled),
                f.enabled
                    ? _fajrText('Fajr alarm off')
                    : _fajrText('Fajr alarm on — sent to the band'))),
        if (f.enabled) ...[
          SetRow(LucideIcons.alarmClock, C.green, _fajrText('Next'),
              value: when, chevron: false),
          SetRow(LucideIcons.clock, C.blue, _fajrText('Minutes after Fajr'),
              value: '${f.offsetMinutes} min',
              chevron: false,
              onTap: () => _pickNumber(
                  c,
                  _fajrText('Minutes after Fajr'),
                  const [0, 5, 10, 15, 20, 25, 30, 45, 60, 90, 120],
                  (m) => '$m min',
                  (m) => set(off: m))),
          SetRow(LucideIcons.vibrate, C.orange, _fajrText('Buzzes'),
              value: '${f.buzzCount}',
              chevron: false,
              onTap: () => _pickNumber(
                  c,
                  _fajrText('Buzzes'),
                  [for (var i = 1; i <= 10; i++) i, 15, 20],
                  (n) => '$n',
                  (n) => set(n: n))),
          SetRow(LucideIcons.timer, C.purple,
              _fajrText('Pause between buzzes'),
              value: _pauseLabel(f.pauseSteps),
              chevron: false,
              onTap: () => _pickNumber(
                  c,
                  _fajrText('Pause between buzzes'),
                  [for (var i = 1; i <= FajrAlarmSettings.maxPause; i++) i],
                  _pauseLabel,
                  (g) => set(gap: g))),
          SetRow(LucideIcons.mapPin, C.blue, _fajrText('Prayer times for'),
              value: where,
              chevron: false,
              onTap: () => _run(c, onRefreshFajr,
                  _fajrText('Prayer times updated'))),
        ],
      ]),
      if (f.enabled && connected) ...[
        const SizedBox(height: S.x3),
        BigButton(_fajrText('Test the Fajr buzz (in 1 minute)'),
            icon: LucideIcons.vibrate,
            color: C.yellow,
            soft: true,
            onTap: () => _run(c, onTestFajr,
                _fajrText('Test alarm set — the band buzzes in about a minute'))),
      ],
    ]);
  }

  /// The other four prayers: one switch each, the next buzz, and the two
  /// shared numbers (minutes after the adhan, buzzes).
  Widget _prayerGroup(BuildContext c, PrayerBuzzSettings s) {
    final ar = Localizations.localeOf(c).languageCode == 'ar';
    String t(String en, String arabic) => ar ? arabic : en;
    final next = prayerNext;
    Future<void> set({Prayer? toggle, int? off, int? n}) async {
      if (onSetPrayer == null) return;
      await onSetPrayer!(toggle: toggle, offsetMinutes: off, buzzCount: n);
    }

    return settingsGroup(c, t('Prayer buzzes', 'تنبيهات الصلاة'), [
      for (final pr in Prayer.values)
        SetRow(
          switch (pr) {
            Prayer.dhuhr => LucideIcons.sun,
            Prayer.asr => LucideIcons.sunMedium,
            Prayer.maghrib => LucideIcons.sunset,
            Prayer.isha => LucideIcons.moonStar,
          },
          switch (pr) {
            Prayer.dhuhr => C.yellow,
            Prayer.asr => C.orange,
            Prayer.maghrib => C.red,
            Prayer.isha => C.indigo,
          },
          pr.label(ar),
          sub: prayerToday[pr] == null ? '' : _hhmm(prayerToday[pr]!),
          chevron: false,
          badge: pr.api.substring(0, 1),
          badgeOn: s.isOn(pr),
          trailing: Switch.adaptive(
            value: s.isOn(pr),
            onChanged: onSetPrayer == null
                ? null
                : (on) => _run(
                    c,
                    () => set(toggle: pr),
                    on
                        ? t('${pr.api} buzz on', 'تم تفعيل تنبيه ${pr.arabic}')
                        : t('${pr.api} buzz off', 'تم إيقاف تنبيه ${pr.arabic}')),
          ),
          onTap: onSetPrayer == null
              ? null
              : () => _run(c, () => set(toggle: pr), null),
        ),
      if (s.anyOn) ...[
        SetRow(LucideIcons.alarmClock, C.green, t('Next', 'التالي'),
            value: next == null
                ? t('Fetching prayer times…', 'جارٍ جلب مواقيت الصلاة…')
                : '${next.prayer.label(ar)} · ${_hhmm(next.at)}',
            chevron: false),
        SetRow(LucideIcons.clock, C.blue,
            t('Minutes after the adhan', 'دقائق بعد الأذان'),
            value: '${s.offsetMinutes} ${t('min', 'د')}',
            chevron: false,
            onTap: () => _pickNumber(
                c,
                t('Minutes after the adhan', 'دقائق بعد الأذان'),
                const [0, 5, 10, 15, 20, 30, 45, 60],
                (m) => '$m ${t('min', 'د')}',
                (m) => set(off: m))),
        SetRow(LucideIcons.vibrate, C.orange, t('Buzzes', 'عدد الاهتزازات'),
            value: '${s.buzzCount}',
            chevron: false,
            onTap: () => _pickNumber(c, t('Buzzes', 'عدد الاهتزازات'),
                [for (var i = 1; i <= 10; i++) i], (n) => '$n',
                (n) => set(n: n))),
      ],
    ]);
  }

  /// A plain pick-one dialog for one of the Fajr numbers, then save it.
  Future<void> _pickNumber(
    BuildContext c,
    String title,
    List<int> options,
    String Function(int) label,
    Future<void> Function(int) save,
  ) async {
    final picked = await showDialog<int>(
      context: c,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final o in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, o),
              child: Text(label(o)),
            ),
        ],
      ),
    );
    if (picked == null || !c.mounted) return;
    await _run(c, () => save(picked),
        AppLocalizations.of(c)?.alarmSentToBand ?? 'Alarm sent to the band');
  }

  Future<void> _pickDayTime(BuildContext c, AlarmScheduleEntry day) async {
    final picked = await showAppTimePicker(
      context: c,
      initialTime: TimeOfDay(hour: day.hour, minute: day.minute),
    );
    if (picked == null || !c.mounted) return;
    await _run(
        c,
        () => onSetDayTime!(day.weekday, picked.hour, picked.minute),
        AppLocalizations.of(c)?.alarmSentToBand ?? 'Alarm sent to the band');
  }

  /// Off, or how many minutes before [day]'s wake time the band may buzz
  /// early once light sleep is detected. Capped at 45 min — the standard
  /// window size other wearables with this feature use — and [day]'s
  /// hour:minute NEVER changes: it stays the hard fallback, armed on the
  /// band exactly as before.
  Future<void> _pickSmartWindow(BuildContext c, AlarmScheduleEntry day) async {
    final picked = await showDialog<int>(
      context: c,
      builder: (ctx) => SimpleDialog(
        title: Text(uiText(ctx, 'Smart wake window')),
        children: [0, 15, 30, 45]
            .map(
              (m) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, m),
                child: Text(
                  m == 0
                      ? uiText(ctx, 'Off')
                      : AppLocalizations.of(
                              ctx,
                            )?.supplementSmartWindowMinutes(m) ??
                            '$m min before wake time',
                ),
              ),
            )
            .toList(),
      ),
    );
    if (picked == null || !c.mounted) return;
    await _run(
      c,
      () => onSetSmartWindow!(day.weekday, picked),
      picked == 0
          ? uiText(c, 'Smart wake off')
          : uiText(
              c,
              'Smart wake on — the band still buzzes at the wake time either way',
            ),
    );
  }

  /// Run a band/schedule write and report what happened. Every one of these
  /// throws when the band is not connected, and silence would read as success.
  /// A null [ok] reports only a failure (the day toggle's row already shows
  /// the change).
  static Future<void> _run(
      BuildContext c, Future<void> Function()? action, String? ok) async {
    if (action == null) return;
    try {
      await action();
      if (c.mounted && ok != null) _say(c, ok);
    } catch (e) {
      if (c.mounted) _say(c, '$e'.replaceFirst('Exception: ', ''));
    }
  }

  /// Replaces what this screen said before, shown or still queued, instead of
  /// stacking behind it: repeat taps would otherwise queue one 4-second
  /// snackbar each and keep an old result on screen long after it stopped
  /// being true. Only while this screen is on top — a result that lands after
  /// the user moved on must not wipe another screen's message.
  static void _say(BuildContext c, String msg) {
    final messenger = ScaffoldMessenger.of(c);
    if (ModalRoute.of(c)?.isCurrent ?? true) messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(msg)));
  }

  static String _hhmm(DateTime d) => _hhmmOf(d.hour, d.minute);

  static String _hhmmOf(int hour, int minute) => formatClock(hour, minute);

  /// "Tue 07:30" — the weekday plus the time, both from the ARMED instant
  /// (not merely from the schedule row), so this never claims a day the band
  /// hasn't actually latched yet.
  static String _dayAndTime(BuildContext c, DateTime at) =>
      '${weekdayShortName(at.weekday, AppLocalizations.of(c))} ${_hhmm(at)}';

  /// Short weekday label for a schedule row. [weekday] is the 0=Mon..6=Sun
  /// convention `AlarmScheduleEntry` uses; `weekdayShortName` wants
  /// `DateTime.weekday` (1=Mon..7=Sun), hence the `+ 1`.
  static String _weekdayLabel(BuildContext c, int weekday) =>
      weekdayShortName(weekday + 1, AppLocalizations.of(c));

  static String _whichDay(BuildContext c, DateTime d, DateTime now) {
    final l = AppLocalizations.of(c);
    final days = calendarDaysBetween(now, d);
    if (days < 0) {
      return l?.alarmInThePast ??
          'In the past — it has already fired or been missed';
    }
    if (days == 0) return l?.alarmLaterToday ?? 'Later today';
    if (days == 1) return l?.alarmTomorrow ?? 'Tomorrow';
    return l?.alarmInDays(days) ?? 'In $days days';
  }

  // Kept context-free and @visibleForTesting: the arm-state contract this
  // guards ("only `confirmed` may claim it") is tested without a widget tree.
  @visibleForTesting
  static String stateLabel(AlarmArmState s) => switch (s) {
        AlarmArmState.confirmed => 'Confirmed',
        AlarmArmState.pending => 'Waiting',
        AlarmArmState.unknown => 'Not confirmed',
        AlarmArmState.none => 'Not set',
      };

  static String _localizedStateLabel(BuildContext c, AlarmArmState s) {
    final l = AppLocalizations.of(c);
    return switch (s) {
      AlarmArmState.confirmed => l?.alarmStateConfirmed ?? 'Confirmed',
      AlarmArmState.pending => l?.alarmStateWaiting ?? 'Waiting',
      AlarmArmState.unknown => l?.alarmStateNotConfirmed ?? 'Not confirmed',
      AlarmArmState.none => l?.alarmStateNotSet ?? 'Not set',
    };
  }

  static Color _stateColor(AlarmArmState s) => switch (s) {
        AlarmArmState.confirmed => C.green,
        AlarmArmState.pending => C.blue,
        AlarmArmState.unknown => C.orange,
        AlarmArmState.none => C.blue,
      };

  static IconData _stateIcon(AlarmArmState s) => switch (s) {
        AlarmArmState.confirmed => LucideIcons.badgeCheck,
        AlarmArmState.pending => LucideIcons.loader,
        AlarmArmState.unknown => LucideIcons.circleHelp,
        AlarmArmState.none => LucideIcons.alarmClock,
      };

  static String _stateHeadline(BuildContext c, AlarmArmState s) {
    final l = AppLocalizations.of(c);
    return switch (s) {
      AlarmArmState.confirmed =>
        l?.alarmHeadlineConfirmed ?? 'The band has this alarm',
      AlarmArmState.pending =>
        l?.alarmHeadlinePending ?? 'Sent — waiting for the band to confirm',
      AlarmArmState.unknown =>
        l?.alarmHeadlineUnknown ?? 'We cannot tell whether this will fire',
      AlarmArmState.none => l?.alarmHeadlineNone ?? 'No alarm is set',
    };
  }

  static String? _stateDetail(BuildContext c, AlarmArmState s) {
    final l = AppLocalizations.of(c);
    return switch (s) {
      AlarmArmState.confirmed => l?.alarmDetailConfirmed ??
          'The band reported that it latched the alarm.',
      AlarmArmState.pending => l?.alarmDetailPending ??
          'The write reached the band. Its confirmation usually arrives within '
              'a few seconds.',
      AlarmArmState.unknown => l?.alarmDetailUnknown ??
          'This is the time the app last sent, but the band never confirmed it. Set it again while connected if you need to be sure.',
      AlarmArmState.none => null,
    };
  }
}
