import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/models/notification_models.dart';
import '../core/services/app_refresh_service.dart';
import '../core/services/auth_service.dart';
import '../core/services/notification_navigation_service.dart';
import '../core/services/notification_service.dart';
import '../theme/app_colors.dart';
import '../widgets/gradient_background.dart';
import 'login_screen.dart';

class NotificationsScreen extends StatefulWidget {
  NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _loading = true;
  bool _markingAll = false;
  int? _busyId;
  int _lastRefreshTick = 0;
  final Set<int> _readLocallyIds = {};
  List<AppNotification> _notifications = [];

  @override
  void initState() {
    super.initState();
    AppRefreshService.instance.tick.addListener(_onAppRefresh);
    _loadNotifications();
  }

  @override
  void dispose() {
    AppRefreshService.instance.tick.removeListener(_onAppRefresh);
    super.dispose();
  }

  void _onAppRefresh() {
    final refresh = AppRefreshService.instance;
    if (_lastRefreshTick == refresh.tick.value) return;
    _lastRefreshTick = refresh.tick.value;
    if (refresh.hasAny({
      AppRefreshTopic.auth,
      AppRefreshTopic.notifications,
      AppRefreshTopic.demandes,
      AppRefreshTopic.conversations,
    })) {
      if (_busyId != null || _markingAll) return;
      _loadNotifications(silent: true);
    }
  }

  List<AppNotification> _applyLocalReadState(
    List<AppNotification> notifications,
  ) {
    if (_readLocallyIds.isEmpty) return notifications;
    return notifications
        .map(
          (item) => _readLocallyIds.contains(item.id)
              ? item.copyWith(isRead: true)
              : item,
        )
        .toList();
  }

