import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../l10n/app_localizations.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'guide_catalogue.dart';
import 'help_screen.dart';
import '../profile/profile.dart' show ProfileAvatar;

export 'guide_catalogue.dart' show GuideTopic;

/// The last item in a tab's scroll content, so Help never covers a card.
class HelpEntry extends StatelessWidget {
  final GuideTopic topic;
  const HelpEntry({super.key, required this.topic});

  void _open(BuildContext context) {
    final band = bandGenerationOf(context.read<AppState>().paired);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HelpScreen(topic: topic, band: band),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final label = (AppLocalizations.of(context) ??
            lookupAppLocalizations(const Locale('en')))
        .helpLookingForSomething;
    // Glass and Line: search lives in the title row ([HeaderActions]), one
    // tap from the top of every tab, so the foot of the page carries nothing.
    if (p.glass || p.metro) return const SizedBox.shrink();
    if (p.glass || p.metro) {
      return Padding(
        padding: const EdgeInsets.only(top: S.x4),
        child: Pressable(
          onTap: () => _open(context),
          semanticLabel: label,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            decoration: BoxDecoration(color: p.card, borderRadius: R.rPill),
            child: Row(children: [
              Icon(LucideIcons.search, size: 16, color: p.ink3),
              const SizedBox(width: S.x2),
              Text('Search features', style: F.body.copyWith(color: p.ink3)),
            ]),
          ),
        ),
      );
    }
    return _plain(context);
  }

  Widget _plain(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: S.x4),
    child: SizedBox(
      width: double.infinity,
      child: TextButton(
        style: TextButton.styleFrom(
          foregroundColor: P.of(context).ink3,
          minimumSize: const Size(0, 48),
          textStyle: F.cap,
        ),
        onPressed: () {
          final band = bandGenerationOf(context.read<AppState>().paired);
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => HelpScreen(topic: topic, band: band),
            ),
          );
        },
        child: Text(
          (AppLocalizations.of(context) ??
                  lookupAppLocalizations(const Locale('en')))
              .helpLookingForSomething,
        ),
      ),
    ),
  );
}


/// The top-right of a tab: search (Line and Glass) and the profile avatar.
/// Search opens the same feature search the foot of the page used to.
class HeaderActions extends StatelessWidget {
  final GuideTopic topic;
  final Color accent;
  const HeaderActions({super.key, required this.topic, required this.accent});

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    if (!(p.glass || p.metro)) return ProfileAvatar(accent: accent);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Pressable(
        semanticLabel: 'Search features',
        onTap: () {
          final band = bandGenerationOf(context.read<AppState>().paired);
          Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => HelpScreen(topic: topic, band: band)));
        },
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: p.card, border: Border.all(color: p.line)),
          child: Icon(LucideIcons.search, size: 18, color: p.ink2),
        ),
      ),
      const SizedBox(width: S.x2),
      ProfileAvatar(accent: accent),
    ]);
  }
}
