// Healthspan: an estimated age from six habits, and each habit on its own.
// The math and its caveats live in compute/healthspan.dart.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../compute/healthspan.dart';
import '../../data/db.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import '../../l10n/personal_text.dart';
import 'home_screen.dart' show repoOf;

class HealthspanScreen extends StatefulWidget {
  const HealthspanScreen({super.key});

  @override
  State<HealthspanScreen> createState() => _HealthspanScreenState();
}

class _HealthspanScreenState extends State<HealthspanScreen> {
  HealthspanResult? _now, _before;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    int? age;
    try {
      age = (context.read<AppState>().user?['age'] as num?)?.round();
    } catch (_) {}
    final today = DateTime.now();
    String day(int back) =>
        _dayKey(DateTime(today.year, today.month, today.day - back));

    Future<Map<String, double>> series(String key) async {
      try {
        final rows = await LocalDb.metricSeries(key);
        return {
          for (final r in rows)
            if (r['value'] is num) '${r['date']}': (r['value'] as num).toDouble(),
        };
      } catch (_) {
        return const {};
      }
    }

    final sleep = await series('tst_min');
    final rhr = await series('rhr');
    final rmssd = await series('rmssd');
    final steps = await series('steps');
    final strain = await series('strain');
    final onsets = <String, double>{};
    try {
      final repo = mounted ? repoOf(context) : null;
      for (final w in await repo?.sleepWindows(days: 60) ?? const []) {
        final ts = w['onset_ts'];
        if (ts is! num) continue;
        final t = DateTime.fromMillisecondsSinceEpoch(ts.toInt() * 1000);
        // Minutes from 18:00, so bedtimes either side of midnight are close.
        onsets['${w['date']}'] = ((t.hour * 60 + t.minute - 18 * 60) % 1440).toDouble();
      }
    } catch (_) {}

    HealthspanResult window(int from, int to) {
      List<double> pick(Map<String, double> m) => [
            for (var b = from; b < to; b++)
              ?m[day(b)],
          ];
      return Healthspan.compute(
        age: age,
        sleepMin: pick(sleep),
        onsetMinutes: pick(onsets),
        rhr: pick(rhr),
        rmssd: pick(rmssd),
        steps: pick(steps),
        strain: pick(strain),
      );
    }

