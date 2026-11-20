// Fajr alarm — arms the band's own wake alarm at Fajr + N minutes, every day.
//
// The band alarm is the one thing in Edge that keeps working when the phone
// does not: it is armed on the strap's RTC and fires on its own. The weekly
// schedule (alarm_schedule.dart) gives it a fixed time per weekday; Fajr moves
// every day, so this module supplies "the next Fajr + offset" as a second
// source for the same single strap slot. Whichever of the two comes first is
// what gets armed (see [armNextScheduledOccurrence]).
//
// Prayer times come from the AlAdhan API, method 16 (UAE: Fajr angle 18.2°),
// at the phone's location — the same source the Fajr Edge Alarm shortcut
// used, checked against the official awqaf.gov.ae Sharjah timetable for every
// day of 2026 (never more than 1 minute apart). A month and the next are
// fetched at once and cached, so re-arming from a headless background sync
// never needs the network or GPS at that moment; the cache only has to be
// refreshed now and then, which the foreground does on every connect.

import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../ble/ble_state.dart' show AlarmPayloads;

/// Al Majaz, Sharjah — used when the phone's location is unavailable. Of the
/// points checked against the awqaf.gov.ae Sharjah table this matched best
/// (324 of 365 days exact in 2026, the rest within one minute).
const double kFajrFallbackLat = 25.3255;
const double kFajrFallbackLon = 55.3870;

/// AlAdhan calculation method 16 — UAE (Fajr and Isha angle 18.2°).
const int kFajrMethod = 16;

const String _kEnabled = 'fajr_alarm_enabled';
const String _kOffset = 'fajr_alarm_offset_min';
const String _kCount = 'fajr_alarm_buzz_count';
const String _kGap = 'fajr_alarm_pause_steps';
const String _kCache = 'fajr_alarm_cache_v1';
const String _kCoords = 'fajr_alarm_coords_v1';
const String _kFetchedAt = 'fajr_alarm_fetched_at_ms';
const String _kSource = 'fajr_alarm_coords_source';
const String _kBuzzTimer = 'buzz_timer_epoch';

/// The user's numbers — the same three the shortcut had.
class FajrAlarmSettings {
  final bool enabled;

  /// Minutes after Fajr the band buzzes (0..120).
  final int offsetMinutes;

  /// How many buzzes (1..20).
  final int buzzCount;

  /// Pause between buzzes, in steps of the strap's stock 240 ms pause
  /// (1..7, i.e. 0.24–1.68 s). The WHOOP 5 only accepts waveform values from
  /// its own effect table (it answers `invalid_waveform_effect` otherwise —
  /// seen on hardware for longer DRV2605-style pauses), so the pause is built
  /// from repeats of the one pause value the stock alarm already uses.
  final int pauseSteps;

  const FajrAlarmSettings({
    this.enabled = false,
    this.offsetMinutes = 15,
    this.buzzCount = 3,
    this.pauseSteps = 7,
  });

  static const int maxOffset = 120;
  static const int maxCount = 20;
  static const int maxPause = 7;

  /// One pause step, as the strap plays it.
  static const int pauseStepMs = 240;

  FajrAlarmSettings copyWith({
    bool? enabled,
    int? offsetMinutes,
    int? buzzCount,
    int? pauseSteps,
  }) => FajrAlarmSettings(
    enabled: enabled ?? this.enabled,
    offsetMinutes: (offsetMinutes ?? this.offsetMinutes).clamp(0, maxOffset),
    buzzCount: (buzzCount ?? this.buzzCount).clamp(1, maxCount),
    pauseSteps: (pauseSteps ?? this.pauseSteps).clamp(1, maxPause),
  );

  static FajrAlarmSettings load(SharedPreferences prefs) =>
      const FajrAlarmSettings().copyWith(
        enabled: prefs.getBool(_kEnabled),
        offsetMinutes: prefs.getInt(_kOffset),
        buzzCount: prefs.getInt(_kCount),
        pauseSteps: prefs.getInt(_kGap),
      );

