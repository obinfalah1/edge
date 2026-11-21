// A one-file PDF summary to show a doctor or coach: the person's own daily
// numbers over a chosen window, as a summary table, a small trend chart per
// metric and weekly averages. Plain ASCII punctuation: the built-in PDF
// font has no en dash or arrow. Built entirely on the phone (package:pdf);
// nothing is uploaded. English only: it is meant for a clinician.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One metric in the report.
class ReportMetric {
  final String key, name, unit;

  /// Decimal places shown.
  final int decimals;
  const ReportMetric(this.key, this.name, this.unit, {this.decimals = 0});
}

const List<ReportMetric> kReportMetrics = [
  ReportMetric('rhr', 'Resting heart rate', 'bpm'),
  ReportMetric('rmssd', 'HRV (RMSSD)', 'ms'),
  ReportMetric('tst_min', 'Sleep', 'h', decimals: 1),
  ReportMetric('resp_rate', 'Breathing rate', '/min', decimals: 1),
  ReportMetric('readiness', 'Recovery', '/100'),
  ReportMetric('strain', 'Strain', '/21', decimals: 1),
  ReportMetric('steps', 'Steps', '/day'),
];

class ReportStats {
  final int days;
  final double? mean, min, max, firstHalf, secondHalf;
  const ReportStats(
      this.days, this.mean, this.min, this.max, this.firstHalf, this.secondHalf);

  static ReportStats of(List<double> v) {
    if (v.isEmpty) return const ReportStats(0, null, null, null, null, null);
    double avg(Iterable<double> x) => x.reduce((a, b) => a + b) / x.length;
    final h = v.length ~/ 2;
    return ReportStats(
      v.length,
      avg(v),
      v.reduce(math.min),
      v.reduce(math.max),
      h == 0 ? null : avg(v.sublist(0, h)),
      h == 0 ? null : avg(v.sublist(h)),
    );
  }
}

/// [series]: metric key → (day `yyyy-MM-dd` → value), oldest first.
/// Sleep arrives in minutes and is shown in hours.
Future<Uint8List> buildDoctorReport({
  required DateTime from,
  required DateTime to,
  required Map<String, Map<String, double>> series,
  int? age,
  String? sex,
  DateTime? generated,
}) async {
  String day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  final days = <String>[
    for (var d = DateTime(from.year, from.month, from.day);
        !d.isAfter(to);
        d = DateTime(d.year, d.month, d.day + 1))
      day(d),
  ];
  double conv(String key, double v) => key == 'tst_min' ? v / 60 : v;
  List<double?> dense(ReportMetric m) => [
        for (final d in days)
          if (series[m.key]?[d] case final v?) conv(m.key, v) else null,
      ];
  String fmt(ReportMetric m, double? v) =>
      v == null ? '-' : v.toStringAsFixed(m.decimals);

  final doc = pw.Document(title: 'Health summary', author: 'Edge');
  final grey = PdfColor.fromInt(0xFF6C6C70);
  final line = PdfColor.fromInt(0xFFE5E5EA);
  final accent = PdfColor.fromInt(0xFF007AFF);

  pw.Widget spark(List<double?> v) => pw.SizedBox(
        height: 34,
        child: pw.CustomPaint(
          size: const PdfPoint(150, 34),
          painter: (canvas, size) {
            final pts = [
              for (var i = 0; i < v.length; i++)
                if (v[i] != null) (i, v[i]!),
            ];
            if (pts.length < 2) return;
            final lo = pts.map((p) => p.$2).reduce(math.min);
            final hi = pts.map((p) => p.$2).reduce(math.max);
            final span = hi - lo == 0 ? 1 : hi - lo;
            double x(int i) => i / math.max(1, v.length - 1) * size.x;
            double y(double val) => 3 + (val - lo) / span * (size.y - 6);
            canvas
              ..setStrokeColor(accent)
              ..setLineWidth(1.2)
              ..moveTo(x(pts.first.$1), y(pts.first.$2));
            for (final p in pts.skip(1)) {
              canvas.lineTo(x(p.$1), y(p.$2));
            }
            canvas.strokePath();
          },
        ),
      );

  // Weekly averages, newest week last.
  final weeks = <(String, Map<String, double?>)>[];
  for (var s = 0; s < days.length; s += 7) {
    final slice = days.sublist(s, math.min(s + 7, days.length));
    weeks.add((
      '${slice.first.substring(5)} to ${slice.last.substring(5)}',
      {
        for (final m in kReportMetrics)
          m.key: ReportStats.of([
            for (final d in slice)
              if (series[m.key]?[d] case final v?) conv(m.key, v),
          ]).mean,
      },
    ));
  }

  final cell = pw.TextStyle(fontSize: 8.5);
  final head = pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold);

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(32),
    build: (c) => [
      pw.Text('Health summary',
          style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 4),
      pw.Text(
          '${day(from)} to ${day(to)} (${days.length} days)'
          '${age == null ? '' : ' · age $age'}'
          '${sex == null ? '' : ' · ${sex == 'f' ? 'female' : sex == 'm' ? 'male' : sex}'}',
          style: pw.TextStyle(fontSize: 10, color: grey)),
      pw.SizedBox(height: 14),
      pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: .5)),
        columnWidths: const {
          0: pw.FlexColumnWidth(2.2),
          1: pw.FlexColumnWidth(1),
          2: pw.FlexColumnWidth(1.4),
          3: pw.FlexColumnWidth(1.4),
          4: pw.FlexColumnWidth(.8),
          5: pw.FlexColumnWidth(2.6),
        },
        children: [
          pw.TableRow(children: [
            for (final h in ['Measure', 'Average', 'Range', 'First half, then second', 'Days', 'Daily trend'])
              pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 5), child: pw.Text(h, style: head)),
          ]),
          for (final m in kReportMetrics)
            () {
              final d = dense(m);
              final st = ReportStats.of([for (final v in d) ?v]);
              return pw.TableRow(
                verticalAlignment: pw.TableCellVerticalAlignment.middle,
                children: [
                  pw.Text('${m.name} (${m.unit})', style: cell),
                  pw.Text(fmt(m, st.mean), style: head),
                  pw.Text(st.min == null ? '-' : '${fmt(m, st.min)} to ${fmt(m, st.max)}', style: cell),
                  pw.Text(st.firstHalf == null ? '-' : '${fmt(m, st.firstHalf)} then ${fmt(m, st.secondHalf)}', style: cell),
                  pw.Text('${st.days}', style: cell),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: spark(d)),
                ],
              );
            }(),
        ],
      ),
      pw.SizedBox(height: 18),
      pw.Text('Weekly averages', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: .5)),
        children: [
          pw.TableRow(children: [
            pw.Text('Week', style: head),
            for (final m in kReportMetrics) pw.Text(m.name.split(' (').first, style: head),
          ]),
          for (final (label, vals) in weeks)
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 3), child: pw.Text(label, style: cell)),
              for (final m in kReportMetrics) pw.Text(fmt(m, vals[m.key]), style: cell),
            ]),
        ],
      ),
      pw.SizedBox(height: 18),
      pw.Text(
          'Measured by a wrist-worn WHOOP band and computed on the phone by the '
          'open-source Edge app. HRV is overnight RMSSD from 1 Hz beat timing; '
          'sleep is a wrist estimate; Recovery and Strain are the app\'s own '
          'scores. These are approximations for context, not medical-grade '
          'measurements or a diagnosis.'
          '${generated == null ? '' : ' Generated ${day(generated)}.'}',
          style: pw.TextStyle(fontSize: 8, color: grey)),
    ],
  ));
  return doc.save();
}
