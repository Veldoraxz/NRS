// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/auth/auth_user.dart';
import 'package:nrs_backend/database/connection.dart';
import 'package:nrs_backend/repositories/checkout_repository.dart';
import 'package:nrs_backend/repositories/device_repository.dart';
import 'package:nrs_backend/repositories/reservation_repository.dart';
import 'package:nrs_backend/repositories/return_repository.dart';
import 'package:nrs_backend/repositories/student_repository.dart' as student_repo;
import 'package:ulid/ulid.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final user        = context.read<AuthUser>();
  final body        = await context.request.json() as Map<String, dynamic>;
  final checkoutId  = body['checkout_id']?.toString().trim();
  final deviceNotes = body['device_notes']?.toString().trim();
  final hasDamage   = body['has_damage'] as bool? ?? false;
  final description = body['damage_description']?.toString().trim();

  if (checkoutId == null || checkoutId.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'checkout_id es requerido'},
    );
  }

  if (hasDamage && (description == null || description.isEmpty)) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      // ignore: lines_longer_than_80_chars
      body: {'error': 'damage_description es requerido cuando has_damage es true'},
    );
  }

  try {
    final checkout = await CheckoutRepository().findById(checkoutId);
    if (checkout == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Checkout no encontrado'},
      );
    }

    final returnRepo = ReturnRepository();
    if (await returnRepo.existsByCheckout(checkoutId)) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'Este checkout ya tiene una devolución registrada'},
      );
    }

    final reservation = await ReservationRepository()
        .findById(checkout.reservationId);
    if (reservation == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'Reserva asociada no encontrada'},
      );
    }

    final device = await DeviceRepository().findById(reservation.deviceId);
    if (device == null || device.status != 'in_use') {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'El dispositivo no está en uso, no se puede devolver'},
      );
    }

    // Obtener datos del alumno si la reserva es de un estudiante
    String? studentDni;
    String? studentFullName;
    if (reservation.bookerType == 'student' && reservation.studentId != null) {
  final student = await student_repo.StudentRepository()
      .findById(reservation.studentId!);
  studentDni      = student?.dni;
  studentFullName = student?.fullName;
}

    // ignore: flutter_style_todos
    // Todo en una sola transacción, incluido el cálculo del estado de watchlist
    String? watchlistStatus;

    final conn     = await getConnection();
    final returnId = Ulid().toString();

    await conn.runTx((tx) async {
      // 1. Crear devolución
      await tx.execute(
        r'''
          INSERT INTO returns
            (id, checkout_id, admin_id, device_notes, has_damage)
          VALUES ($1, $2, $3, $4, $5)
        ''',
        parameters: [returnId, checkoutId, user.userId, deviceNotes, hasDamage],
      );

      // 2. Device: in_use → available
      await tx.execute(
        r'UPDATE devices SET status = $1 WHERE id = $2',
        parameters: ['available', reservation.deviceId],
      );

      // 3. Si hay daño y es reserva de alumno → damage + watchlist
      if (hasDamage && studentDni != null && studentFullName != null) {
        // Registrar daño
        final damageId = Ulid().toString();
        await tx.execute(
          r'''
            INSERT INTO damages (id, dni, return_id, description)
            VALUES ($1, $2, $3, $4)
          ''',
          parameters: [damageId, studentDni, returnId, description],
        );

        // Incrementar watchlist (insert o update) CON LOCK
        final existing = await tx.execute(
          r'SELECT damage_count FROM watchlist WHERE dni = $1 FOR UPDATE',
          parameters: [studentDni],
        );

        if (existing.isEmpty) {
          final watchlistId = Ulid().toString();
          await tx.execute(
            r'''
              INSERT INTO watchlist (id, dni, full_name, damage_count, active)
              VALUES ($1, $2, $3, 1, true)
            ''',
            parameters: [watchlistId, studentDni, studentFullName],
          );
          watchlistStatus = 'advertencia (1/3 roturas)';
        } else {
          // Obtener el nuevo damage_count DESPUÉS de update
          final currentCount = existing.first[0] as int?;
          final newCount = (currentCount ?? 0) + 1;

          await tx.execute(
            r'''
              UPDATE watchlist
              SET damage_count = $1,
                  updated_at   = NOW()
              WHERE dni = $2
            ''',
            parameters: [newCount, studentDni],
          );

          watchlistStatus = newCount >= 3
              ? 'bloqueado ($newCount roturas)'
              : 'advertencia ($newCount/3 roturas)';
        }
      }
    });

    final returnModel = await returnRepo.findByCheckout(checkoutId);

    return Response.json(
      statusCode: HttpStatus.created,
      body: {
        'return':           returnModel!.toJson(),
        'watchlist_status': watchlistStatus,
      },
    );

  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}
