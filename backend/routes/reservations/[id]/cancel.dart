// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/auth/auth_user.dart';
import 'package:nrs_backend/repositories/reservation_repository.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  if (context.request.method != HttpMethod.patch) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final user = context.read<AuthUser>();

  try {
    final repo        = ReservationRepository();
    final reservation = await repo.findById(id);

    if (reservation == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Reserva no encontrada'},
      );
    }

    // Verificar que no esté ya cancelada o completada
    if (reservation.status == 'cancelled') {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'La reserva ya está cancelada'},
      );
    }

    if (reservation.status == 'completed') {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'No se puede cancelar una reserva completada'},
      );
    }

    // Si no es admin, solo puede cancelar la suya
    if (!user.isAdmin) {
      final esDelUsuario =
        (user.role == 'student' && reservation.studentId == user.userId) ||
        (user.role == 'teacher' && reservation.teacherId == user.userId);

      if (!esDelUsuario) {
        return Response.json(
          statusCode: HttpStatus.forbidden,
          body: {'error': 'No podés cancelar una reserva que no es tuya'},
        );
      }
    }

    // Validar que no tenga checkout activo
    if (await repo.hasActiveCheckout(id)) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'No podés cancelar una reserva que ya fue retirada'},
      );
    }

    final cancelled = await repo.cancel(id);

    return Response.json(body: cancelled!.toJson());

  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}
