import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/models/demande_service_models.dart';
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
import 'demandes_client_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

class DemandesPrestataireScreen extends StatefulWidget {
  DemandesPrestataireScreen({super.key});

  @override
  State<DemandesPrestataireScreen> createState() =>
      _DemandesPrestataireScreenState();
}

class _DemandesPrestataireScreenState extends State<DemandesPrestataireScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  final List<DemandeService> _demandes = [];
  int? _prestataireId;
  String? _selectedStatus;
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasNext = false;
  int? _busyId;
  int _lastRefreshTick = 0;
  StreamSubscription<UserRealtimeEvent>? _userRealtimeSub;

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
    _init();
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
      AppRefreshTopic.profile,
    })) {
      if (_prestataireId == null) {
        _init();
      } else {
        _loadDemandes(page: 1, silent: true);
      }
    }
  }

  void _handleUserRealtimeEvent(UserRealtimeEvent event) {
    final demandeEvent = DemandeStatusRealtimeEvent.fromUserEvent(event);
    if (demandeEvent == null || !mounted) return;

    final index = _demandes.indexWhere(
      (demande) => demande.id == demandeEvent.id,
    );
    if (index == -1) {
      if (_prestataireId != null) {
        unawaited(_loadDemandes(page: 1, silent: true));
      }
      return;
    }

    setState(() {
      _demandes[index] = _demandes[index].copyWith(
        statut: demandeEvent.statut,
        dateModification: demandeEvent.dateModification,
      );
    });
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 220 &&
        !_loadingMore &&
        _hasNext) {
      _loadMore();
    }
  }

  Future<void> _init() async {
    final user = AuthService.instance.currentUser;
    if (user == null || !user.estPrestataire) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final profil = await PrestataireService.instance.getMonProfil();
      _prestataireId = profil.id;
      await _loadDemandes(page: 1);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack(userFriendlyError(e));
    }
  }

  Future<void> _loadDemandes({int page = 1, bool silent = false}) async {
    if (_prestataireId == null) return;
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
        prestataire: _prestataireId,
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

  Future<void> _runAction({
    required DemandeService demande,
    required String title,
    required String message,
    required Future<DemandeService> Function() action,
  }) async {
    final ok = await showDialog<bool>(
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
            onPressed: () => Navigator.pop(context, true),
            child: Text('Confirmer'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busyId = demande.id);
    try {
      await action();
      _showSnack('Demande mise à jour');
      await _loadDemandes(page: 1);
    } catch (e) {
      _showSnack(userFriendlyError(e));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _openChat(DemandeService demande) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          demande: demande,
          title: demande.client.displayName,
          allowAcceptPrestation: true,
        ),
      ),
    );
    if (mounted) _loadDemandes(page: 1);
  }

  void _showSnack(String message) {
    debugPrint('[DemandesPrestataire] $message');
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      return _AccessScaffold(
        title: 'Connectez-vous',
        message: 'Votre boîte de demandes est liée à votre compte prestataire.',
        actionLabel: 'Connexion',
        onAction: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => LoginScreen())),
      );
    }
    if (!user.estPrestataire) {
      return _AccessScaffold(
        title: 'Espace prestataire',
        message:
            'Activez votre profil prestataire pour recevoir et gérer les demandes.',
        actionLabel: 'Ouvrir mon profil',
        onAction: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => ProfileScreen())),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: GradientBackground(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _ProviderRequestsHeader(
                  onBack: () => Navigator.maybePop(context),
                ),
                _ProviderDemandesTabs(),
                Expanded(
                  child: TabBarView(
                    children: [
                      DemandesClientScreen(
                        embedded: true,
                        title: 'Demandes envoyées',
                        subtitle:
                            'Les demandes que vous créez en tant que client.',
                      ),
                      _buildReceivedTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReceivedTab() {
    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _loadDemandes(page: 1),
      child: CustomScrollView(
        controller: _scrollCtrl,
        physics: AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        slivers: [
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
                title: 'Aucune demande reçue',
                message:
                    'Les nouvelles demandes de vos clients apparaîtront ici.',
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 28),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index.isOdd) return SizedBox(height: 12);
                    final itemIndex = index ~/ 2;
                    if (itemIndex >= _demandes.length) {
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
                    final demande = _demandes[itemIndex];
                    return _DemandePrestataireCard(
                      demande: demande,
                      busy: _busyId == demande.id,
                      unreadCount: ConversationUnreadService.instance
                          .countForConversation(demande.conversationId),
                      onChat: () => _openChat(demande),
                      onRefuse: () => _runAction(
                        demande: demande,
                        title: 'Refuser la demande',
                        message: 'Cette demande quittera votre file active.',
                        action: () => DemandeServiceService.instance
                            .refuserDemande(demande.id),
                      ),
                      onStart: () => _runAction(
                        demande: demande,
                        title: 'Commencer l’intervention',
                        message: 'Le statut passera en cours.',
                        action: () => DemandeServiceService.instance
                            .demarrerDemande(demande.id),
                      ),
                      onFinish: () => _runAction(
                        demande: demande,
                        title: 'Terminer l’intervention',
                        message:
                            'Le client pourra ensuite noter la prestation.',
                        action: () => DemandeServiceService.instance
                            .terminerDemande(demande.id),
                      ),
                    );
                  },
                  childCount:
                      (_demandes.length * 2 - 1) + (_loadingMore ? 1 : 0),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DemandePrestataireCard extends StatelessWidget {
  _DemandePrestataireCard({
    required this.demande,
    required this.busy,
    required this.unreadCount,
    required this.onRefuse,
    required this.onStart,
    required this.onFinish,
    required this.onChat,
  });

  final DemandeService demande;
  final bool busy;
  final int unreadCount;
  final VoidCallback onRefuse;
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final meta = _statusMeta(demande.statut);
    final isInProgress = demande.statut == 'en_cours';
    return _GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primarySurface,
                child: Text(
                  demande.client.displayName.isNotEmpty
                      ? demande.client.displayName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      demande.client.displayName,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      demande.client.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: AppColors.textHint, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (isInProgress) ...[
                _WorkInProgressIndicator(color: meta.color),
                SizedBox(width: 8),
              ],
              _StatusBadge(meta: meta),
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
              fontSize: 13,
              height: 1.35,
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
              if (demande.dateCreation != null)
                _InfoStripItem(
                  Icons.inbox_outlined,
                  'Reçue ${_formatDate(demande.dateCreation!)}',
                ),
            ],
          ),
          SizedBox(height: 10),
          if (busy)
            Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2.4,
                ),
              ),
            )
          else
            _ActionRow(
              statut: demande.statut,
              onRefuse: onRefuse,
              onStart: onStart,
              onFinish: onFinish,
              onChat: onChat,
              unreadCount: unreadCount,
            ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  _ActionRow({
    required this.statut,
    required this.onRefuse,
    required this.onStart,
    required this.onFinish,
    required this.onChat,
    required this.unreadCount,
  });

  final String statut;
  final VoidCallback onRefuse;
  final VoidCallback onStart;
  final VoidCallback onFinish;
  final VoidCallback onChat;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    if (statut == 'en_attente') {
      return Row(
        children: [
          Expanded(
            child: _ActionButton(
              label: 'Refuser',
              icon: Icons.close_rounded,
              color: AppColors.error,
              outline: true,
              onTap: onRefuse,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: _ActionButton(
              label: 'Chat',
              icon: Icons.chat_bubble_outline_rounded,
              color: AppColors.primary,
              onTap: onChat,
              badgeCount: unreadCount,
            ),
          ),
        ],
      );
    }
    if (statut == 'acceptee') {
      return Row(
        children: [
          Expanded(
            child: _ActionButton(
              label: 'Chat',
              icon: Icons.chat_bubble_outline_rounded,
              color: AppColors.primary,
              outline: true,
              onTap: onChat,
              badgeCount: unreadCount,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: _ActionButton(
              label: 'Commencer',
              icon: Icons.play_arrow_rounded,
              color: AppColors.info,
              onTap: onStart,
            ),
          ),
        ],
      );
    }
    if (statut == 'en_cours') {
      return Row(
        children: [
          Expanded(
            child: _ActionButton(
              label: 'Chat',
              icon: Icons.chat_bubble_outline_rounded,
              color: AppColors.primary,
              outline: true,
              onTap: onChat,
              badgeCount: unreadCount,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: _ActionButton(
              label: 'Terminer le boulot',
              icon: Icons.done_all_rounded,
              onTap: onFinish,
            ),
          ),
        ],
      );
    }
    return _ActionButton(
      label: 'Chat',
      icon: Icons.chat_bubble_outline_rounded,
      color: AppColors.primary,
      outline: true,
      onTap: onChat,
      badgeCount: unreadCount,
    );
  }
}

class _ProviderRequestsHeader extends StatelessWidget {
  _ProviderRequestsHeader({required this.onBack});
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
                  'Demandes',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Séparez vos demandes envoyées et celles reçues comme prestataire.',
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

class _ProviderDemandesTabs extends StatelessWidget {
  _ProviderDemandesTabs();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            height: 48,
            padding: EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.glassBorder, width: 1.2),
            ),
            child: TabBar(
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(14),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textSecondary,
              labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              unselectedLabelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              tabs: [
                Tab(
                  iconMargin: EdgeInsets.zero,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.send_outlined, size: 16),
                      SizedBox(width: 6),
                      Text('Envoyées'),
                    ],
                  ),
                ),
                Tab(
                  iconMargin: EdgeInsets.zero,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox_outlined, size: 16),
                      SizedBox(width: 6),
                      Text('Reçues'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
    'en_attente': 'Nouvelles',
    'acceptee': 'Acceptées',
    'en_cours': 'En cours',
    'terminee': 'Terminées',
    'refusee': 'Refusées',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        scrollDirection: Axis.horizontal,
        itemCount: _filters.length,
        separatorBuilder: (_, __) => SizedBox(width: 8),
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
      ),
    );
  }
}

