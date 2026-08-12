// ── Requests ─────────────────────────────────────────────────────────────────

class LoginRequest {
  final String identifier;
  final String password;

  const LoginRequest({required this.identifier, required this.password});

  Map<String, dynamic> toJson() => {
    'identifier': identifier,
    'password': password,
  };
}

class RegisterRequest {
  final String? username;
  final String email;
  final String password;
  final String firstName;
  final String lastName;
  final String telephone;

  const RegisterRequest({
    this.username,
    required this.email,
    required this.password,
    required this.firstName,
    required this.lastName,
    required this.telephone,
  });

  Map<String, dynamic> toJson() => {
    if (username?.trim().isNotEmpty == true) 'username': username!.trim(),
    if (email.trim().isNotEmpty) 'email': email.trim(),
    'password': password,
    'first_name': firstName,
    'last_name': lastName,
    'telephone': telephone,
  };
}

// ── Response ─────────────────────────────────────────────────────────────────

class AuthData {
  final String token;
  final int userId;
  final String username;
  final String email;
  final bool estPrestataire;
  final String? photo;
  final String? firstName;
  final String? lastName;
  final String? telephone;

  const AuthData({
    required this.token,
    required this.userId,
    required this.username,
    required this.email,
    required this.estPrestataire,
    this.photo,
    this.firstName,
    this.lastName,
    this.telephone,
  });

  factory AuthData.fromJson(Map<String, dynamic> json) => AuthData(
    token: json['token'] as String,
    userId: json['user_id'] as int,
    username: json['username'] as String,
    email: json['email'] as String,
    estPrestataire: json['est_prestataire'] as bool,
    // API returns 'photo_profil'; stored session uses 'photo'
    photo: (json['photo_profil'] ?? json['photo']) as String?,
    firstName: json['first_name'] as String?,
    lastName: json['last_name'] as String?,
    telephone: json['telephone'] as String?,
  );

  /// Creates a copy with updated profile fields, keeping the auth token.
  AuthData copyWithProfile({
    String? email,
    String? firstName,
    String? lastName,
    String? telephone,
    String? photo,
  }) => AuthData(
    token: token,
    userId: userId,
    username: username,
    email: email ?? this.email,
    estPrestataire: estPrestataire,
    photo: photo ?? this.photo,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    telephone: telephone ?? this.telephone,
  );

  /// Creates a copy after becoming a provider (flips estPrestataire to true).
  AuthData copyWithPrestataire({bool estPrestataire = true, String? photo}) =>
      AuthData(
        token: token,
        userId: userId,
        username: username,
        email: email,
        estPrestataire: estPrestataire,
        photo: photo ?? this.photo,
        firstName: firstName,
        lastName: lastName,
        telephone: telephone,
      );

  String get displayName {
    final full = '${firstName ?? ''} ${lastName ?? ''}'.trim();
    return full.isNotEmpty ? full : 'Utilisateur';
  }
}

class LoginResponse {
  final bool success;
  final AuthData? data;
  final String message;
  final int statusCode;

  const LoginResponse({
    required this.success,
    this.data,
    required this.message,
    required this.statusCode,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) => LoginResponse(
    success: json['success'] as bool,
    data: json['data'] != null
        ? AuthData.fromJson(json['data'] as Map<String, dynamic>)
        : null,
    message: json['message'] as String,
    statusCode: json['status_code'] as int,
  );
}
