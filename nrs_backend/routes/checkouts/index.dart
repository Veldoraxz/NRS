// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/auth/auth_user.dart';
import 'package:nrs_backend/repositories/checkout_repository.dart';
import 'package:nrs_backend/repositories/device_repository.dart';
import 'package:nrs_backend/repositories/reservation_repository.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final user = context.read<AuthUser>();
  final body = await context.request.json() as Map<String, dynamic>;
  final reservationId = body['reservation_id']?.toString().trim();
  final deviceNotes   = body['device_notes']?.toString().trim();

  if (reservationId == null || reservationId.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'reservation_id es requerido'},
    );
  }

  try {
    final reservationRepo = ReservationRepository();
    final reservation     = await reservationRepo.findById(reservationId);

    // Reserva existe
    if (reservation == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Reserva no encontrada'},
      );
    }

    // Reserva debe estar confirmed
    if (reservation.status != 'confirmed') {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {
          'error': 'Solo se puede hacer checkout de reservas confirmadas. '
              'Estado actual: ${reservation.status}',
        },
      );
    }

    // No debe existir ya un checkout
    if (await reservationRepo.hasActiveCheckout(reservationId)) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'Esta reserva ya tiene un checkout registrado'},
      );
    }

    // El dispositivo debe estar available
    final device = await DeviceRepository().findById(reservation.deviceId);
    if (device == null || device.status != 'available') {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'El dispositivo no está disponible para retiro'},
      );
    }

    // Crear checkout
    final checkout = await CheckoutRepository().create(
      reservationId: reservationId,
      adminId:       user.userId,
      deviceNotes:   deviceNotes,
    );

    // Actualizar dispositivo a in_use y reserva a completed
    await DeviceRepository().updateStatus(reservation.deviceId, 'in_use');
    await reservationRepo.updateStatus(reservationId, 'completed');

    return Response.json(
      statusCode: HttpStatus.created,
      body: checkout.toJson(),
    );

  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}
