// The chosen look (see EdgeTheme in theme.dart): saved, and listened to by
// the app so a change repaints every screen.

import 'package:flutter/foundation.dart';

import '../state/prefs.dart';
import 'theme.dart';

class EdgeThemes {
  EdgeThemes._();
  static const themePrefKey = 'ui.theme';

  static final ValueNotifier<EdgeTheme> current =
      ValueNotifier<EdgeTheme>(_read());

  static EdgeTheme _read() {
    final s = Prefs.getString(themePrefKey, EdgeTheme.prism.name);
    return EdgeTheme.values.firstWhere((e) => e.name == s,
        orElse: () => EdgeTheme.prism);
  }

  static void load() => current.value = _read();

  static void set(EdgeTheme t) {
    current.value = t;
    Prefs.setString(themePrefKey, t.name);
  }
}
