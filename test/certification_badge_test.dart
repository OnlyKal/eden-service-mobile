import 'package:eden_service_mobile/core/models/prestataire_models.dart';
import 'package:eden_service_mobile/theme/app_colors.dart';
import 'package:eden_service_mobile/widgets/certification_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Payload minimal d'un prestataire, enrichi des champs testés.
Map<String, dynamic> prestataireJson({
  bool isCertified = false,
  bool estValide = true,
}) {
  return {
    'id': 1,
    'utilisateur': {
      'id': 10,
      'username': 'jean',
      'email': 'jean@test.cd',
      'first_name': 'Jean',
      'last_name': 'Kabasele',
      'est_prestataire': true,
      'statut_compte': 'actif',
      'date_joined': '2026-01-01T00:00:00Z',
    },
    'type_service': 'Plombier',
    'services': <dynamic>[],
    'presentation': '',
    'commune': 'Gombe',
    'ville': 'Kinshasa',
    'est_valide': estValide,
    'is_certified': isCertified,
    'is_available': true,
  };
}

void main() {
  group('Lecture du champ is_certified', () {
    test('is_certified = true est lu', () {
      final p = Prestataire.fromJson(prestataireJson(isCertified: true));
      expect(p.isCertified, isTrue);
    });

    test('is_certified = false est lu', () {
      final p = Prestataire.fromJson(prestataireJson(isCertified: false));
      expect(p.isCertified, isFalse);
    });

    test('champ absent : false par défaut, aucun crash', () {
      final json = prestataireJson()..remove('is_certified');
      expect(Prestataire.fromJson(json).isCertified, isFalse);
    });

    test('is_certified est indépendant de est_valide', () {
      // Validé mais non certifié, et l'inverse.
      final valideNonCertifie = Prestataire.fromJson(
        prestataireJson(estValide: true, isCertified: false),
      );
      expect(valideNonCertifie.estValide, isTrue);
      expect(valideNonCertifie.isCertified, isFalse);

      final certifieNonValide = Prestataire.fromJson(
        prestataireJson(estValide: false, isCertified: true),
      );
      expect(certifieNonValide.estValide, isFalse);
      expect(certifieNonValide.isCertified, isTrue);
    });

    test('copyWith conserve la certification', () {
      final p = Prestataire.fromJson(
        prestataireJson(isCertified: true),
      ).copyWith(isAvailable: false);
      expect(p.isCertified, isTrue);
    });
  });

  group('CertificationBadge', () {
    testWidgets('icône bleue, sans texte', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: CertificationBadge(size: 18)),
        ),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, AppColors.certification);
      expect(icon.size, 18);
      expect(find.textContaining('Certifi'), findsNothing);
    });
  });

  group('NameWithCertification', () {
    testWidgets('certifié : nom + badge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NameWithCertification(
              name: 'Jean Kabasele',
              estCertifie: true,
            ),
          ),
        ),
      );
      expect(find.text('Jean Kabasele'), findsOneWidget);
      expect(find.byType(CertificationBadge), findsOneWidget);
    });

    testWidgets('non certifié : nom seul, aucun badge', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NameWithCertification(
              name: 'Marie Kabongo',
              estCertifie: false,
            ),
          ),
        ),
      );
      expect(find.text('Marie Kabongo'), findsOneWidget);
      expect(find.byType(CertificationBadge), findsNothing);
    });

    testWidgets('nom long : pas de débordement', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 150,
              child: NameWithCertification(
                name: 'Jean-Baptiste Kabasele Mulumba',
                estCertifie: true,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
