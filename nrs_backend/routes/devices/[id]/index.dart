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

  if (method == HttpMethod.get) {
    return _handleGet(id);
  } else if (method == HttpMethod.delete) {
    return _handleDelete(id);
  }

  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _handleGet(String id) async {
  try {
    if (id.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'id es requerido'},
      );
    }

    final deviceRepository = DeviceRepository();
    final device = await deviceRepository.findById(id);

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
      body: {'error': 'Error al obtener dispositivo: $e'},
    );
  }
}

Future<Response> _handleDelete(String id) async {
  try {
    if (id.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'id es requerido'},
      );
    }

    final deviceRepository = DeviceRepository();
    final device = await deviceRepository.findById(id);

    if (device == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Dispositivo no encontrado'},
      );
    }

    await deviceRepository.delete(id);

    return Response.json(
      body: {'message': 'Dispositivo eliminado exitosamente'},
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error al eliminar dispositivo: $e'},
    );
  }
}
