// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:nrs_backend/auth/auth_user.dart';
import 'package:nrs_backend/auth/jwt_service.dart';

// Token fijo legacy — compatibilidad con herramientas externas.
// El frontend Flutter usa JWT con role='admin'.
const _legacyAdminToken = 'admin-secret-token';

Handler adminAuthMiddleware(Handler handler) {
  return (context) async {
    final auth = context.request.headers['Authorization'];

    if (auth == null || !auth.startsWith('Bearer ')) {
      return Response.json(
        statusCode: HttpStatus.unauthorized,
        body: {'error': 'No autorizado'},
      );
    }

    final token = auth.substring(7);

    // 1. Token fijo legacy (compatibilidad)
    if (token == _legacyAdminToken) {
      return handler(
        context.provide<AuthUser>(
          () => AuthUser(userId: 'legacy-admin', role: 'admin'),
        ),
      );
    }

    // 2. JWT firmado con role='admin'
    try {
      final payload = JwtService.verify(token);
      final role    = payload['role'] as String?;

      if (role != 'admin') {
        return Response.json(
          statusCode: HttpStatus.forbidden,
          body: {'error': 'No tenés permisos de administrador'},
        );
      }

      final user = AuthUser(
        userId: payload['user_id'] as String,
        role:   'admin',
      );

      return handler(context.provide<AuthUser>(() => user));

    } on JWTExpiredException {
      return Response.json(
        statusCode: HttpStatus.unauthorized,
        body: {'error': 'Token expirado'},
      );
    } on JWTInvalidException {
      return Response.json(
        statusCode: HttpStatus.unauthorized,
        body: {'error': 'Token inválido'},
      );
    } catch (_) {
      return Response.json(
        statusCode: HttpStatus.unauthorized,
        body: {'error': 'No autorizado'},
      );
    }
  };
}
