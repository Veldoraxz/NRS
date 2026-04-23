// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/auth/jwt_service.dart';
import 'package:nrs_backend/repositories/teacher_repository.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final body  = await context.request.json() as Map<String, dynamic>;
  final email = body['email']?.toString().trim();
  final dni   = body['dni']?.toString().trim();

  if (email == null || email.isEmpty || dni == null || dni.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Email y DNI son requeridos'},
    );
  }

  try {
    final userData = await TeacherRepository().loginForAuth(
      email: email,
      dni:   dni,
    );

    if (userData == null) {
      return Response.json(
        statusCode: HttpStatus.unauthorized,
        body: {'error': 'Email o DNI incorrectos'},
      );
    }

    // Sin chequeo de is_active — la cuenta la crea el admin,
    // siempre está activa
    final token = JwtService().generateToken(
      userId: userData['id'] as String,
      email:  userData['email'] as String,
      role:   'teacher',
    );

    return Response.json(body: {'token': token});
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}
