/// Model représentant le statut d'abonnement d'un prestataire.
class AbonnementStatut {
  final int prestataireId;
  final bool estEnEssai;
  final int joursEssaiRestants;
  final DateTime? dateFinEssai;
  final DateTime? dateDebutAbonnement;
  final DateTime? dateFinAbonnement;
  final bool estAbonneActif;
  final String statutPrestataire;
  final bool? estValide;
  final bool? isAvailable;

  /// Détail de l'abonnement actif (peut être null).
  final Map<String, dynamic>? abonnementActif;

  /// Dernier abonnement connu, même expiré.
  final Map<String, dynamic>? dernierAbonnement;

  const AbonnementStatut({
    required this.prestataireId,
    required this.estEnEssai,
    required this.joursEssaiRestants,
    required this.dateFinEssai,
    required this.dateDebutAbonnement,
    required this.dateFinAbonnement,
    required this.estAbonneActif,
    required this.statutPrestataire,
    required this.estValide,
    required this.isAvailable,
    this.abonnementActif,
    this.dernierAbonnement,
  });

  factory AbonnementStatut.fromJson(Map<String, dynamic> json) {
    final abonnementActifRaw = json['abonnement_actif'];
    final dernierAbonnementRaw = json['dernier_abonnement'];
    // Les anciens champs d'essai peuvent encore être renvoyés par l'API,
    // mais aucun accès prestataire ne doit en dépendre.
    const dateFinEssai = null;
    const joursEssaiRestants = 0;
    const estEnEssai = false;

    return AbonnementStatut(
      prestataireId: _parseInt(json['prestataire_id']),
      estEnEssai: estEnEssai,
      joursEssaiRestants: joursEssaiRestants > 0
          ? joursEssaiRestants
          : _daysUntil(dateFinEssai),
      dateFinEssai: dateFinEssai,
      dateDebutAbonnement: _parseDate(json['date_debut_abonnement']),
      dateFinAbonnement: _parseDate(json['date_fin_abonnement']),
      estAbonneActif: _parseBool(json['est_abonne_actif']) ?? false,
      statutPrestataire: json['statut_prestataire']?.toString() ?? '',
      estValide: _parseBool(json['est_valide']),
      isAvailable: _parseBool(json['is_available']),
      abonnementActif: abonnementActifRaw is Map<String, dynamic>
          ? abonnementActifRaw
          : null,
      dernierAbonnement: dernierAbonnementRaw is Map<String, dynamic>
          ? dernierAbonnementRaw
          : null,
    );
  }

  /// Id de l'abonnement actif (utile pour le renouvellement).
  int? get abonnementActifId => _parseIntOrNull(abonnementActif?['id']);

  DateTime? get dateFinAbonnementEffective =>
      dateFinAbonnement ?? _parseDate(abonnementActif?['date_fin']);

  bool get abonnementDateExpiree {
    final fin = dateFinAbonnementEffective;
    if (fin == null) return false;
    return !fin.isAfter(DateTime.now());
  }

  bool get estAbonnementCourantActif =>
      estAbonneActif && !abonnementDateExpiree;

  int? get joursAbonnementRestants {
    final fin = dateFinAbonnementEffective;
    if (fin == null || abonnementDateExpiree) return null;
    final seconds = fin.difference(DateTime.now()).inSeconds;
    if (seconds <= 0) return 0;
    return (seconds / 86400).ceil();
  }

  DateTime? get dateFinDernierAbonnement =>
      _parseDate(dernierAbonnement?['date_fin']);

  String get statutDernierAbonnement =>
      dernierAbonnement?['statut']?.toString() ?? '';

  bool get prestataireBloqueMalgreAbonnement {
    final statut = statutPrestataire.toLowerCase().trim();
    return estAbonnementCourantActif &&
        (statut == 'inactif' || estValide == false || isAvailable == false);
  }

  /// L'essai est terminé : l'utilisateur était en essai mais les jours sont écoulés.
  bool get essaiTermine => !estEnEssai && joursEssaiRestants <= 0;

  /// L'abonnement payant est terminé (ou n'a jamais été souscrit).
  bool get abonnementTermine =>
      !estAbonnementCourantActif || abonnementDateExpiree;

  /// Compte totalement inactif : ni essai en cours, ni abonnement actif.
  bool get estInactif => !estAbonnementCourantActif;
}

int _parseInt(dynamic value) => _parseIntOrNull(value) ?? 0;

int _daysUntil(DateTime? value) {
  if (value == null || !value.isAfter(DateTime.now())) return 0;
  final seconds = value.difference(DateTime.now()).inSeconds;
  return (seconds / 86400).ceil();
}

int? _parseIntOrNull(dynamic value) {
  if (value is int) return value;
  if (value == null) return null;
  return int.tryParse(value.toString());
}

bool? _parseBool(dynamic value) {
  if (value is bool) return value;
  if (value == null) return null;
  final normalized = value.toString().toLowerCase().trim();
  if (normalized == 'true' || normalized == '1') return true;
  if (normalized == 'false' || normalized == '0') return false;
  return null;
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}

// ── Tarif d'abonnement ────────────────────────────────────────────────────────

class TarifAbonnement {
  final int id;
  final String typeAbonnement; // "mensuel" | "annuel"
  final String typeDisplay; // "Mensuel" | "Annuel"
  final String prix; // "1.00"
  final String description;
  final bool actif;

  const TarifAbonnement({
    required this.id,
    required this.typeAbonnement,
    required this.typeDisplay,
    required this.prix,
    required this.description,
    required this.actif,
  });

