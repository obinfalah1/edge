// Healthspan: six habits the research ties to long-term health, each scored
// on its own, and an ESTIMATED "Healthspan age" that adds up what they say.
//
// What this is not. Upstream deleted a "fitness age" that counted resting HR
// twice (a VO2max that was k/RHR, plus RHR again) with made-up divisors. This
// keeps every input independent and every step visible:
//   * each pillar reads ONE measured series, never another pillar's output;
//   * each pillar's contribution is capped, so no one number dominates;
//   * the whole thing is labelled an estimate from population associations,
//     not a measured biological age, and the screen shows every pillar.
//
// Pillars (30-day means of the person's own data):
//   sleep length     7-9 h is neutral; each hour outside adds up to +3 y
//   sleep regularity spread of sleep onset; past 30 min adds up to +2 y
//   resting HR       60 bpm neutral; ±0.15 y per bpm, capped ±3 y
//   HRV for age      RMSSD vs a typical value for the age; ±3 y (log scale)
//   steps            7,000/day neutral; −0.4 y per extra 1,000, ±3 y
//   active days      days/week with Strain ≥ 10; 3+ helps, 0 costs, ±1.5 y
// A pillar with fewer than [minDays] days of data is left out (and shown as
// "not enough data"), never filled in.

import 'dart:math' as math;

enum HealthspanPillar { sleepLength, sleepRegularity, restingHr, hrv, steps, activeDays }

class PillarResult {
  final HealthspanPillar pillar;

  /// The 30-day value in the pillar's own unit (h, min, bpm, ms, steps,
  /// days/week); null when there is not enough data.
  final double? value;

  /// Years this pillar adds (+) or takes off (−) the estimate; 0 when absent.
  final double years;

  /// How many days fed it.
  final int days;

  const PillarResult(this.pillar, this.value, this.years, this.days);

  bool get hasData => value != null;
}

class HealthspanResult {
  final int? age;
  final List<PillarResult> pillars;

  const HealthspanResult(this.age, this.pillars);

  double get yearsDelta =>
      pillars.fold(0.0, (s, p) => s + (p.hasData ? p.years : 0));

  int get pillarsWithData => pillars.where((p) => p.hasData).length;

  /// Shown only with an age and at least four of six pillars measured.
  double? get healthspanAge =>
      age == null || pillarsWithData < 4 ? null : age! + yearsDelta;
}

class Healthspan {
  Healthspan._();

  static const int minDays = 10;

  static double _clamp(double v, double cap) => v.clamp(-cap, cap).toDouble();

  static double? _mean(List<double> v) =>
      v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;

  static double? _sd(List<double> v) {
    final m = _mean(v);
    if (m == null || v.length < 2) return null;
    final s = v.fold(0.0, (a, x) => a + (x - m) * (x - m)) / (v.length - 1);
    return math.sqrt(s);
  }

  /// A typical overnight RMSSD for [age]: falls with age, floored at 18 ms.
  static double typicalRmssd(int age) =>
      math.max(18, 62 - 0.7 * (age - 20)).toDouble();

  /// [sleepMin], [rhr], [rmssd], [steps], [strain]: one value per day over
  /// the window. [onsetMinutes]: sleep onset as minutes from 18:00 (so a
  /// 23:30 and a 00:30 bedtime are 330 and 390, not 1410 and 30).
  static HealthspanResult compute({
    required int? age,
    required List<double> sleepMin,
    required List<double> onsetMinutes,
    required List<double> rhr,
    required List<double> rmssd,
    required List<double> steps,
    required List<double> strain,
    int windowDays = 30,
  }) {
    PillarResult pillar(HealthspanPillar p, List<double> v,
        double? Function(List<double>) value, double Function(double) years) {
      if (v.length < minDays) return PillarResult(p, null, 0, v.length);
      final x = value(v);
      return x == null
          ? PillarResult(p, null, 0, v.length)
          : PillarResult(p, x, years(x), v.length);
    }

    final a = age ?? 40;
    return HealthspanResult(age, [
      pillar(HealthspanPillar.sleepLength, sleepMin, (v) => _mean(v)! / 60,
          (h) => h < 7 ? _clamp((7 - h) * 1.5, 3) : (h > 9 ? _clamp((h - 9) * 1.5, 3) : 0)),
      pillar(HealthspanPillar.sleepRegularity, onsetMinutes, _sd,
          (sd) => sd <= 30 ? 0 : _clamp((sd - 30) / 30, 2)),
      pillar(HealthspanPillar.restingHr, rhr, _mean,
          (b) => _clamp((b - 60) * 0.15, 3)),
      pillar(HealthspanPillar.hrv, rmssd, _mean,
          (ms) => _clamp(-3 * math.log(ms / typicalRmssd(a)) / math.ln2, 3)),
      pillar(HealthspanPillar.steps, steps, _mean,
          (s) => _clamp(-(s - 7000) / 1000 * 0.4, 3)),
      pillar(HealthspanPillar.activeDays, strain, (v) {
        final active = v.where((s) => s >= 10).length;
        return active / v.length * 7; // days per week
      }, (d) => _clamp(1.5 - d, 1.5)), // 0 → +1.5, 3+ → −1.5
    ]);
  }
}
