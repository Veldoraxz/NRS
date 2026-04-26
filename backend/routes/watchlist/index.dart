// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/auth/auth_user.dart';
import 'package:nrs_backend/repositories/watchlist_repository.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get  => _getAll(),
    HttpMethod.post => _addManually(context),
    _ => Future.value(Response(statusCode: HttpStatus.methodNotAllowed)),
  };
}

Future<Response> _getAll() async {
  try {
    final entries = await WatchlistRepository().getAll();
    return Response.json(
      body: entries.map((e) => e.toJson()).toList(),
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}

Future<Response> _addManually(RequestContext context) async {
  final user = context.read<AuthUser>();
  final body = await context.request.json() as Map<String, dynamic>;

  final dni = body['dni']?.toString().trim();

  if (dni == null || dni.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'dni es requerido'},
    );
  }

  try {
    final entry = await WatchlistRepository().addManually(
      dni:     dni,
      adminId: user.userId,
    );

    return Response.json(
      statusCode: HttpStatus.created,
      body: entry.toJson(),
    );
  } on Exception catch (e) {
    final msg = e.toString();
    if (msg.contains('No existe un alumno')) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'No existe un alumno registrado con ese DNI'},
      );
    }
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}
