// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/auth/auth_user.dart';
import 'package:nrs_backend/repositories/checkout_repository.dart';
import 'package:nrs_backend/repositories/reservation_repository.dart';
import 'package:nrs_backend/repositories/student_repository.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final user          = context.read<AuthUser>();
  final body          = await context.request.json() as Map<String, dynamic>;
  final reservationId = body['reservation_id']?.toString().trim();
  final deviceNotes   = body['device_notes']?.toString().trim();
  final confirm       = body['confirm'] == true;

  if (reservationId == null || reservationId.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'reservation_id es requerido'},
    );
  }

  try {
    final reservationRepo = ReservationRepository();
    final reservation     = await reservationRepo.findById(reservationId);

    if (reservation == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Reserva no encontrada'},
      );
    }

    if (await reservationRepo.hasActiveCheckout(reservationId)) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'Esta reserva ya tiene un checkout registrado'},
      );
    }

    // Las validaciones de reservation.status y device.status se hacen
    // dentro de la transacción en approveCheckout()

    // ── Reserva de alumno ────────────────────────────────────────────────────
    if (reservation.bookerType == 'student') {
      final studentRepo = StudentRepository();
      final student     = await studentRepo.findById(reservation.studentId!);
      final wasInactive = student != null && !student.isActive;

      // Alumno inactivo y admin no confirmó → warning
      if (wasInactive && !confirm) {
        return Response.json(
          statusCode: HttpStatus.accepted,
          body: {
            'requires_confirmation': true,
            'message':
                'El alumno no está activado. '
                'Verificá sus datos antes de continuar. '
                'Al aprobar, la cuenta se activará automáticamente.',
            'student': {
              'id':        student.id,
              'full_name': student.fullName,
              'dni':       student.dni,
              'email':     student.email,
            },
          },
        );
      }

      // ignore: flutter_style_todos
      // Todo en una sola transacción
      final checkout = await CheckoutRepository().approveCheckout(
        reservationId:   reservationId,
        adminId:         user.userId,
        deviceId:        reservation.deviceId,
        deviceNotes:     deviceNotes,
        studentId:       student?.id,
        activateStudent: wasInactive,
      );

      return Response.json(
        statusCode: HttpStatus.created,
        body: {
          'checkout':          checkout.toJson(),
          'student_activated': wasInactive,
        },
      );
    }

    // ── Reserva de profesor → checkout directo, sin warning ─────────────────
    final checkout = await CheckoutRepository().approveCheckout(
      reservationId:   reservationId,
      adminId:         user.userId,
      deviceId:        reservation.deviceId,
      deviceNotes:     deviceNotes,
      studentId:       null,
      activateStudent: false,
    );

    return Response.json(
      statusCode: HttpStatus.created,
      body: checkout.toJson(),
    );

  } catch (e) {
    final msg = e.toString().toLowerCase();

    if (msg.contains('no está disponible') ||
        msg.contains('dispositivo no encontrado')) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': e.toString()},
      );
    }

    if (msg.contains('no se puede hacer checkout')) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': e.toString()},
      );
    }

    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}
