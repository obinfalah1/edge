import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/state/alarm_schedule.dart';
import 'package:openstrap_edge/state/fajr_alarm.dart';
import 'package:openstrap_edge/state/prayer_buzz.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart' as proto;
import 'package:shared_preferences/shared_preferences.dart';

List<List<int>> _installGen5(BleEngine engine) {
  final sets = <List<int>>[];
  engine.debugInstallFakeLink(
    band: proto.BandProfile.gen5,
    onWrite: (frame) async {
      final inner =
          proto.parseFrame(frame, profile: proto.BandProfile.gen5)?.inner;
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
  final body =
      File('test/fixtures/aladhan_sharjah_2026_11.json').readAsStringSync();
  final cache = PrayerTimes.parseCalendar(body);
  final fajrCache = FajrTimes.parseCalendar(body);
  DateTime dubai(int h, int m) =>
      DateTime.utc(2026, 11, 20, h - 4, m); // +04:00
  BleEngine engine() =>
      BleEngine(onRecord: (_, _) async {}, onState: (_) {}, log: (_) {});

  test('parses all four prayers per day', () {
    final day = cache['2026-11-20']!;
    expect(day.keys.toSet(), {'dhuhr', 'asr', 'maghrib', 'isha'});
    expect(DateTime.fromMillisecondsSinceEpoch(day['asr']! * 1000).toUtc(),
        dubai(15, 9));
  });

  test('each prayer has its own switch; next is the earliest one on', () {
    const none = PrayerBuzzSettings();
    expect(nextPrayerBuzz(cache, none, dubai(10, 0)), isNull);
    final asrOnly = none.toggle(Prayer.asr);
    final n = nextPrayerBuzz(cache, asrOnly, dubai(10, 0))!;
    expect(n.prayer, Prayer.asr);
    expect(n.at.toUtc(), dubai(15, 9));
    // Dhuhr off is skipped even though it comes first.
    final both = asrOnly.toggle(Prayer.isha).copyWith(offsetMinutes: 5);
    final after = nextPrayerBuzz(cache, both, dubai(15, 20))!;
    expect(after.prayer, Prayer.isha);
    expect(after.at.toUtc(), dubai(18, 55));
    // Switching off removes it again.
    expect(both.toggle(Prayer.isha).isOn(Prayer.isha), isFalse);
  });

  test('settings round-trip through prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    final s = const PrayerBuzzSettings()
        .toggle(Prayer.maghrib)
        .copyWith(offsetMinutes: 10, buzzCount: 4);
    await s.save(p);
    expect(PrayerBuzzSettings.load(p), s);
  });

  test(
    'Fajr is untouched: prayers only take the slot when they come first',
    () async {
      final fajrSettings = const FajrAlarmSettings(enabled: true);
      final atNight = dubai(20, 0); // after Isha → tomorrow's Fajr first
      final fajr = (
        next: nextFajrAlarm(fajrCache, fajrSettings, atNight),
        haptics: fajrHapticPattern(buzzCount: 3, pauseSteps: 7),
      );
      final s = const PrayerBuzzSettings().toggle(Prayer.dhuhr);
      final prayers = (
        next: nextPrayerBuzz(cache, s, atNight)?.at,
        haptics: fajrHapticPattern(buzzCount: 2, pauseSteps: 7),
      );
      var e = engine();
      var sets = _installGen5(e);
      var r = await armNextScheduledOccurrence(
        engine: e,
        schedule: const [],
        currentArmedEpoch: null,
        now: atNight,
        fajr: fajr,
        prayers: prayers,
      );
      expect(r.epoch, fajr.next!.millisecondsSinceEpoch ~/ 1000);
      expect(sets.single.sublist(8, 20), fajr.haptics);

      // Mid-morning: Dhuhr comes before tomorrow's Fajr.
      final morning = dubai(9, 0);
      e = engine();
      sets = _installGen5(e);
      r = await armNextScheduledOccurrence(
        engine: e,
        schedule: const [],
        currentArmedEpoch: null,
        now: morning,
        fajr: (
          next: nextFajrAlarm(fajrCache, fajrSettings, morning),
          haptics: fajr.haptics,
        ),
        prayers: (
          next: nextPrayerBuzz(cache, s, morning)?.at,
          haptics: prayers.haptics,
        ),
      );
      expect(r.epoch, dubai(12, 7).millisecondsSinceEpoch ~/ 1000);
      expect(sets.single.sublist(8, 20), prayers.haptics);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
