import 'package:eden_service_mobile/core/constants/locations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Villes couvertes', () {
    test('les 5 villes demandées sont présentes', () {
      expect(
        Locations.nomsVilles,
        containsAll(['Kinshasa', 'Goma', 'Beni', 'Lubumbashi', 'Butembo']),
      );
    });

    test('Goma, Beni, Lubumbashi et Butembo ont les bonnes communes', () {
      expect(Locations.communesDe('Goma'), ['Goma', 'Karisimbi']);
      expect(Locations.communesDe('Beni'), [
        'Beu',
        'Bungulu',
        'Mulekera',
        'Ruwenzori',
      ]);
      expect(Locations.communesDe('Lubumbashi'), [
        'Annexe',
        'Kamalondo',
        'Kampemba',
        'Katuba',
        'Kenya',
        'Lubumbashi',
        'Ruashi',
      ]);
      expect(Locations.communesDe('Butembo'), [
        'Bulengera',
        'Kimemi',
        'Mususa',
        'Vulamba',
      ]);
    });

    test('les 24 communes de Kinshasa sont conservées', () {
      final communes = Locations.communesDe('Kinshasa');
      expect(communes.length, 24);
      expect(communes, contains('Bandalungwa'));
      expect(communes, contains('N\'Sele'));
      expect(communes, contains('Selembao'));
      // Orthographe canonique (l'ancienne liste portait « Kimbaseke »).
      expect(communes, contains('Kimbanseke'));
      expect(communes, isNot(contains('Kimbaseke')));
    });
  });

  group('communesDe', () {
    test('insensible à la casse et aux espaces', () {
      expect(Locations.communesDe('kinshasa').length, 24);
      expect(Locations.communesDe('  GOMA  '), ['Goma', 'Karisimbi']);
    });

    test('liste vide pour une ville inconnue ou absente', () {
      expect(Locations.communesDe('Kolwezi'), isEmpty);
      expect(Locations.communesDe(''), isEmpty);
      expect(Locations.communesDe(null), isEmpty);
    });
  });

  group('communeAppartientA', () {
    test('accepte une commune de la bonne ville', () {
      expect(
        Locations.communeAppartientA(commune: 'Karisimbi', ville: 'Goma'),
        isTrue,
      );
      expect(
        Locations.communeAppartientA(commune: 'Ruashi', ville: 'Lubumbashi'),
        isTrue,
      );
    });

    test('refuse une commune d’une autre ville', () {
      expect(
        Locations.communeAppartientA(commune: 'Bandalungwa', ville: 'Goma'),
        isFalse,
      );
      // Limpete est à Lubumbashi, pas à Kinshasa.
      expect(
        Locations.communeAppartientA(commune: 'Kamalondo', ville: 'Kinshasa'),
        isFalse,
      );
    });

    test('insensible à la casse', () {
      expect(
        Locations.communeAppartientA(commune: 'KARISIMBI', ville: 'goma'),
        isTrue,
      );
    });

    test('refuse si ville ou commune absente', () {
      expect(Locations.communeAppartientA(commune: 'Goma', ville: null), isFalse);
      expect(
        Locations.communeAppartientA(commune: null, ville: 'Goma'),
        isFalse,
      );
    });
  });

  group('villeDeCommune', () {
    test('retourne la ville propriétaire', () {
      expect(Locations.villeDeCommune('Karisimbi'), 'Goma');
      expect(Locations.villeDeCommune('Mulekera'), 'Beni');
      expect(Locations.villeDeCommune('Katuba'), 'Lubumbashi');
      expect(Locations.villeDeCommune('Vulamba'), 'Butembo');
    });

    test('retourne null pour une commune inconnue', () {
      expect(Locations.villeDeCommune('Inconnue'), isNull);
      expect(Locations.villeDeCommune(null), isNull);
    });
  });

  group('villeValide', () {
    test('normalise la casse sur le nom de référence', () {
      // Données existantes en base : « kinshasa », « lubumbashi ».
      expect(Locations.villeValide('kinshasa'), 'Kinshasa');
      expect(Locations.villeValide('LUBUMBASHI'), 'Lubumbashi');
    });

    test('conserve une ville hors liste pour ne rien perdre', () {
      expect(Locations.villeValide('Lubumbashi / Kolwezi'), 'Lubumbashi / Kolwezi');
    });

    test('retourne null si absente', () {
      expect(Locations.villeValide(null), isNull);
      expect(Locations.villeValide('  '), isNull);
    });
  });

  group('Isolation des listes', () {
    test('chaque ville a ses propres communes (aucun mélange)', () {
      for (final v in Locations.villes) {
        for (final c in Locations.communesDe(v.nom)) {
          // Une commune ne doit appartenir qu'à une seule ville.
          final owners = Locations.villes
              .where((autre) =>
                  Locations.communeAppartientA(commune: c, ville: autre.nom))
              .map((autre) => autre.nom)
              .toList();
          expect(owners, [v.nom], reason: '$c de ${v.nom} est ambiguë');
        }
      }
    });

    test('les communes sont uniques dans une même ville', () {
      for (final v in Locations.villes) {
        expect(
          v.communes.toSet().length,
          v.communes.length,
          reason: 'doublon dans ${v.nom}',
        );
      }
    });
  });
}
