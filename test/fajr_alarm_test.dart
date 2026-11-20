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
    test('defaults match the shortcut: 15 min, 3 buzzes, 5 s apart', () {
      const s = FajrAlarmSettings();
      expect(
          [s.enabled, s.offsetMinutes, s.buzzCount, s.gapSeconds],
          [false, 15, 3, 5]);
    });

    test('round-trip through SharedPreferences, clamped to range', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await const FajrAlarmSettings()
          .copyWith(enabled: true, offsetMinutes: 500, buzzCount: 0, gapSeconds: 99)
          .save(prefs);
      final s = FajrAlarmSettings.load(prefs);
      expect([s.enabled, s.offsetMinutes, s.buzzCount, s.gapSeconds],
          [true, 120, 1, 8]);
    });
  });

  group('buzz pattern', () {
    test('is always the 12 bytes the strap expects', () {
      for (var n = 1; n <= 20; n++) {
        for (var g = 0; g <= 8; g++) {
          expect(fajrHapticPattern(buzzCount: n, gapSeconds: g).length, 12);
        }
      }
    });

    test('3 buzzes 5 s apart: effect 47, 5 s of pauses, loop 3', () {
      final p = fajrHapticPattern(buzzCount: 3, gapSeconds: 5);
      expect(p[0], 47);
      final pauseMs = [
        for (final b in p.sublist(1, 8))
          if (b & 0x80 != 0) (b & 0x7f) * 10
      ].fold<int>(0, (a, b) => a + b);
      expect(pauseMs, 5000);
      expect(p.sublist(8, 10), [0, 0]);
      expect(p[10], 3, reason: 'overall loop = buzz count');
      expect(p[11], greaterThanOrEqualTo(3 * 5));
    });

    test('no gap keeps the stock 240 ms pause', () {
      expect(fajrHapticPattern(buzzCount: 7, gapSeconds: 0).sublist(0, 2),
          AlarmPayloads.defaultHaptics.sublist(0, 2));
    });

    test('the longest gap still fits the seven pause slots', () {
      final p = fajrHapticPattern(buzzCount: 1, gapSeconds: 8);
      final pauseMs = [
        for (final b in p.sublist(1, 8))
          if (b & 0x80 != 0) (b & 0x7f) * 10
      ].fold<int>(0, (a, b) => a + b);
      expect(pauseMs, 8000);
    });
  });

  group('arming the strap', () {
    final cache = FajrTimes.parseCalendar(_fixture());
    const on = FajrAlarmSettings(enabled: true);
    final now = DateTime.utc(2026, 11, 20, 0, 0); // 04:00 Dubai
    final plan = (
      next: nextFajrAlarm(cache, on, now),
      haptics: fajrHapticPattern(buzzCount: 3, gapSeconds: 5),
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
