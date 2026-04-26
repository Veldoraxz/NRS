// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/models/teacher.dart';
import 'package:nrs_backend/repositories/teacher_repository.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get  => _getAll(),
    HttpMethod.post => _create(context),
    _ => Future.value(Response(statusCode: HttpStatus.methodNotAllowed)),
  };
}

Future<Response> _getAll() async {
  final teachers = await TeacherRepository().getAll();
  return Response.json(
    body: teachers.map((Teacher t) => t.toJson()).toList(),
  );
}

Future<Response> _create(RequestContext context) async {
  final body = await context.request.json() as Map<String, dynamic>;

  final fullName = body['full_name']?.toString().trim();
  final email    = body['email']?.toString().trim();
  final dni      = body['dni']?.toString().trim();

  if (fullName == null || fullName.isEmpty ||
      email    == null || email.isEmpty    ||
      dni      == null || dni.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'full_name, email y dni son requeridos'},
    );
  }

  // Validación básica de email
  final emailRegex = RegExp(r'^[\w\-.]+@[\w\-.]+\.\w+$');
  if (!emailRegex.hasMatch(email)) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Formato de email inválido'},
    );
  }

  try {
    final repo = TeacherRepository();

    if (await repo.existsByEmail(email)) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'El email ya está registrado'},
      );
    }

    if (await repo.existsByDni(dni)) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'El DNI ya está registrado'},
      );
    }

    final teacher = await repo.create(
      fullName: fullName,
      email:    email,
      dni:      dni,
    );

    return Response.json(
      statusCode: HttpStatus.created,
      body: teacher.toJson(),
    );

  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}
