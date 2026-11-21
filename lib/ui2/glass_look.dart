// The Liquid Glass switch: on by default, saved, and listened to by the app
// so flipping it rebuilds every screen through the theme (see [EdgeLook]).
import 'package:flutter/foundation.dart';

import '../state/prefs.dart';

class GlassLook {
  GlassLook._();

  static final ValueNotifier<bool> enabled =
      ValueNotifier<bool>(Prefs.getBool('ui.liquid_glass', true));

  /// Re-read after prefs load (the notifier may be created before that).
  static void load() => enabled.value = Prefs.getBool('ui.liquid_glass', true);

  static void set(bool on) {
    enabled.value = on;
    Prefs.setBool('ui.liquid_glass', on);
  }
}
