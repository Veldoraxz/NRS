// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/auth/auth_user.dart';
import 'package:nrs_backend/repositories/reservation_repository.dart';
import 'package:nrs_backend/repositories/teacher_token_repository.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final user = context.read<AuthUser>();

  // Solo teachers pueden generar tokens
  if (user.role != 'teacher') {
    return Response.json(
      statusCode: HttpStatus.forbidden,
      body: {'error': 'Solo un profesor puede generar tokens'},
    );
  }

  try {
    final reservation = await ReservationRepository().findById(id);

    if (reservation == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Reserva no encontrada'},
      );
    }

    // Solo puede generar token para sus propias reservas
    if (reservation.teacherId != user.userId) {
      return Response.json(
        statusCode: HttpStatus.forbidden,
        // ignore: lines_longer_than_80_chars
        body: {'error': 'No podés generar un token para una reserva que no es tuya'},
      );
    }

    // La reserva debe estar pending
    if (reservation.status != 'pending') {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {
          'error': 'Solo se puede generar un token para reservas pendientes. '
              'Estado actual: ${reservation.status}',
        },
      );
    }

    final tokenRepo = TeacherTokenRepository();

    // Si ya existe un token para esta reserva, devolverlo
    final existing = await tokenRepo.findByReservation(id);
    if (existing != null) {
      if (existing.isExpired) {
        return Response.json(
          statusCode: HttpStatus.conflict,
          // ignore: lines_longer_than_80_chars
          body: {'error': 'El token anterior ya expiró. La reserva no puede usarse.'},
        );
      }
      // Devolver el token existente si todavía es válido
      return Response.json(body: existing.toJson());
    }

    final token = await tokenRepo.create(
      reservationId:   id,
      reservationDate: reservation.date,
      startTime:       reservation.startTime,
    );

    return Response.json(
      statusCode: HttpStatus.created,
      body: token.toJson(),
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}
