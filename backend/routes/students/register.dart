// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/repositories/student_repository.dart';

const _validSpecialties = ['electronica', 'construcciones', 'programacion'];

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  try {
    final body     = await context.request.json() as Map<String, dynamic>;
    final repo     = StudentRepository();
    final year     = body['year'] as int;
    final division = body['division'] as int;
    final specialty = body['specialty']?.toString().trim().toLowerCase();

    if (year < 1 || year > 7) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'Año inválido, debe ser entre 1 y 7'},
      );
    }

    if (division < 1 || division > 10) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'División inválida'},
      );
    }

    // Ciclo básico (1-3): no debe tener especialidad
    if (year <= 3 && specialty != null) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {
          'error': 'Los alumnos de 1° a 3° no tienen especialidad. '
              'Se les asigna ciclo básico automáticamente.',
        },
      );
    }

    // Ciclo superior (4-7): especialidad obligatoria y válida
    if (year >= 4) {
      if (specialty == null || specialty.isEmpty) {
        return Response.json(
          statusCode: HttpStatus.badRequest,
          body: {
            'error': 'Los alumnos de 4° a 7° deben indicar su especialidad. '
                'Opciones: ${_validSpecialties.join(", ")}',
          },
        );
      }

      if (!_validSpecialties.contains(specialty)) {
        return Response.json(
          statusCode: HttpStatus.badRequest,
          body: {
            'error': 'Especialidad inválida. '
                'Opciones válidas: ${_validSpecialties.join(", ")}',
          },
        );
      }
    }

    if (await repo.existsByEmail(body['email'] as String)) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'Email ya registrado'},
      );
    }

    if (await repo.existsByDni(body['dni'] as String)) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'DNI ya registrado'},
      );
    }

    final student = await repo.register(
      fullName:  body['full_name'] as String,
      email:     body['email']    as String,
      dni:       body['dni']      as String,
      year:      year,
      division:  division,
      specialty: year <= 3 ? null : specialty,
    );

    if (student == null) {
      return Response.json(
        statusCode: HttpStatus.badRequest,
        body: {'error': 'No se pudo registrar el estudiante'},
      );
    }

    return Response.json(
      statusCode: HttpStatus.created,
      body: student.toJson(),
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}
