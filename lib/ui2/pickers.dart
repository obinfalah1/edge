// The time picker, the iPhone way.
//
// On iOS a time is picked on the wheel in a bottom sheet (Cancel / Done), as
// Clock and Calendar do; Material's clock dial is an Android control. Other
// platforms keep `showTimePicker`. Same arguments and result as
// `showTimePicker`, so call sites only change the name.

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'theme.dart';

Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String? helpText,
}) {
  if (defaultTargetPlatform != TargetPlatform.iOS) {
    return showTimePicker(
        context: context, initialTime: initialTime, helpText: helpText);
  }
  final now = DateTime.now();
  var picked = DateTime(
      now.year, now.month, now.day, initialTime.hour, initialTime.minute);
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    showDragHandle: false,
    sheetAnimationStyle: sheetMotion(context),
    builder: (sheet) {
      final p = P.of(sheet);
      final mat = MaterialLocalizations.of(sheet);
      final l = AppLocalizations.of(sheet);
      final title = helpText == null
          ? null
          : helpText[0] + helpText.substring(1).toLowerCase();
      return SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x2, 0),
            child: Row(children: [
              TextButton(
                onPressed: () => Navigator.pop(sheet),
                child: Text(_sentence(mat.cancelButtonLabel)),
              ),
              Expanded(
                child: Text(title ?? '',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.head.copyWith(color: p.ink)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(
                    sheet, TimeOfDay(hour: picked.hour, minute: picked.minute)),
                child: Text(l?.actionDone ?? 'Done',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ]),
          ),
          SizedBox(
            height: 216,
            child: CupertinoTheme(
              data: CupertinoThemeData(
                brightness: p.dark ? Brightness.dark : Brightness.light,
              ),
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                initialDateTime: picked,
                use24hFormat: MediaQuery.alwaysUse24HourFormatOf(sheet),
                onDateTimeChanged: (d) => picked = d,
              ),
            ),
          ),
        ]),
      );
    },
  );
}

/// Material spells some labels in capitals (CANCEL); iOS uses sentence case.
String _sentence(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();
