// Band timer: "remind me in 20 minutes" from Siri / Apple Intelligence
// (BandTimerIntent in ios/OpenStrapIntents.swift). The band buzzes instead of
// the phone ringing. There is no screen; Siri is the whole interface.
//
// Separate from the Fajr alarm (fajr_alarm.dart) and the weekly schedule: its
// own storage, its own buzz count. The one thing it shares is the strap's
// single alarm slot, the only way to make the band buzz on its own with the
// phone locked and Edge suspended. [armNextScheduledOccurrence] arms whichever
// of weekly / Fajr / timer comes first; once the timer has fired, the usual
// re-arm moves on and the next alarm is back on the band.

import 'package:shared_preferences/shared_preferences.dart';

const String _kBandTimerAt = 'band_timer_epoch';
const String _kBandTimerCount = 'band_timer_buzz_count';

typedef BandTimerPlan = ({DateTime? next, List<int> haptics});

class BandTimer {
  static const Duration shortest = Duration(seconds: 15);
  static const Duration longest = Duration(hours: 24);
  static const int defaultCount = 3, maxCount = 20;

  /// When the running timer goes off, or null when none is running.
  static DateTime? pending(SharedPreferences prefs, DateTime now) {
    final sec = prefs.getInt(_kBandTimerAt);
    if (sec == null) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    return at.isAfter(now) ? at : null;
  }

  /// The stored end (unix seconds), past or not.
  static int? storedEpoch(SharedPreferences prefs) =>
      prefs.getInt(_kBandTimerAt);

  /// Starts a timer of [length] (clamped to 15 s .. 24 h) from [now], in whole
  /// seconds as the strap stores them, buzzing [buzzes] times.
  static Future<DateTime> start(
    SharedPreferences prefs,
    Duration length, {
    int buzzes = defaultCount,
    DateTime? now,
  }) async {
    final secs = length.inSeconds.clamp(shortest.inSeconds, longest.inSeconds);
    final from = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    await prefs.setInt(_kBandTimerCount, buzzes.clamp(1, maxCount));
    await prefs.setInt(_kBandTimerAt, from + secs);
    return DateTime.fromMillisecondsSinceEpoch((from + secs) * 1000);
  }

  static Future<void> cancel(SharedPreferences prefs) =>
      prefs.remove(_kBandTimerAt);

  static int buzzCount(SharedPreferences prefs) =>
      (prefs.getInt(_kBandTimerCount) ?? defaultCount).clamp(1, maxCount);

  /// The strap's stock alarm buzz (47, then its 240 ms pause value 152), the
  /// only waveform values a WHOOP 5 accepts, played [count] times.
  static List<int> haptics(int count) {
    final n = count.clamp(1, maxCount);
    final secs = (n * (500 + 7 * 240) / 1000).ceil() + 5;
    return [
      47,
      152,
      152,
      152,
      152,
      152,
      152,
      152,
      0,
      0,
      n,
      secs < 30 ? 30 : secs,
    ];
  }
}

/// The running timer and its buzz, for the alarm arming. No network.
BandTimerPlan loadBandTimerPlan(SharedPreferences prefs, DateTime now) => (
  next: BandTimer.pending(prefs, now),
  haptics: BandTimer.haptics(BandTimer.buzzCount(prefs)),
);
