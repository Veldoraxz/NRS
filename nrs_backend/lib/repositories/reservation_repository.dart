// ignore_for_file: public_member_api_docs

import 'package:nrs_backend/database/connection.dart';
import 'package:nrs_backend/models/reservation.dart';
import 'package:ulid/ulid.dart';

class ReservationRepository {
  Future<bool> studentHasReservationOnDate({
    required String studentId,
    required String date,
  }) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id FROM reservations
        WHERE student_id = $1 AND date = $2 AND status IN ('pending', 'confirmed')
      ''',
      parameters: [studentId, date],
    );
    return result.isNotEmpty;
  }

  Future<bool> hasConflict({
    required String deviceId,
    required String date,
    required String startTime,
    required String endTime,
  }) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id FROM reservations
        WHERE device_id = $1 AND date = $2 AND status IN ('pending', 'confirmed')
          AND (
            (start_time <= $3 AND end_time > $3) OR
            (start_time < $4 AND end_time >= $4) OR
            (start_time >= $3 AND end_time <= $4)
          )
      ''',
      parameters: [deviceId, date, startTime, endTime],
    );
    return result.isNotEmpty;
  }

  Future<Reservation> createForStudent({
    required String studentId,
    required String deviceId,
    required String date,
    required String startTime,
    required String endTime,
  }) async {
    final conn = await getConnection();
    final id = Ulid().toString();

    await conn.execute(
      r'''
        INSERT INTO reservations
          (id, booker_type, student_id, device_id, date, start_time, end_time, status)
        VALUES ($1, 'student', $2, $3, $4, $5, $6, 'pending')
      ''',
      parameters: [id, studentId, deviceId, date, startTime, endTime],
    );

    return (await findById(id))!;
  }

  Future<List<Reservation>> getByStudent(String studentId) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT
          r.id, r.booker_type, r.student_id, r.teacher_id, r.device_id,
          r.date, r.start_time, r.end_time, r.status, r.created_at,
          s.full_name as student_name,
          t.full_name as teacher_name
        FROM reservations r
        LEFT JOIN students s ON r.student_id = s.id
        LEFT JOIN teachers t ON r.teacher_id = t.id
        WHERE r.student_id = $1
        ORDER BY r.date DESC, r.start_time DESC
      ''',
      parameters: [studentId],
    );
    return result.map(Reservation.fromRow).toList();
  }

  Future<Reservation?> findById(String id) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT
          r.id, r.booker_type, r.student_id, r.teacher_id, r.device_id,
          r.date, r.start_time, r.end_time, r.status, r.created_at,
          s.full_name as student_name,
          t.full_name as teacher_name
        FROM reservations r
        LEFT JOIN students s ON r.student_id = s.id
        LEFT JOIN teachers t ON r.teacher_id = t.id
        WHERE r.id = $1
      ''',
      parameters: [id],
    );
    if (result.isEmpty) return null;
    return Reservation.fromRow(result.first);
  }

  Future<List<Reservation>> getAll() async {
    final conn = await getConnection();
    final result = await conn.execute(
      '''
        SELECT
          r.id, r.booker_type, r.student_id, r.teacher_id, r.device_id,
          r.date, r.start_time, r.end_time, r.status, r.created_at,
          s.full_name as student_name,
          t.full_name as teacher_name
        FROM reservations r
        LEFT JOIN students s ON r.student_id = s.id
        LEFT JOIN teachers t ON r.teacher_id = t.id
        ORDER BY r.date DESC, r.start_time DESC
      ''',
    );
    return result.map(Reservation.fromRow).toList();
  }

  Future<Reservation?> cancel(String id) async {
    final conn = await getConnection();
    await conn.execute(
      r'''
      UPDATE reservations
      SET status = 'cancelled'
      WHERE id = $1
    ''',
      parameters: [id],
    );
    return findById(id);
  }

  Future<bool> hasActiveCheckout(String reservationId) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'SELECT id FROM checkouts WHERE reservation_id = $1',
      parameters: [reservationId],
    );
    return result.isNotEmpty;
  }

  Future<void> updateStatus(String id, String status) async {
    final conn = await getConnection();
    await conn.execute(
      r'UPDATE reservations SET status = $1 WHERE id = $2',
      parameters: [status, id],
    );
  }

  // ─── TEACHERS ───────────────────────────────────────────────────────────

  /// Crea una o más reservas de notebook
  /// para un profesor.
  Future<List<Reservation>> createForTeacher({
    required String teacherId,
    required List<String> deviceIds,
    required String date,
    required String startTime,
    required String endTime,
  }) async {
    final conn = await getConnection();
    final ids = <String>[];

    for (final deviceId in deviceIds) {
      final id = Ulid().toString();
      ids.add(id);

      await conn.execute(
        r'''
        INSERT INTO reservations
          (id, booker_type, teacher_id, device_id, date, start_time, end_time, status)
        VALUES ($1, 'teacher', $2, $3, $4, $5, $6, 'pending')
      ''',
        parameters: [id, teacherId, deviceId, date, startTime, endTime],
      );
    }

    final reservations = <Reservation>[];
    for (final id in ids) {
      final r = await findById(id);
      if (r != null) reservations.add(r);
    }
    return reservations;
  }

  /// Crea una reserva de TV para un profesor (solo 1 permitida por bloque).
  Future<Reservation> createTvForTeacher({
    required String teacherId,
    required String deviceId,
    required String date,
    required String startTime,
    required String endTime,
  }) async {
    final conn = await getConnection();
    final id = Ulid().toString();

    await conn.execute(
      r'''
      INSERT INTO reservations
        (id, booker_type, teacher_id, device_id, date, start_time, end_time, status)
      VALUES ($1, 'teacher', $2, $3, $4, $5, $6, 'pending')
    ''',
      parameters: [id, teacherId, deviceId, date, startTime, endTime],
    );

    return (await findById(id))!;
  }

  /// Verifica si el profesor ya tiene una TV reservada en ese bloque horario.
  Future<bool> teacherHasTvReservationOnDateAndTime({
    required String teacherId,
    required String date,
    required String startTime,
    required String endTime,
  }) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
      SELECT r.id FROM reservations r
      JOIN devices d ON r.device_id = d.id
      WHERE r.teacher_id = $1
        AND r.date = $2
        AND r.status IN ('pending', 'confirmed')
        AND d.type = 'television'
        AND (
          (r.start_time <= $3 AND r.end_time > $3) OR
          (r.start_time < $4 AND r.end_time >= $4) OR
          (r.start_time >= $3 AND r.end_time <= $4)
        )
    ''',
      parameters: [teacherId, date, startTime, endTime],
    );
    return result.isNotEmpty;
  }

  /// Devuelve todas las reservas de un profesor.
  Future<List<Reservation>> getByTeacher(String teacherId) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
      SELECT
        r.id, r.booker_type, r.student_id, r.teacher_id, r.device_id,
        r.date, r.start_time, r.end_time, r.status, r.created_at,
        s.full_name as student_name,
        t.full_name as teacher_name
      FROM reservations r
      LEFT JOIN students s ON r.student_id = s.id
      LEFT JOIN teachers t ON r.teacher_id = t.id
      WHERE r.teacher_id = $1
      ORDER BY r.date DESC, r.start_time DESC
    ''',
      parameters: [teacherId],
    );
    return result.map(Reservation.fromRow).toList();
  }
}