  Future<void> _loadNotifications({bool silent = false}) async {
    if (!AuthService.instance.isLoggedIn) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!silent) setState(() => _loading = true);
    try {
      final response = await NotificationService.instance.getNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = _applyLocalReadState(response.results);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack('Impossible de charger les notifications. Réessayez.');
    }
  }

  Future<void> _markAsRead(AppNotification notification) async {
    if (notification.isRead || _busyId != null) return;
    setState(() {
      _busyId = notification.id;
      _readLocallyIds.add(notification.id);
      _notifications = _notifications
          .map(
            (item) =>
                item.id == notification.id ? item.copyWith(isRead: true) : item,
          )
          .toList();
    });
    try {
      await NotificationService.instance.markAsRead(notification.id);
    } catch (_) {
      if (mounted) {
        setState(() {
          _readLocallyIds.remove(notification.id);
          _notifications = _notifications
              .map(
                (item) => item.id == notification.id
                    ? item.copyWith(isRead: notification.isRead)
                    : item,
              )
              .toList();
        });
      }
      _showSnack('Impossible de marquer cette notification.');
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _openNotification(AppNotification notification) async {
    await _markAsRead(notification);
    await NotificationNavigationService.instance.handlePayload({
      if (notification.conversationId != null)
        'conversation_id': notification.conversationId,
      if (notification.demandeId != null) 'demande_id': notification.demandeId,
      if (notification.type != null) 'type': notification.type,
    });
  }

  Future<void> _markAllAsRead() async {
    if (_markingAll || !_notifications.any((item) => !item.isRead)) return;
    final previous = List<AppNotification>.from(_notifications);
    setState(() {
      _markingAll = true;
      _readLocallyIds.addAll(_notifications.map((item) => item.id));
      _notifications = _notifications
          .map((item) => item.copyWith(isRead: true))
          .toList();
    });
    try {
      await NotificationService.instance.markAllAsRead();
    } catch (_) {
      if (mounted) {
        setState(() {
          _readLocallyIds.clear();
          _notifications = previous;
        });
      }
      _showSnack('Impossible de marquer les notifications.');
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  void _showSnack(String message) {
    debugPrint('[Notifications] $message');
  }

  @override
  Widget build(BuildContext context) {
    if (!AuthService.instance.isLoggedIn) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: GradientBackground(
          child: SafeArea(
            child: _AccessState(
              onBack: () => Navigator.maybePop(context),
              onLogin: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => LoginScreen())),
            ),
          ),
        ),
      );
    }

    final unreadCount = _notifications.where((item) => !item.isRead).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GradientBackground(
        child: SafeArea(
          bottom: false,
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => _loadNotifications(),
            child: CustomScrollView(
              physics: AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: _Header(
                    unreadCount: unreadCount,
                    markingAll: _markingAll,
                    onBack: () => Navigator.maybePop(context),
                    onMarkAll: _markAllAsRead,
                  ),
                ),
                if (_loading)
                  SliverToBoxAdapter(child: _NotificationsLoading())
                else if (_notifications.isEmpty)
                  SliverToBoxAdapter(child: _EmptyNotifications())
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(20, 10, 20, 110),
                    sliver: SliverList.separated(
                      itemCount: _notifications.length,
                      separatorBuilder: (_, __) => SizedBox(height: 12),
                      itemBuilder: (_, index) {
                        final notification = _notifications[index];
                        return _NotificationCard(
                          notification: notification,
                          busy: _busyId == notification.id,
                          onTap: () =>
                              unawaited(_openNotification(notification)),
                        );
                      },
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

class _Header extends StatelessWidget {
  _Header({
    required this.unreadCount,
    required this.markingAll,
    required this.onBack,
    required this.onMarkAll,
  });

  final int unreadCount;
  final bool markingAll;
  final VoidCallback onBack;
  final VoidCallback onMarkAll;

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
                  'Notifications',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  unreadCount == 0
                      ? 'Tout est à jour'
                      : '$unreadCount notification${unreadCount > 1 ? 's' : ''} non lue${unreadCount > 1 ? 's' : ''}',
                  style: TextStyle(color: AppColors.textHint, fontSize: 12),
                ),
              ],
            ),
          ),
          if (unreadCount > 0)
            _TextAction(
              loading: markingAll,
              label: 'Tout lire',
              onTap: onMarkAll,
            ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  _NotificationCard({
    required this.notification,
    required this.busy,
    required this.onTap,
  });

  final AppNotification notification;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !notification.isRead;
    return GestureDetector(
      onTap: onTap,
      child: _GlassPanel(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: unread
                    ? AppColors.primarySurface
                    : AppColors.divider.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                unread
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                color: unread ? AppColors.primary : AppColors.textHint,
                size: 22,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.message.isEmpty
                        ? 'Nouvelle notification'
                        : notification.message,
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: unread ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _formatDate(notification.dateCreation),
                    style: TextStyle(
                      color: AppColors.textHint,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (busy)
              SizedBox(
                width: 24,
                height: 24,
                child: Padding(
                  padding: EdgeInsets.all(3),
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 2,
                  ),
                ),
              )
            else if (unread)
              Container(
                width: 9,
                height: 9,
                margin: EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AccessState extends StatelessWidget {
  _AccessState({required this.onBack, required this.onLogin});

  final VoidCallback onBack;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _IconBubble(icon: Icons.arrow_back_rounded, onTap: onBack),
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: _GlassPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      color: AppColors.primary,
                      size: 42,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Connectez-vous',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Vos notifications sont liées à votre compte.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    SizedBox(height: 18),
                    _PrimaryButton(
                      label: 'Connexion',
                      icon: Icons.login_rounded,
                      onTap: onLogin,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 44, 20, 110),
      child: _GlassPanel(
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primarySurface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                color: AppColors.primary,
                size: 36,
              ),
            ),
            SizedBox(height: 14),
            Text(
              'Aucune notification',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 8),
            Text(
              'Les confirmations, messages et mises à jour apparaîtront ici.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationsLoading extends StatelessWidget {
  _NotificationsLoading();

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
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          height: 12,
                          width: 210,
                          decoration: BoxDecoration(
                            color: AppColors.divider,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        SizedBox(height: 8),
                        Container(
                          height: 10,
                          width: 120,
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

class _TextAction extends StatelessWidget {
  _TextAction({
    required this.loading,
    required this.label,
    required this.onTap,
  });

  final bool loading;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 38,
        padding: EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primarySurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.22)),
        ),
        child: loading
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 2,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
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
          padding: EdgeInsets.all(16),
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

class _PrimaryButton extends StatelessWidget {
  _PrimaryButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDate(DateTime? date) {
  if (date == null) return 'À l’instant';
  final now = DateTime.now();
  final diff = now.difference(date.toLocal());
  if (diff.inMinutes < 1) return 'À l’instant';
  if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'Il y a ${diff.inHours} h';
  if (diff.inDays < 7) return 'Il y a ${diff.inDays} j';
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