  factory TarifAbonnement.fromJson(Map<String, dynamic> json) =>
      TarifAbonnement(
        id: json['id'] as int,
        typeAbonnement: json['type_abonnement'] as String,
        typeDisplay:
            json['get_type_abonnement_display'] as String? ??
            json['type_abonnement'] as String,
        prix: json['prix'] as String,
        description: json['description'] as String? ?? '',
        actif: json['actif'] as bool? ?? true,
      );
}

class PaiementPlan {
  final int dureeMois;
  final String montantUsd;
  final String montantCdf;
  final String montantInitialUsd;
  final String montantInitialCdf;
  final String montantReductionUsd;
  final String montantReductionCdf;
  final String reductionPourcentage;

  const PaiementPlan({
    required this.dureeMois,
    required this.montantUsd,
    required this.montantCdf,
    this.montantInitialUsd = '0.00',
    this.montantInitialCdf = '0',
    this.montantReductionUsd = '0.00',
    this.montantReductionCdf = '0',
    this.reductionPourcentage = '0',
  });

  factory PaiementPlan.fromJson(Map<String, dynamic> json) => PaiementPlan(
    dureeMois: json['duree_mois'] as int? ?? 0,
    montantUsd: json['montant_usd']?.toString() ?? '0.00',
    montantCdf: json['montant_cdf']?.toString() ?? '0',
    montantInitialUsd: json['montant_initial_usd']?.toString() ?? '0.00',
    montantInitialCdf: json['montant_initial_cdf']?.toString() ?? '0',
    montantReductionUsd: json['montant_reduction_usd']?.toString() ?? '0.00',
    montantReductionCdf: json['montant_reduction_cdf']?.toString() ?? '0',
    reductionPourcentage: json['reduction_pourcentage']?.toString() ?? '0',
  );

  String amountFor(String currency) =>
      currency == 'USD' ? montantUsd : montantCdf;

  String initialAmountFor(String currency) =>
      currency == 'USD' ? montantInitialUsd : montantInitialCdf;

  String discountAmountFor(String currency) =>
      currency == 'USD' ? montantReductionUsd : montantReductionCdf;
}

class PaiementConfig {
  final String prixMensuelUsd;
  final String tauxUsdCdf;
  final bool flexpayActif;
  final String coutCertificationUsd;
  final String coutCertificationCdf;
  final List<PaiementPlan> plans;

  const PaiementConfig({
    required this.prixMensuelUsd,
    required this.tauxUsdCdf,
    required this.flexpayActif,
    this.coutCertificationUsd = '0.00',
    this.coutCertificationCdf = '0',
    required this.plans,
  });

  factory PaiementConfig.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? const {};
    return PaiementConfig(
      prixMensuelUsd: data['prix_mensuel_usd']?.toString() ?? '0.00',
      tauxUsdCdf: data['taux_usd_cdf']?.toString() ?? '0.00',
      flexpayActif: data['flexpay_actif'] as bool? ?? false,
      coutCertificationUsd:
          data['cout_certification_usd']?.toString() ?? '0.00',
      coutCertificationCdf: data['cout_certification_cdf']?.toString() ?? '0',
      plans: (data['plans'] as List<dynamic>? ?? const [])
          .map((e) => PaiementPlan.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Libellé lisible d'un statut de paiement ou d'abonnement renvoyé par l'API
/// (ex. « PENDING » → « En attente »).
String statutLisible(String statut) {
  switch (statut.trim().toLowerCase()) {
    case 'success':
    case 'complete':
    case 'completed':
    case 'reussi':
      return 'Réussi';
    case 'pending':
    case 'en_attente':
      return 'En attente';
    case 'failed':
    case 'echoue':
      return 'Échoué';
    case 'cancelled':
    case 'canceled':
    case 'annule':
      return 'Annulé';
    case 'refunded':
    case 'rembourse':
      return 'Remboursé';
    case 'active':
    case 'actif':
      return 'Actif';
    case 'expired':
    case 'expire':
      return 'Expiré';
    case 'inactive':
    case 'inactif':
      return 'Inactif';
    case '':
      return '-';
  }
  final clean = statut.replaceAll('_', ' ').trim().toLowerCase();
  return clean[0].toUpperCase() + clean.substring(1);
}

class PaiementTransaction {
  final int id;
  final String montant;
  final String devise;
  final int dureeMois;
  final String telephone;
  final String statut;
  final String referenceTransaction;
  final String orderNumber;
  final String? datePaiement;
  final String? dateConfirmation;

  const PaiementTransaction({
    required this.id,
    required this.montant,
    required this.devise,
    required this.dureeMois,
    required this.telephone,
    required this.statut,
    required this.referenceTransaction,
    required this.orderNumber,
    this.datePaiement,
    this.dateConfirmation,
  });

  factory PaiementTransaction.fromJson(Map<String, dynamic> json) =>
      PaiementTransaction(
        id: json['id'] as int? ?? 0,
        montant: json['montant']?.toString() ?? '',
        devise: (json['devise'] ?? json['currency'])?.toString() ?? '',
        dureeMois: json['duree_mois'] as int? ?? 0,
        telephone: json['telephone']?.toString() ?? '',
        statut:
            (json['statut'] ?? json['status'])?.toString().toUpperCase() ?? '',
        referenceTransaction: json['reference_transaction']?.toString() ?? '',
        orderNumber: json['order_number']?.toString() ?? '',
        datePaiement: json['date_paiement']?.toString(),
        dateConfirmation: json['date_confirmation']?.toString(),
      );

  String get statutLabel => statutLisible(statut);

  PaiementTransaction copyWith({String? statut}) => PaiementTransaction(
    id: id,
    montant: montant,
    devise: devise,
    dureeMois: dureeMois,
    telephone: telephone,
    statut: statut ?? this.statut,
    referenceTransaction: referenceTransaction,
    orderNumber: orderNumber,
    datePaiement: datePaiement,
    dateConfirmation: dateConfirmation,
  );
}
