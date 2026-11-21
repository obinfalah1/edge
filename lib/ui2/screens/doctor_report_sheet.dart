// "Report for your doctor": pick a range, build the PDF on the phone
// (compute/doctor_report.dart), hand it to the share sheet.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../compute/doctor_report.dart';
import '../../data/db.dart';
import '../../l10n/personal_text.dart';
import '../../state/app_state.dart';
import '../ui2.dart';

Future<void> showDoctorReportSheet(BuildContext c) async {
  final days = await showModalBottomSheet<int>(
    context: c,
    sheetAnimationStyle: sheetMotion(c),
    builder: (s) {
      final p = P.of(s);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x4),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr(s, 'Report for your doctor', 'تقرير لطبيبك'),
                style: F.t2.copyWith(color: p.ink)),
            const SizedBox(height: S.x1),
            Text(
                tr(s, 'A PDF of your daily numbers, made on this iPhone. Choose how far back.',
                    'ملف PDF بأرقامك اليومية يُنشأ على هذا الآيفون. اختر المدة.'),
                style: F.cap.copyWith(color: p.ink2)),
            const SizedBox(height: S.x4),
            for (final d in const [30, 90])
              Padding(
                padding: const EdgeInsets.only(bottom: S.x2),
                child: BigButton(tr(s, 'Last $d days', 'آخر $d يومًا'),
                    icon: LucideIcons.fileText,
                    color: C.blue,
                    soft: d == 90,
                    onTap: () => Navigator.pop(s, d)),
              ),
          ]),
        ),
      );
    },
  );
  if (days == null || !c.mounted) return;
  final messenger = ScaffoldMessenger.of(c);
  final box = c.findRenderObject() as RenderBox?;
  try {
    final user = c.read<AppState>().user;
    final to = DateTime.now();
    final from = DateTime(to.year, to.month, to.day - days + 1);
    final series = <String, Map<String, double>>{};
    for (final m in kReportMetrics) {
      final rows = await LocalDb.metricSeries(m.key, measuredOnly: true);
      series[m.key] = {
        for (final r in rows)
          if (r['value'] is num) '${r['date']}': (r['value'] as num).toDouble(),
      };
    }
    final bytes = await buildDoctorReport(
      from: from,
      to: to,
      series: series,
      age: (user?['age'] as num?)?.round(),
      sex: user?['sex'] as String?,
      generated: to,
    );
    await Share.shareXFiles(
      [XFile.fromData(bytes, mimeType: 'application/pdf', name: 'health-summary.pdf')],
      sharePositionOrigin:
          box == null ? null : box.localToGlobal(Offset.zero) & box.size,
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
}
