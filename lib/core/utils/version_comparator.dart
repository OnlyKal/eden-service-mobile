/// Utilitaire de comparaison de versions sémantique.
///
/// Gère les formats comme `1.0.5`, `1.0.10`, `405`, `2.1.0-beta`, etc.
/// La comparaison est numérique segment par segment, pas une comparaison
/// naïve de chaînes de caractères.
class VersionComparator {
  VersionComparator._();

  /// Compare deux versions.
  ///
  /// Retourne :
  /// - `-1` si [a] est inférieure à [b]
  /// - `0`  si [a] est égale à [b]
  /// - `1`  si [a] est supérieure à [b]
  ///
  /// Les préfixes `v`/`V` sont ignorés. Les suffixes (ex: `-beta`, `+build`)
  /// sont ignorés pour la comparaison numérique principale.
  static int compare(String a, String b) {
    final segmentsA = _parseSegments(a);
    final segmentsB = _parseSegments(b);

    final maxLength = segmentsA.length > segmentsB.length
        ? segmentsA.length
        : segmentsB.length;

    for (var i = 0; i < maxLength; i++) {
      final numA = i < segmentsA.length ? segmentsA[i] : 0;
      final numB = i < segmentsB.length ? segmentsB[i] : 0;
      if (numA < numB) return -1;
      if (numA > numB) return 1;
    }

    return 0;
  }

  /// Retourne `true` si [a] est strictement inférieure à [b].
  static bool isLower(String a, String b) => compare(a, b) < 0;

  /// Retourne `true` si [a] est strictement supérieure à [b].
  static bool isHigher(String a, String b) => compare(a, b) > 0;

  /// Retourne `true` si [a] est égale à [b].
  static bool isEqual(String a, String b) => compare(a, b) == 0;

  /// Retourne `true` si [a] est inférieure ou égale à [b].
  static bool isLowerOrEqual(String a, String b) => compare(a, b) <= 0;

  /// Retourne `true` si [a] est supérieure ou égale à [b].
  static bool isHigherOrEqual(String a, String b) => compare(a, b) >= 0;

  /// Parse une chaîne de version en segments numériques.
  ///
  /// Exemples :
  /// - `"405"` → `[405]`
  /// - `"1.0.5"` → `[1, 0, 5]`
  /// - `"1.0.10"` → `[1, 0, 10]`
  /// - `"v2.1.0-beta"` → `[2, 1, 0]`
  /// - `"1.0.0+123"` → `[1, 0, 0]`
  static List<int> _parseSegments(String version) {
    var cleaned = version.trim().toLowerCase();

    // Retire le préfixe 'v' éventuel (ex: "v1.2.3")
    if (cleaned.startsWith('v')) {
      cleaned = cleaned.substring(1);
    }

    // Retire le suffixe build éventuel (ex: "1.0.0+123")
    final plusIndex = cleaned.indexOf('+');
    if (plusIndex >= 0) {
      cleaned = cleaned.substring(0, plusIndex);
    }

    // Retire le suffixe pre-release éventuel (ex: "1.0.0-beta", "1.0.0-rc.1")
    final dashIndex = cleaned.indexOf('-');
    if (dashIndex >= 0) {
      cleaned = cleaned.substring(0, dashIndex);
    }

    // Sépare par points et convertit chaque segment en entier.
    // Les segments non numériques sont ignorés (traités comme 0).
    final parts = cleaned.split('.');
    final segments = <int>[];
    for (final part in parts) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final parsed = int.tryParse(trimmed);
      segments.add(parsed ?? 0);
    }

    // Si aucun segment numérique n'a été trouvé, retourne [0].
    if (segments.isEmpty) return [0];

    return segments;
  }
}