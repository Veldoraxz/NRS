// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/middleware/admin_auth.dart';
import 'package:nrs_backend/repositories/device_repository.dart';

Handler middleware(Handler handler) {
  return adminAuthMiddleware(handler);
}

Future<Response> onRequest(RequestContext context, String id) async {
  final method = context.request.method;

  if (method != HttpMethod.patch) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    if (id.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'id es requerido'},
      );
    }

    final body = await context.request.json() as Map<String, dynamic>;
    final newStatus = body['status']?.toString().trim();

    if (newStatus == null || newStatus.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'status es requerido'},
      );
    }

    final validStatuses = [
      'available',
      'in_use',
      'out_of_service',
      'maintenance',
    ];
    if (!validStatuses.contains(newStatus)) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {
          'error': 'status debe ser uno de: ${validStatuses.join(", ")}',
        },
      );
    }

    final deviceRepository = DeviceRepository();
    final device = await deviceRepository.updateStatus(id, newStatus);

    if (device == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Dispositivo no encontrado'},
      );
    }

    return Response.json(body: device.toJson());
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error al actualizar estado del dispositivo: $e'},
    );
  }
}
