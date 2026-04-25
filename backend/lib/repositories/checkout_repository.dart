// ignore_for_file: public_member_api_docs

import 'package:nrs_backend/database/connection.dart';
import 'package:nrs_backend/models/checkout.dart';
import 'package:ulid/ulid.dart';

class CheckoutRepository {
  Future<Checkout?> findById(String id) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id, reservation_id, admin_id, device_notes, checked_out_at
        FROM checkouts WHERE id = $1
      ''',
      parameters: [id],
    );
    if (result.isEmpty) return null;
    return Checkout.fromRow(result.first);
  }

  Future<Checkout?> findByReservation(String reservationId) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id, reservation_id, admin_id, device_notes, checked_out_at
        FROM checkouts WHERE reservation_id = $1
      ''',
      parameters: [reservationId],
    );
    if (result.isEmpty) return null;
    return Checkout.fromRow(result.first);
  }

  Future<Checkout> create({
    required String reservationId,
    required String adminId,
    String? deviceNotes,
  }) async {
    final conn = await getConnection();
    final id   = Ulid().toString();

    await conn.execute(
      r'''
        INSERT INTO checkouts (id, reservation_id, admin_id, device_notes)
        VALUES ($1, $2, $3, $4)
      ''',
      parameters: [id, reservationId, adminId, deviceNotes],
    );

    return (await findByReservation(reservationId))!;
  }

  /// Crea el checkout, actualiza el device a in_use y la reserva a completed
  /// dentro de una sola transacción. Valida que el device esté 'available'.
  /// Si algo falla, todo se revierte.
  Future<Checkout> approveCheckout({
    required String reservationId,
    required String adminId,
    required String deviceId,
    required String? deviceNotes,
    required String? studentId,
    required bool activateStudent,
  }) async {
    final conn = await getConnection();
    final id   = Ulid().toString();

    await conn.runTx((tx) async {
      // 1. Validar que device está disponible CON LOCK PESSIMISTIC
      final device = await tx.execute(
        r'SELECT status FROM devices WHERE id = $1 FOR UPDATE',
        parameters: [deviceId],
      );

      if (device.isEmpty) {
        throw Exception('Dispositivo no encontrado');
      }

      if (device.first[0]! as String != 'available') {
        throw Exception('El dispositivo no está disponible para retiro');
      }

      // 2. Validar que reserva está en estado válido CON LOCK
      final reservation = await tx.execute(
        r'SELECT status FROM reservations WHERE id = $1 FOR UPDATE',
        parameters: [reservationId],
      );

      if (reservation.isEmpty) {
        throw Exception('Reserva no encontrada');
      }

      final status = reservation.first[0] as String?;
      if (status != 'pending' && status != 'confirmed') {
        throw Exception(
          'No se puede hacer checkout de una reserva con estado: $status',
        );
      }

      // 3. Crear checkout
      await tx.execute(
        r'''
          INSERT INTO checkouts (id, reservation_id, admin_id, device_notes)
          VALUES ($1, $2, $3, $4)
        ''',
        parameters: [id, reservationId, adminId, deviceNotes],
      );

      // 4. Device: available → in_use
      await tx.execute(
        r'UPDATE devices SET status = $1 WHERE id = $2',
        parameters: ['in_use', deviceId],
      );

      // 5. Reserva: pending/confirmed → completed
      await tx.execute(
        r'UPDATE reservations SET status = $1 WHERE id = $2',
        parameters: ['completed', reservationId],
      );

      // 6. Activar alumno si corresponde (primer retiro)
      if (activateStudent && studentId != null) {
        await tx.execute(
          r'UPDATE students SET is_active = true WHERE id = $1',
          parameters: [studentId],
        );
      }
    });

    return (await findByReservation(reservationId))!;
  }
}
