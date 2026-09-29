import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/demande_service_models.dart';
import '../core/models/prestataire_models.dart';
import '../core/services/app_refresh_service.dart';
import '../core/services/auth_service.dart';
import '../core/services/conversation_unread_service.dart';
import '../core/services/demande_service_service.dart';
import '../core/services/prestataire_service.dart';
import '../core/services/user_realtime_service.dart';
import '../core/utils/user_friendly_error.dart';
import '../theme/app_colors.dart';
import '../widgets/gradient_background.dart';
import 'conversation_screen.dart';
import 'login_screen.dart';

class DemandesClientScreen extends StatefulWidget {
  DemandesClientScreen({
    super.key,
    this.initialPrestataire,
    this.openCreateOnStart = false,
    this.embedded = false,
    this.title = 'Mes demandes',
    this.subtitle = 'Suivez vos interventions du rendez-vous à la notation.',
  });

  final Prestataire? initialPrestataire;
  final bool openCreateOnStart;
  final bool embedded;
  final String title;
  final String subtitle;

  @override
  State<DemandesClientScreen> createState() => _DemandesClientScreenState();
}

class _DemandesClientScreenState extends State<DemandesClientScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  final List<DemandeService> _demandes = [];
  String? _selectedStatus;
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = false;
  bool _didOpenInitialSheet = false;
  bool _ratingSheetOpen = false;
  int _lastRefreshTick = 0;
  final Set<int> _ratingPromptedDemandes = {};
  StreamSubscription<UserRealtimeEvent>? _userRealtimeSub;

  static const _ratingPromptedKey = 'rating_prompted_demandes';
  bool _ratingPrefsLoaded = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    AppRefreshService.instance.tick.addListener(_onAppRefresh);
    ConversationUnreadService.instance.counts.addListener(_onUnreadChanged);
    UserRealtimeService.instance.watch();
    _userRealtimeSub = UserRealtimeService.instance.events.listen(
      _handleUserRealtimeEvent,
    );
    _loadRatingPromptedFromPrefs();
    _loadDemandes();
  }

  /// Charge les IDs des demandes déjà notées depuis SharedPreferences
  /// pour ne jamais re-proposer la modale après un redémarrage.
  Future<void> _loadRatingPromptedFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_ratingPromptedKey) ?? const [];
      _ratingPromptedDemandes
        ..clear()
        ..addAll(raw.map(int.tryParse).whereType<int>());
    } catch (_) {
      // En cas d'erreur, on garde le set vide.
    } finally {
      _ratingPrefsLoaded = true;
    }
  }

  /// Persiste l'ID d'une demande déjà notée pour éviter la boucle infinie.
  Future<void> _persistRatingPrompted(int demandeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _ratingPromptedKey,
        _ratingPromptedDemandes.map((id) => id.toString()).toList(),
      );
    } catch (_) {
      // La persistance est best-effort.
    }
  }

  @override
  void dispose() {
    _scrollCtrl
      ..removeListener(_onScroll)
      ..dispose();
    AppRefreshService.instance.tick.removeListener(_onAppRefresh);
    ConversationUnreadService.instance.counts.removeListener(_onUnreadChanged);
    _userRealtimeSub?.cancel();
    UserRealtimeService.instance.unwatch();
    super.dispose();
  }

  void _onUnreadChanged() {
    if (mounted) setState(() {});
  }

  void _onAppRefresh() {
    final refresh = AppRefreshService.instance;
    if (_lastRefreshTick == refresh.tick.value) return;
    _lastRefreshTick = refresh.tick.value;
    if (refresh.hasAny({
      AppRefreshTopic.auth,
      AppRefreshTopic.demandes,
      AppRefreshTopic.conversations,
      AppRefreshTopic.notifications,
    })) {
      _loadDemandes(page: 1, silent: true);
    }
  }

  void _handleUserRealtimeEvent(UserRealtimeEvent event) {
    final demandeEvent = DemandeStatusRealtimeEvent.fromUserEvent(event);
    if (demandeEvent == null || !mounted) return;

    final index = _demandes.indexWhere(
      (demande) => demande.id == demandeEvent.id,
    );
    if (index == -1) {
      unawaited(_loadDemandes(page: 1, silent: true));
      return;
    }

    final previous = _demandes[index];
    setState(() {
      _demandes[index] = _demandes[index].copyWith(
        statut: demandeEvent.statut,
        dateModification: demandeEvent.dateModification,
      );
    });
    if (previous.statut != 'terminee' && demandeEvent.statut == 'terminee') {
      // Attend que les prefs soient chargées pour éviter de re-proposer
      // une modale déjà affichée pour cette demande.
      if (_ratingPrefsLoaded) {
        _showMandatoryRating(_demandes[index]);
      } else {
        unawaited(
          _loadRatingPromptedFromPrefs().then((_) {
            if (mounted) _showMandatoryRating(_demandes[index]);
          }),
        );
      }
    }
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 220 &&
        !_loadingMore &&
        _hasNext) {
      _loadMore();
    }
  }

  Future<void> _loadDemandes({int page = 1, bool silent = false}) async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!silent) {
      setState(() {
        if (page == 1) {
          _loading = true;
          _demandes.clear();
        }
      });
    }
    try {
      final res = await DemandeServiceService.instance.getDemandes(
        page: page,
        client: user.userId,
        statut: _selectedStatus,
        ordering: '-date_creation',
      );
      if (!mounted) return;
      setState(() {
        if (page == 1) {
          _demandes
            ..clear()
            ..addAll(res.results);
        } else {
          _demandes.addAll(res.results);
        }
        _page = res.currentPage;
        _hasNext = res.hasNext;
        _loading = false;
        _loadingMore = false;
      });
      ConversationUnreadService.instance.watchConversations(
        res.results.map((demande) => demande.conversationId),
      );
      _openInitialSheetIfNeeded();
      _promptLatestUnratedCompleted();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
      });
      if (!silent) {
        _showSnack('Impossible de charger les demandes. Réessayez.');
      }
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    await _loadDemandes(page: _page + 1);
  }

  void _openInitialSheetIfNeeded() {
    if (_didOpenInitialSheet ||
        !widget.openCreateOnStart ||
        widget.initialPrestataire == null) {
      return;
    }
    _didOpenInitialSheet = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openDemandeSheet(prestataire: widget.initialPrestataire);
    });
  }

  void _showSnack(String message) {
    debugPrint('[DemandesClient] $message');
  }

  void _promptLatestUnratedCompleted() {
    if (_ratingSheetOpen || !_ratingPrefsLoaded) return;
    for (final demande in _demandes) {
      if (demande.statut == 'terminee' &&
          demande.noteClient == null &&
          !_ratingPromptedDemandes.contains(demande.id)) {
        _showMandatoryRating(demande);
        return;
      }
    }
  }

  Future<void> _showMandatoryRating(DemandeService demande) async {
    if (_ratingSheetOpen || _ratingPromptedDemandes.contains(demande.id)) {
      return;
    }
    _ratingSheetOpen = true;
    _ratingPromptedDemandes.add(demande.id);
    unawaited(_persistRatingPrompted(demande.id));
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MandatoryRatingSheet(demande: demande),
    );
    _ratingSheetOpen = false;
    // Ne recharge PAS ici : le rechargement re-déclencherait la modale
    // si le serveur ne retourne pas encore noteClient. L'ID est déjà
    // persisté, donc la modale ne sera plus proposée pour cette demande.
  }

  Future<void> _openDemandeSheet({
    Prestataire? prestataire,
    DemandeService? demande,
  }) async {
    if (demande == null && prestataire == null) {
      _showSnack(
        'Choisissez un prestataire depuis sa fiche pour créer une demande.',
      );
      return;
    }
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _DemandeFormSheet(prestataire: prestataire, demande: demande),
    );
    if (changed == true) _loadDemandes(page: 1);
  }

  Future<void> _cancelDemande(DemandeService demande) async {
    final ok = await _confirm(
      title: 'Annuler la demande',
      message: 'Cette demande sera annulée et restera dans votre suivi.',
      actionLabel: 'Annuler',
      danger: true,
    );
    if (ok != true) return;
    try {
      await DemandeServiceService.instance.annulerDemande(demande.id);
      _showSnack('Demande annulée');
      await _loadDemandes(page: 1);
    } catch (e) {
      _showSnack(userFriendlyError(e));
    }
  }

  Future<void> _openChat(DemandeService demande) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          demande: demande,
          title: demande.prestataire.typeService ?? 'Discussion',
        ),
      ),
    );
    if (mounted) _loadDemandes(page: 1);
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String actionLabel,
    bool danger = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Retour'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: danger ? AppColors.error : AppColors.primary,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      final access = _AccessState(
        title: 'Connectez-vous',
        message:
            'Vos demandes de service seront synchronisées avec votre compte.',
        actionLabel: 'Connexion',
        onAction: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => LoginScreen())),
      );
      if (widget.embedded) return access;
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: GradientBackground(child: SafeArea(child: access)),
      );
    }

    final content = RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _loadDemandes(page: 1),
      child: CustomScrollView(
        controller: _scrollCtrl,
        physics: AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
          if (!widget.embedded)
            SliverToBoxAdapter(
              child: _RequestsHeader(
                title: widget.title,
                subtitle: widget.subtitle,
                onBack: () => Navigator.maybePop(context),
              ),
            ),
          SliverToBoxAdapter(
            child: _StatusFilterBar(
              selected: _selectedStatus,
              onChanged: (value) {
                setState(() => _selectedStatus = value);
                _loadDemandes(page: 1);
              },
            ),
          ),
          if (_loading)
            SliverToBoxAdapter(child: _DemandesLoading())
          else if (_demandes.isEmpty)
            SliverToBoxAdapter(
              child: _EmptyRequests(
                title: 'Aucune demande envoyée',
                message:
                    'Pour créer une demande, ouvrez la fiche d’un prestataire puis appuyez sur “Demander ce service”.',
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                20,
                10,
                20,
                widget.embedded ? 28 : 120,
              ),
              sliver: SliverList.separated(
                itemCount: _demandes.length + (_loadingMore ? 1 : 0),
                separatorBuilder: (_, __) => SizedBox(height: 12),
                itemBuilder: (_, index) {
                  if (index >= _demandes.length) {
                    return Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2.4,
                        ),
                      ),
                    );
                  }
                  final demande = _demandes[index];
                  return _DemandeClientCard(
                    demande: demande,
                    unreadCount: ConversationUnreadService.instance
                        .countForConversation(demande.conversationId),
                    onChat: () => _openChat(demande),
                    onEdit: _canEdit(demande)
                        ? () => _openDemandeSheet(demande: demande)
                        : null,
                    onCancel: _canCancel(demande)
                        ? () => _cancelDemande(demande)
                        : null,
                  );
                },
              ),
            ),
        ],
      ),
    );

    if (widget.embedded) return content;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GradientBackground(child: SafeArea(bottom: false, child: content)),
    );
  }

  bool _canEdit(DemandeService d) => d.statut == 'en_attente';
  bool _canCancel(DemandeService d) =>
      d.statut == 'en_attente' || d.statut == 'acceptee';
}

