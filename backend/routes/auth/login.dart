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

  if (email == null || email.isEmpty || password == null || password.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'email y password son requeridos'},
    );
  }

  try {
    // Auto-detect: si no viene role, probamos student -> teacher -> admin.
    final candidates = (role == null || role.isEmpty)
        ? <String>['student', 'teacher', 'admin']
        : <String>[role];

    for (final r in candidates) {
      final result = await _tryLogin(role: r, email: email, password: password);
      if (result != null) return result;
    }

    return Response.json(
      statusCode: HttpStatus.unauthorized,
      body: {'error': 'Credenciales incorrectas'},
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}

Future<Response?> _tryLogin({
  required String role,
  required String email,
  required String password,
}) async {
  Map<String, dynamic>? user;

  switch (role) {
    case 'admin':
      user = await AdminRepository().loginByEmail(
        email:    email,
        password: password,
      );
    case 'teacher':
      final teacher = await TeacherRepository().login(
        email: email,
        dni:   password,
      );
      if (teacher != null) {
        user = {
          ...teacher.toJson(),
          'role': 'teacher',
        };
      }
    case 'student':
      final student = await StudentRepository().login(
        email: email,
        dni:   password,
      );
      if (student != null) {
        user = {
          ...student.toJson(),
          'role': 'student',
        };
      }
    default:
      return null;
  }

  if (user == null) return null;

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
      'user':  user,
    },
  );
}
