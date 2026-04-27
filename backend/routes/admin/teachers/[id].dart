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
    HttpMethod.patch  => _patch(context, id),
    HttpMethod.delete => _delete(id),
    _ => Future.value(Response(statusCode: HttpStatus.methodNotAllowed)),
  };
}

Future<Response> _patch(RequestContext context, String id) async {
  final body   = await context.request.json() as Map<String, dynamic>;
  final action = body['action']?.toString().trim();

  if (action != null && action.isNotEmpty) {
    return _toggleStatus(id, action);
  }
  return _updateTeacher(id, body);
}

Future<Response> _toggleStatus(String id, String action) async {
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

Future<Response> _updateTeacher(String id, Map<String, dynamic> body) async {
  final fullName = body['full_name']?.toString().trim() ?? '';
  final email    = body['email']?.toString().trim() ?? '';
  final dni      = body['dni']?.toString().trim() ?? '';

  if (fullName.isEmpty || email.isEmpty || dni.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'full_name, email y dni son obligatorios'},
    );
  }

  try {
    final repo     = TeacherRepository();
    final existing = await repo.findById(id);
    if (existing == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Profesor no encontrado'},
      );
    }

    if (email != existing.email &&
        await repo.existsByEmailExcludingId(email, id)) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'Ya existe un profesor con ese email'},
      );
    }
    if (dni != existing.dni &&
        await repo.existsByDniExcludingId(dni, id)) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'Ya existe un profesor con ese DNI'},
      );
    }

    final updated = await repo.update(
      id:       id,
      fullName: fullName,
      email:    email,
      dni:      dni,
    );
    return Response.json(body: updated!.toJson());
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}

Future<Response> _delete(String id) async {
  try {
    final repo     = TeacherRepository();
    final existing = await repo.findById(id);
    if (existing == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Profesor no encontrado'},
      );
    }

    if (await repo.hasCheckoutHistory(id)) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {
          'error':
              'El profesor tiene reservas con retiros registrados. '
              'Desactivalo en lugar de eliminarlo para preservar el historial.',
        },
      );
    }

    await repo.delete(id);
    return Response.json(body: {'ok': true});
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}
