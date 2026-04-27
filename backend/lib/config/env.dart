// ignore_for_file: public_member_api_docs

import 'dart:io';

String get jwtSecret {
  final secret = Platform.environment['JWT_SECRET'];
  if (secret == null || secret.isEmpty) {
    throw StateError('JWT_SECRET environment variable is not set');
  }
  return secret;
}

int get jwtExpiryHours {
  return int.tryParse(Platform.environment['JWT_EXPIRY_HOURS'] ?? '8') ?? 8;
}

/// Returns the database connection string from DATABASE_URL environment variable.
/// Falls back to local development URL if not set.
String get databaseUrl {
  return Platform.environment['DATABASE_URL'] ??
      'postgresql://postgres:12345@localhost:5432/nrs';
}

/// Returns the server port from PORT environment variable.
/// Defaults to 8080 for local development.
int get serverPort {
  return int.tryParse(Platform.environment['PORT'] ?? '8080') ?? 8080;
}

/// Returns the API base URL for internal services.
/// Falls back to localhost for local development.
String get apiBaseUrl {
  return Platform.environment['API_BASE_URL'] ?? 'http://localhost:8080';
}
