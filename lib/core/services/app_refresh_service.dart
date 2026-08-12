import 'dart:async';

import 'package:flutter/foundation.dart';

enum AppRefreshTopic {
  auth,
  home,
  prestataires,
  favorites,
  demandes,
  conversations,
  notifications,
  statuts,
  profile,
  ratings,
  abonnement,
}

class AppRefreshService {
  AppRefreshService._();

  static final AppRefreshService instance = AppRefreshService._();

  final ValueNotifier<int> tick = ValueNotifier<int>(0);
  final ValueNotifier<Set<AppRefreshTopic>> topics =
      ValueNotifier<Set<AppRefreshTopic>>(<AppRefreshTopic>{});

  Timer? _debounce;
  Set<AppRefreshTopic> _pendingTopics = <AppRefreshTopic>{};

  void notify(Iterable<AppRefreshTopic> changed) {
    final changedSet = changed.toSet();
    if (changedSet.isEmpty) return;

    _pendingTopics = <AppRefreshTopic>{..._pendingTopics, ...changedSet};
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      topics.value = _pendingTopics;
      _pendingTopics = <AppRefreshTopic>{};
      tick.value++;
    });
  }

  void notifyAuthChanged() {
    notify(const {
      AppRefreshTopic.auth,
      AppRefreshTopic.home,
      AppRefreshTopic.prestataires,
      AppRefreshTopic.favorites,
      AppRefreshTopic.demandes,
      AppRefreshTopic.conversations,
      AppRefreshTopic.notifications,
      AppRefreshTopic.statuts,
      AppRefreshTopic.profile,
      AppRefreshTopic.abonnement,
    });
  }

  bool hasAny(Iterable<AppRefreshTopic> wanted) {
    final current = topics.value;
    return wanted.any(current.contains);
  }
}
