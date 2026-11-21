// The dark Liquid Glass background: slow, drifting fields of deep colour
// behind every page, so the glass cards have something to sit over.
//
// One per route (painted under the page by the theme's page transition, see
// `_Gated` in theme.dart), all reading the same wall clock so a push or pop
// never shows two backgrounds out of step. Static when the user has asked for
// reduced motion.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'theme.dart';

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
            child: CustomPaint(painter: _Fields(_t)),
          ),
        ),
        widget.child,
      ]);
}

/// Four deep colour fields on slow, unrelated orbits over black.
class _Fields extends CustomPainter {
  final ValueNotifier<double> t;
  _Fields(this.t) : super(repaint: t);

  static const _fields = <(Color, double, double, double, double)>[
    // colour, x-speed, y-speed, phase, size (fraction of the long side)
    (Color(0xFF16205C), .021, .017, 0.0, .75), // deep indigo
    (Color(0xFF0A3A3E), .016, .023, 1.7, .70), // deep teal
    (Color(0xFF2E1040), .019, .013, 3.1, .65), // deep plum
    (Color(0xFF0A2247), .013, .019, 4.6, .70), // midnight blue
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF000000));
    final long = math.max(size.width, size.height);
    final s = t.value;
    for (final (colour, sx, sy, ph, k) in _fields) {
      final cx = size.width * (.5 + .45 * math.sin(s * sx * 2 * math.pi + ph));
      final cy = size.height * (.5 + .45 * math.cos(s * sy * 2 * math.pi + ph * 1.3));
      final r = long * k;
      canvas.drawRect(
        rect,
        Paint()
          // Dark fields over black: they layer, but never add up to bright.
          ..shader = RadialGradient(
            colors: [colour.withValues(alpha: .7), colour.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(_Fields old) => false;
}
