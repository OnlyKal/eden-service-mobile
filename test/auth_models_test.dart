import 'package:eden_service_mobile/core/models/auth_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoginResponse.fromJson — enveloppes d’erreur', () {
    test('lit error.message (compte bloqué / identifiants invalides)', () {
      // Enveloppe réelle renvoyée par l'API en cas de refus.
      final response = LoginResponse.fromJson({
        'success': false,
        'error': {
          'code': 'INVALID_CREDENTIALS',
          'message':
              "Nom d'utilisateur, email, téléphone ou mot de passe invalide",
        },
        'status_code': 401,
      });

      expect(response.success, isFalse);
      expect(
        response.message,
        "Nom d'utilisateur, email, téléphone ou mot de passe invalide",
      );
      expect(response.statusCode, 401);
    });

    test('ne lève pas d’erreur de cast sans message', () {
      final response = LoginResponse.fromJson({
        'success': false,
        'error': {'code': 'ACCOUNT_INACTIVE'},
        'status_code': 403,
      });

      expect(response.success, isFalse);
      expect(response.message, isNotEmpty);
      expect(response.statusCode, 403);
    });

    test('lit detail (format DRF)', () {
      final response = LoginResponse.fromJson({
        'success': false,
        'detail': 'Token non valide.',
        'status_code': 401,
      });

      expect(response.message, 'Token non valide.');
    });

    test('message de succès prioritaire', () {
      final response = LoginResponse.fromJson({
        'success': true,
        'message': 'Connexion réussie',
        'data': {
          'token': 'abc',
          'user_id': 1,
          'username': 'jean',
          'email': 'jean@test.cd',
          'est_prestataire': false,
        },
        'status_code': 200,
      });

      expect(response.message, 'Connexion réussie');
      expect(response.data?.userId, 1);
    });

    test('repli lisible si aucun message exploitable', () {
      final response = LoginResponse.fromJson({'success': false});

      expect(response.message, isNotEmpty);
      expect(response.statusCode, 0);
      expect(response.data, isNull);
    });
  });
}
