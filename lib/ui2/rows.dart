// Grouped list rows for the Line and Liquid Glass styles.
//
// One row shape for every "label, value, chevron" line on Today, Sleep,
// Activity, Health and the detail screens, so a reader learns it once:
// a small icon tile, the title with an optional one-line sub, the figure on
// the right and a chevron when the row opens something. [RowGroup] stacks
// them in one card split by hairlines (iOS inset grouped list).
//
// At large text sizes the figure moves under the title instead of squeezing
// it, the way Apple's own lists reflow.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'charts.dart' show LineTrack;
import 'grammar.dart';
import 'theme.dart';

/// "6 h 42" / "42 min": hours and minutes set like a timetable.
String hmSpaced(num min) {
  final m = min.round();
  if (m < 60) return '$m min';
  return '${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';
}

/// Rows in one card, split by hairlines.
class RowGroup extends StatelessWidget {
  final List<Widget> children;
  const RowGroup(this.children, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final kids = [for (final w in children) if (w is! SizedBox) w];
    return Surface(
      pad: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < kids.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.only(left: S.x4),
              child: SizedBox(
                  height: 1, width: double.infinity, child: ColoredBox(color: p.line)),
            ),
          kids[i],
        ],
      ]),
    );
  }
}

/// The small icon tile a row leads with. Line keeps it neutral (colour is
/// for data and gold for prayer); Glass tints it with its one accent.
Widget rowLead(BuildContext c, IconData icon, {Color? color}) {
  final p = P.of(c);
  final ink = color ?? (p.glass ? p.on(p.tint) : p.ink2);
  return Container(
    width: 30,
    height: 30,
    alignment: Alignment.center,
    decoration: BoxDecoration(
        color: p.glass ? p.wash(color ?? p.tint) : p.card2,
        borderRadius: R.rSm),
    child: Icon(icon, size: 17, color: ink),
  );
}

/// One list row.
class ListRow extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final Widget? leading;
  final String title;
  final String? sub;

  /// The figure on the right, set in the figure face, and its unit.
  final String? value;
  final String? unit;

  /// Plain text on the right (a setting's current choice).
  final String? detail;

  /// Anything else on the right (a switch).
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;

  const ListRow({
    super.key,
    this.icon,
    this.iconColor,
    this.leading,
    required this.title,
    this.sub,
    this.value,
    this.unit,
    this.detail,
    this.trailing,
    this.onTap,
    bool? chevron,
  }) : chevron = chevron ?? onTap != null;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final big = bigText(c);
    final fig = value == null
        ? null
        : Text.rich(
            TextSpan(children: [
              TextSpan(text: value, style: F.n24.copyWith(color: p.ink)),
              if (unit != null && unit!.isNotEmpty)
                TextSpan(text: ' $unit', style: F.cap.copyWith(color: p.ink3)),
            ]),
            softWrap: false,
          );
    final det = detail == null
        ? null
        : Text(detail!, style: F.body.copyWith(color: p.ink3), softWrap: false);
    final right = <Widget>[
      if (!big && fig != null) fig,
      if (!big && det != null) det,
      ?trailing,
      if (chevron) ...[
        const SizedBox(width: S.x1),
        Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
      ],
    ];
    final lead = leading ?? (icon == null ? null : rowLead(c, icon!, color: iconColor));
    return Pressable(
      onTap: onTap,
      semanticLabel: [title, ?sub, if (value != null) '$value${unit == null ? '' : ' $unit'}', ?detail]
          .join(', '),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
          child: Row(children: [
            if (lead != null) ...[lead, const SizedBox(width: S.x3)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: F.body.copyWith(color: p.ink)),
                if (sub != null && sub!.isNotEmpty)
                  Text(sub!, style: F.cap.copyWith(color: p.ink3)),
                if (big && fig != null) fig,
                if (big && det != null) det,
              ]),
            ),
            if (right.isNotEmpty) ...[const SizedBox(width: S.x3), ...right],
          ]),
        ),
      ),
    );
  }
}

