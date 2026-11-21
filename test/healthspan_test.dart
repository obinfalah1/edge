import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/healthspan.dart';

List<double> days(double v, [int n = 30]) => List.filled(n, v);

void main() {
  test('on-target habits leave the estimate at the real age', () {
    final r = Healthspan.compute(
      age: 40,
      sleepMin: days(8 * 60),
      onsetMinutes: [for (var i = 0; i < 30; i++) 330.0 + (i.isEven ? 10 : -10)],
      rhr: days(60),
      rmssd: days(Healthspan.typicalRmssd(40)),
      steps: days(7000),
      strain: [for (var i = 0; i < 30; i++) i % 7 < 3 ? 12.0 : 6.0],
    );
    // 3 active days a week takes 1.5 y off; everything else is neutral.
    expect(r.healthspanAge, closeTo(38.5, 0.3));
  });

  test('each pillar is capped and reads only its own series', () {
    final r = Healthspan.compute(
      age: 30,
      sleepMin: days(3 * 60),
      onsetMinutes: [for (var i = 0; i < 30; i++) i.isEven ? 200.0 : 500.0],
      rhr: days(95),
      rmssd: days(5),
      steps: days(500),
      strain: days(2),
    );
    for (final p in r.pillars) {
      expect(p.years, lessThanOrEqualTo(3.0), reason: '${p.pillar}');
    }
    expect(r.yearsDelta, lessThanOrEqualTo(3 + 2 + 3 + 3 + 3 + 1.5));
  });

  test('too little data: the pillar is left out, never filled in', () {
    final r = Healthspan.compute(
      age: 30,
      sleepMin: days(480, 5),
      onsetMinutes: const [],
      rhr: days(60, 9),
      rmssd: const [],
      steps: days(9000),
      strain: days(12),
    );
    expect(r.pillarsWithData, 2);
    expect(r.healthspanAge, isNull, reason: 'needs four of six');
  });
}
