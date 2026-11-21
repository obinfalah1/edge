// Settings › Color (Liquid Glass): the five colours as small live previews, each a tiny page
// of its own backdrop with a glass card on it, so the choice is made by
// seeing it rather than by reading a name.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'grammar.dart';
import 'theme.dart';

class ThemePickerRow extends StatelessWidget {
  final EdgeTheme chosen;
  final ValueChanged<EdgeTheme> onPick;
  const ThemePickerRow({super.key, required this.chosen, required this.onPick});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.wash(p.tint), borderRadius: R.rSm),
            child: Icon(LucideIcons.palette, size: 16, color: p.on(p.tint)),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Color', style: F.body.copyWith(color: p.ink)),
              Text(chosen.blurb, style: F.over.copyWith(color: p.ink3)),
            ]),
          ),
        ]),
        const SizedBox(height: S.x3),
        Wrap(spacing: S.x2, runSpacing: S.x3, children: [
          for (final t in EdgeTheme.values)
            _ThemeChoice(look: t, selected: t == chosen, onTap: () => onPick(t)),
        ]),
      ]),
    );
  }
}

class _ThemeChoice extends StatelessWidget {
  final EdgeTheme look;
  final bool selected;
  final VoidCallback onTap;
  const _ThemeChoice(
      {required this.look, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final sky = skyFor(look, p.tone);
    final ring = selected ? p.on(look.tint) : p.line;
    return Pressable(
      onTap: onTap,
      semanticLabel: '${look.label} colour. ${look.blurb}.'
          '${selected ? ' Selected.' : ''}',
      child: SizedBox(
        width: 58,
        child: Column(children: [
          Container(
            width: 58,
            height: 78,
            padding: const EdgeInsets.all(S.x1 / 2),
            decoration: BoxDecoration(
              borderRadius: R.rMd,
              border: Border.all(color: ring, width: selected ? 2 : 1),
            ),
            child: ClipRRect(
              borderRadius: R.rSm,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [sky.fields[0], sky.base, sky.fields[2]],
                  ),
                ),
                child: Stack(children: [
                  // A glass card and the look's tint as a pill, in miniature.
                  Positioned(
                    left: 6,
                    right: 6,
                    top: 10,
                    height: 26,
                    child: DecoratedBox(
                      decoration: glassDecoration(p,
                          radius: R.rSm, shadow: const []),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 8,
                    height: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                          color: look.tint, borderRadius: R.rPill),
                    ),
                  ),
                  if (selected)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Icon(LucideIcons.circleCheck,
                          size: 14, color: look.tint),
                    ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: S.x1),
          Text(look.label,
              style: F.over.copyWith(
                  color: selected ? p.ink : p.ink3,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }
}
