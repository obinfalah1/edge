import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/ble/ble_state.dart' show AlarmPayloads;
import 'package:openstrap_edge/state/alarm_schedule.dart';
import 'package:openstrap_edge/state/fajr_alarm.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart' as proto;
import 'package:shared_preferences/shared_preferences.dart';

/// A real AlAdhan /v1/calendar response: Sharjah (Al Majaz), November 2026,
/// method 16, iso8601=true.
String _fixture() =>
    File('test/fixtures/aladhan_sharjah_2026_11.json').readAsStringSync();

/// Official awqaf.gov.ae Sharjah (Al Majaz) Fajr, November 2026.
const _awqafNov2026 = [
  '05:07', '05:08', '05:08', '05:09', '05:10', '05:10', '05:11', '05:11',
  '05:12', '05:12', '05:13', '05:13', '05:14', '05:15', '05:15', '05:16',
  '05:16', '05:17', '05:18', '05:18', '05:19', '05:19', '05:20', '05:21',
  '05:21', '05:22', '05:22', '05:23', '05:24', '05:24',
];

/// SET_ALARM_TIME bodies a fake WHOOP 5 received.
List<List<int>> _installGen5(BleEngine engine, {bool accept = true}) {
  final sets = <List<int>>[];
  engine.debugInstallFakeLink(
    band: proto.BandProfile.gen5,
    onWrite: (frame) async {
      final parsed = proto.parseFrame(frame, profile: proto.BandProfile.gen5);
      final inner = parsed?.inner;
      if (inner != null &&
          inner.length > 3 &&
          inner[2] == proto.Cmd.setAlarmTime) {
        sets.add(inner.sublist(3));
        return accept;
      }
      return true;
    },
  );
  return sets;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AlAdhan calendar parsing', () {
    test('reads every day as an exact instant in Asia/Dubai', () {
      final days = FajrTimes.parseCalendar(_fixture());
      expect(days.length, 30);
      final nov20 =
          DateTime.fromMillisecondsSinceEpoch(days['2026-11-20']! * 1000)
              .toUtc();
      // 05:18 +04:00 == 01:18 UTC, whatever zone the test machine is in.
      expect(nov20, DateTime.utc(2026, 11, 20, 1, 18));
    });

    test('matches the official awqaf.gov.ae Sharjah table within 1 minute',
        () {
      final days = FajrTimes.parseCalendar(_fixture());
      var exact = 0;
      for (var d = 1; d <= 30; d++) {
        final key = '2026-11-${d.toString().padLeft(2, '0')}';
        final utc =
            DateTime.fromMillisecondsSinceEpoch(days[key]! * 1000).toUtc();
        final dubai = utc.add(const Duration(hours: 4));
        final p = _awqafNov2026[d - 1].split(':');
        final official = int.parse(p[0]) * 60 + int.parse(p[1]);
        final api = dubai.hour * 60 + dubai.minute;
        expect((api - official).abs(), lessThanOrEqualTo(1), reason: key);
        if (api == official) exact++;
      }
      expect(exact, greaterThanOrEqualTo(25));
    });

    test('a broken body yields nothing instead of throwing', () {
      expect(FajrTimes.parseCalendar('{"code":500}'), isEmpty);
      expect(FajrTimes.parseCalendar('{"data":[{"x":1}]}'), isEmpty);
    });
  });

  group('next Fajr alarm', () {
    final cache = FajrTimes.parseCalendar(_fixture());
    const on = FajrAlarmSettings(enabled: true, offsetMinutes: 15);

    test('is Fajr + offset of the same morning before it passes', () {
      final now = DateTime.utc(2026, 11, 20, 0, 0); // 04:00 Dubai
      expect(nextFajrAlarm(cache, on, now)!.toUtc(),
          DateTime.utc(2026, 11, 20, 1, 33)); // 05:33 Dubai
    });

    test('rolls to the next morning once it has passed', () {
      final now = DateTime.utc(2026, 11, 20, 1, 33); // exactly 05:33
      expect(nextFajrAlarm(cache, on, now)!.toUtc(),
          DateTime.utc(2026, 11, 21, 1, 34)); // 21st: 05:19 + 15
    });

    test('follows the offset setting', () {
      final now = DateTime.utc(2026, 11, 20, 0, 0);
      expect(
          nextFajrAlarm(cache, on.copyWith(offsetMinutes: 0), now)!.toUtc(),
          DateTime.utc(2026, 11, 20, 1, 18));
    });

    test('is null when switched off or nothing is cached', () {
      final now = DateTime.utc(2026, 11, 20);
      expect(nextFajrAlarm(cache, const FajrAlarmSettings(), now), isNull);
      expect(nextFajrAlarm(const {}, on, now), isNull);
    });
  });

  group('settings', () {
    test('a pending test buzz holds automatic re-arms until it has rung',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime(2026, 11, 25, 10, 49, 21);
      expect(fajrTestPending(prefs, now), isFalse);
      await holdForFajrTest(
          prefs, now.add(const Duration(minutes: 1) + kAlarmRingHold));
      // 36 s later the app went to the background and re-armed (the bug).
      expect(fajrTestPending(prefs, now.add(const Duration(seconds: 36))),
          isTrue);
      expect(fajrTestPending(prefs, now.add(const Duration(minutes: 3))),
          isFalse);
    });

    test('defaults: 15 min after Fajr, 3 buzzes, longest pause', () {
      const s = FajrAlarmSettings();
      expect([s.enabled, s.offsetMinutes, s.buzzCount, s.pauseSteps],
          [false, 15, 3, 7]);
    });

    test('round-trip through SharedPreferences, clamped to range', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await const FajrAlarmSettings()
          .copyWith(
              enabled: true, offsetMinutes: 500, buzzCount: 0, pauseSteps: 99)
          .save(prefs);
      final s = FajrAlarmSettings.load(prefs);
      expect([s.enabled, s.offsetMinutes, s.buzzCount, s.pauseSteps],
          [true, 120, 1, 7]);
    });
  });

  group('buzz pattern', () {
    // A WHOOP 5 answered invalid_waveform_effect to other pause values; the
    // only waveform values it is known to take are the stock alarm's.
    const accepted = {47, 152, 0};

    test('is 12 bytes and uses only waveform values the band accepts', () {
      for (var n = 1; n <= FajrAlarmSettings.maxCount; n++) {
        for (var g = 1; g <= FajrAlarmSettings.maxPause; g++) {
          final p = fajrHapticPattern(buzzCount: n, pauseSteps: g);
          expect(p.length, 12);
          expect(p.sublist(0, 8).every(accepted.contains), isTrue,
              reason: '$p');
          expect(p[11], greaterThanOrEqualTo(30), reason: 'stock duration');
        }
      }
    });

    test('3 buzzes, 7 pause steps: 47 then seven 152s, loop 3', () {
      final p = fajrHapticPattern(buzzCount: 3, pauseSteps: 7);
      expect(p.sublist(0, 8), [47, 152, 152, 152, 152, 152, 152, 152]);
      expect(p.sublist(8, 10), [0, 0]);
      expect(p[10], 3, reason: 'overall loop = buzz count');
      expect(p[11], 30);
    });

    test('one pause step is exactly the stock pattern but for the loop', () {
      final p = fajrHapticPattern(buzzCount: 7, pauseSteps: 1);
      expect(p, AlarmPayloads.defaultHaptics);
    });
  });

  group('arming the strap', () {
    final cache = FajrTimes.parseCalendar(_fixture());
    const on = FajrAlarmSettings(enabled: true);
    final now = DateTime.utc(2026, 11, 20, 0, 0); // 04:00 Dubai
    final plan = (
      next: nextFajrAlarm(cache, on, now),
      haptics: fajrHapticPattern(buzzCount: 3, pauseSteps: 7),
    );
    List<AlarmScheduleEntry> weekly({required bool enabled}) => [
          for (var w = 0; w < 7; w++)
            AlarmScheduleEntry(
                weekday: w, hour: 7, minute: 0, enabled: enabled),
        ];

    BleEngine engine() =>
        BleEngine(onRecord: (_, _) async {}, onState: (_) {}, log: (_) {});

    test('Fajr wins when it comes first, with the custom pattern', () async {
      final e = engine();
      final sets = _installGen5(e);
      final r = await armNextScheduledOccurrence(
        engine: e,
        schedule: weekly(enabled: true),
        currentArmedEpoch: null,
        now: now,
        fajr: plan,
      );
      expect(r.failed, isFalse);
      expect(r.epoch, plan.next!.millisecondsSinceEpoch ~/ 1000);
      expect(sets, hasLength(1));
      // rich gen5 body: [0x04][idx][u32 sec][u16 subsec][12 haptics][crescendo]
      expect(sets.single.sublist(8, 20), plan.haptics);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('the weekly alarm wins when it comes first, stock pattern', () async {
      final e = engine();
      final sets = _installGen5(e);
      final early = DateTime.utc(2026, 11, 20, 0, 0).toLocal();
      final r = await armNextScheduledOccurrence(
        engine: e,
        schedule: [
          for (var w = 0; w < 7; w++)
            AlarmScheduleEntry(
                weekday: w,
                hour: early.add(const Duration(minutes: 10)).hour,
                minute: early.add(const Duration(minutes: 10)).minute),
        ],
        currentArmedEpoch: null,
        now: early,
        fajr: plan,
      );
      expect(r.failed, isFalse);
      expect(r.epoch, isNot(plan.next!.millisecondsSinceEpoch ~/ 1000));
      expect(sets.single.sublist(8, 20), AlarmPayloads.defaultHaptics);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('Fajr alone arms the band with nothing on the weekly schedule',
        () async {
      final e = engine();
      final sets = _installGen5(e);
      final r = await armNextScheduledOccurrence(
        engine: e,
        schedule: weekly(enabled: false),
        currentArmedEpoch: null,
        now: now,
        fajr: plan,
      );
      expect(r.epoch, plan.next!.millisecondsSinceEpoch ~/ 1000);
      expect(sets, hasLength(1));
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a refused custom pattern is retried with the stock one', () async {
      final e = engine();
      final sets = _installGen5(e, accept: false);
      final r = await armNextScheduledOccurrence(
        engine: e,
        schedule: weekly(enabled: false),
        currentArmedEpoch: null,
        now: now,
        fajr: plan,
      );
      expect(r.failed, isTrue, reason: 'this fake band takes nothing');
      expect(sets, hasLength(2));
      expect(sets[0].sublist(8, 20), plan.haptics);
      expect(sets[1].sublist(8, 20), AlarmPayloads.defaultHaptics);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('a refused long buzz falls back to the own buzzes, then the stock',
        () async {
      final e = engine();
      final sets = _installGen5(e, accept: false);
      final long = (next: plan.next, haptics: fajrLongPattern());
      final own = fajrHapticPattern(buzzCount: 7, pauseSteps: 7);
      await armNextScheduledOccurrence(
        engine: e,
        schedule: weekly(enabled: false),
        currentArmedEpoch: null,
        now: now,
        fajr: long,
        fajrFallback: own,
      );
      expect(sets, hasLength(3));
      expect(sets[0].sublist(8, 20), fajrLongPattern());
      expect(sets[1].sublist(8, 20), own);
      expect(sets[2].sublist(8, 20), AlarmPayloads.defaultHaptics);
    }, timeout: const Timeout(Duration(seconds: 90)));

    test('an unchanged arm is not rewritten', () async {
      final e = engine();
      final sets = _installGen5(e);
      final r = await armNextScheduledOccurrence(
        engine: e,
        schedule: weekly(enabled: false),
        currentArmedEpoch: plan.next!.millisecondsSinceEpoch ~/ 1000,
        now: now,
        fajr: plan,
      );
      expect(r.epoch, isNull);
      expect(sets, isEmpty);
    });
  });

  group('long buzz and repeats', () {
    test('the long pattern uses only accepted values, 42 buzzes, 7 loops', () {
      final p = fajrLongPattern();
      expect(p, hasLength(12));
      expect(p.sublist(0, 8).every((v) => v == 47 || v == 152), isTrue);
      expect(p.sublist(0, 8).where((v) => v == 47).length * p[10], 42);
      expect(p[10], 7);
    });

    test('an ignored Fajr buzz repeats twice, then stops', () async {
      final fajr = DateTime(2026, 11, 25, 5, 21);
      final fired = fajr.add(const Duration(minutes: 15));
      final firedSec = fired.millisecondsSinceEpoch ~/ 1000;
      SharedPreferences.setMockInitialValues({
        'fajr_alarm_enabled': true,
        'fajr_alarm_cache_v1':
            '{"2026-11-25": ${fajr.millisecondsSinceEpoch ~/ 1000}}',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(FajrAlarmSettings.load(prefs).longBuzz, isTrue);
      expect(loadFajrPlan(prefs, fired).haptics, fajrLongPattern());

      // 1st repeat: 2 minutes after the alarm.
      var now = fired.add(const Duration(seconds: 60));
      await noteFajrAlarmFired(prefs,
          firedEpoch: firedSec, dismissed: false, now: now);
      final r1 = loadFajrPlan(prefs, now).next!;
      expect(r1, fired.add(const Duration(minutes: 2)));

      // The phone only woke 3 minutes after the 1st repeat: 45 s from then.
      now = r1.add(const Duration(minutes: 3));
      await noteFajrAlarmFired(prefs,
          firedEpoch: r1.millisecondsSinceEpoch ~/ 1000,
          dismissed: false,
          now: now);
      final r2 = loadFajrPlan(prefs, now).next!;
      expect(r2, now.add(const Duration(seconds: 45)));

      // After the 2nd repeat there is no third.
      now = r2.add(const Duration(seconds: 60));
      await noteFajrAlarmFired(prefs,
          firedEpoch: r2.millisecondsSinceEpoch ~/ 1000,
          dismissed: false,
          now: now);
      expect(loadFajrPlan(prefs, now).next, isNull);
    });

    test('a double tap, a test buzz or the switch off cancels repeats',
        () async {
      final fajr = DateTime(2026, 11, 25, 5, 21);
      final fired = fajr.add(const Duration(minutes: 15));
      final firedSec = fired.millisecondsSinceEpoch ~/ 1000;
      final now = fired.add(const Duration(seconds: 60));
      SharedPreferences.setMockInitialValues({
        'fajr_alarm_enabled': true,
        'fajr_alarm_cache_v1':
            '{"2026-11-25": ${fajr.millisecondsSinceEpoch ~/ 1000}}',
      });
      final prefs = await SharedPreferences.getInstance();
      await noteFajrAlarmFired(prefs,
          firedEpoch: firedSec, dismissed: true, now: now);
      expect(loadFajrPlan(prefs, now).next, isNull);
      // Some other alarm (a test, the weekly one) is not the Fajr buzz.
      await noteFajrAlarmFired(prefs,
          firedEpoch: firedSec + 3600, dismissed: false, now: now);
      expect(loadFajrPlan(prefs, now).next, isNull);
    });
  });

  test('a weekday smart-wake window does not attach to a Fajr arm', () {
    final fajrAt = DateTime(2026, 11, 20, 5, 33);
    final schedule = [
      for (var w = 0; w < 7; w++)
        AlarmScheduleEntry(
            weekday: w, hour: 7, minute: 0, smartWindowMinutes: 30),
    ];
    expect(
        armedSmartWakeWindow(
            epoch: fajrAt.millisecondsSinceEpoch ~/ 1000, schedule: schedule),
        isNull);
    final weeklyAt = DateTime(2026, 11, 20, 7, 0);
    expect(
        armedSmartWakeWindow(
                epoch: weeklyAt.millisecondsSinceEpoch ~/ 1000,
                schedule: schedule)!
            .minutes,
        30);
  });
}
