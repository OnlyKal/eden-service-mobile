import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Texte long replié sur [collapsedMaxLines], avec un bouton « Voir plus ».
///
/// Le nombre de lignes est mesuré à la volée : le bouton n'apparaît que si le
/// texte est réellement tronqué, ce qui évite d'afficher « Voir plus » sur une
/// description courte. L'ouverture et la fermeture sont animées.
class ExpandableText extends StatefulWidget {
  const ExpandableText({
    super.key,
    required this.text,
    this.collapsedMaxLines = 4,
    this.style,
  });

  final String text;
  final int collapsedMaxLines;
  final TextStyle? style;

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool _expanded = false;

  /// Style par défaut repris de l'affichage d'origine de la description.
  static const TextStyle _defaultStyle = TextStyle(
    fontSize: 14,
    color: AppColors.textSecondary,
    height: 1.6,
  );

  TextStyle get _style => widget.style ?? _defaultStyle;

  /// Mesure le texte à la largeur disponible pour savoir s'il est tronqué.
  bool _isTruncated(double maxWidth) {
    if (!maxWidth.isFinite || maxWidth <= 0) return false;
    final painter = TextPainter(
      text: TextSpan(text: widget.text, style: _style),
      maxLines: widget.collapsedMaxLines,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxWidth);
    final truncated = painter.didExceedMaxLines;
    painter.dispose();
    return truncated;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final truncated = _isTruncated(constraints.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Text(
                widget.text,
                style: _style,
                maxLines: _expanded ? null : widget.collapsedMaxLines,
                overflow: _expanded
                    ? TextOverflow.clip
                    : TextOverflow.ellipsis,
              ),
            ),
            if (truncated)
              _ExpandToggle(
                expanded: _expanded,
                onTap: () => setState(() => _expanded = !_expanded),
              ),
          ],
        );
      },
    );
  }
}

class _ExpandToggle extends StatelessWidget {
  const _ExpandToggle({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.only(top: 8, right: 8, bottom: 2, left: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              expanded ? 'Voir moins' : 'Voir plus',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            SizedBox(width: 2),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: AppColors.primary,
                size: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
