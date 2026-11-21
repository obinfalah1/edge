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
  // WHOOP-style: a dark page, big numbers, a colour per family.
  final bg = PdfColor.fromInt(0xFF0B0F12);
  final card = PdfColor.fromInt(0xFF171D22);
  final ink = PdfColors.white;
  final grey = PdfColor.fromInt(0xFF8E979D);
  final line = PdfColor.fromInt(0xFF2A3238);
  final recGreen = PdfColor.fromInt(0xFF16EC06);
  final recYellow = PdfColor.fromInt(0xFFFFDE00);
  final recRed = PdfColor.fromInt(0xFFFF0026);
  final strainBlue = PdfColor.fromInt(0xFF0093E7);
  final sleepBlue = PdfColor.fromInt(0xFF7BA1BB);
  final heart = PdfColor.fromInt(0xFFFF5D73);
  PdfColor recovery(double? v) => v == null
      ? grey
      : (v >= 67 ? recGreen : (v >= 34 ? recYellow : recRed));
  PdfColor colourOf(ReportMetric m, double? mean) => switch (m.key) {
        'readiness' => recovery(mean),
        'strain' => strainBlue,
        'tst_min' => sleepBlue,
        'rhr' || 'rmssd' => heart,
        _ => PdfColor.fromInt(0xFFB0B8BE),
      };

  pw.Widget spark(List<double?> v, PdfColor colour) => pw.SizedBox(
        height: 30,
        child: pw.CustomPaint(
          size: const PdfPoint(150, 30),
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
              ..setStrokeColor(colour)
              ..setLineWidth(1.4)
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

  final cap = pw.TextStyle(fontSize: 7.5, color: grey, fontWeight: pw.FontWeight.bold, letterSpacing: .8);
  final cell = pw.TextStyle(fontSize: 8.5, color: ink);
  final stats = {
    for (final m in kReportMetrics)
      m.key: ReportStats.of([for (final v in dense(m)) ?v]),
  };

  pw.Widget hero(String label, String value, String sub, PdfColor colour) =>
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
              color: card, borderRadius: pw.BorderRadius.circular(10)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label, style: cap),
            pw.SizedBox(height: 6),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 26, color: colour, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 2),
            pw.Text(sub, style: pw.TextStyle(fontSize: 8, color: grey)),
          ]),
        ),
      );

  final rec = stats['readiness']!, str = stats['strain']!, slp = stats['tst_min']!;
  doc.addPage(pw.MultiPage(
    pageTheme: pw.PageTheme(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      buildBackground: (c) => pw.FullPage(
          ignoreMargins: true, child: pw.Container(color: bg)),
    ),
    build: (c) => [
      pw.Text('HEALTH SUMMARY',
          style: pw.TextStyle(
              fontSize: 22, color: ink, fontWeight: pw.FontWeight.bold, letterSpacing: 1.5)),
      pw.SizedBox(height: 4),
      pw.Text(
          '${day(from)} to ${day(to)} (${days.length} days)'
          '${age == null ? '' : ' · age $age'}'
          '${sex == null ? '' : ' · ${sex == 'f' ? 'female' : sex == 'm' ? 'male' : sex}'}',
          style: pw.TextStyle(fontSize: 9.5, color: grey)),
      pw.SizedBox(height: 16),
      pw.Row(children: [
        hero('AVG RECOVERY', rec.mean == null ? '-' : '${rec.mean!.round()}%',
            '${rec.days} days scored', recovery(rec.mean)),
        pw.SizedBox(width: 8),
        hero('AVG STRAIN', str.mean == null ? '-' : str.mean!.toStringAsFixed(1),
            'out of 21', strainBlue),
        pw.SizedBox(width: 8),
        hero('AVG SLEEP', slp.mean == null ? '-' : '${slp.mean!.toStringAsFixed(1)} h',
            '${slp.days} nights', sleepBlue),
      ]),
      pw.SizedBox(height: 14),
      for (final m in kReportMetrics)
        () {
          final d = dense(m);
          final st = stats[m.key]!;
          final colour = colourOf(m, st.mean);
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 6),
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: pw.BoxDecoration(
                color: card, borderRadius: pw.BorderRadius.circular(8)),
            child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
              pw.SizedBox(
                width: 150,
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(m.name.toUpperCase(), style: cap),
                  pw.SizedBox(height: 3),
                  pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                    pw.Text(fmt(m, st.mean),
                        style: pw.TextStyle(fontSize: 17, color: ink, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(width: 3),
                    pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 2),
                        child: pw.Text(m.unit, style: pw.TextStyle(fontSize: 8, color: grey))),
                  ]),
                ]),
              ),
              pw.SizedBox(
                width: 120,
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(st.min == null ? 'No data' : 'Range ${fmt(m, st.min)} to ${fmt(m, st.max)}',
                      style: pw.TextStyle(fontSize: 8, color: grey)),
                  pw.SizedBox(height: 2),
                  pw.Text(st.firstHalf == null ? '' : 'First half ${fmt(m, st.firstHalf)}, then ${fmt(m, st.secondHalf)}',
                      style: pw.TextStyle(fontSize: 8, color: grey)),
                  pw.SizedBox(height: 2),
                  pw.Text('${st.days} days measured', style: pw.TextStyle(fontSize: 8, color: grey)),
                ]),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(child: spark(d, colour)),
            ]),
          );
        }(),
      pw.SizedBox(height: 10),
      pw.Text('WEEKLY AVERAGES', style: cap.copyWith(fontSize: 9, color: ink)),
      pw.SizedBox(height: 6),
      pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: line, width: .5)),
        children: [
          pw.TableRow(children: [
            pw.Text('WEEK', style: cap),
            for (final m in kReportMetrics)
              pw.Text(m.name.split(' (').first.toUpperCase(), style: cap),
          ]),
          for (final (label, vals) in weeks)
            pw.TableRow(children: [
              pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 4), child: pw.Text(label, style: cell)),
              for (final m in kReportMetrics)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 4),
                  child: pw.Text(fmt(m, vals[m.key]),
                      style: m.key == 'readiness'
                          ? cell.copyWith(color: recovery(vals[m.key]), fontWeight: pw.FontWeight.bold)
                          : cell),
                ),
            ]),
        ],
      ),
      pw.SizedBox(height: 16),
      pw.Text(
          'Measured by a wrist-worn WHOOP band and computed on the phone by the '
          'open-source Edge app. HRV is overnight RMSSD from 1 Hz beat timing; '
          'sleep is a wrist estimate; Recovery and Strain are the app\'s own '
          'scores. These are approximations for context, not medical-grade '
          'measurements or a diagnosis.'
          '${generated == null ? '' : ' Generated ${day(generated)}.'}',
          style: pw.TextStyle(fontSize: 7.5, color: grey)),
    ],
  ));
  return doc.save();
}
