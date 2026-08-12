import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../models/notification_models.dart';
import 'app_refresh_service.dart';
import 'auth_service.dart';
import 'user_realtime_service.dart';

class NotificationBadgeService {
  NotificationBadgeService._();

  static final NotificationBadgeService instance = NotificationBadgeService._();

  final ValueNotifier<int> count = ValueNotifier<int>(0);

  StreamSubscription<UserRealtimeEvent>? _subscription;
  final Set<int> _unreadIds = <int>{};
  int _fallbackUnreadCount = 0;
  bool _watching = false;
  DateTime? _lastRealtimeNotificationAt;

  int get totalUnread => count.value;

  Future<void> syncAndWatch() async {
    if (!AuthService.instance.isLoggedIn) {
      clear();
      return;
    }

    await syncUnreadCount();
    watch();
  }

  Future<void> syncUnreadCount() async {
    final token = AuthService.instance.currentUser?.token;
    if (token == null || token.trim().isEmpty) {
      _setCount(0);
      return;
    }

    try {
      final response = await http.get(
        Uri.parse(ApiConstants.notifications),
        headers: {'Content-Type': 'application/json', 'Authorization': token},
      );
      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final notifications = PaginatedNotifications.fromJson(decoded).results;
      final nextUnreadIds = notifications
          .where((notification) => !notification.isRead)
          .map((notification) => notification.id)
          .where((id) => id > 0)
          .toSet();
      final nextFallbackUnreadCount = notifications
          .where((notification) => !notification.isRead && notification.id <= 0)
          .length;
      final nextTotal = nextUnreadIds.length + nextFallbackUnreadCount;
      final recentlyReceivedRealtime =
          _lastRealtimeNotificationAt != null &&
          DateTime.now().difference(_lastRealtimeNotificationAt!) <
              Duration(seconds: 5);
      if (recentlyReceivedRealtime && nextTotal < count.value) {
        _unreadIds.addAll(nextUnreadIds);
        _fallbackUnreadCount = count.value - _unreadIds.length;
        if (_fallbackUnreadCount < 0) _fallbackUnreadCount = 0;
        _emit();
        return;
      }

      _unreadIds
        ..clear()
        ..addAll(nextUnreadIds);
      _fallbackUnreadCount = nextFallbackUnreadCount;
      _emit();
    } catch (_) {
      // Keep the last known badge count if the HTTP refresh fails.
    }
  }

  void watch() {
    final token = AuthService.instance.currentUser?.token;
    if (token == null || token.trim().isEmpty) return;

    if (_watching) return;
    _watching = true;
    UserRealtimeService.instance.watch();
    _subscription = UserRealtimeService.instance.events.listen(
      _handleRealtimeEvent,
    );
  }

  void unwatch() {
    if (!_watching) return;
    _watching = false;
    _subscription?.cancel();
    _subscription = null;
    UserRealtimeService.instance.unwatch();
  }

  void applyRemoteMessageData(Map<String, dynamic> data) {
    if (!AuthService.instance.isLoggedIn) return;
    _lastRealtimeNotificationAt = DateTime.now();
    final id = _parseInt(data['notification_id'] ?? data['notificationId']);
    if (id != null && id > 0) {
      if (_unreadIds.add(id)) _emit(notifyRefresh: true);
      return;
    }

    _fallbackUnreadCount++;
    _emit(notifyRefresh: true);
  }

  void markRead(int notificationId) {
    if (notificationId <= 0) return;
    var changed = _unreadIds.remove(notificationId);
    if (!changed && _fallbackUnreadCount > 0) {
      _fallbackUnreadCount--;
      changed = true;
    }
    if (changed) _emit();
  }

  void markAllRead() {
    if (_unreadIds.isEmpty && _fallbackUnreadCount == 0 && count.value == 0) {
      return;
    }
    _unreadIds.clear();
    _fallbackUnreadCount = 0;
    _setCount(0);
  }

  void clear() {
    final wasWatching = _watching;
    _watching = false;
    _unreadIds.clear();
    _fallbackUnreadCount = 0;
    _setCount(0);
    _subscription?.cancel();
    _subscription = null;
    if (wasWatching) UserRealtimeService.instance.unwatch();
  }

  void _handleRealtimeEvent(UserRealtimeEvent event) {
    try {
      if (event.type != 'notification') return;
      final data = event.data;
      final notification = AppNotification.fromJson(data);
      if (notification.isRead) {
        markRead(notification.id);
        return;
      }
      if (notification.id > 0) {
        if (!_unreadIds.add(notification.id)) return;
      } else {
        _fallbackUnreadCount++;
      }
      _lastRealtimeNotificationAt = DateTime.now();
      _emit(notifyRefresh: true);
    } catch (_) {
      // Ignore malformed realtime payloads without interrupting the app.
    }
  }

  void _emit({bool notifyRefresh = false}) {
    final total = _unreadIds.length + _fallbackUnreadCount;
    _setCount(total);
    if (notifyRefresh) {
      AppRefreshService.instance.notify(const {AppRefreshTopic.notifications});
    }
  }

  void _setCount(int value) {
    final next = value < 0 ? 0 : value;
    if (count.value != next) count.value = next;
  }

  int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
