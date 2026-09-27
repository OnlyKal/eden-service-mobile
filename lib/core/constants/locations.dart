/// Une ville couverte par l'application, avec ses communes.
class Ville {
  const Ville({required this.nom, required this.communes});

  final String nom;
  final List<String> communes;

  @override
  String toString() => nom;
}

/// Villes couvertes par Zwacop et leurs communes.
///
/// Source de vérité unique du découpage Ville → Commune : elle est utilisée
/// par le formulaire « Devenir prestataire », la modification du profil
/// prestataire et les filtres de recherche côté client, afin que les trois
/// parcours restent rigoureusement identiques.
class Locations {
  Locations._();

  /// Une ville et la liste de ses communes.
  static const List<Ville> villes = [
    Ville(
      nom: 'Kinshasa',
      communes: [
        'Bandalungwa',
        'Barumbu',
        'Bumbu',
        'Gombe',
        'Kalamu',
        'Kasa-Vubu',
        'Kimbanseke',
        'Kinshasa',
        'Kintambo',
        'Kisenso',
        'Lemba',
        'Limete',
        'Lingwala',
        'Makala',
        'Maluku',
        'Masina',
        'Matete',
        'Mont-Ngafula',
        'Ndjili',
        'Ngaba',
        'Ngaliema',
        'Ngiri-Ngiri',
        'N\'Sele',
        'Selembao',
      ],
    ),
    Ville(
      nom: 'Goma',
      communes: ['Goma', 'Karisimbi'],
    ),
    Ville(
      nom: 'Beni',
      communes: ['Beu', 'Bungulu', 'Mulekera', 'Ruwenzori'],
    ),
    Ville(
      nom: 'Lubumbashi',
      communes: [
        'Annexe',
        'Kamalondo',
        'Kampemba',
        'Katuba',
        'Kenya',
        'Lubumbashi',
        'Ruashi',
      ],
    ),
    Ville(
      nom: 'Butembo',
      communes: ['Bulengera', 'Kimemi', 'Mususa', 'Vulamba'],
    ),
  ];

  /// Noms des villes, dans l'ordre d'affichage.
  static List<String> get nomsVilles =>
      villes.map((v) => v.nom).toList(growable: false);

  /// Communes d'une ville.
  ///
  /// La recherche ignore la casse : la base contient des valeurs saisies
  /// librement (« kinshasa », « lubumbashi »).
  /// Renvoie une liste vide si la ville est inconnue.
  static List<String> communesDe(String? ville) {
    if (ville == null || ville.trim().isEmpty) return const [];
    final recherche = _normaliser(ville);
    for (final v in villes) {
      if (_normaliser(v.nom) == recherche) return v.communes;
    }
    return const [];
  }

  /// Vrai si la ville fait partie des villes couvertes.
  static bool estVilleConnue(String? ville) {
    if (ville == null || ville.trim().isEmpty) return false;
    return communesDe(ville).isNotEmpty;
  }

  /// Vrai si la commune appartient à la ville donnée.
  static bool communeAppartientA({String? commune, String? ville}) {
    if (commune == null || commune.trim().isEmpty) return false;
    if (ville == null || ville.trim().isEmpty) return false;
    final c = _normaliser(commune);
    return communesDe(ville).any((item) => _normaliser(item) == c);
  }

  /// Ville à laquelle appartient une commune (comparaison insensible à la
  /// casse), ou `null` si aucune ville connue ne la contient.
  static String? villeDeCommune(String? commune) {
    if (commune == null || commune.trim().isEmpty) return null;
    final c = _normaliser(commune);
    for (final v in villes) {
      if (v.communes.any((item) => _normaliser(item) == c)) return v.nom;
    }
    return null;
  }

  /// Nom de référence d'une ville si elle est connue (insensible à la casse),
  /// sinon la valeur d'origine, afin de ne jamais perdre une localisation
  /// déjà enregistrée.
  static String? villeValide(String? ville) {
    if (ville == null || ville.trim().isEmpty) return null;
    final recherche = _normaliser(ville);
    for (final v in villes) {
      if (_normaliser(v.nom) == recherche) return v.nom;
    }
    return ville;
  }

  /// Commune canonique d'une ville à partir d'une valeur enregistrée.
  ///
  /// Les anciennes fiches peuvent contenir une orthographe ou une casse
  /// différente : la valeur d'origine est alors conservée pour ne jamais
  /// perdre la donnée, tout en renvoyant la commune de référence si elle
  /// existe.
  static String? communeValide({String? ville, String? commune}) {
    if (commune == null || commune.trim().isEmpty) return null;
    if (ville != null && communeAppartientA(commune: commune, ville: ville)) {
      return commune;
    }
    final canonique = villeDeCommune(commune);
    // La commune est connue mais dans une autre ville : on ne l'écrase pas.
    if (canonique != null && ville == null) return commune;
    return commune;
  }

  static String _normaliser(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
