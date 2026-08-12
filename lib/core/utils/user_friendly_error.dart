String userFriendlyError(Object error, {String? fallback}) {
  final raw = error.toString().toLowerCase();
  if (raw.contains('socketexception') ||
      raw.contains('clientexception') ||
      raw.contains('failed host lookup') ||
      raw.contains('network is unreachable') ||
      raw.contains('connection') ||
      raw.contains('bad file descriptor') ||
      raw.contains('timed out') ||
      raw.contains('timeout')) {
    return 'Connexion indisponible. Vérifiez votre internet puis réessayez.';
  }

  final cleaned = error.toString().replaceFirst('Exception: ', '').trim();
  if (cleaned.isNotEmpty &&
      !cleaned.contains('http') &&
      !cleaned.contains('SocketException') &&
      !cleaned.contains('ClientException')) {
    return cleaned;
  }

  return fallback ?? 'Une erreur est survenue. Réessayez dans un instant.';
}
