import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/repositories/student_repository.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final repo = StudentRepository();

    final student = await repo.login(
      email: body['email'] as String,
      dni:   body['dni']   as String,
    );

    if (student == null) {
      return Response.json(
        statusCode: HttpStatus.unauthorized,
        body: {'error': 'Credenciales inválidas'},
      );
    }

    return Response.json(body: student.toJson());
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}
