import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/statut_prestataire_models.dart';
import 'app_refresh_service.dart';
import 'auth_service.dart';
import 'statut_prestataire_service.dart';
import 'statut_realtime_service.dart';

class StatutUnreadService {
  StatutUnreadService._();

  static final StatutUnreadService instance = StatutUnreadService._();

  final ValueNotifier<int> count = ValueNotifier<int>(0);

  Timer? _syncDebounce;
  bool _watching = false;

  /// IDs of statuts that are still unread (not viewed by me and not expired).
  final Set<int> _unreadIds = <int>{};

  /// Known expiration for each statut seen, used to purge the unread set when
  /// a statut expires without being explicitly viewed.
  final Map<int, DateTime> _knownExpirations = <int, DateTime>{};

  int get totalUnread => _unreadIds.length;
  bool get hasUnread => _unreadIds.isNotEmpty;

  Future<void> syncAndWatch() async {
    if (!AuthService.instance.isLoggedIn) {
      clear();
      return;
    }
    await syncUnreadCount();
    watch();
  }

  Future<void> syncUnreadCount() async {
    if (!AuthService.instance.isLoggedIn) {
      _clearTracked();
      return;
    }
    try {
      final all = <StatutPrestataire>[];
      var page = 1;
      // Fetch every page (capped at 1000 statuts) so the unread badge is not
      // limited to the first page of results.
      while (all.length < 1000 && page <= 10) {
        final response = await StatutPrestataireService.instance.getStatuts(
          page: page,
          pageSize: 100,
        );
        all.addAll(response.results);
        if (!response.hasNext) break;
        page++;
      }
      _registerStatuts(all, reset: true);
    } catch (_) {
      // Keep the last known value if the lightweight refresh fails.
    }
  }

  void watch() {
    if (_watching) return;
    _watching = true;
    StatutRealtimeService.instance.watchGlobal();
    StatutRealtimeService.instance.watchUser();
    StatutRealtimeService.instance.changes.addListener(_scheduleSync);
  }

  void unwatch() {
    if (!_watching) return;
    _watching = false;
    _syncDebounce?.cancel();
    _syncDebounce = null;
    StatutRealtimeService.instance.changes.removeListener(_scheduleSync);
    StatutRealtimeService.instance.unwatchGlobal();
    StatutRealtimeService.instance.unwatchUser();
  }

  void registerStatuts(Iterable<StatutPrestataire> statuts) {
    _registerStatuts(statuts, reset: false);
  }

  void _registerStatuts(
    Iterable<StatutPrestataire> statuts, {
    required bool reset,
  }) {
    if (reset) {
      _unreadIds.clear();
      _knownExpirations.clear();
    }
    final now = DateTime.now();
    for (final statut in statuts) {
      if (statut.id <= 0) continue;
      if (statut.isExpiredNow) {
        _unreadIds.remove(statut.id);
        _knownExpirations.remove(statut.id);
        continue;
      }
      _knownExpirations[statut.id] =
          statut.dateExpiration ?? now.add(const Duration(hours: 24));
      if (statut.vuParMoi) {
        _unreadIds.remove(statut.id);
      } else {
        _unreadIds.add(statut.id);
      }
    }
    // Purge statuts that expired since the last registration.
    final expiredIds = _knownExpirations.entries
        .where((entry) => !entry.value.isAfter(now))
        .map((entry) => entry.key)
        .toList();
    for (final id in expiredIds) {
      _unreadIds.remove(id);
      _knownExpirations.remove(id);
    }
    _setCount(_unreadIds.length);
  }

  void markViewed(int statutId) {
    if (statutId <= 0) return;
    if (_unreadIds.remove(statutId)) {
      _setCount(_unreadIds.length);
    }
  }

  void clear() {
    unwatch();
    _clearTracked();
  }

  void _clearTracked() {
    _unreadIds.clear();
    _knownExpirations.clear();
    _setCount(0);
  }

  void _scheduleSync() {
    if (!_watching) return;
    _syncDebounce?.cancel();
    _syncDebounce = Timer(Duration(milliseconds: 600), () {
      unawaited(syncUnreadCount());
    });
  }

  void _setCount(int value) {
    final next = value < 0 ? 0 : value;
    if (count.value == next) return;
    count.value = next;
    // Notify only "home" so the badge refreshes without triggering a full
    // reload of the statuts screen (which would cause a refresh loop).
    AppRefreshService.instance.notify(const {
      AppRefreshTopic.home,
    });
  }
}