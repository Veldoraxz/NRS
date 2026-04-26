// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/auth/jwt_service.dart';
import 'package:nrs_backend/repositories/admin_repository.dart';
import 'package:nrs_backend/repositories/student_repository.dart';
import 'package:nrs_backend/repositories/teacher_repository.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final body     = await context.request.json() as Map<String, dynamic>;
  final email    = body['email']?.toString().trim();
  final password = body['password']?.toString().trim();
  final role     = body['role']?.toString().trim();

  if (email == null    || email.isEmpty    ||
      password == null || password.isEmpty ||
      role == null     || role.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'email, password y role son requeridos'},
    );
  }

  try {
    Map<String, dynamic>? user;

    switch (role) {
      case 'admin':
        user = await AdminRepository().loginByEmail(
          email:    email,
          password: password,
        );
      case 'teacher':
        user = await TeacherRepository().loginForAuth(
          email: email,
          dni:   password,
        );
      case 'student':
        user = await StudentRepository().loginForAuth(
          email: email,
          dni:   password,
        );
      default:
        return Response.json(
          statusCode: HttpStatus.badRequest,
          body: {'error': 'role debe ser admin, teacher o student'},
        );
    }

    if (user == null) {
      return Response.json(
        statusCode: HttpStatus.unauthorized,
        body: {'error': 'Credenciales incorrectas'},
      );
    }

    final token = JwtService.generate(
      userId: user['id'] as String,
      email:  user['email'] as String,
      role:   user['role'] as String,
    );

    return Response.json(
      body: {
        'token': token,
        'role':  user['role'],
        'email': user['email'],
      },
    );

  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}