/// A score or a "so far" count with its track: "Recovery, 2 of 14 nights",
/// then the track, then one plain line. Learning tracks are drawn as stops.
class TrackRow extends StatelessWidget {
  final String title;
  final String value;
  final String? unit;
  final double fill;
  final int? stops;
  final Color color;
  final String? note;
  final VoidCallback? onTap;
  final bool first;
  const TrackRow({
    super.key,
    required this.title,
    required this.value,
    this.unit,
    required this.fill,
    this.stops,
    required this.color,
    this.note,
    this.onTap,
    this.first = true,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final big = bigText(c);
    final fig = Text.rich(
      TextSpan(children: [
        TextSpan(text: value, style: F.n24.copyWith(color: p.ink)),
        if (unit != null) TextSpan(text: ' $unit', style: F.cap.copyWith(color: p.ink3)),
      ]),
    );
    final label = Text(title, style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600));
    return Pressable(
      onTap: onTap,
      semanticLabel: '$title, $value${unit == null ? '' : ' $unit'}${note == null ? '' : '. $note'}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
        decoration: first
            ? null
            : BoxDecoration(border: Border(top: BorderSide(color: p.line))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (big) ...[label, fig]
          else
            Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic, children: [
              label,
              const Spacer(),
              fig,
              if (onTap != null) ...[
                const SizedBox(width: S.x1),
                Icon(LucideIcons.chevronRight, size: 16, color: p.ink3),
              ],
            ]),
          const SizedBox(height: S.x2),
          SizedBox(
            height: 14,
            width: double.infinity,
            child: CustomPaint(
              painter: LineTrack(
                  fill: fill, stops: stops, color: color, track: p.track, knock: p.card),
            ),
          ),
          if (note != null && note!.isNotEmpty) ...[
            const SizedBox(height: S.x1),
            Text(note!, style: F.cap.copyWith(color: p.ink3)),
          ],
        ]),
      ),
    );
  }
}

/// A light haptic for a primary action, a selection tick for a choice. Kept
/// here so screens ask for a kind of feedback, never a raw vibration.
void tapHaptic() => HapticFeedback.lightImpact();
void selectHaptic() => HapticFeedback.selectionClick();
void successHaptic() => HapticFeedback.mediumImpact();

/// The one filled button: gold with sign ink in Line, the look's accent in
/// Glass. Feedback on press, a light haptic on tap.
class PrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  const PrimaryButton(this.label, {super.key, this.icon, this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final bg = p.metro ? LineTok.lapis : (p.dark ? p.tint : p.fill(p.tint));
    final ink = p.metro ? LineTok.sign : (p.dark ? C.onAccent : p.inkOnFill);
    return Pressable(
      semanticLabel: label,
      onTap: onTap == null
          ? null
          : () {
              tapHaptic();
              onTap!();
            },
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
        decoration: BoxDecoration(color: bg, borderRadius: R.rPill),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 18, color: ink), const SizedBox(width: S.x2)],
          Flexible(
            child: Text(label,
                textAlign: TextAlign.center,
                style: F.body.copyWith(color: ink, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

/// The quiet partner of [PrimaryButton]: the card colour and the page ink.
class SecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  const SecondaryButton(this.label, {super.key, this.icon, this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      pad: EdgeInsets.zero,
      onTap: onTap == null
          ? null
          : () {
              tapHaptic();
              onTap!();
            },
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 18, color: p.ink), const SizedBox(width: S.x2)],
          Flexible(
            child: Text(label,
                textAlign: TextAlign.center,
                style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

/// Glass's learning ring: [need] beads around a circle, [have] of them lit,
/// the same shape the rings on Today draw while learning.
class SegmentRing extends CustomPainter {
  final int have, need;
  final Color color, track;
  final double stroke;
  const SegmentRing(this.have, this.need, this.color, this.track, {this.stroke = 8});

  @override
  void paint(Canvas cv, Size s) {
    if (need <= 0) return;
    final r = (s.shortestSide - stroke) / 2;
    final rect = Rect.fromCircle(center: s.center(Offset.zero), radius: r);
    const gap = 0.07;
    final seg = 2 * 3.141592653589793 / need;
    for (var i = 0; i < need; i++) {
      cv.drawArc(
          rect,
          -3.141592653589793 / 2 + i * seg + gap / 2,
          seg - gap,
          false,
          Paint()
            ..color = i < have ? color : track
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(SegmentRing o) =>
      o.have != have || o.need != need || o.color != color || o.track != track;
}
