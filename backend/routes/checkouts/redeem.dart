// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/auth/auth_user.dart';
import 'package:nrs_backend/repositories/checkout_repository.dart';
import 'package:nrs_backend/repositories/device_repository.dart';
import 'package:nrs_backend/repositories/reservation_repository.dart';
import 'package:nrs_backend/repositories/teacher_token_repository.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final user        = context.read<AuthUser>();
  final body        = await context.request.json() as Map<String, dynamic>;
  final tokenValue  = body['token']?.toString().trim();
  final deviceNotes = body['device_notes']?.toString().trim();

  if (tokenValue == null || tokenValue.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'token es requerido'},
    );
  }

  try {
    final tokenRepo = TeacherTokenRepository();
    final token     = await tokenRepo.findByToken(tokenValue);

    // Token existe
    if (token == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Token inválido'},
      );
    }

    // Token no usado
    if (token.used) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'Este token ya fue utilizado'},
      );
    }

    // Token no expirado
    if (token.isExpired) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'El token ha expirado'},
      );
    }

    final reservationRepo = ReservationRepository();
    final reservation     = await reservationRepo.findById(token.reservationId);

    if (reservation == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Reserva asociada al token no encontrada'},
      );
    }

    // Reserva debe estar pending
    if (reservation.status != 'pending') {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {
          'error': 'La reserva no está en estado pendiente. '
              'Estado actual: ${reservation.status}',
        },
      );
    }

    // No debe existir ya un checkout
    if (await reservationRepo.hasActiveCheckout(token.reservationId)) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'Esta reserva ya tiene un checkout registrado'},
      );
    }

    // Device debe estar available
    final device = await DeviceRepository().findById(reservation.deviceId);
    if (device == null || device.status != 'available') {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'El dispositivo no está disponible para retiro'},
      );
    }

    // ignore: flutter_style_todos
    // Todo en una sola transacción
    final checkout = await CheckoutRepository().approveCheckout(
      reservationId:   token.reservationId,
      adminId:         user.userId,
      deviceId:        reservation.deviceId,
      deviceNotes:     deviceNotes,
      studentId:       null,
      activateStudent: false,
    );

    // Marcar token como usado
    await tokenRepo.markAsUsed(token.id);

    return Response.json(
      statusCode: HttpStatus.created,
      body: {
        'checkout': checkout.toJson(),
        'token_used': token.token,
      },
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}