  Future<void> save(SharedPreferences prefs) async {
    await prefs.setBool(_kEnabled, enabled);
    await prefs.setInt(_kOffset, offsetMinutes);
    await prefs.setInt(_kCount, buzzCount);
    await prefs.setInt(_kGap, pauseSteps);
  }

  @override
  bool operator ==(Object other) =>
      other is FajrAlarmSettings &&
      other.enabled == enabled &&
      other.offsetMinutes == offsetMinutes &&
      other.buzzCount == buzzCount &&
      other.pauseSteps == pauseSteps;

  @override
  int get hashCode =>
      Object.hash(enabled, offsetMinutes, buzzCount, pauseSteps);

  @override
  String toString() =>
      'FajrAlarmSettings(enabled: $enabled, '
      'offset: ${offsetMinutes}m, buzzes: $buzzCount, pause steps: $pauseSteps)';
}

/// The strap's 12-byte alarm haptic pattern for [buzzCount] buzzes with
/// [pauseSteps] × 240 ms of pause after each.
///
/// Layout (see [AlarmPayloads.defaultHaptics]): eight waveform slots, a u16
/// per-effect loop control, the overall loop count, and the maximum alarm
/// duration in seconds. The stock pattern is `[47, 152, 0 ×6, 0, 0, 7, 30]`:
/// effect 47 (the buzz) then 152 (a 240 ms pause), looped 7 times.
///
/// Only those two waveform values are used — a WHOOP 5 refused other pause
/// values with `invalid_waveform_effect` — so the pause is 152 repeated and
/// the buzz count is the overall loop. If the band still refuses the pattern
/// (e.g. the loop count or duration), the caller arms the stock one instead.
List<int> fajrHapticPattern({required int buzzCount, required int pauseSteps}) {
  final count = buzzCount.clamp(1, FajrAlarmSettings.maxCount);
  final pauses = pauseSteps.clamp(1, FajrAlarmSettings.maxPause);
  final slots = <int>[47, for (var i = 0; i < pauses; i++) 152];
  while (slots.length < 8) {
    slots.add(0);
  }
  // Enough time for every buzz (≈0.5 s each, generous) and its pauses; never
  // below the stock 30 s the strap is known to accept.
  final needed =
      (count * (500 + pauses * FajrAlarmSettings.pauseStepMs) / 1000).ceil() +
      5;
  final duration = needed < 30 ? 30 : (needed > 255 ? 255 : needed);
  return <int>[...slots, 0, 0, count, duration];
}

