// Copy for the personal additions (prayer buzzes, Healthspan, Apple on-device
// AI). English and Arabic only, side by side at the call site, so they stay out
// of the eight-language ARB set and its coverage tests.
import 'package:flutter/widgets.dart';

bool isArabic(BuildContext c) =>
    Localizations.maybeLocaleOf(c)?.languageCode == 'ar';

/// [en] or, when the app runs in Arabic, [ar].
String tr(BuildContext c, String en, String ar) => isArabic(c) ? ar : en;
