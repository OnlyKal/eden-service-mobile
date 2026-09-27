import 'package:eden_service_mobile/core/services/whatsapp_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WhatsappService.normalizePhone', () {
    test('conserve un numéro déjà au format international', () {
      expect(WhatsappService.normalizePhone('243812345678'), '243812345678');
      expect(WhatsappService.normalizePhone('+243 81 234 5678'), '243812345678');
    });

    test('convertit le format national congolais', () {
      expect(WhatsappService.normalizePhone('0812345678'), '243812345678');
      expect(WhatsappService.normalizePhone('081 234 5678'), '243812345678');
    });

    test('supprime le préfixe international 00', () {
      expect(WhatsappService.normalizePhone('00243812345678'), '243812345678');
      expect(WhatsappService.normalizePhone('000243812345678'), '243812345678');
    });

    test('ignore séparateurs divers', () {
      expect(WhatsappService.normalizePhone('+243 (81) 234-56.78'), '243812345678');
    });

    test('ajoute l’indicatif si le numéro est national sans zéro', () {
      expect(WhatsappService.normalizePhone('812345678'), '243812345678');
    });

    test('ne touche pas un numéro étranger déjà international', () {
      expect(WhatsappService.normalizePhone('+33 6 12 34 56 78'), '33612345678');
    });

    test('renvoie une chaîne vide si le numéro est absent ou vide', () {
      expect(WhatsappService.normalizePhone(null), '');
      expect(WhatsappService.normalizePhone(''), '');
      expect(WhatsappService.normalizePhone('   '), '');
      expect(WhatsappService.normalizePhone('abc'), '');
    });

    test('est idempotent', () {
      final once = WhatsappService.normalizePhone('+243 81 234 5678');
      expect(WhatsappService.normalizePhone(once), once);
    });
  });

  group('WhatsappService.isValidPhone', () {
    test('accepte les numéros exploitables', () {
      expect(WhatsappService.isValidPhone('+243 81 234 5678'), isTrue);
      expect(WhatsappService.isValidPhone('0812345678'), isTrue);
      expect(WhatsappService.isValidPhone('00243812345678'), isTrue);
    });

    test('refuse les valeurs absentes ou trop courtes', () {
      expect(WhatsappService.isValidPhone(null), isFalse);
      expect(WhatsappService.isValidPhone(''), isFalse);
      expect(WhatsappService.isValidPhone('12345'), isFalse);
    });

    test('refuse les numéros trop longs (> 15 chiffres E.164)', () {
      expect(WhatsappService.isValidPhone('+1 234 567 891 234 567 890'), isFalse);
    });
  });

  group('WhatsappService.buildMessage', () {
    test('inclut le nom du client et le texte demandé', () {
      final message = WhatsappService.buildMessage(
        clientName: 'Jean Kabasele',
      );

      expect(
        message,
        'Bonjour, moi c\u2019est Jean Kabasele. J\u2019aimerais savoir si '
        'vous êtes disponible. Je vous ai trouvé sur l\u2019application Zwacop.',
      );
    });

    test('ne contient aucune URL ni lien vers le logo', () {
      final message = WhatsappService.buildMessage(clientName: 'Jean');

      expect(message, isNot(contains('http')));
      expect(message, isNot(contains('zwacop')));
      expect(message, isNot(contains('/')));
    });

    test('retombe sur une formule générique si le nom est vide', () {
      final message = WhatsappService.buildMessage(clientName: '   ');

      expect(message, startsWith('Bonjour, moi c\u2019est un client Zwacop.'));
    });
  });

  group('WhatsappService.buildDeepLink', () {
    test('construit un lien wa.me avec le numéro en chemin et le message', () {
      final uri = WhatsappService.buildDeepLink(
        phone: '243812345678',
        message: 'Bonjour, moi c\u2019est Jean & Ana',
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/243812345678');
      expect(uri.queryParameters['text'], 'Bonjour, moi c\u2019est Jean & Ana');
    });

    test('le lien de conversation ne contient pas d’URL de logo', () {
      final uri = WhatsappService.buildDeepLink(
        phone: WhatsappService.normalizePhone('+243 81 234 5678'),
        message: WhatsappService.buildMessage(clientName: 'Jean'),
      );

      expect(uri.host, 'wa.me');
      expect(uri.path, '/243812345678');
      expect(uri.queryParameters['text'], isNot(contains('http')));
      expect(uri.queryParameters['text'], isNot(contains('zwacop')));
    });

    test('le lien produit reste ouvrable et encode les caractères spéciaux', () {
      final uri = WhatsappService.buildDeepLink(
        phone: '243812345678',
        message: 'Bonjour, moi c\u2019est Jean & Ana 100%',
      );

      expect(uri.toString(), startsWith('https://wa.me/243812345678?text='));
      // Le texte doit être échappé, pas injecté tel quel dans l'URL.
      expect(uri.toString(), isNot(contains(' & ')));
      expect(uri.queryParameters['text'], 'Bonjour, moi c\u2019est Jean & Ana 100%');
    });
  });
}
