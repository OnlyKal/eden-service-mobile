class ConversationDemande {
  const ConversationDemande({
    required this.id,
    required this.statut,
    this.conversationId,
  });

  final int id;
  final String statut;
  final int? conversationId;

  factory ConversationDemande.fromJson(Map<String, dynamic> json) {
    return ConversationDemande(
      id: json['id'] as int? ?? 0,
      statut: json['statut'] as String? ?? '',
      conversationId: json['conversation_id'] as int?,
    );
  }
}

class ConversationClient {
  const ConversationClient({
    required this.id,
    required this.username,
    this.firstName = '',
    this.lastName = '',
  });

  final int id;
  final String username;
  final String firstName;
  final String lastName;

  factory ConversationClient.fromJson(Map<String, dynamic> json) {
    return ConversationClient(
      id: json['id'] as int? ?? 0,
      username: json['username'] as String? ?? 'Client',
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
    );
  }

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isNotEmpty ? full : 'Client';
  }
}

class ConversationPrestataire {
  const ConversationPrestataire({required this.id, required this.typeService});

  final int id;
  final String typeService;

  factory ConversationPrestataire.fromJson(Map<String, dynamic> json) {
    return ConversationPrestataire(
      id: json['id'] as int? ?? 0,
      typeService: json['type_service'] as String? ?? 'Service',
    );
  }
}

class Conversation {
  const Conversation({
    required this.id,
    required this.demande,
    required this.client,
    required this.prestataire,
    this.dernierMessage,
    this.dateCreation,
    this.dateModification,
    this.unreadCount,
  });

  final int id;
  final ConversationDemande demande;
  final ConversationClient client;
  final ConversationPrestataire prestataire;
  final ChatMessage? dernierMessage;
  final DateTime? dateCreation;
  final DateTime? dateModification;
  final int? unreadCount;

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final dernierRaw = json['dernier_message'];
    return Conversation(
      id: json['id'] as int? ?? 0,
      demande: ConversationDemande.fromJson(
        json['demande'] as Map<String, dynamic>? ?? const {},
      ),
      client: ConversationClient.fromJson(
        json['client'] as Map<String, dynamic>? ?? const {},
      ),
      prestataire: ConversationPrestataire.fromJson(
        json['prestataire'] as Map<String, dynamic>? ?? const {},
      ),
      dernierMessage: dernierRaw is Map<String, dynamic>
          ? ChatMessage.fromJson(dernierRaw)
          : null,
      dateCreation: DateTime.tryParse(json['date_creation'] as String? ?? ''),
      dateModification: DateTime.tryParse(
        json['date_modification'] as String? ?? '',
      ),
      unreadCount: _parseIntOrNull(
        json['unread_count'] ??
            json['messages_non_lus'] ??
            json['non_lus'] ??
            json['unread_messages_count'],
      ),
    );
  }
}

class PaginatedConversations {
  const PaginatedConversations({
    required this.count,
    this.next,
    this.previous,
    required this.results,
  });

  final int count;
  final String? next;
  final String? previous;
  final List<Conversation> results;

  factory PaginatedConversations.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? const {};
    return PaginatedConversations(
      count: data['count'] as int? ?? 0,
      next: data['next'] as String?,
      previous: data['previous'] as String?,
      results: (data['results'] as List<dynamic>? ?? const [])
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ChatSender {
  const ChatSender({
    required this.id,
    required this.username,
    this.firstName = '',
    this.lastName = '',
  });

  final int id;
  final String username;
  final String firstName;
  final String lastName;

  factory ChatSender.fromJson(Map<String, dynamic> json) {
    return ChatSender(
      id: json['id'] as int? ?? json['user_id'] as int? ?? 0,
      username: json['username'] as String? ?? '',
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
    );
  }

  String get displayName {
    final full = '$firstName $lastName'.trim();
    return full.isNotEmpty ? full : 'Utilisateur';
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.contenu,
    this.sender,
    this.dateCreation,
    this.isLocalPending = false,
  });

  final int id;
  final String contenu;
  final ChatSender? sender;
  final DateTime? dateCreation;
  final bool isLocalPending;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final senderRaw =
        json['sender'] ?? json['expediteur'] ?? json['utilisateur'];
    final contenuRaw = json['contenu'] ?? json['message'] ?? json['content'];
    return ChatMessage(
      id: json['id'] as int? ?? 0,
      contenu: contenuRaw as String? ?? '',
      sender: senderRaw is Map<String, dynamic>
          ? ChatSender.fromJson(senderRaw)
          : senderRaw is int
          ? ChatSender(id: senderRaw, username: '')
          : null,
      dateCreation: DateTime.tryParse(
        json['date_creation'] as String? ??
            json['created_at'] as String? ??
            json['timestamp'] as String? ??
            '',
      ),
    );
  }

  ChatMessage copyWithPending(bool value) {
    return ChatMessage(
      id: id,
      contenu: contenu,
      sender: sender,
      dateCreation: dateCreation,
      isLocalPending: value,
    );
  }
}

class PaginatedMessages {
  const PaginatedMessages({
    required this.count,
    this.next,
    this.previous,
    required this.results,
  });

  final int count;
  final String? next;
  final String? previous;
  final List<ChatMessage> results;

  factory PaginatedMessages.fromJson(Map<String, dynamic> json) {
    final data = json['data'];
    final payload = data is Map<String, dynamic> ? data : json;
    final rawResults = payload['results'] ?? payload['messages'] ?? data;
    final list = rawResults is List<dynamic> ? rawResults : const [];
    return PaginatedMessages(
      count: payload['count'] as int? ?? list.length,
      next: payload['next'] as String?,
      previous: payload['previous'] as String?,
      results: list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

int? _parseIntOrNull(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
