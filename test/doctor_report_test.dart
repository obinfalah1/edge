import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/doctor_report.dart';

void main() {
  test('builds a PDF from daily series, gaps included', () async {
    final to = DateTime(2026, 11, 21);
    final from = DateTime(2026, 10, 23);
    String day(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    Map<String, double> wave(double base, double amp) => {
          for (var i = 0; i < 30; i++)
            if (i % 9 != 4) day(from.add(Duration(days: i))): base + amp * math.sin(i / 3),
        };
    final bytes = await buildDoctorReport(
      from: from,
      to: to,
      age: 34,
      sex: 'm',
      generated: to,
      series: {
        'rhr': wave(56, 3),
        'rmssd': wave(58, 8),
        'tst_min': wave(430, 35),
        'resp_rate': wave(14.2, .4),
        'readiness': wave(68, 14),
        'strain': wave(10.5, 3),
        'steps': wave(7800, 2200),
      },
    );
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final out = Platform.environment['REPORT_OUT'];
    if (out != null) File(out).writeAsBytesSync(bytes);
  });
}
