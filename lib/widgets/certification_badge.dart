import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Badge bleu de certification du compte, placé à côté du nom.
///
/// Alimenté par le champ `is_certified`, géré **exclusivement** par
/// l'administrateur Django. Un compte non certifié affiche simplement son
/// nom, sans badge. Aucun texte n'accompagne le badge.
class CertificationBadge extends StatelessWidget {
  const CertificationBadge({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Compte certifié',
      child: Icon(
        Icons.verified_rounded,
        size: size,
        color: AppColors.certification,
      ),
    );
  }
}

/// Nom d'un prestataire accompagné de son éventuel badge de certification.
///
/// `estCertifie` correspond au champ `is_certified` de l'API. Le composant
/// s'aligne sur la ligne de base du nom pour rester discret et propre.
class NameWithCertification extends StatelessWidget {
  const NameWithCertification({
    super.key,
    required this.name,
    required this.estCertifie,
    this.style,
    this.badgeSize = 16,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign,
  });

  final String name;
  final bool estCertifie;
  final TextStyle? style;
  final double badgeSize;
  final int maxLines;
  final TextOverflow overflow;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      name,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
    );
    if (!estCertifie) return text;

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: textAlign == TextAlign.center
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(child: text),
        SizedBox(width: badgeSize * 0.22),
        CertificationBadge(size: badgeSize),
      ],
    );
  }
}