/// Today's and the coming weeks' Fajr instants, keyed by local date
/// (`yyyy-MM-dd`) → unix seconds.
class FajrTimes {
  FajrTimes._();

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static Map<String, int> readCache(SharedPreferences prefs) {
    final raw = prefs.getString(_kCache);
    if (raw == null) return {};
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in m.entries) e.key: (e.value as num).toInt()};
    } catch (_) {
      return {};
    }
  }

  static DateTime? lastFetched(SharedPreferences prefs) {
    final ms = prefs.getInt(_kFetchedAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// "lat,lon" the cached times were fetched for.
  static String? coords(SharedPreferences prefs) => prefs.getString(_kCoords);

  /// "gps", "last" (last GPS fix stored earlier) or "sharjah" (fallback).
  static String? coordsSource(SharedPreferences prefs) =>
      prefs.getString(_kSource);

  /// True when the cache is missing any of the next [aheadDays] days or is
  /// older than a week (a moved phone, or a corrected API, gets picked up).
  static bool needsRefresh(
    SharedPreferences prefs,
    DateTime now, {
    int aheadDays = 10,
  }) {
    final cache = readCache(prefs);
    for (var i = 0; i <= aheadDays; i++) {
      if (!cache.containsKey(
        dayKey(DateTime(now.year, now.month, now.day + i)),
      )) {
        return true;
      }
    }
    final fetched = lastFetched(prefs);
    return fetched == null || now.difference(fetched) > const Duration(days: 7);
  }

  /// Best available coordinates. With [useGps] (foreground only) it asks the
  /// phone for a fix — requesting permission first only when [askPermission]
  /// (the user just switched the Fajr alarm on) — and remembers it; otherwise
  /// it reuses the last stored fix, else Sharjah.
  static Future<({double lat, double lon, String source})> _coordinates(
    SharedPreferences prefs, {
    required bool useGps,
    bool askPermission = false,
  }) async {
    if (useGps) {
      try {
        if (await Geolocator.isLocationServiceEnabled()) {
          var perm = await Geolocator.checkPermission();
          if (perm == LocationPermission.denied && askPermission) {
            perm = await Geolocator.requestPermission();
          }
          if (perm == LocationPermission.whileInUse ||
              perm == LocationPermission.always) {
            final pos =
                await Geolocator.getLastKnownPosition() ??
                await Geolocator.getCurrentPosition(
                  locationSettings: const LocationSettings(
                    accuracy: LocationAccuracy.low,
                    timeLimit: Duration(seconds: 10),
                  ),
                );
            return (lat: pos.latitude, lon: pos.longitude, source: 'gps');
          }
        }
      } catch (_) {
        // Fall through to the stored fix / Sharjah.
      }
    }
    final stored = coords(prefs)?.split(',');
    final prevSource = coordsSource(prefs);
    if (stored != null && stored.length == 2 && prevSource != 'sharjah') {
      final lat = double.tryParse(stored[0]);
      final lon = double.tryParse(stored[1]);
      if (lat != null && lon != null)
        return (lat: lat, lon: lon, source: 'last');
    }
    return (lat: kFajrFallbackLat, lon: kFajrFallbackLon, source: 'sharjah');
  }

  /// Fetch this month and next month from AlAdhan and merge them into the
  /// cache. Returns true when at least one month arrived. Never throws.
  static Future<bool> refresh(
    SharedPreferences prefs, {
    bool useGps = false,
    bool askPermission = false,
    DateTime? now,
    http.Client? client,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final at = now ?? DateTime.now();
    final c = await _coordinates(
      prefs,
      useGps: useGps,
      askPermission: askPermission,
    );
    final http.Client cl = client ?? http.Client();
    final fresh = <String, int>{};
    try {
      for (final month in [
        DateTime(at.year, at.month),
        DateTime(at.year, at.month + 1),
      ]) {
        final uri = Uri.https(
          'api.aladhan.com',
          '/v1/calendar/${month.year}/${month.month}',
          {
            'latitude': c.lat.toStringAsFixed(4),
            'longitude': c.lon.toStringAsFixed(4),
            'method': '$kFajrMethod',
            'iso8601': 'true',
          },
        );
        try {
          final res = await cl.get(uri).timeout(timeout);
          if (res.statusCode != 200) continue;
          fresh.addAll(parseCalendar(res.body));
        } catch (_) {
          // One month failing is not fatal; the other may still land.
        }
      }
    } finally {
      if (client == null) cl.close();
    }
    if (fresh.isEmpty) return false;
    final merged = {...readCache(prefs), ...fresh};
    // Keep two days back (an alarm armed just before midnight still finds its
    // day) and drop the rest.
    final keepFrom = dayKey(DateTime(at.year, at.month, at.day - 2));
    merged.removeWhere((k, _) => k.compareTo(keepFrom) < 0);
    await prefs.setString(_kCache, jsonEncode(merged));
    await prefs.setInt(_kFetchedAt, at.millisecondsSinceEpoch);
    await prefs.setString(
      _kCoords,
      '${c.lat.toStringAsFixed(4)},${c.lon.toStringAsFixed(4)}',
    );
    await prefs.setString(_kSource, c.source);
    return true;
  }

  /// Parse an AlAdhan `/v1/calendar` body (with `iso8601=true`) into
  /// `yyyy-MM-dd` → Fajr unix seconds. The ISO time carries its UTC offset
  /// (`2026-11-20T05:18:00+04:00`), so the instant is exact whatever time
  /// zone the phone is set to. Malformed days are skipped.
  static Map<String, int> parseCalendar(String body) {
    final out = <String, int>{};
    final decoded = jsonDecode(body);
    if (decoded is! Map || decoded['data'] is! List) return out;
    for (final day in decoded['data'] as List) {
      try {
        final raw = (day['timings']['Fajr'] as String).split(' ').first;
        final fajr = DateTime.parse(raw);
        final g = day['date']['gregorian']['date'] as String; // dd-MM-yyyy
        final p = g.split('-');
        out['${p[2]}-${p[1]}-${p[0]}'] = fajr.millisecondsSinceEpoch ~/ 1000;
      } catch (_) {
        continue;
      }
    }
    return out;
  }
}

/// The next Fajr + offset strictly after [now] from [cache], or null when the
/// Fajr alarm is off or nothing cached lies ahead.
DateTime? nextFajrAlarm(
  Map<String, int> cache,
  FajrAlarmSettings settings,
  DateTime now,
) {
  if (!settings.enabled) return null;
  DateTime? best;
  for (final sec in cache.values) {
    final at = DateTime.fromMillisecondsSinceEpoch(
      sec * 1000,
    ).add(Duration(minutes: settings.offsetMinutes));
    if (!at.isAfter(now)) continue;
    if (best == null || at.isBefore(best)) best = at;
  }
  return best;
}

/// Everything the arming code needs about the Fajr alarm right now.
typedef FajrPlan = ({DateTime? next, List<int> haptics});

/// A one-off "buzz in N minutes" timer, set from Siri / Shortcuts
/// (BuzzTimerIntent in ios/OpenStrapIntents.swift). It shares the strap's one
/// alarm slot with the weekly schedule and Fajr: whichever comes first is
/// armed, and once the timer has fired the usual re-arm moves on to the next
/// one, so Fajr comes back by itself.
class BuzzTimer {
  static const int maxMinutes = 720;

  /// The pending timer, or null when none is set or it has already passed.
  static DateTime? pending(SharedPreferences prefs, DateTime now) {
    final sec = prefs.getInt(_kBuzzTimer);
    if (sec == null) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    return at.isAfter(now) ? at : null;
  }

  /// Sets the timer [minutes] from [now] (whole seconds, which is what the
  /// strap stores) and returns when it goes off.
  static Future<DateTime> start(
    SharedPreferences prefs,
    int minutes, {
    DateTime? now,
  }) async {
    final from = now ?? DateTime.now();
    final sec =
        from.millisecondsSinceEpoch ~/ 1000 + minutes.clamp(1, maxMinutes) * 60;
    await prefs.setInt(_kBuzzTimer, sec);
    return DateTime.fromMillisecondsSinceEpoch(sec * 1000);
  }

  /// The timer's unix second as stored, past or not (null when none).
  static int? storedEpoch(SharedPreferences prefs) => prefs.getInt(_kBuzzTimer);

  static Future<void> cancel(SharedPreferences prefs) =>
      prefs.remove(_kBuzzTimer);
}

/// Read settings + cache and compute the plan: the next Fajr + offset or a
/// pending buzz timer, whichever is first. Both buzz with the Fajr pattern.
/// No network.
FajrPlan loadFajrPlan(SharedPreferences prefs, DateTime now) {
  final s = FajrAlarmSettings.load(prefs);
  final fajr = nextFajrAlarm(FajrTimes.readCache(prefs), s, now);
  final timer = BuzzTimer.pending(prefs, now);
  final next = timer != null && (fajr == null || timer.isBefore(fajr))
      ? timer
      : fajr;
  return (
    next: next,
    haptics: fajrHapticPattern(
      buzzCount: s.buzzCount,
      pauseSteps: s.pauseSteps,
    ),
  );
}

/// Refresh the cache when it is stale, within [timeout]. Never throws.
Future<void> refreshFajrTimesIfNeeded(
  SharedPreferences prefs, {
  required bool useGps,
  DateTime? now,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final at = now ?? DateTime.now();
  if (!FajrAlarmSettings.load(prefs).enabled) return;
  if (!FajrTimes.needsRefresh(prefs, at)) return;
  try {
    await FajrTimes.refresh(prefs, useGps: useGps, now: at).timeout(timeout);
  } catch (_) {
    // Stale cache is still used; the next connect tries again.
  }
}
