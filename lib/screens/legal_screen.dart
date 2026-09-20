import 'dart:ui';

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.onAccept});

  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context)),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverList.separated(
                itemCount: _sections.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final section = _sections[index];
                  return _LegalSection(
                    title: section.$1,
                    paragraphs: section.$2,
                  );
                },
              ),
            ),
            SliverToBoxAdapter(child: _buildAcceptButton(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF0FDF6), Color(0xFFE8F8F2)],
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.glassBorder,
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.glassShadow,
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_back_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Informations légales',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'Politique de confidentialité\net Conditions d’utilisation',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
                height: 1.2,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'ZWACOP',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAcceptButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: GestureDetector(
            onTap: () {
              Navigator.of(context).pop();
              onAccept();
            },
            child: Container(
              height: 52,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.35),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'J’accepte',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalSection extends StatelessWidget {
  const _LegalSection({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AppColors.glassShadow,
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradientSoft,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...paragraphs.map(
            (paragraph) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                paragraph,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.55,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const List<(String, List<String>)> _sections = [
  (
    '1. À propos de ZWACOP',
    [
      'ZWACOP est une plateforme qui met en relation les clients avec des prestataires de services.',
      'Le client peut rechercher un service, consulter les prestataires disponibles, voir leurs profils et réalisations, puis les contacter directement.',
    ],
  ),
  (
    '2. Données collectées',
    [
      'Pour permettre le fonctionnement de ZWACOP, nous pouvons collecter notamment :',
      '• Nom et postnom\n• Username\n• Adresse e-mail\n• Numéro de téléphone\n• Mot de passe\n• Photo/portrait de profil\n• Activité ou métier professionnel\n• Adresse ou zone d’intervention\n• Informations sur les services proposés\n• Carte d’identité ou autres documents nécessaires à la vérification\n• Photos des activités, travaux et réalisations professionnelles\n• Autres informations fournies volontairement par l’utilisateur',
    ],
  ),
  (
    '3. Utilisation des données',
    [
      'Ces informations peuvent être utilisées pour :',
      '• Créer et gérer votre compte\n• Permettre aux clients de trouver les prestataires\n• Présenter les services et réalisations des prestataires\n• Vérifier et sécuriser les comptes\n• Améliorer ZWACOP\n• Envoyer des notifications\n• Prévenir les fraudes et abus\n• Assurer la sécurité de la plateforme',
    ],
  ),
  (
    '4. Protection des données',
    [
      'Les données des utilisateurs sont protégées et administrées par LiviaTech, responsable du système ZWACOP.',
      'LiviaTech met en place des mesures de sécurité pour protéger les informations personnelles des utilisateurs contre les accès non autorisés, la perte, la modification ou la divulgation.',
      'Aucune plateforme connectée à Internet ne peut cependant garantir une sécurité absolue.',
    ],
  ),
  (
    '5. Responsabilité concernant les prestations',
    [
      'ZWACOP est une plateforme de mise en relation entre clients et prestataires.',
      'ZWACOP et LiviaTech ne sont pas responsables des désagréments, accidents, dommages, pertes, blessures, conflits, retards ou autres incidents pouvant survenir pendant ou à l’occasion d’une prestation entre un client et un prestataire.',
      'Le client et le prestataire sont responsables de leurs échanges, de leurs accords et de la prestation réalisée.',
    ],
  ),
  (
    '6. Abonnement des prestataires',
    [
      'L’abonnement est obligatoire pour chaque prestataire souhaitant utiliser les fonctionnalités professionnelles de ZWACOP.',
      'Les conditions, le prix et la durée de l’abonnement sont indiqués dans l’application.',
      'Le non-paiement ou l’expiration de l’abonnement peut entraîner la suspension des fonctionnalités du compte prestataire.',
    ],
  ),
  (
    '7. Contenus interdits',
    [
      'Il est strictement interdit de publier sur ZWACOP :',
      '• Des contenus pornographiques\n• Des nudités\n• Des contenus sexuels explicites\n• Des contenus illégaux\n• Des contenus frauduleux\n• Des contenus portant atteinte aux autres utilisateurs',
      'Tout compte qui publie volontairement des nudités ou des contenus pornographiques pourra être banni définitivement de ZWACOP.',
    ],
  ),
  (
    '8. Informations professionnelles',
    [
      'Chaque prestataire doit fournir des informations exactes concernant son métier, ses compétences et ses services.',
      'Les photos publiées doivent représenter, autant que possible, ses propres activités ou réalisations.',
      'Toute fausse information, usurpation d’identité ou fausse réalisation peut entraîner la suspension ou la suppression du compte.',
    ],
  ),
  (
    '9. Suspension ou suppression d’un compte',
    [
      'ZWACOP peut suspendre ou supprimer un compte en cas de :',
      '• Violation des présentes conditions\n• Fraude ou tentative de fraude\n• Publication de contenus interdits\n• Fausse identité ou fausses informations\n• Utilisation abusive de la plateforme\n• Comportement portant atteinte à la sécurité des utilisateurs\n• Non-respect des conditions d’abonnement',
      'Selon la gravité des faits, le compte peut être banni définitivement.',
    ],
  ),
  (
    '10. Suppression du compte',
    [
      'Un utilisateur peut demander la suppression de son compte selon les options disponibles dans l’application ou en contactant LiviaTech.',
      'Certaines données peuvent être conservées lorsque la loi l’exige ou lorsqu’elles sont nécessaires pour la sécurité, la prévention de la fraude ou la résolution d’un litige.',
    ],
  ),
  (
    '11. Modification des conditions',
    [
      'LiviaTech peut modifier la présente politique et les conditions d’utilisation afin de tenir compte de l’évolution de ZWACOP, de ses fonctionnalités ou des exigences légales.',
      'Les nouvelles conditions pourront être publiées dans l’application.',
    ],
  ),
  (
    '12. Contact',
    [
      'LiviaTech – Responsable du système ZWACOP',
      'E-mail : jb@liviatech.store\nSite : zwacop.app',
      'En créant un compte ou en utilisant ZWACOP, vous reconnaissez avoir pris connaissance de ces conditions et acceptez de les respecter.',
      'ZWACOP – Trouvez le bon prestataire au bon moment.',
    ],
  ),
];
