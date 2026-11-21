// Line's signature: the day as a metro line on Today.
//
// The prayers are the stations, in order. Stations already passed sit on a
// gold stretch of line, "you are here" is pinned between the last one passed
// and the next, and a signage panel above counts down to the next stop, like
// a platform display. Only stations the app actually has times for appear.

import 'package:flutter/material.dart';

import 'skeleton/guide_plot.dart' show GuideDecoration;
import 'theme.dart';

class MetroStop {
  final String name;
  final DateTime at;

  /// A note beside the station ("Band buzzed 5:34").
  final String note;
  const MetroStop(this.name, this.at, {this.note = ''});
}

/// The signage panel: the next stop and how long until it.
class MetroSign extends StatelessWidget {
  final MetroStop next;
  final DateTime now;
  final String Function(DateTime) clock;
  const MetroSign(
      {super.key, required this.next, required this.now, required this.clock});

  @override
  Widget build(BuildContext c) {
    final left = next.at.difference(now);
    final mins = left.inMinutes.clamp(0, 24 * 60);
    final count = mins >= 60 ? '${mins ~/ 60} h ${mins % 60}' : '$mins';
    final unit = mins >= 60 ? 'min away' : 'minutes away';
    return Semantics(
      label: 'Next stop ${next.name} at ${clock(next.at)}, $count $unit',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x4),
          decoration: const BoxDecoration(
              color: LineTok.sign, borderRadius: R.rMetro),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  color: LineTok.lapis, borderRadius: R.rMd),
              child: Text(next.name.substring(0, 1),
                  style: F.head.copyWith(
                      color: LineTok.sign,
                      fontFamily: LineTok.display,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Next stop',
                        style: F.cap.copyWith(color: LineTok.signMute)),
                    Text('${next.name} ${clock(next.at)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: F.t2.copyWith(
                            color: LineTok.signInk,
                            fontFamily: LineTok.display,
                            fontWeight: FontWeight.w500)),
                  ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(count,
                  style: F.n24.copyWith(
                      color: LineTok.lapis,
                      fontFamily: LineTok.display,
                      fontWeight: FontWeight.w400)),
              Text(unit, style: F.over.copyWith(color: LineTok.signMute)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// The line itself: stations top to bottom, "you are here" between them.
class MetroDay extends StatelessWidget {
  final List<MetroStop> stops;
  final DateTime now;
  final String Function(DateTime) clock;
  const MetroDay(
      {super.key, required this.stops, required this.now, required this.clock});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final passed = stops.where((s) => !s.at.isAfter(now)).length;
    final rows = <Widget>[];
    for (var i = 0; i <= stops.length; i++) {
      if (i == passed) rows.add(_here(p));
      if (i < stops.length) {
        final s = stops[i];
        final state = i < passed ? 0 : (i == passed ? 1 : 2); // past, next, later
        rows.add(_station(p, s, state, first: i == 0, last: i == stops.length - 1 && passed < stops.length));
      }
    }
    return Semantics(
      label: 'Today\'s stations: ${[
        for (final s in stops) '${s.name} ${clock(s.at)}'
      ].join(', ')}',
      child: ExcludeSemantics(child: Column(children: rows)),
    );
  }

  static const _timeW = 62.0, _railW = 28.0, _rowH = 46.0;

  Widget _station(P p, MetroStop s, int state,
      {required bool first, required bool last}) {
    final gold = p.on(LineTok.lapis);
    final ink = switch (state) { 0 => p.ink2, 1 => gold, _ => p.ink };
    return SizedBox(
      height: _rowH,
      child: Row(children: [
        SizedBox(
          width: _timeW,
          child: Text(clock(s.at),
              textAlign: TextAlign.right,
              style: F.body.copyWith(
                  color: state == 1 ? gold : p.ink3,
                  fontFamily: LineTok.display)),
        ),
        const SizedBox(width: S.x2),
        SizedBox(
          width: _railW,
          height: _rowH,
          child: CustomPaint(
              painter: _Rail(
                  state: state,
                  first: first,
                  last: last,
                  gold: LineTok.lapis,
                  track: p.track,
                  knock: p.bgSolid,
                  later: p.ink3)),
        ),
        const SizedBox(width: S.x2),
        Text(s.name,
            style: F.head.copyWith(
                color: ink,
                fontFamily: LineTok.display,
                fontWeight: FontWeight.w500)),
        const Spacer(),
        if (s.note.isNotEmpty) Text(s.note, style: F.cap.copyWith(color: p.ink3)),
      ]),
    );
  }

  Widget _here(P p) => SizedBox(
        height: 32,
        child: Row(children: [
          const SizedBox(width: _timeW + S.x2),
          SizedBox(
            width: _railW,
            height: 32,
            child: CustomPaint(
                painter: _Pin(ink: p.ink, knock: p.bgSolid, gold: LineTok.lapis, track: p.track)),
          ),
          const SizedBox(width: S.x2),
          Text('You are here, ${clock(now)}',
              style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _Rail extends CustomPainter implements GuideDecoration {
  final int state;
  final bool first, last;
  final Color gold, track, knock, later;
  const _Rail(
      {required this.state,
      required this.first,
      required this.last,
      required this.gold,
      required this.track,
      required this.knock,
      required this.later});

  @override
  void paint(Canvas cv, Size s) {
    final cx = s.width / 2, cy = s.height / 2;
    final above = state == 0 ? gold : track;
    final below = state == 0 ? gold : track;
    final w = Paint()
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.butt;
    if (!first) cv.drawLine(Offset(cx, 0), Offset(cx, cy), w..color = above);
    if (!last) cv.drawLine(Offset(cx, cy), Offset(cx, s.height), w..color = below);
    cv.drawCircle(Offset(cx, cy), 9, Paint()..color = knock);
    switch (state) {
      case 0:
        cv.drawCircle(Offset(cx, cy), 6.5, Paint()..color = gold);
      case 1:
        cv.drawCircle(Offset(cx, cy), 9, Paint()..color = gold.withValues(alpha: .25));
        cv.drawCircle(Offset(cx, cy), 6, Paint()
          ..color = gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3);
      default:
        cv.drawCircle(Offset(cx, cy), 6, Paint()
          ..color = later
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
    }
  }

  @override
  bool shouldRepaint(_Rail o) =>
      o.state != state || o.first != first || o.last != last || o.knock != knock;
}

class _Pin extends CustomPainter implements GuideDecoration {
  final Color ink, knock, gold, track;
  const _Pin({required this.ink, required this.knock, required this.gold, required this.track});

  @override
  void paint(Canvas cv, Size s) {
    final cx = s.width / 2, cy = s.height / 2;
    final w = Paint()..strokeWidth = 6;
    cv.drawLine(Offset(cx, 0), Offset(cx, cy), w..color = gold);
    cv.drawLine(Offset(cx, cy), Offset(cx, s.height), w..color = track);
    cv.drawCircle(Offset(cx, cy), 14, Paint()..color = knock);
    cv.drawCircle(Offset(cx, cy), 11, Paint()..color = ink);
    cv.drawCircle(Offset(cx, cy), 4, Paint()..color = knock);
  }

  @override
  bool shouldRepaint(_Pin o) => o.ink != ink || o.knock != knock;
}
