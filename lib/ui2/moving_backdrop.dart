// The Liquid Glass background: slow, drifting fields of colour behind every
// page, so the glass cards have something to sit over. The colours come from
// the tone (Sky in theme.dart).
//
// One per route (painted under the page by the theme's page transition, see
// `_Gated` in theme.dart), all reading the same wall clock so a push or pop
// never shows two backgrounds out of step. Static when the user has asked for
// reduced motion.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'theme.dart';
import 'skeleton/guide_plot.dart' show GuideDecoration;

class MovingBackdrop extends StatefulWidget {
  final Widget child;
  const MovingBackdrop({super.key, required this.child});

  @override
  State<MovingBackdrop> createState() => _MovingBackdropState();
}

class _MovingBackdropState extends State<MovingBackdrop>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _t = ValueNotifier(_now());

  /// Seconds on the wall clock, shared by every backdrop.
  static double _now() => DateTime.now().millisecondsSinceEpoch / 1000.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _t.value = _now());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = Motion.enabled(context);
    if (animate && !_ticker.isActive) _ticker.start();
    if (!animate && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Stack(fit: StackFit.passthrough, children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(painter: _Fields(_t, P.of(c))),
          ),
        ),
        widget.child,
      ]);
}

/// Four colour fields on slow, unrelated orbits over the look's base.
class _Fields extends CustomPainter implements GuideDecoration {
  final ValueNotifier<double> t;
  final P p;
  _Fields(this.t, this.p) : super(repaint: t);

  static const _orbits = <(double, double, double, double)>[
    // x-speed, y-speed, phase, size (fraction of the long side)
    (.021, .017, 0.0, .75),
    (.016, .023, 1.7, .70),
    (.019, .013, 3.1, .65),
    (.013, .019, 4.6, .70),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final sky = skyFor(p.look, p.tone);
    canvas.drawRect(rect, Paint()..color = sky.base);
    final long = math.max(size.width, size.height);
    final s = t.value;
    for (var i = 0; i < _orbits.length; i++) {
      final (sx, sy, ph, k) = _orbits[i];
      final colour = sky.fields[i];
      final cx = size.width * (.5 + .45 * math.sin(s * sx * 2 * math.pi + ph));
      final cy = size.height * (.5 + .45 * math.cos(s * sy * 2 * math.pi + ph * 1.3));
      final r = long * k;
      canvas.drawRect(
        rect,
        Paint()
          // Fields layer, but never add up past the colour itself.
          ..shader = RadialGradient(
            colors: [
              colour.withValues(alpha: MovingFields.alpha),
              colour.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_Fields old) =>
      old.p.look != p.look || old.p.tone != p.tone;
}
