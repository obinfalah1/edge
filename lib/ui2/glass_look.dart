// The chosen style (Original, Liquid Glass or Instrument): saved, and listened
// to by the app so a change rebuilds every screen through the theme (see
// [EdgeLook]).
import 'package:flutter/foundation.dart';

import '../state/prefs.dart';
import 'theme.dart';

class GlassLook {
  GlassLook._();
  static const styleKey = 'ui.style';

  static final ValueNotifier<EdgeStyle> style =
      ValueNotifier<EdgeStyle>(_read());

  static EdgeStyle _read() {
    final s = Prefs.getString(styleKey, '');
    for (final e in EdgeStyle.values) {
      if (e.name == s) return e;
    }
    // Before styles: the old Liquid Glass switch, if it was turned off,
    // meant the original look. Otherwise start in Instrument.
    return Prefs.getBool('ui.liquid_glass', true)
        ? EdgeStyle.instrument
        : EdgeStyle.original;
  }

  /// Re-read after prefs load (the notifier may be created before that).
  static void load() => style.value = _read();

  static void set(EdgeStyle s) {
    style.value = s;
    Prefs.setString(styleKey, s.name);
  }
}
