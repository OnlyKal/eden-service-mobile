import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/models/abonnement_models.dart';
import '../core/services/auth_service.dart';
import '../core/services/certification_service.dart';
import '../core/services/app_refresh_service.dart';
import '../theme/app_colors.dart';

class CertificationScreen extends StatefulWidget {
  const CertificationScreen({super.key});

  @override
  State<CertificationScreen> createState() => _CertificationScreenState();
}

class _CertificationScreenState extends State<CertificationScreen> {
  final _phone = TextEditingController();
  Map<String, dynamic>? _demande;
  PaiementConfig? _config;
  int? _transactionId;
  String _currency = 'CDF';
  String _identityType = 'carte_identite';
  PlatformFile? _identity;
  PlatformFile? _competence;
  bool _busy = true;
  bool _submitting = false;
  bool _checkingStatus = false;
  String? _error;
  Timer? _pollTimer;

  String get _status => _demande?['statut']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    final phone = AuthService.instance.currentUser?.telephone ?? '';
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    _phone.text = digits.startsWith('0') && digits.length == 10
        ? '243${digits.substring(1)}'
        : digits;
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        AuthService.instance.getPaiementConfig(),
        CertificationService.instance.getDemande(),
      ]);
      if (!mounted) return;
      setState(() {
        _config = results[0] as PaiementConfig;
        _demande = results[1] as Map<String, dynamic>;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _pay() async {
    final phone = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^243\d{9}$').hasMatch(phone)) {
      setState(() => _error = 'Entrez un numéro au format 243XXXXXXXXX.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await CertificationService.instance.createPayment(
        phone: phone,
        currency: _currency,
      );
      final tx = result['transaction'];
      final id = tx is Map ? int.tryParse('${tx['id']}') : null;
      if (id == null) {
        throw Exception('La transaction n’a pas été créée correctement.');
      }
      if (!mounted) return;
      setState(() {
        _transactionId = id;
        _demande = result['demande'] is Map
            ? Map<String, dynamic>.from(result['demande'] as Map)
            : _demande;
        _submitting = false;
      });
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => _checkPayment(),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confirmez le paiement sur votre téléphone.'),
        ),
      );
    } on TimeoutException {
      if (!mounted) return;
      // Le paiement a pu être créé : « Payer » reprendra la transaction en
      // attente côté serveur au lieu d'en lancer une seconde.
      setState(() {
        _submitting = false;
        _error =
            'La demande de paiement prend trop de temps. Si vous avez reçu une demande de confirmation, validez-la puis appuyez de nouveau sur Payer pour suivre le paiement.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _checkPayment() async {
    final id = _transactionId;
    if (id == null || _submitting || _checkingStatus) return;
    setState(() => _checkingStatus = true);
    try {
      final tx = await AuthService.instance.getPaiementStatus(id);
      final status = tx.statut.toUpperCase();
      if (status == 'SUCCESS') {
        _pollTimer?.cancel();
        await _load();
      } else if (status == 'FAILED' ||
          status == 'CANCELLED' ||
          status == 'REFUNDED') {
        _pollTimer?.cancel();
        if (mounted) {
          setState(() {
            _transactionId = null;
            _error =
                'Paiement ${statutLisible(status).toLowerCase()}. Vous pouvez réessayer.';
          });
        }
      }
    } catch (_) {
      // Le prochain intervalle ou le bouton de vérification réessaiera.
    } finally {
      if (mounted) setState(() => _checkingStatus = false);
    }
  }

  Future<PlatformFile?> _pickPdf() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    if (!file.name.toLowerCase().endsWith('.pdf') ||
        file.size > 10 * 1024 * 1024) {
      setState(() => _error = 'Choisissez un PDF de 10 Mo maximum.');
      return null;
    }
    setState(() => _error = null);
    return file;
  }

  Future<void> _sendDocuments() async {
    final id = int.tryParse('${_demande?['id']}');
    if (id == null || _identity == null || _competence == null) {
      setState(() => _error = 'Sélectionnez les deux documents PDF.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await CertificationService.instance.submitDocuments(
        demandeId: id,
        typeDocumentIdentite: _identityType,
        documentIdentite: _identity!,
        documentCompetence: _competence!,
      );
      AppRefreshService.instance.notify(const {
        AppRefreshTopic.profile,
        AppRefreshTopic.prestataires,
        AppRefreshTopic.home,
      });
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final price = config == null
        ? '—'
        : _currency == 'USD'
        ? config.coutCertificationUsd
        : config.coutCertificationCdf;
    return Scaffold(
      appBar: AppBar(title: const Text('Certification prestataire')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_error != null) _notice(_error!, AppColors.error),
                if (_demande == null || _demande!.isEmpty) ...[
                  _notice(
                    'La certification renforce la confiance des clients. Préparez votre pièce d’identité et un justificatif de compétence.',
                    AppColors.primary,
                  ),
                  const SizedBox(height: 18),
                  _currencyPicker(),
                  const SizedBox(height: 16),
                  Text(
                    'Frais : $price $_currency',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Téléphone Mobile Money',
                      hintText: '243812000000',
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _submitting ? null : _pay,
                    child: _submitting
                        ? const CircularProgressIndicator()
                        : const Text('Payer et continuer'),
                  ),
                ] else ...[
                  _statusCard(),
                  if (_status == 'attente_paiement') ...[
                    const SizedBox(height: 12),
                    _currencyPicker(),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Téléphone Mobile Money',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _submitting || _checkingStatus
                          ? null
                          : _transactionId == null
                          ? _pay
                          : _checkPayment,
                      child: _checkingStatus
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _transactionId == null
                                  ? 'Payer $price $_currency'
                                  : 'Vérifier le paiement',
                            ),
                    ),
                    if (_transactionId != null) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'Paiement en attente : confirmez la demande sur votre téléphone.',
                      ),
                    ],
                  ],
                  if (_status == 'attente_documents') ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: _identityType,
                      decoration: const InputDecoration(
                        labelText: 'Type de pièce d’identité',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'carte_identite',
                          child: Text('Carte d’identité'),
                        ),
                        DropdownMenuItem(
                          value: 'passeport',
                          child: Text('Passeport'),
                        ),
                        DropdownMenuItem(
                          value: 'permis_conduire',
                          child: Text('Permis de conduire'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _identityType = v ?? _identityType),
                    ),
                    const SizedBox(height: 12),
                    _fileButton('Document d’identité', _identity, () async {
                      final f = await _pickPdf();
                      if (f != null) setState(() => _identity = f);
                    }),
                    _fileButton(
                      'Justificatif de compétence',
                      _competence,
                      () async {
                        final f = await _pickPdf();
                        if (f != null) setState(() => _competence = f);
                      },
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _submitting ? null : _sendDocuments,
                      child: _submitting
                          ? const CircularProgressIndicator()
                          : const Text('Envoyer les documents'),
                    ),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _currencyPicker() => SegmentedButton<String>(
    segments: const [
      ButtonSegment(value: 'CDF', label: Text('CDF')),
      ButtonSegment(value: 'USD', label: Text('USD')),
    ],
    selected: {_currency},
    onSelectionChanged: (v) => setState(() => _currency = v.first),
  );

  Widget _statusCard() {
    final labels = <String, String>{
      'attente_paiement': 'En attente de paiement',
      'attente_documents': 'Paiement confirmé, documents attendus',
      'verification': 'Documents en cours de vérification',
      'approuvee': 'Certification approuvée',
      'rejetee': 'Demande rejetée',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              labels[_status] ?? _status,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            if ((_demande?['commentaire_admin'] ?? '')
                .toString()
                .isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_demande!['commentaire_admin'].toString()),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fileButton(String label, PlatformFile? file, VoidCallback onTap) =>
      Padding(
        padding: const EdgeInsets.only(top: 10),
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(file?.name ?? 'Choisir $label (PDF, max 10 Mo)'),
        ),
      );

  Widget _notice(String message, Color color) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Text(message, style: TextStyle(color: color)),
  );
}
