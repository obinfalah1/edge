import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/edge6/e6.dart';
import 'package:openstrap_edge/edge6/e6_screens.dart';
import 'package:openstrap_edge/models/metric.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart' show HomeData;
import 'package:openstrap_edge/ui2/sleep_ring_model.dart' show SleepStageMin;

E6Data _data() => E6Data(
  const HomeData(
    readiness: Metric(value: 78),
    strain: Metric(value: 11.4),
    sleepMin: Metric(value: 462),
    sleepNeedMin: Metric(value: 508),
    rhr: Metric(value: 54),
    steps: Metric(value: 6318),
    calories: Metric(value: 1240),
    bedtime: Metric(value: 1284),
    strainTarget: {'low': 14, 'high': 16},
    sleepStages: SleepStageMin(deep: 91, rem: 112, light: 259, awake: 12),
  ),
  const {
    'hrv': {'rmssd': 62},
    'resp': {'value': 14.2},
  },
  const [62, 70, 55, 30, 66, 80, 78],
);

Future<void> _pump(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(440 * 3, 956 * 3);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: w));
  await t.pump();
}

void main() {
  test('derived values', () {
    final d = _data();
    expect(d.sleepPct!.round(), 91);
    expect(d.hrv, 62);
    expect(d.targetHigh, 16);
    expect(E6C.recovery(78), E6C.rec);
    expect(E6C.recovery(50), E6C.mid);
    expect(E6C.recovery(20), E6C.low);
    expect(e6Clock(1284), '9:24 PM');
    expect(e6Hm(462), '7:42');
  });

  for (final glass in [false, true]) {
    final look = glass ? 'glass' : 'classic';
    testWidgets('recovery, sleep and strain render ($look)', (t) async {
      E6Prefs.glass.value = glass;
      for (final screen in [
        E6RecoveryScreen(data: _data()),
        E6SleepScreen(data: _data()),
        E6StrainScreen(data: _data()),
      ]) {
        await _pump(t, screen);
        expect(t.takeException(), isNull);
        if (screen is E6SleepScreen) expect(find.text('7:42'), findsWidgets);
      }
    });

    testWidgets('a screen with no data yet still renders ($look)', (t) async {
      E6Prefs.glass.value = glass;
      await _pump(
        t,
        E6RecoveryScreen(data: E6Data(const HomeData(), const {}, const [])),
      );
      expect(t.takeException(), isNull);
      expect(find.textContaining('not scored'), findsOneWidget);
    });
  }
}
