// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/database/connection.dart';
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

    final device = await DeviceRepository().findById(id);

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

    final device = await DeviceRepository().findById(id);

    if (device == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Dispositivo no encontrado'},
      );
    }

    if (device.status == 'in_use') {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'No se puede eliminar un dispositivo que está en uso'},
      );
    }

    final conn = await getConnection();
    await conn.runTx((tx) async {
      await tx.execute(
        r'''
          UPDATE reservations
          SET status = 'cancelled'
          WHERE device_id = $1
            AND status IN ('pending', 'confirmed')
        ''',
        parameters: [id],
      );

      await tx.execute(
        r'DELETE FROM devices WHERE id = $1',
        parameters: [id],
      );
    });

    return Response.json(
      body: {
        'message':
            'Dispositivo ${device.type} N°${device.number} eliminado correctamente. '
            'Las reservas activas fueron canceladas.',
      },
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error al eliminar dispositivo: $e'},
    );
  }
}
