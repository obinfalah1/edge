// app_icon.dart — the Dart side of the `openstrap/app_icon` method channel:
// which icon the home screen shows.
//
// iOS only, deliberately. `setAlternateIconName` is a supported API that costs
// the user one unavoidable system alert per change. Android has no equivalent:
// the only way is to enable one `<activity-alias>` and disable another with
// `PackageManager.setComponentEnabledSetting`, which on most launchers removes
// the app from the home screen and back again, drops any user-placed shortcut,
// and kills the running task. That is a worse outcome than not offering the
// choice, so [available] answers false there and the settings row is not drawn
// rather than drawn and dead.
//
// iOS owns the state. Nothing is mirrored into prefs: [current] reads
// `UIApplication.alternateIconName` every time, so the app cannot end up
// disagreeing with the home screen (a change made from a restored backup, or a
// failed set, would leave a stored preference lying).

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The icons compiled into the iOS asset catalog. The wire names are the
/// `.appiconset` names — `null` is the primary icon, the plain Orbit.
enum AppIconChoice {
  orbit(null, 'Orbit'),
  orbitGlass('AppIconGlass', 'Orbit Glass'),
  orbitTinted('AppIconTinted', 'Orbit Tinted');

  const AppIconChoice(this.wireName, this.label);

  final String? wireName;
  final String label;

  String get asset => switch (this) {
    AppIconChoice.orbit => 'assets/images/icon_orbit.png',
    AppIconChoice.orbitGlass => 'assets/images/icon_orbit_glass.png',
    AppIconChoice.orbitTinted => 'assets/images/icon_orbit_tinted.png',
  };

  /// An icon iOS reports that is not one of these (the older black-and-white
  /// one) reads as the main icon, so picking one always moves off it.
  static AppIconChoice fromWireName(String? name) => AppIconChoice.values
      .firstWhere((c) => c.wireName == name, orElse: () => AppIconChoice.orbit);
}

class AppIcon {
  static const _ch = MethodChannel('openstrap/app_icon');

  /// Whether this device can change its home-screen icon at all. False off
  /// iOS, and false on the managed configurations where iOS refuses.
  static Future<bool> available() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      return await _ch.invokeMethod<bool>('available') ?? false;
    } catch (e) {
      debugPrint('[app_icon] available failed: $e');
      return false;
    }
  }

  /// What the home screen is showing right now, straight from iOS.
  static Future<AppIconChoice> current() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return AppIconChoice.orbit;
    }
    try {
      return AppIconChoice.fromWireName(
        await _ch.invokeMethod<String>('current'),
      );
    } catch (e) {
      debugPrint('[app_icon] current failed: $e');
      return AppIconChoice.orbit;
    }
  }

  /// Ask iOS to switch. Returns false if it refused — the caller must not
  /// redraw as if it had worked. iOS shows its own confirmation alert.
  static Future<bool> set(AppIconChoice choice) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      return await _ch.invokeMethod<bool>('set', {'name': choice.wireName}) ??
          false;
    } catch (e) {
      debugPrint('[app_icon] set(${choice.name}) failed: $e');
      return false;
    }
  }
}
