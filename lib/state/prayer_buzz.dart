// Prayer buzzes: the band buzzes at Dhuhr, Asr, Maghrib and Isha (+ N min).
//
// Separate from the Fajr alarm (fajr_alarm.dart), which is untouched: Fajr
// keeps its own switch, numbers and cache. This module supplies "the next
// enabled prayer + offset" as one more source for the strap's single alarm
// slot; whichever source comes first is armed (see
// [armNextScheduledOccurrence]). After a buzz fires, the normal re-arm on the
// strap's fired event / next sync moves the slot to the next prayer.
//
// Times come from the same AlAdhan calendar as Fajr (method 16, UAE), at the
// phone's location, cached two months at a time so a headless background
// re-arm never needs the network.

import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'fajr_alarm.dart'
    show FajrTimes, fajrHapticPattern, kFajrFallbackLat, kFajrFallbackLon, kFajrMethod;

/// The four prayers after Fajr, in day order. [api] is AlAdhan's timing key.
enum Prayer {
  dhuhr('Dhuhr', 'الظهر', 'prayer_buzz_on_dhuhr'),
  asr('Asr', 'العصر', 'prayer_buzz_on_asr'),
  maghrib('Maghrib', 'المغرب', 'prayer_buzz_on_maghrib'),
  isha('Isha', 'العشاء', 'prayer_buzz_on_isha');

  const Prayer(this.api, this.arabic, this.prefKey);
  final String api;
  final String arabic;

  /// The pref holding this prayer's switch.
  final String prefKey;

  String label(bool arabicUi) => arabicUi ? arabic : api;
}

const String _kOffset = 'prayer_buzz_offset_min';
const String _kCount = 'prayer_buzz_count';
const String _kCache = 'prayer_buzz_cache_v1';
const String _kFetchedAt = 'prayer_buzz_fetched_at_ms';

/// Every pref key this module owns (for the backup registry).
const List<String> kPrayerBuzzPrefKeys = [
  'prayer_buzz_on_dhuhr',
  'prayer_buzz_on_asr',
  'prayer_buzz_on_maghrib',
  'prayer_buzz_on_isha',
  _kOffset,
  _kCount,
];

/// Cache keys: device-local, re-fetched, never backed up.
const List<String> kPrayerBuzzCacheKeys = [_kCache, _kFetchedAt];

class PrayerBuzzSettings {
  final Set<Prayer> enabled;

  /// Minutes after the adhan the band buzzes (0..60).
  final int offsetMinutes;

  /// How many buzzes (1..20).
  final int buzzCount;

  const PrayerBuzzSettings({
    this.enabled = const {},
    this.offsetMinutes = 0,
    this.buzzCount = 2,
  });

  static const int maxOffset = 60;
  static const int maxCount = 20;

  bool get anyOn => enabled.isNotEmpty;
  bool isOn(Prayer p) => enabled.contains(p);

  PrayerBuzzSettings copyWith({
    Set<Prayer>? enabled,
    int? offsetMinutes,
    int? buzzCount,
  }) =>
      PrayerBuzzSettings(
        enabled: enabled ?? this.enabled,
        offsetMinutes:
            (offsetMinutes ?? this.offsetMinutes).clamp(0, maxOffset),
        buzzCount: (buzzCount ?? this.buzzCount).clamp(1, maxCount),
      );

  PrayerBuzzSettings toggle(Prayer p) => copyWith(
      enabled: isOn(p) ? ({...enabled}..remove(p)) : {...enabled, p});

  static PrayerBuzzSettings load(SharedPreferences prefs) =>
      const PrayerBuzzSettings().copyWith(
        enabled: {
          for (final p in Prayer.values)
            if (prefs.getBool(p.prefKey) ?? false) p,
        },
        offsetMinutes: prefs.getInt(_kOffset),
        buzzCount: prefs.getInt(_kCount),
      );

  Future<void> save(SharedPreferences prefs) async {
    for (final p in Prayer.values) {
      await prefs.setBool(p.prefKey, isOn(p));
    }
    await prefs.setInt(_kOffset, offsetMinutes);
    await prefs.setInt(_kCount, buzzCount);
  }

  @override
  bool operator ==(Object other) =>
      other is PrayerBuzzSettings &&
      other.enabled.length == enabled.length &&
      other.enabled.containsAll(enabled) &&
      other.offsetMinutes == offsetMinutes &&
      other.buzzCount == buzzCount;

  @override
  int get hashCode => Object.hash(
      Object.hashAllUnordered(enabled), offsetMinutes, buzzCount);
}

/// Cached prayer instants: `yyyy-MM-dd` → prayer name → unix seconds.
class PrayerTimes {
  PrayerTimes._();

