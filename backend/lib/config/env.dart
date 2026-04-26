// ignore_for_file: public_member_api_docs

import 'package:dotenv/dotenv.dart';

final _env = DotEnv(includePlatformEnvironment: true)..load();

String get jwtSecret {
  final secret = _env['JWT_SECRET'];
  if (secret == null || secret.isEmpty) {
    throw StateError('JWT_SECRET no está configurado en .env');
  }
  return secret;
}

int get jwtExpiryHours {
  return int.tryParse(_env['JWT_EXPIRY_HOURS'] ?? '8') ?? 8;
}
