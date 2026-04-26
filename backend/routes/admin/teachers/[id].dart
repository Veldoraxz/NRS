// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/middleware/admin_auth.dart';
import 'package:nrs_backend/repositories/teacher_repository.dart';

Handler middleware(Handler handler) {
  return adminAuthMiddleware(handler);
}

Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.patch  => _toggleStatus(context, id),
    _ => Future.value(Response(statusCode: HttpStatus.methodNotAllowed)),
  };
}

Future<Response> _toggleStatus(RequestContext context, String id) async {
  final body   = await context.request.json() as Map<String, dynamic>;
  final action = body['action']?.toString().trim();

  if (action != 'activate' && action != 'deactivate') {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'action debe ser "activate" o "deactivate"'},
    );
  }

  try {
    final repo    = TeacherRepository();
    final teacher = await repo.findById(id);

    if (teacher == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Profesor no encontrado'},
      );
    }

    if (action == 'deactivate') {
      if (!teacher.isActive) {
        return Response.json(
          statusCode: HttpStatus.conflict,
          body: {'error': 'El profesor ya está inactivo'},
        );
      }
      await repo.deactivate(id);
    } else {
      if (teacher.isActive) {
        return Response.json(
          statusCode: HttpStatus.conflict,
          body: {'error': 'El profesor ya está activo'},
        );
      }
      await repo.activate(id);
    }

    final updated = await repo.findById(id);
    return Response.json(body: updated!.toJson());
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}
