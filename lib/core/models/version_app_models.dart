/// Modèle représentant la version actuelle de l'application
/// retournée par l'API Django.
class VersionApp {
  const VersionApp({
    required this.version,
    required this.messageAlerte,
    required this.estObligatoire,
    required this.estActif,
    this.id,
    this.dateCreation,
    this.dateModification,
  });

  final int? id;
  final String version;
  final String messageAlerte;
  final bool estObligatoire;
  final bool estActif;
  final DateTime? dateCreation;
  final DateTime? dateModification;

  factory VersionApp.fromJson(Map<String, dynamic> json) {
    return VersionApp(
      id: _parseIntOrNull(json['id']),
      version: json['version']?.toString() ?? '',
      messageAlerte:
          json['message_alerte']?.toString() ??
          json['messageAlerte']?.toString() ??
          '',
      estObligatoire: _parseBool(
        json['est_obligatoire'] ?? json['estObligatoire'],
      ),
      estActif: _parseBool(json['est_actif'] ?? json['estActif']),
      dateCreation: DateTime.tryParse(
        json['date_creation']?.toString() ?? '',
      ),
      dateModification: DateTime.tryParse(
        json['date_modification']?.toString() ?? '',
      ),
    );
  }
}

bool _parseBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.toLowerCase().trim();
    return normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes' ||
        normalized == 'oui';
  }
  return false;
}

int? _parseIntOrNull(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}