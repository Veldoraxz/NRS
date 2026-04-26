// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:nrs_backend/auth/auth_user.dart';
import 'package:nrs_backend/auth/jwt_service.dart';

Handler authMiddleware(Handler handler) {
  return (context) async {
    final authHeader = context.request.headers['Authorization'];

    if (authHeader == null || !authHeader.startsWith('Bearer ')) {
      return Response.json(
        statusCode: HttpStatus.unauthorized,
        body: {'error': 'Token requerido'},
      );
    }

    final token = authHeader.substring(7); // saca "Bearer "

    try {
      final payload = JwtService.verify(token);
      final user    = AuthUser(
        userId: payload['user_id'] as String,
        role:   payload['role']    as String,
      );

      // Inyectamos el usuario en el contexto del request
      return handler(
        context.provide<AuthUser>(() => user),
      );

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
    }
  };
}
