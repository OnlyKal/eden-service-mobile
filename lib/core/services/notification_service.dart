import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../models/notification_models.dart';
import 'app_refresh_service.dart';
import 'auth_service.dart';
import 'notification_badge_service.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  Future<PaginatedNotifications> getNotifications() async {
    final response = await http.get(
      Uri.parse(ApiConstants.notifications),
      headers: _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(
          response,
          'Erreur ${response.statusCode} lors du chargement des notifications',
        ),
      );
    }

    return PaginatedNotifications.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> markAsRead(int notificationId) async {
    final response = await http.post(
      Uri.parse(ApiConstants.marquerNotificationLue(notificationId)),
      headers: _headers(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _errorMessage(
          response,
          'Erreur ${response.statusCode} lors du marquage de la notification',
        ),
      );
    }
    NotificationBadgeService.instance.markRead(notificationId);
    AppRefreshService.instance.notify(const {
      AppRefreshTopic.notifications,
      AppRefreshTopic.home,
    });
  }

  Future<void> markAllAsRead() async {
    final response = await http.post(
      Uri.parse(ApiConstants.toutMarquerNotificationsLu),
      headers: _headers(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _errorMessage(
          response,
          'Erreur ${response.statusCode} lors du marquage des notifications',
        ),
      );
    }
    NotificationBadgeService.instance.markAllRead();
    AppRefreshService.instance.notify(const {
      AppRefreshTopic.notifications,
      AppRefreshTopic.home,
    });
  }

  Map<String, String> _headers() {
    final token = AuthService.instance.currentUser?.token;
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': token,
    };
  }

  String _errorMessage(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final error = body['error'];
      if (error is Map<String, dynamic> && error['message'] != null) {
        return error['message'] as String;
      }
      if (body['message'] != null) return body['message'] as String;
    } catch (_) {
      return fallback;
    }
    return fallback;
  }
}