class _AccessScaffold extends StatelessWidget {
  _AccessScaffold({
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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GradientBackground(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: _GlassPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.assignment_ind_outlined,
                      color: AppColors.primary,
                      size: 42,
                    ),
                    SizedBox(height: 12),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                    SizedBox(height: 18),
                    _ActionButton(
                      label: actionLabel,
                      icon: Icons.arrow_forward_rounded,
                      onTap: onAction,
                    ),
                  ],
                ),
              ),
            ),
          ),
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
          width: double.infinity,
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

class _ActionButton extends StatelessWidget {
  _ActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color = AppColors.primary,
    this.outline = false,
    this.badgeCount = 0,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  final bool outline;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 42,
            decoration: BoxDecoration(
              gradient: outline
                  ? null
                  : LinearGradient(
                      colors: [color, color.withValues(alpha: 0.78)],
                    ),
              color: outline ? color.withValues(alpha: 0.08) : null,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: color.withValues(alpha: outline ? 0.45 : 0),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: outline ? color : Colors.white, size: 18),
                SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: outline ? color : Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
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
    ('en_attente', 'Reçue'),
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

class _EmptyRequests extends StatelessWidget {
  _EmptyRequests({required this.title, required this.message});
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 42, 20, 110),
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
                Icons.inbox_outlined,
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
                    width: 44,
                    height: 44,
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
                          width: 150,
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

String _formatDate(DateTime date) {
  final local = date.toLocal();
  return '${local.day.toString().padLeft(2, '0')}/'
      '${local.month.toString().padLeft(2, '0')}/'
      '${local.year}';
}