  static Map<String, Map<String, int>> readCache(SharedPreferences prefs) {
    final raw = prefs.getString(_kCache);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in m.entries)
          e.key: {
            for (final t in (e.value as Map<String, dynamic>).entries)
              t.key: (t.value as num).toInt(),
          },
      };
    } catch (_) {
      return {};
    }
  }

  static DateTime? lastFetched(SharedPreferences prefs) {
    final ms = prefs.getInt(_kFetchedAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static bool needsRefresh(SharedPreferences prefs, DateTime now,
      {int aheadDays = 10}) {
    final cache = readCache(prefs);
    for (var i = 0; i <= aheadDays; i++) {
      final k =
          FajrTimes.dayKey(DateTime(now.year, now.month, now.day + i));
      if (!cache.containsKey(k)) return true;
    }
    final f = lastFetched(prefs);
    return f == null || now.difference(f) > const Duration(days: 7);
  }

  /// GPS (foreground only), else the location the Fajr alarm last used,
  /// else Sharjah.
  static Future<({double lat, double lon})> _coordinates(
      SharedPreferences prefs,
      {required bool useGps, bool askPermission = false}) async {
    if (useGps) {
      try {
        if (await Geolocator.isLocationServiceEnabled()) {
          var perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.denied && askPermission) {
            perm = await Geolocator.requestPermission();
          }
          if (perm == LocationPermission.whileInUse ||
              perm == LocationPermission.always) {
            final pos = await Geolocator.getLastKnownPosition() ??
                await Geolocator.getCurrentPosition(
                  locationSettings: const LocationSettings(
                    accuracy: LocationAccuracy.low,
                    timeLimit: Duration(seconds: 10),
                  ),
                );
            return (lat: pos.latitude, lon: pos.longitude);
          }
        }
      } catch (_) {}
    }
    final stored = FajrTimes.coords(prefs)?.split(',');
    if (stored != null && stored.length == 2) {
      final lat = double.tryParse(stored[0]);
      final lon = double.tryParse(stored[1]);
      if (lat != null && lon != null) return (lat: lat, lon: lon);
    }
    return (lat: kFajrFallbackLat, lon: kFajrFallbackLon);
  }

  /// Fetch this month and next and merge into the cache. Never throws.
  static Future<bool> refresh(
    SharedPreferences prefs, {
    bool useGps = false,
    bool askPermission = false,
    DateTime? now,
    http.Client? client,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final at = now ?? DateTime.now();
    final c = await _coordinates(prefs,
        useGps: useGps, askPermission: askPermission);
    final http.Client cl = client ?? http.Client();
    final fresh = <String, Map<String, int>>{};
    try {
      for (final month in [
        DateTime(at.year, at.month),
        DateTime(at.year, at.month + 1),
      ]) {
        final uri = Uri.https('api.aladhan.com',
            '/v1/calendar/${month.year}/${month.month}', {
          'latitude': c.lat.toStringAsFixed(4),
          'longitude': c.lon.toStringAsFixed(4),
          'method': '$kFajrMethod',
          'iso8601': 'true',
        });
        try {
          final res = await cl.get(uri).timeout(timeout);
          if (res.statusCode != 200) continue;
          fresh.addAll(parseCalendar(res.body));
        } catch (_) {}
      }
    } finally {
      if (client == null) cl.close();
    }
    if (fresh.isEmpty) return false;
    final merged = {...readCache(prefs), ...fresh};
    final keepFrom =
        FajrTimes.dayKey(DateTime(at.year, at.month, at.day - 2));
    merged.removeWhere((k, _) => k.compareTo(keepFrom) < 0);
    await prefs.setString(_kCache, jsonEncode(merged));
    await prefs.setInt(_kFetchedAt, at.millisecondsSinceEpoch);
    return true;
  }

  /// AlAdhan `/v1/calendar` (iso8601) → day → prayer → unix seconds.
  static Map<String, Map<String, int>> parseCalendar(String body) {
    final out = <String, Map<String, int>>{};
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['data'] is! List) return out;
    for (final day in decoded['data'] as List) {
      try {
        final g = day['date']['gregorian']['date'] as String; // dd-MM-yyyy
        final p = g.split('-');
        final times = <String, int>{};
        for (final prayer in Prayer.values) {
          final raw = day['timings'][prayer.api];
          if (raw is! String) continue;
          final t = DateTime.parse(raw.split(' ').first);
          times[prayer.name] = t.millisecondsSinceEpoch ~/ 1000;
        }
        if (times.isNotEmpty) out['${p[2]}-${p[1]}-${p[0]}'] = times;
      } catch (_) {
        continue;
      }
    }
    return out;
  }
}

/// The next enabled prayer + offset strictly after [now], with its prayer.
({DateTime at, Prayer prayer})? nextPrayerBuzz(
  Map<String, Map<String, int>> cache,
  PrayerBuzzSettings settings,
  DateTime now,
) {
  if (!settings.anyOn) return null;
  ({DateTime at, Prayer prayer})? best;
  for (final day in cache.values) {
    for (final p in settings.enabled) {
      final sec = day[p.name];
      if (sec == null) continue;
      final at = DateTime.fromMillisecondsSinceEpoch(sec * 1000)
          .add(Duration(minutes: settings.offsetMinutes));
      if (!at.isAfter(now)) continue;
      if (best == null || at.isBefore(best.at)) best = (at: at, prayer: p);
    }
  }
  return best;
}

/// Same shape as the Fajr and band-timer plans.
typedef PrayerBuzzPlan = ({DateTime? next, List<int> haptics});

PrayerBuzzPlan loadPrayerBuzzPlan(SharedPreferences prefs, DateTime now) {
  final s = PrayerBuzzSettings.load(prefs);
  return (
    next: nextPrayerBuzz(PrayerTimes.readCache(prefs), s, now)?.at,
    // The Fajr pattern builder, with the stock pause: values the band accepts.
    haptics: fajrHapticPattern(buzzCount: s.buzzCount, pauseSteps: 7),
  );
}

Future<void> refreshPrayerTimesIfNeeded(
  SharedPreferences prefs, {
  required bool useGps,
  DateTime? now,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final at = now ?? DateTime.now();
  // The buzzes are not armed in this build; the times still feed Today, so
  // they are kept fresh while the Fajr alarm is on.
  if (!PrayerBuzzSettings.load(prefs).anyOn &&
      !(prefs.getBool('fajr_alarm_enabled') ?? false)) {
    return;
  }
  if (!PrayerTimes.needsRefresh(prefs, at)) return;
  try {
    await PrayerTimes.refresh(prefs, useGps: useGps, now: at).timeout(timeout);
  } catch (_) {}
}
