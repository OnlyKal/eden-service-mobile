bool _parseBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.toLowerCase().trim();
    return normalized == 'true' ||
        normalized == '1' ||
        normalized == 'yes' ||
        normalized == 'oui';
  }
  return false;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.message,
    required this.isRead,
    this.type,
    this.demandeId,
    this.conversationId,
    this.statutId,
    this.dateCreation,
  });

  final int id;
  final String message;
  final bool isRead;
  final String? type;
  final int? demandeId;
  final int? conversationId;
  final int? statutId;
  final DateTime? dateCreation;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    final conversationRaw = json['conversation'];
    final demandeRaw = json['demande'];
    final statutRaw = json['statut'];
    return AppNotification(
      id: json['id'] as int? ?? 0,
      message: json['message'] as String? ?? json['contenu'] as String? ?? '',
      isRead: _parseBool(
        json['is_read'] ??
            json['isRead'] ??
            json['lue'] ??
            json['lu'] ??
            json['est_lue'] ??
            json['est_lu'] ??
            json['read'],
      ),
      type: json['type'] as String? ?? json['type_notification'] as String?,
      demandeId:
          _parseIntOrNull(
            json['demande_id'] ?? json['demandeId'] ?? json['demande'],
          ) ??
          (demandeRaw is Map<String, dynamic>
              ? _parseIntOrNull(demandeRaw['id'])
              : null),
      conversationId:
          _parseIntOrNull(
            json['conversation_id'] ??
                json['conversationId'] ??
                json['conversation'],
          ) ??
          (conversationRaw is Map<String, dynamic>
              ? _parseIntOrNull(conversationRaw['id'])
              : null),
      statutId:
          _parseIntOrNull(
            json['statut_id'] ?? json['statutId'] ?? json['statut'],
          ) ??
          (statutRaw is Map<String, dynamic>
              ? _parseIntOrNull(statutRaw['id'])
              : null),
      dateCreation: DateTime.tryParse(json['date_creation'] as String? ?? ''),
    );
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      message: message,
      isRead: isRead ?? this.isRead,
      type: type,
      demandeId: demandeId,
      conversationId: conversationId,
      statutId: statutId,
      dateCreation: dateCreation,
    );
  }
}

int? _parseIntOrNull(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

class PaginatedNotifications {
  const PaginatedNotifications({
    required this.count,
    this.next,
    this.previous,
    required this.results,
  });

  final int count;
  final String? next;
  final String? previous;
  final List<AppNotification> results;

  factory PaginatedNotifications.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? const {};
    return PaginatedNotifications(
      count: data['count'] as int? ?? 0,
      next: data['next'] as String?,
      previous: data['previous'] as String?,
      results: (data['results'] as List<dynamic>? ?? const [])
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