    if (!mounted) return;
    setState(() {
      _now = window(0, 30);
      _before = window(30, 60);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(tr(c, 'Healthspan', 'مدى الصحة'),
                sub: tr(c, 'Your habits, in years', 'عاداتك بالسنوات')),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator.adaptive())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
                    children: [
                      _hero(c, p),
                      const SizedBox(height: S.x4),
                      Section(
                        tr(c, 'What moves it', 'ما الذي يؤثر فيه'),
                        Surface(
                          pad: const EdgeInsets.symmetric(horizontal: S.x4),
                          child: Column(children: [
                            for (final (i, r) in _now!.pillars.indexed) ...[
                              if (i > 0) Divider(color: p.line, height: 1),
                              _pillar(c, p, r),
                            ],
                          ]),
                        ),
                      ),
                      const SizedBox(height: S.x4),
                      Text(
                          tr(c, 'An estimate from what large studies link to long-term health, applied to your last 30 days. It is not a measured biological age and not medical advice. Each habit is capped so no single number decides it.', 'تقدير مبني على ما تربطه الدراسات الكبيرة بالصحة على المدى الطويل، مطبّق على آخر 30 يومًا. ليس عمرًا بيولوجيًا مقيسًا ولا نصيحة طبية. لكل عادة حدّ أقصى حتى لا يحسم رقم واحد النتيجة.'),
                          style: F.cap.copyWith(color: p.ink3)),
                    ],
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _hero(BuildContext c, P p) {
    final now = _now!;
    final est = now.healthspanAge;
    final prev = _before?.healthspanAge;
    if (now.age == null) {
      return StatusCard(tr(c, 'Add your age', 'أضف عمرك'),
          tr(c, 'Healthspan compares your habits with your age. Add it in Profile.', 'يقارن مدى الصحة عاداتك بعمرك. أضفه من الملف الشخصي.'),
          icon: LucideIcons.userRound);
    }
    if (est == null) {
      return StatusCard(
          tr(c, 'Not enough data yet', 'لا توجد بيانات كافية بعد'),
          tr(c, 'Healthspan needs at least 10 days in four of the six habits below. Keep wearing the band.', 'يحتاج مدى الصحة إلى 10 أيام على الأقل في أربع من العادات الست أدناه. استمر في ارتداء السوار.'),
          icon: LucideIcons.hourglass);
    }
    final delta = est - now.age!;
    final younger = delta <= 0;
    final tone = younger ? C.green : C.orange;
    final change = prev == null ? null : est - prev;
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tr(c, 'HEALTHSPAN AGE', 'عمر مدى الصحة'), style: F.over.copyWith(color: p.ink3)),
        const SizedBox(height: S.x1),
        Text(est.toStringAsFixed(1), style: F.n48.copyWith(color: p.ink)),
        const SizedBox(height: S.x1),
        Text('${tr(c, 'You are', 'عمرك')} ${now.age}', style: F.cap.copyWith(color: p.ink2)),
        const SizedBox(height: S.x3),
        Wrap(spacing: S.x2, runSpacing: S.x2, children: [
          Pill(
              '${delta.abs().toStringAsFixed(1)} ${younger ? tr(c, 'years younger', 'سنة أصغر') : tr(c, 'years older', 'سنة أكبر')}',
              tone,
              icon: younger ? LucideIcons.trendingDown : LucideIcons.trendingUp),
          if (change != null && change.abs() >= 0.1)
            Pill(
                '${change > 0 ? '+' : '−'}${change.abs().toStringAsFixed(1)} ${tr(c, 'vs the 30 days before', 'مقارنة بالـ30 يومًا السابقة')}',
                change < 0 ? C.green : C.orange),
        ]),
      ]),
    );
  }

  Widget _pillar(BuildContext c, P p, PillarResult r) {
    final (IconData icon, Color color, String title, String Function(double) fmt) =
        switch (r.pillar) {
      HealthspanPillar.sleepLength => (LucideIcons.bedDouble, C.indigo,
          tr(c, 'Sleep length', 'مدة النوم'), (v) => '${v.toStringAsFixed(1)} h'),
      HealthspanPillar.sleepRegularity => (LucideIcons.clock, C.purple,
          tr(c, 'Bedtime regularity', 'انتظام موعد النوم'), (v) => '± ${v.round()} min'),
      HealthspanPillar.restingHr => (LucideIcons.heartPulse, C.red,
          tr(c, 'Resting heart rate', 'نبض الراحة'), (v) => '${v.round()} bpm'),
      HealthspanPillar.hrv => (LucideIcons.activity, C.green,
          tr(c, 'HRV for your age', 'تقلّب النبض لعمرك'), (v) => '${v.round()} ms'),
      HealthspanPillar.steps => (LucideIcons.footprints, C.orange,
          tr(c, 'Daily steps', 'الخطوات اليومية'), (v) => v.round().toString()),
      HealthspanPillar.activeDays => (LucideIcons.flame, C.yellow,
          tr(c, 'Active days a week', 'أيام النشاط في الأسبوع'), (v) => v.toStringAsFixed(1)),
    };
    final years = r.years;
    final effect = !r.hasData
        ? tr(c, 'Not enough data', 'بيانات غير كافية')
        : years.abs() < 0.05
            ? tr(c, 'On target', 'ضمن الهدف')
            : '${years < 0 ? '−' : '+'}${years.abs().toStringAsFixed(1)} ${tr(c, 'y', 'سنة')}';
    final effectColor = !r.hasData || years.abs() < 0.05
        ? p.ink3
        : (years < 0 ? p.on(C.green) : p.on(C.orange));
    return Semantics(
      label: '$title, ${r.hasData ? fmt(r.value!) : ''}, $effect',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.wash(color), borderRadius: R.rSm),
            child: Icon(icon, size: 16, color: p.on(color)),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: F.body.copyWith(color: p.ink)),
              if (r.hasData)
                Text(fmt(r.value!), style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
          Text(effect,
              style: F.body.copyWith(color: effectColor, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// `yyyy-MM-dd` for a local day.
String _dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
