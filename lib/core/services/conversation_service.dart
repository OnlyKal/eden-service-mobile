import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../models/conversation_models.dart';
import 'app_refresh_service.dart';
import 'auth_service.dart';

class ConversationService {
  ConversationService._();
  static final ConversationService instance = ConversationService._();

  Future<PaginatedConversations> getConversations() async {
    final response = await http.get(
      Uri.parse(ApiConstants.conversations),
      headers: _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(
          response,
          'Erreur ${response.statusCode} lors du chargement des conversations',
        ),
      );
    }

    return PaginatedConversations.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<Conversation> getConversationForDemande(int demandeId) async {
    final conversations = await getConversations();
    return conversations.results.firstWhere(
      (conversation) => conversation.demande.id == demandeId,
      orElse: () => throw Exception(
        'Conversation introuvable pour cette demande. Réessayez dans un instant.',
      ),
    );
  }

  Future<List<ChatMessage>> getMessages(int conversationId) async {
    final response = await http.get(
      Uri.parse(ApiConstants.conversationMessages(conversationId)),
      headers: _headers(),
    );

    if (response.statusCode != 200) {
      throw Exception(
        _errorMessage(
          response,
          'Erreur ${response.statusCode} lors du chargement des messages',
        ),
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return PaginatedMessages.fromJson(body).results;
  }

  Future<ChatMessage> sendMessage(int conversationId, String contenu) async {
    final response = await http.post(
      Uri.parse(ApiConstants.conversationMessages(conversationId)),
      headers: _headers(),
      body: jsonEncode({'contenu': contenu}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        _errorMessage(
          response,
          'Erreur ${response.statusCode} lors de l’envoi du message',
        ),
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final data = body['data'];
    final message = data is Map<String, dynamic>
        ? ChatMessage.fromJson(data)
        : ChatMessage.fromJson(body);
    AppRefreshService.instance.notify(const {
      AppRefreshTopic.conversations,
      AppRefreshTopic.demandes,
      AppRefreshTopic.notifications,
    });
    return message;
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
