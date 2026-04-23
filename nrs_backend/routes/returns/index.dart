// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/auth/auth_user.dart';
import 'package:nrs_backend/repositories/checkout_repository.dart';
import 'package:nrs_backend/repositories/device_repository.dart';
import 'package:nrs_backend/repositories/return_repository.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final user = context.read<AuthUser>();
  final body = await context.request.json() as Map<String, dynamic>;

  final checkoutId  = body['checkout_id']?.toString().trim();
  final deviceNotes = body['device_notes']?.toString().trim();
  final hasDamage   = body['has_damage'] as bool? ?? false;

  if (checkoutId == null || checkoutId.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'checkout_id es requerido'},
    );
  }

  try {
    // Checkout existe
    final checkout = await CheckoutRepository()
        .findById(checkoutId);

    if (checkout == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Checkout no encontrado'},
      );
    }

    // No existe ya una devolución
    final returnRepo = ReturnRepository();
    if (await returnRepo.existsByCheckout(checkoutId)) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'Este checkout ya tiene una devolución registrada'},
      );
    }

    // Crear devolución
    final returnModel = await returnRepo.create(
      checkoutId:  checkoutId,
      adminId:     user.userId,
      hasDamage:   hasDamage,
      deviceNotes: deviceNotes,
    );

    // Dispositivo vuelve a available
    await DeviceRepository().updateStatus(
      checkout.reservationId,
      'available',
    );

    return Response.json(
      statusCode: HttpStatus.created,
      body: returnModel.toJson(),
    );

  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}
