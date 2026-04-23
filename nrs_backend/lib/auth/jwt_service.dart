// ignore_for_file: public_member_api_docs

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:nrs_backend/config/env.dart';

class JwtService {
  /// Genera un token firmado con HS256
  static String generate({
    required String userId,
    required String email,
    required String role,
  }) {
    final jwt = JWT(
      {
        'user_id': userId,
        'email':   email,
        'role':    role,
      },
    );

    return jwt.sign(
      SecretKey(jwtSecret),
      expiresIn: Duration(hours: jwtExpiryHours),
    );
  }

  /// Verifica y decodifica. Lanza JWTExpiredError o JWTError si falla.
  static Map<String, dynamic> verify(String token) {
    final jwt = JWT.verify(token, SecretKey(jwtSecret));
    return jwt.payload as Map<String, dynamic>;
  }

  String generateToken({
    required String userId,
    required String email,
    required String role,
  }) {
    return JwtService.generate(userId: userId, email: email, role: role);
  }
}
