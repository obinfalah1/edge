import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/state/alarm_schedule.dart';
import 'package:openstrap_edge/state/band_timer.dart';
import 'package:openstrap_edge/state/fajr_alarm.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart' as proto;
import 'package:shared_preferences/shared_preferences.dart';

/// SET_ALARM_TIME bodies a fake WHOOP 5 received.
List<List<int>> _installGen5(BleEngine engine) {
  final sets = <List<int>>[];
  engine.debugInstallFakeLink(
    band: proto.BandProfile.gen5,
    onWrite: (frame) async {
      final inner = proto
          .parseFrame(frame, profile: proto.BandProfile.gen5)
          ?.inner;
      if (inner != null &&
          inner.length > 3 &&
          inner[2] == proto.Cmd.setAlarmTime) {
        sets.add(inner.sublist(3));
      }
      return true;
    },
  );
  return sets;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 11, 20, 0, 0); // 04:00 Dubai
  final fajrCache = FajrTimes.parseCalendar(
    File('test/fixtures/aladhan_sharjah_2026_11.json').readAsStringSync(),
  );
  // Fajr 05:18 + 15 = 05:33 Dubai.
  final fajr = (
    next: nextFajrAlarm(fajrCache, const FajrAlarmSettings(enabled: true), now),
    haptics: fajrHapticPattern(buzzCount: 3, pauseSteps: 7),
  );
  BleEngine engine() =>
      BleEngine(onRecord: (_, _) async {}, onState: (_) {}, log: (_) {});

  Future<SharedPreferences> prefs() async {
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }

  test('start: whole seconds, clamped, own buzz count', () async {
    final p = await prefs();
    final at = await BandTimer.start(
      p,
      const Duration(minutes: 20),
      buzzes: 5,
      now: now,
    );
    expect(at.toUtc(), DateTime.utc(2026, 11, 20, 0, 20));
    expect(BandTimer.pending(p, now), at);
    expect(BandTimer.buzzCount(p), 5);
    expect(BandTimer.pending(p, at), isNull, reason: 'over once it is due');
    expect(
      (await BandTimer.start(p, Duration.zero, now: now)).difference(now),
      BandTimer.shortest,
    );
    expect(
      (await BandTimer.start(
        p,
        const Duration(days: 3),
        now: now,
      )).difference(now),
      BandTimer.longest,
    );
    await BandTimer.cancel(p);
    expect(BandTimer.pending(p, now), isNull);
  });

  test('pattern: only the waveform values the band takes', () {
    for (var n = 1; n <= BandTimer.maxCount; n++) {
      final h = BandTimer.haptics(n);
      expect(h.length, 12);
      expect(h.sublist(0, 8).every({47, 152}.contains), isTrue);
      expect(h[10], n);
      expect(h[11], greaterThanOrEqualTo(30));
    }
  });

  test(
    'a timer due before Fajr borrows the slot with its own buzz count',
    () async {
      final p = await prefs();
      await BandTimer.start(
        p,
        const Duration(minutes: 20),
        buzzes: 6,
        now: now,
      );
      final e = engine();
      final sets = _installGen5(e);
      final r = await armNextScheduledOccurrence(
        engine: e,
        schedule: const [],
        currentArmedEpoch: fajr.next!.millisecondsSinceEpoch ~/ 1000,
        now: now,
        fajr: fajr,
        timer: loadBandTimerPlan(p, now),
      );
      expect(r.epoch, now.millisecondsSinceEpoch ~/ 1000 + 20 * 60);
      expect(sets.single.sublist(8, 20), BandTimer.haptics(6));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'after the timer, Fajr goes back on unchanged',
    () async {
      final p = await prefs();
      final timerAt = await BandTimer.start(
        p,
        const Duration(minutes: 20),
        now: now,
      );
      final after = timerAt.add(const Duration(seconds: 1));
      final e = engine();
      final sets = _installGen5(e);
      final r = await armNextScheduledOccurrence(
        engine: e,
        schedule: const [],
        currentArmedEpoch: null,
        now: after,
        fajr: fajr,
        timer: loadBandTimerPlan(p, after),
      );
      expect(r.epoch, fajr.next!.millisecondsSinceEpoch ~/ 1000);
      expect(sets.single.sublist(8, 20), fajr.haptics);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('a timer due after Fajr waits; Fajr keeps the slot', () async {
    final p = await prefs();
    await BandTimer.start(p, const Duration(hours: 3), now: now); // 07:00
    final e = engine();
    final sets = _installGen5(e);
    final r = await armNextScheduledOccurrence(
      engine: e,
      schedule: const [],
      currentArmedEpoch: fajr.next!.millisecondsSinceEpoch ~/ 1000,
      now: now,
      fajr: fajr,
      timer: loadBandTimerPlan(p, now),
    );
    expect(r.epoch, isNull, reason: 'Fajr is already armed; nothing written');
    expect(sets, isEmpty);
  });

  test(
    'stopping a timer with nothing else set clears the band',
    () async {
      final p = await prefs();
      final at = await BandTimer.start(p, const Duration(minutes: 5), now: now);
      await BandTimer.cancel(p);
      final e = engine();
      _installGen5(e);
      final r = await armNextScheduledOccurrence(
        engine: e,
        schedule: const [],
        currentArmedEpoch: at.millisecondsSinceEpoch ~/ 1000,
        now: now,
        timer: loadBandTimerPlan(p, now),
      );
      expect(r.disabled, isTrue);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
