import 'package:eden_service_mobile/core/models/prestataire_models.dart';
import 'package:eden_service_mobile/core/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _prestataireJson({Object? distance}) => {
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
  'type_service': 'Plomberie',
  'services': <dynamic>[],
  'presentation': '',
  'commune': 'Gombe',
  'ville': 'Kinshasa',
  'est_valide': true,
  'is_available': true,
  'missions_reussies': 12,
  if (distance != null) 'distance_km': distance,
};

void main() {
  group('formatDistance', () {
    test('affiche les mètres sous 1 km', () {
      expect(formatDistance(0.02), 'à moins de 50 m');
      expect(formatDistance(0.347), 'à 350 m');
      expect(formatDistance(0.998), 'à 1 km');
    });

    test('affiche les km avec une décimale sous 10 km', () {
      expect(formatDistance(1), 'à 1 km');
      expect(formatDistance(2.36), 'à 2,4 km');
      expect(formatDistance(9.96), 'à 10 km');
    });

    test('arrondit au km au-delà de 10 km', () {
      expect(formatDistance(15.4), 'à 15 km');
    });
  });

  group('Prestataire.distanceKm', () {
    test('lit la distance renvoyée par le serveur', () {
      expect(
        Prestataire.fromJson(_prestataireJson(distance: 1.109)).distanceKm,
        1.109,
      );
    });

    test('reste null sans distance et survit à copyWith', () {
      final sans = Prestataire.fromJson(_prestataireJson());
      expect(sans.distanceKm, isNull);
      expect(sans.missionsReussies, 12);
      final avec = Prestataire.fromJson(_prestataireJson(distance: 2.5));
      expect(avec.copyWith(isAvailable: false).distanceKm, 2.5);
    });
  });
}
