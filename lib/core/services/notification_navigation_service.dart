import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../screens/conversation_screen.dart';
import '../../screens/demandes_client_screen.dart';
import '../../screens/demandes_prestataire_screen.dart';
import '../../screens/login_screen.dart';
import '../../screens/statuts_prestataires_screen.dart';
import '../models/demande_service_models.dart';
import 'auth_service.dart';
import 'conversation_unread_service.dart';
import 'demande_service_service.dart';
import 'notification_service.dart';
import 'statut_prestataire_service.dart';

class NotificationNavigationService {
  NotificationNavigationService._();

  static final NotificationNavigationService instance =
      NotificationNavigationService._();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final List<Map<String, dynamic>> _pendingPayloads = <Map<String, dynamic>>[];
  bool _navigating = false;

  Future<void> handlePayload(Map<String, dynamic> payload) async {
    if (payload.isEmpty) return;
    if (navigatorKey.currentState == null) {
      _pendingPayloads.add(payload);
      return;
    }
    if (_navigating) {
      _pendingPayloads.add(payload);
      return;
    }

    _navigating = true;
    try {
      await _openFromPayload(payload);
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('[NotificationNavigation] failed payload=$payload');
        debugPrint('$error');
        debugPrint('$stackTrace');
      }
    } finally {
      _navigating = false;
    }
  }

  void flushPending() {
    if (_pendingPayloads.isEmpty) return;
    final payloads = List<Map<String, dynamic>>.from(_pendingPayloads);
    _pendingPayloads.clear();
    for (final payload in payloads) {
      unawaited(handlePayload(payload));
    }
  }

  Future<void> _openFromPayload(Map<String, dynamic> payload) async {
    if (!AuthService.instance.isLoggedIn) {
      final navigator = navigatorKey.currentState;
      if (navigator == null) return;
      await navigator.push(MaterialPageRoute(builder: (_) => LoginScreen()));
      if (!AuthService.instance.isLoggedIn) return;
    }

    final notificationId = _parseInt(
      payload['notification_id'] ?? payload['notificationId'],
    );
    if (notificationId != null && notificationId > 0) {
      unawaited(NotificationService.instance.markAsRead(notificationId));
    }

    // Statut (like, commentaire, nouveau statut, etc.)
    final statutId = _parseInt(payload['statut_id'] ?? payload['statutId']);
    if (statutId != null && statutId > 0) {
      await _openStatut(statutId);
      return;
    }

    final conversationId = _parseInt(
      payload['conversation_id'] ?? payload['conversationId'],
    );
    if (conversationId != null && conversationId > 0) {
      await _openConversation(conversationId);
      return;
    }

    final demandeId = _parseInt(payload['demande_id'] ?? payload['demandeId']);
    if (demandeId != null && demandeId > 0) {
      final demande = await DemandeServiceService.instance.getDemande(
        demandeId,
      );
      if (demande.conversationId != null && demande.conversationId! > 0) {
        await _openConversation(demande.conversationId!, demande);
        return;
      }
      await _openDemandes();
    }
  }

  /// Ouvre directement le statut concerné (like, commentaire, nouveau statut).
  Future<void> _openStatut(int statutId) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    try {
      final statut = await StatutPrestataireService.instance.getStatut(
        statutId,
      );
      if (statut.id <= 0) return;
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => StatutViewerScreen(
            statuts: [statut],
            initialIndex: 0,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[NotificationNavigation] open statut error: $e');
      // Fallback : ouvre l'écran des statuts.
      await navigator.push(
        MaterialPageRoute(builder: (_) => StatutsPrestatairesScreen()),
      );
    }
  }

  Future<void> _openConversation(
    int conversationId, [
    DemandeService? fallbackDemande,
  ]) async {
    final unread = ConversationUnreadService.instance;
    await unread.syncAndWatchConversations();
    final conversation = unread.conversationFor(conversationId);
    final demande =
        fallbackDemande ?? await unread.demandeForConversation(conversationId);
    if (demande == null) {
      await _openDemandes();
      return;
    }

    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    unread.markConversationOpen(conversationId);
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => ConversationScreen(
          demande: demande,
          title: conversation == null
              ? _titleForDemande(demande)
              : unread.titleFor(conversation),
          allowAcceptPrestation:
              AuthService.instance.currentUser?.estPrestataire ?? false,
        ),
      ),
    );
    unread.markConversationRead(conversationId);
    await unread.syncAndWatchConversations();
  }

  Future<void> _openDemandes() async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    final isPrestataire =
        AuthService.instance.currentUser?.estPrestataire ?? false;
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => isPrestataire
            ? DemandesPrestataireScreen()
            : DemandesClientScreen(),
      ),
    );
  }

  String _titleForDemande(DemandeService demande) {
    if (AuthService.instance.currentUser?.estPrestataire ?? false) {
      return demande.client.displayName;
    }
    final service = demande.prestataire.typeService?.trim();
    return service == null || service.isEmpty ? 'Conversation' : service;
  }
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
