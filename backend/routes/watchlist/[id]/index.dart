// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/repositories/watchlist_repository.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.delete => _delete(id),
    _ => Future.value(Response(statusCode: HttpStatus.methodNotAllowed)),
  };
}

/// DELETE /watchlist/:id — elimina la entrada (alumno que ya no está)
Future<Response> _delete(String id) async {
  try {
    final repo  = WatchlistRepository();
    final entry = await repo.findById(id);

    if (entry == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Entrada no encontrada en el watchlist'},
      );
    }

    await repo.delete(id);

    return Response.json(
      body: {'message': 'Entrada eliminada correctamente'},
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}