class _DemandeFormSheet extends StatefulWidget {
  _DemandeFormSheet({this.prestataire, this.demande});

  final Prestataire? prestataire;
  final DemandeService? demande;

  @override
  State<_DemandeFormSheet> createState() => _DemandeFormSheetState();
}

class _DemandeFormSheetState extends State<_DemandeFormSheet> {
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _lieuCtrl;
  DateTime? _dateSouhaitee;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final demande = widget.demande;
    _descriptionCtrl = TextEditingController(text: demande?.description ?? '');
    _lieuCtrl = TextEditingController(text: demande?.lieuIntervention ?? '');
    _dateSouhaitee = demande?.dateSouhaitee;
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _lieuCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _dateSouhaitee ?? now.add(Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        _dateSouhaitee ?? now.add(Duration(hours: 2)),
      ),
    );
    setState(() {
      _dateSouhaitee = DateTime(
        date.year,
        date.month,
        date.day,
        time?.hour ?? 9,
        time?.minute ?? 0,
      );
    });
  }

  Future<void> _save() async {
    final prestataireId =
        widget.prestataire?.id ?? widget.demande?.prestataire.id;
    final description = _descriptionCtrl.text.trim();
    final lieu = _lieuCtrl.text.trim();
    if (prestataireId == null) {
      return _snack('Choisissez un prestataire valide.');
    }
    if (description.length < 8) {
      return _snack('Décrivez le besoin en quelques mots.');
    }
    if (_dateSouhaitee == null) return _snack('Choisissez une date souhaitée.');
    if (lieu.isEmpty) return _snack('Ajoutez le lieu d’intervention.');

    setState(() => _saving = true);
    try {
      final demande = widget.demande;
      if (demande == null) {
        await DemandeServiceService.instance.createDemande(
          prestataire: prestataireId,
          description: description,
          dateSouhaitee: _dateSouhaitee!,
          lieuIntervention: lieu,
        );
      } else {
        await DemandeServiceService.instance.updateDemande(
          demande.id,
          description: description,
          dateSouhaitee: _dateSouhaitee,
          lieuIntervention: lieu,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _snack(userFriendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message) {
    debugPrint('[DemandesClient] $message');
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.prestataire;
    return _GlassSheet(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _SheetHandle(
            title: widget.demande == null
                ? 'Nouvelle demande'
                : 'Modifier la demande',
          ),
          if (p != null) ...[
            SizedBox(height: 14),
            _SelectedProvider(prestataire: p),
          ],
          SizedBox(height: 14),
          _SheetTextField(
            controller: _descriptionCtrl,
            label: 'Décrivez le problème à résoudre',
            icon: Icons.notes_rounded,
            minLines: 3,
            maxLines: 5,
          ),
          SizedBox(height: 14),
          _SheetTextField(
            controller: _lieuCtrl,
            label: 'Lieu d’intervention',
            icon: Icons.location_on_outlined,
          ),
          SizedBox(height: 14),
          _SheetPickerTile(
            icon: Icons.event_available_outlined,
            label: 'Date souhaitée',
            value: _dateSouhaitee == null
                ? 'Choisir une date'
                : _formatDateTime(_dateSouhaitee!),
            onTap: _pickDate,
          ),
          SizedBox(height: 22),
          _PrimarySheetButton(
            label: _saving
                ? 'Envoi...'
                : widget.demande == null
                ? 'Envoyer la demande'
                : 'Enregistrer',
            icon: Icons.send_rounded,
            onTap: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

class _DemandeClientCard extends StatelessWidget {
  _DemandeClientCard({
    required this.demande,
    required this.unreadCount,
    this.onEdit,
    this.onCancel,
    this.onChat,
  });

  final DemandeService demande;
  final int unreadCount;
  final VoidCallback? onEdit;
  final VoidCallback? onCancel;
  final VoidCallback? onChat;

  @override
  Widget build(BuildContext context) {
    final status = _statusMeta(demande.statut);
    final prestataire = demande.prestataire;
    final isInProgress = demande.statut == 'en_cours';
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(status.icon, color: status.color, size: 21),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      prestataire.typeService ?? 'Service',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '${prestataire.commune ?? ''}${prestataire.ville == null ? '' : ', ${prestataire.ville}'}',
                      style: TextStyle(color: AppColors.textHint, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (isInProgress) ...[
                _WorkInProgressIndicator(color: status.color),
                SizedBox(width: 8),
              ],
              _StatusBadge(meta: status),
            ],
          ),
          SizedBox(height: 10),
          _DemandeProgressSteps(statut: demande.statut),
          SizedBox(height: 10),
          Text(
            demande.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: AppColors.textSecondary,
              height: 1.35,
              fontSize: 13,
            ),
          ),
          SizedBox(height: 10),
          _InfoStrip(
            items: [
              _InfoStripItem(
                Icons.event_outlined,
                _formatDateTime(demande.dateSouhaitee),
              ),
              _InfoStripItem(
                Icons.location_on_outlined,
                demande.lieuIntervention,
              ),
            ],
          ),
          if (onChat != null || onEdit != null || onCancel != null) ...[
            SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                if (onChat != null)
                  _TinyAction(
                    label: 'Chat',
                    icon: Icons.chat_bubble_outline_rounded,
                    badgeCount: unreadCount,
                    onTap: onChat!,
                  ),
                if (onEdit != null)
                  _TinyAction(
                    label: 'Modifier',
                    icon: Icons.edit_outlined,
                    onTap: onEdit!,
                  ),
                if (onCancel != null)
                  _TinyAction(
                    label: 'Annuler',
                    icon: Icons.close_rounded,
                    color: AppColors.error,
                    onTap: onCancel!,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MandatoryRatingSheet extends StatefulWidget {
  _MandatoryRatingSheet({required this.demande});

  final DemandeService demande;

  @override
  State<_MandatoryRatingSheet> createState() => _MandatoryRatingSheetState();
}

class _MandatoryRatingSheetState extends State<_MandatoryRatingSheet> {
  final _avisCtrl = TextEditingController();
  int _note = 0;
  bool _submitting = false;
  String? _error;

  static const _labels = [
    '',
    'Mauvais',
    'Insuffisant',
    'Correct',
    'Bien',
    'Excellent',
  ];

  @override
  void dispose() {
    _avisCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_note <= 0 || _submitting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await PrestataireService.instance.rateProvider(
        prestataireId: widget.demande.prestataire.id,
        note: _note,
        avis: _avisCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      // L'utilisateur doit savoir que l'avis n'a pas été enregistré,
      // sans être coincé dans la modale.
      setState(() {
        _submitting = false;
        _error = "L'avis n'a pas pu être envoyé. Réessayez ou fermez.";
      });
      debugPrint('[MandatoryRating] error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: Color(0xFFF6F8FA),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textHint.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.star_rounded,
                  color: AppColors.warning,
                  size: 22,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Donnez votre avis',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Votre retour aide à améliorer les services.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Fermeture possible : l'avis est encouragé, jamais imposé.
              GestureDetector(
                onTap: () => Navigator.of(context).pop(false),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
                  child: Icon(
                    Icons.close_rounded,
                    color: AppColors.textHint,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final star = i + 1;
              return GestureDetector(
                onTap: _submitting ? null : () => setState(() => _note = star),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  child: Icon(
                    star <= _note
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: star <= _note
                        ? AppColors.warning
                        : AppColors.textHint.withValues(alpha: 0.55),
                    size: 40,
                  ),
                ),
              );
            }),
          ),
          SizedBox(height: 8),
          Text(
            _note > 0 ? _labels[_note] : 'Sélectionnez une note',
            style: TextStyle(
              color: _note > 0 ? AppColors.warning : AppColors.textHint,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 18),
          TextField(
            controller: _avisCtrl,
            enabled: !_submitting,
            minLines: 2,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Ajoutez un commentaire (optionnel)',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          SizedBox(height: 18),
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.error,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12),
          ],
          GestureDetector(
            onTap: _note == 0 || _submitting ? null : _submit,
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                gradient: _note == 0 || _submitting
                    ? null
                    : AppColors.primaryGradient,
                color: _note == 0 || _submitting
                    ? AppColors.textHint.withValues(alpha: 0.18)
                    : null,
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: _submitting
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.4,
                      ),
                    )
                  : Text(
                      'Envoyer mon avis',
                      style: TextStyle(
                        color: _note == 0 ? AppColors.textHint : Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestsHeader extends StatelessWidget {
  _RequestsHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  final String title;
  final String subtitle;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
      child: Row(
        children: [
          _IconBubble(icon: Icons.arrow_back_rounded, onTap: onBack),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(color: AppColors.textHint, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  _StatusFilterBar({required this.selected, required this.onChanged});
  final String? selected;
  final ValueChanged<String?> onChanged;

  static final _filters = <String?, String>{
    null: 'Tout',
    'en_attente': 'Attente',
    'acceptee': 'Acceptées',
    'en_cours': 'En cours',
    'terminee': 'Terminées',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemBuilder: (_, i) {
          final key = _filters.keys.elementAt(i);
          final label = _filters.values.elementAt(i);
          final active = selected == key;
          return GestureDetector(
            onTap: () => onChanged(key),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 180),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: BoxDecoration(
                gradient: active ? AppColors.primaryGradient : null,
                color: active ? null : Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: AppColors.glassBorder, width: 1.1),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: active ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => SizedBox(width: 8),
        itemCount: _filters.length,
      ),
    );
  }
}

class _GlassSheet extends StatelessWidget {
  _GlassSheet({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border: Border.all(color: AppColors.glassBorder, width: 1.3),
            ),
            child: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(22, 16, 22, 24),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  _SheetHandle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: Icon(Icons.close_rounded),
            ),
          ],
        ),
      ],
    );
  }
}

class _SelectedProvider extends StatelessWidget {
  _SelectedProvider({required this.prestataire});
  final Prestataire prestataire;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Icon(Icons.design_services_outlined, color: AppColors.primary),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  prestataire.utilisateur.displayName,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '${prestataire.servicesLabel} • ${prestataire.commune}',
                  style: TextStyle(color: AppColors.textHint, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetTextField extends StatelessWidget {
  _SheetTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
        filled: true,
        fillColor: AppColors.primarySurface.withValues(alpha: 0.55),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _SheetPickerTile extends StatelessWidget {
  _SheetPickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.primarySurface.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.primary),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(color: AppColors.textHint, fontSize: 11),
                  ),
                  SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.keyboard_arrow_right_rounded, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

class _PrimarySheetButton extends StatelessWidget {
  _PrimarySheetButton({required this.label, required this.icon, this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: onTap == null
              ? LinearGradient(colors: [AppColors.textHint, AppColors.textHint])
              : AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(17),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(
                alpha: onTap == null ? 0 : 0.26,
              ),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 19),
            SizedBox(width: 9),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassPanel extends StatelessWidget {
  _GlassPanel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.78),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.glassBorder, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: AppColors.glassShadow,
                blurRadius: 18,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  _StatusBadge({required this.meta});
  final _StatusMeta meta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: meta.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        meta.label,
        style: TextStyle(
          color: meta.color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _DemandeProgressSteps extends StatelessWidget {
  const _DemandeProgressSteps({required this.statut});

  final String statut;

  static const _steps = [
    ('en_attente', 'Envoyée'),
    ('acceptee', 'Acceptée'),
    ('en_cours', 'En cours'),
    ('terminee', 'Terminée'),
  ];

  @override
  Widget build(BuildContext context) {
    final activeIndex = _activeIndex(statut);
    final stopped = statut == 'refusee' || statut == 'annulee';
    final activeColor = stopped ? AppColors.error : AppColors.primary;
    final progress = stopped ? 1.0 : (activeIndex + 1) / _steps.length;
    final label = stopped ? _stopLabel(statut) : _steps[activeIndex].$2;

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 5,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppColors.primarySurface,
                valueColor: AlwaysStoppedAnimation(activeColor),
                minHeight: 5,
              ),
            ),
          ),
        ),
        SizedBox(width: 10),
        Text(
          stopped ? label : '$label ${activeIndex + 1}/${_steps.length}',
          style: TextStyle(
            color: activeColor,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  int _activeIndex(String value) {
    final index = _steps.indexWhere((step) => step.$1 == value);
    return index < 0 ? 0 : index;
  }

  String _stopLabel(String raw) => raw == 'annulee' ? 'Annulée' : 'Refusée';
}

class _WorkInProgressIndicator extends StatefulWidget {
  const _WorkInProgressIndicator({required this.color});

  final Color color;

  @override
  State<_WorkInProgressIndicator> createState() =>
      _WorkInProgressIndicatorState();
}

class _WorkInProgressIndicatorState extends State<_WorkInProgressIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1200),
    )..repeat();
    _progress = Tween<double>(
      begin: -0.4,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _progress,
      builder: (context, child) {
        return Container(
          width: 58,
          height: 30,
          padding: EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: widget.color.withValues(alpha: 0.18)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.handyman_rounded, color: widget.color, size: 15),
              SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: SizedBox(
                    height: 4,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: widget.color.withValues(alpha: 0.16),
                          ),
                        ),
                        FractionallySizedBox(
                          alignment: Alignment(_progress.value * 2 - 1, 0),
                          widthFactor: 0.45,
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: widget.color),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoStrip extends StatelessWidget {
  _InfoStrip({required this.items});
  final List<_InfoStripItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .where((item) => item.text.trim().isNotEmpty)
          .map(
            (item) => Container(
              padding: EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.primarySurface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, color: AppColors.primary, size: 15),
                  SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 190),
                    child: Text(
                      item.text,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _InfoStripItem {
  _InfoStripItem(this.icon, this.text);
  final IconData icon;
  final String text;
}

class _TinyAction extends StatelessWidget {
  _TinyAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
    this.color = AppColors.primary,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 15),
                SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (badgeCount > 0)
          Positioned(
            right: -7,
            top: -7,
            child: _UnreadBadge(count: badgeCount),
          ),
      ],
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: BoxConstraints(minWidth: 18, minHeight: 18),
      padding: EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: AppColors.error,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  _IconBubble({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.glassBorder, width: 1.1),
        ),
        child: Icon(icon, color: AppColors.primary, size: 20),
      ),
    );
  }
}

class _AccessState extends StatelessWidget {
  _AccessState({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: _GlassPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                color: AppColors.primary,
                size: 40,
              ),
              SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              SizedBox(height: 18),
              _PrimarySheetButton(
                label: actionLabel,
                icon: Icons.login_rounded,
                onTap: onAction,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRequests extends StatelessWidget {
  _EmptyRequests({required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 40, 20, 120),
      child: _GlassPanel(
        child: Column(
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.assignment_outlined,
                color: AppColors.primary,
                size: 34,
              ),
            ),
            SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _DemandesLoading extends StatelessWidget {
  _DemandesLoading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        children: List.generate(
          4,
          (_) => Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: _GlassPanel(
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 12,
                          width: 140,
                          decoration: BoxDecoration(
                            color: AppColors.divider,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        SizedBox(height: 8),
                        Container(
                          height: 10,
                          width: 220,
                          decoration: BoxDecoration(
                            color: AppColors.divider,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

_StatusMeta _statusMeta(String raw) {
  switch (raw) {
    case 'en_attente':
      return _StatusMeta(
        'En attente',
        Icons.schedule_rounded,
        AppColors.warning,
      );
    case 'acceptee':
      return _StatusMeta(
        'Acceptée',
        Icons.check_circle_outline_rounded,
        AppColors.primary,
      );
    case 'en_cours':
      return _StatusMeta(
        'En cours',
        Icons.construction_rounded,
        AppColors.info,
      );
    case 'terminee':
      return _StatusMeta('Terminée', Icons.verified_rounded, AppColors.success);
    case 'refusee':
      return _StatusMeta('Refusée', Icons.block_rounded, AppColors.error);
    default:
      return _StatusMeta(
        raw.isEmpty ? 'Demande' : raw,
        Icons.assignment_outlined,
        AppColors.textSecondary,
      );
  }
}

class _StatusMeta {
  _StatusMeta(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year} à '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
