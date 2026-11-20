// Edge v6 "Performance" UI: shared look, data and building blocks.
//
// A dark, data-first layout with three equal dials (Sleep, Recovery, Strain)
// and two looks the user can switch between in More: Classic (flat dark
// cards) and Liquid Glass (frosted cards with a bright top edge). Everything
// here reads the same stores the original screens read; deep features still
// open the original, tested screens.

import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/local_repository.dart';
import '../models/metric.dart';
import '../ui2/screens/home_screen.dart' show HomeData, metricOf, pointsOf;

/// Colors of the v6 look. Dark only, like the band apps it follows.
class E6C {
  static const ink = Color(0xFFFFFFFF);
  static const ink2 = Color(0xFF8E979D);
  static const ink3 = Color(0xFF4A5257);
  static const line = Color(0x12FFFFFF);
  static const track = Color(0x1AFFFFFF);
  static const sleep = Color(0xFF7FA6C2);
  static const deep = Color(0xFF4C7392);
  static const rem = Color(0xFFB9D3E6);
  static const rec = Color(0xFF33D65C);
  static const mid = Color(0xFFF2C230);
  static const low = Color(0xFFF2504B);
  static const strain = Color(0xFF2F8FE3);
  static const heart = Color(0xFFFF5D73);
  static const base = Color(0xFF0D1012);

  /// Recovery zone color: green 67 and up, yellow 34 to 66, red below.
  static Color recovery(num? v) => v == null
      ? ink3
      : v >= 67
      ? rec
      : v >= 34
      ? mid
      : low;
}

/// Text styles. Numbers and labels use the bundled Barlow Condensed.
class E6T {
  static const _num = 'Barlow Condensed';
  static TextStyle num(double size, {Color color = E6C.ink}) => TextStyle(
    fontFamily: _num,
    fontWeight: FontWeight.w700,
    fontSize: size,
    height: 1,
    color: color,
  );
  static TextStyle cap(double size, {Color color = E6C.ink}) => TextStyle(
    fontFamily: _num,
    fontWeight: FontWeight.w700,
    fontSize: size,
    letterSpacing: size * 0.1,
    color: color,
  );
  static const body = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: E6C.ink,
  );
  static const sub = TextStyle(fontSize: 14, color: E6C.ink2);
  static const small = TextStyle(fontSize: 13, color: E6C.ink2);
}

/// Whether the v6 UI is on, and which look it uses. Stored on the phone.
class E6Prefs {
  static const _kOn = 'edge6_ui';
  static const _kGlass = 'edge6_glass';
  static final glass = ValueNotifier<bool>(false);
  static bool? _on;

  /// Before [load] runs (always the case under test), the default decides.
  static bool get on => _on ?? _defaultOn;

  /// Tests mount the original shell, so the new UI defaults off under test.
  static bool get _defaultOn =>
      !Platform.environment.containsKey('FLUTTER_TEST');

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _on = p.getBool(_kOn) ?? _defaultOn;
    glass.value = p.getBool(_kGlass) ?? false;
  }

  static Future<void> setGlass(bool v) async {
    glass.value = v;
    (await SharedPreferences.getInstance()).setBool(_kGlass, v);
  }

  /// Takes effect on the next launch.
  static Future<void> setOn(bool v) async {
    (await SharedPreferences.getInstance()).setBool(_kOn, v);
  }
}

/// The page background for both looks.
BoxDecoration e6Background(bool glass) => glass
    ? const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -1.15),
          radius: 1.1,
          colors: [Color(0xFF2C3236), Color(0xFF0E1113), Color(0xFF08090A)],
          stops: [0, 0.55, 1],
        ),
      )
    : const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E2427), Color(0xFF14181A), E6C.base],
          stops: [0, 0.38, 1],
        ),
      );

/// A card in the current look: flat in Classic, frosted glass in Liquid Glass.
class E6Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool strong;
  const E6Card({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: E6Prefs.glass,
      builder: (context, glass, _) {
        final radius = BorderRadius.circular(glass ? 24 : 14);
        final inner = Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(padding: padding, child: child),
          ),
        );
        if (!glass) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x0EFFFFFF),
              borderRadius: radius,
            ),
            child: inner,
          );
        }
        return E6Glass(radius: radius, strong: strong, child: inner);
      },
    );
  }
}

/// Liquid Glass surface: blurred backdrop, light gradient, bright top edge.
class E6Glass extends StatelessWidget {
  final Widget child;
  final BorderRadius radius;
  final bool strong;
  const E6Glass({
    super.key,
    required this.child,
    required this.radius,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 34,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: strong
                    ? const [Color(0x2EFFFFFF), Color(0x0FFFFFFF)]
                    : const [Color(0x1FFFFFFF), Color(0x09FFFFFF)],
              ),
              border: Border.all(color: const Color(0x24FFFFFF)),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment(0, -0.85),
                colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A round progress dial with a value in the middle.
class E6Dial extends StatelessWidget {
  final double size;
  final double stroke;
  final double fraction;
  final Color color;
  final String value;
  final String unit;
  final double fontSize;
  final String? caption;
  final double? bandFrom, bandTo;
  const E6Dial({
    super.key,
    required this.size,
    required this.fraction,
    required this.color,
    required this.value,
    this.unit = '',
    this.stroke = 6,
    this.fontSize = 34,
    this.caption,
    this.bandFrom,
    this.bandTo,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          fraction.clamp(0, 1).toDouble(),
          color,
          stroke,
          bandFrom,
          bandTo,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: value, style: E6T.num(fontSize)),
                    if (unit.isNotEmpty)
                      TextSpan(text: unit, style: E6T.num(fontSize * 0.55)),
                  ],
                ),
              ),
              if (caption != null) Text(caption!, style: E6T.small),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double f;
  final Color color;
  final double stroke;
  final double? bandFrom, bandTo;
  _RingPainter(this.f, this.color, this.stroke, this.bandFrom, this.bandTo);

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - stroke;
    final c = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = E6C.track,
    );
    if (bandFrom != null && bandTo != null) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + 2 * math.pi * bandFrom!,
        2 * math.pi * (bandTo! - bandFrom!),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke * 1.9
          ..color = color.withValues(alpha: 0.3),
      );
    }
    if (f > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * f,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.f != f || o.color != color || o.bandFrom != bandFrom;
}

