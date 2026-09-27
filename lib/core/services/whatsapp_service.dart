import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/api_constants.dart';

/// Résultat d'une tentative d'ouverture d'une conversation WhatsApp.
enum WhatsappLaunchResult {
  /// La conversation a été ouverte dans WhatsApp ou WhatsApp Web.
  opened,

  /// Aucun lien n'a pu être ouvert.
  failed,
}

/// Ouvre une conversation WhatsApp avec un message prérempli.
///
/// Le format `https://wa.me/<numéro>?text=<message>` est volontairement en
/// `https` et non en `whatsapp://` :
///  * si WhatsApp est installé, l'OS ouvre directement l'application
///    (App Links sur Android, Universal Links sur iOS) ;
///  * sinon, le navigateur prend le relais et `wa.me` redirige vers
///    WhatsApp Web — le repli est donc natif, sans code supplémentaire.
class WhatsappService {
  WhatsappService._();
  static final WhatsappService instance = WhatsappService._();

  /// Indicatif pays utilisé quand le numéro est saisi en format national.
  /// Cohérent avec les formulaires de l'application (`+243 81 234 5678`) et
  /// avec la normalisation de `profile_screen`.
  static const String defaultCountryCode = '243';

  /// Bornes d'un numéro international (E.164 : 8 à 15 chiffres).
  static const int _minPhoneDigits = 8;
  static const int _maxPhoneDigits = 15;

  /// Normalise un numéro saisi librement vers le format international attendu
  /// par WhatsApp : uniquement des chiffres, préfixe pays inclus.
  ///
  /// Gère le préfixe international `+`/`00`, les espaces, points, tirets et
  /// parenthèses, ainsi que le format national congolais (`0XXXXXXXXX`).
  static String normalizePhone(String? raw) {
    if (raw == null) return '';
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';

    // Retire les zéros de tête : « 00 » est un préfixe international et un
    // « 0 » isolé l'indicatif national. Aucun indicatif pays ne commençant
    // par 0, le retrait est toujours sans risque.
    while (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.isEmpty) return '';

    if (!digits.startsWith(defaultCountryCode) && digits.length <= 10) {
      // Numéro national sans indicatif pays.
      digits = '$defaultCountryCode$digits';
    }

    return digits;
  }

  /// Indique si un numéro peut être exploité par WhatsApp.
  ///
  /// Un numéro congolais doit respecter le format attendu par l'API de
  /// paiement (`243` + 9 chiffres) ; les autres numéros sont validés selon les
  /// bornes E.164.
  static bool isValidPhone(String? raw) {
    final digits = normalizePhone(raw);
    if (digits.isEmpty) return false;

    if (digits.startsWith(defaultCountryCode)) {
      return RegExp('^$defaultCountryCode\\d{9}\$').hasMatch(digits);
    }

    return digits.length >= _minPhoneDigits &&
        digits.length <= _maxPhoneDigits &&
        RegExp(r'^\d+$').hasMatch(digits);
  }

  /// Message prérempli envoyé au prestataire.
  ///
  /// Message texte uniquement : aucun lien, aucune image.
  static String buildMessage({required String clientName}) {
    final name = clientName.trim();
    final who = name.isEmpty ? 'un client Zwacop' : name;
    return 'Bonjour, moi c\u2019est $who. '
        'J\u2019aimerais savoir si vous êtes disponible. '
        'Je vous ai trouvé sur l\u2019application Zwacop.';
  }

  /// Lien profond vers la conversation, message prérempli.
  static Uri buildDeepLink({required String phone, required String message}) {
    return Uri(
      scheme: 'https',
      host: 'wa.me',
      path: '/$phone',
      queryParameters: {'text': message},
    );
  }

  /// Ouvre directement la conversation WhatsApp du prestataire.
  ///
  /// Le message est prérempli et le numéro déjà sélectionné. Si WhatsApp n'est
  /// pas installé, `wa.me` redirige automatiquement vers WhatsApp Web.
  Future<WhatsappLaunchResult> openConversation({
    required String? rawPhone,
    required String clientName,
  }) async {
    final phone = normalizePhone(rawPhone);
    if (!isValidPhone(phone)) {
      debugPrint('[WhatsApp] Numéro invalide: $rawPhone');
      return WhatsappLaunchResult.failed;
    }

    final message = buildMessage(clientName: clientName);
    final launched = await openLink(
      buildDeepLink(phone: phone, message: message),
    );
    return launched
        ? WhatsappLaunchResult.opened
        : WhatsappLaunchResult.failed;
  }

  /// Lance un lien externe en renvoyant `false` si l'OS n'a rien ouvert.
  Future<bool> openLink(Uri link) async {
    try {
      final launched = await launchUrl(
        link,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        debugPrint("[WhatsApp] Impossible d'ouvrir $link");
      }
      return launched;
    } catch (e) {
      debugPrint("[WhatsApp] Erreur d'ouverture de $link : $e");
      return false;
    }
  }
}
