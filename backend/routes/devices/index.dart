// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/config/device_type.dart';
import 'package:nrs_backend/middleware/admin_auth.dart';
import 'package:nrs_backend/repositories/device_repository.dart';

/// GET es público (cualquier usuario puede listar dispositivos para la home).
/// POST requiere admin.
Handler middleware(Handler handler) {
  return (context) async {
    if (context.request.method == HttpMethod.get) {
      return handler(context);
    }
    return adminAuthMiddleware(handler)(context);
  };
}

Future<Response> onRequest(RequestContext context) async {
  final method = context.request.method;

  if (method == HttpMethod.get) {
    return _handleGet(context);
  } else if (method == HttpMethod.post) {
    return _handlePost(context);
  }

  return Response(statusCode: HttpStatus.methodNotAllowed);
}

Future<Response> _handleGet(RequestContext context) async {
  try {
    final uri = context.request.uri;
    final type = uri.queryParameters['type'];
    final status = uri.queryParameters['status'];
    final limitStr = uri.queryParameters['limit'] ?? '50';
    final offsetStr = uri.queryParameters['offset'] ?? '0';

    final limit = int.tryParse(limitStr) ?? 50;
    final offset = int.tryParse(offsetStr) ?? 0;

    if (limit <= 0 || limit > 100) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'limit debe estar entre 1 y 100'},
      );
    }

    if (offset < 0) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'offset no puede ser negativo'},
      );
    }

    final deviceRepository = DeviceRepository();
    final devices = await deviceRepository.getAll(
      type: type,
      status: status,
      limit: limit,
      offset: offset,
    );
    final total = await deviceRepository.count(type: type, status: status);

    return Response.json(
      body: {
        'data': devices.map((d) => d.toJson()).toList(),
        'total': total,
        'limit': limit,
        'offset': offset,
      },
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error al obtener dispositivos: $e'},
    );
  }
}

Future<Response> _handlePost(RequestContext context) async {
  try {
    final body = await context.request.json() as Map<String, dynamic>;
    final number = body['number']?.toString().trim();
    final type = body['type']?.toString().trim();
    final status = body['status']?.toString().trim() ?? 'available';

    if (number == null || number.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'number es requerido'},
      );
    }

    if (type == null || type.isEmpty) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'type es requerido'},
      );
    }

    if (!DeviceType.isValid(type)) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {
          'error': 'type debe ser uno de: ${DeviceType.validTypes.join(", ")}',
        },
      );
    }

    final deviceRepository = DeviceRepository();
    final exists = await deviceRepository.existsByNumber(number, type);

    if (exists) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        // ignore: lines_longer_than_80_chars
        body: {'error': 'Ya existe un dispositivo de tipo "$type" con el número $number'},
      );
    }

    final device = await deviceRepository.create(
      number: number,
      type: type,
      status: status,
    );

    return Response.json(
      statusCode: HttpStatus.created,
      body: device.toJson(),
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error al crear dispositivo: $e'},
    );
  }
}