/// A section title in small spaced capitals.
class E6Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const E6Section(this.title, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
    child: Row(
      children: [
        Expanded(child: Text(title.toUpperCase(), style: E6T.cap(15))),
        if (trailing != null) trailing!,
      ],
    ),
  );
}

/// One row in a card: optional leading chip, title, subtitle, chevron.
class E6Row extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? sub;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;
  const E6Row({
    super.key,
    this.leading,
    required this.title,
    this.sub,
    this.trailing,
    this.onTap,
    this.divider = true,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        border: divider
            ? const Border(bottom: BorderSide(color: E6C.line))
            : null,
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: E6T.body),
                if (sub != null) Text(sub!, style: E6T.sub),
              ],
            ),
          ),
          ?trailing,
          if (trailing == null && onTap != null)
            const Icon(Icons.chevron_right, color: E6C.ink2),
        ],
      ),
    ),
  );
}

/// The colored number block used for activities.
class E6Chip extends StatelessWidget {
  final String text;
  final Color? fill;
  final Color? outline;
  const E6Chip(this.text, {super.key, this.fill, this.outline});
  @override
  Widget build(BuildContext context) => Container(
    width: 56,
    height: 30,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(6),
      border: outline != null ? Border.all(color: outline!, width: 1.5) : null,
    ),
    child: Text(
      text,
      style: E6T.num(17, color: fill == E6C.sleep ? E6C.base : E6C.ink),
    ),
  );
}

/// A round button: flat in Classic, glass in Liquid Glass.
class E6RoundButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const E6RoundButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: ValueListenableBuilder<bool>(
      valueListenable: E6Prefs.glass,
      builder: (context, glass, _) {
        final btn = SizedBox(
          width: 44,
          height: 44,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onTap,
              child: Icon(icon, color: E6C.ink, size: 22),
            ),
          ),
        );
        return glass
            ? E6Glass(radius: BorderRadius.circular(22), child: btn)
            : DecoratedBox(
                decoration: const BoxDecoration(
                  color: Color(0x14FFFFFF),
                  shape: BoxShape.circle,
                ),
                child: btn,
              );
      },
    ),
  );
}

/// Formats minutes as h:mm.
String e6Hm(num? min) {
  if (min == null) return '—';
  final m = min.round();
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
}

/// Formats a minute-of-day as a 12-hour clock time.
String e6Clock(num? minOfDay) {
  if (minOfDay == null) return '—';
  final m = minOfDay.round() % 1440;
  final h = m ~/ 60, mm = m % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${mm.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

String e6TimeOf(DateTime? t) =>
    t == null ? '—' : e6Clock(t.hour * 60 + t.minute);

String e6Num(num? v, {int digits = 0}) =>
    v == null ? '—' : v.toStringAsFixed(digits);

/// Everything the v6 screens show, read once per reload.
class E6Data {
  final HomeData home;
  final Map<String, dynamic> today;
  final List<double> recovery30;

  const E6Data(this.home, this.today, this.recovery30);

  num? get recovery => home.readiness.value;
  num? get strain => home.strain.value;
  num? get sleepMin => home.sleepMin.value;
  num? get needMin => home.sleepNeedMin.value;

  /// Sleep performance: hours slept against the computed need.
  num? get sleepPct {
    final s = sleepMin, n = needMin;
    if (s == null || n == null || n <= 0) return null;
    return (s / n * 100).clamp(0, 100);
  }

  num? get hrv {
    final b = today['hrv'];
    return b is Map ? b['rmssd'] as num? : null;
  }

  num? get resp => metricOf(today['resp']).value;
  num? get stress => metricOf(today['stress']).value;
  num? get spo2 => metricOf(today['spo2']).value;
  num? get skinTempDev {
    final b = today['skin_temp'];
    return b is Map ? b['dev_c'] as num? : null;
  }

  num? get efficiency {
    final s = today['sleep'];
    final e = s is Map ? (s['efficiency'] ?? s['sleep_efficiency']) : null;
    final v = e is Map ? metricOf(e).value : e as num?;
    if (v == null) return null;
    return v <= 1 ? v * 100 : v;
  }

  num? get targetLow => home.strainTarget?['low'] as num?;
  num? get targetHigh => home.strainTarget?['high'] as num?;

  static Future<E6Data> load(LocalRepository repo) async {
    final home = await HomeData.load(repo);
    final today = await repo.getToday();
    List<double> rec = const [];
    try {
      rec = [for (final p in pointsOf(await repo.getChart('recovery'))) p.v];
      if (rec.length > 30) rec = rec.sublist(rec.length - 30);
    } catch (_) {}
    return E6Data(home, today, rec);
  }
}

/// Push a screen on the root navigator.
Future<void> e6Push(BuildContext c, Widget w) =>
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));

/// Empty value used when a metric has not been computed yet.
const Metric e6None = Metric.empty;
