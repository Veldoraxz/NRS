// ignore_for_file: public_member_api_docs

import 'package:nrs_backend/database/connection.dart';
import 'package:nrs_backend/models/reservation.dart';
import 'package:postgres/postgres.dart';
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

    await conn.runTx((tx) async {
      // 1. Lock device para verificar disponibilidad
      final locked = await tx.execute(
        r'SELECT id FROM devices WHERE id = $1 FOR UPDATE',
        parameters: [deviceId],
      );

      if (locked.isEmpty) {
        throw Exception('Dispositivo no encontrado');
      }

      // 2. Verificar conflictos de horario CON LOCK
      final conflict = await tx.execute(
        r'''
          SELECT id FROM reservations
          WHERE device_id = $1 AND date = $2
            AND status IN ('pending', 'confirmed')
            AND (
              (start_time <= $3 AND end_time > $3) OR
              (start_time < $4 AND end_time >= $4) OR
              (start_time >= $3 AND end_time <= $4)
            )
          FOR UPDATE
        ''',
        parameters: [deviceId, date, startTime, endTime],
      );

      if (conflict.isNotEmpty) {
        throw Exception('El dispositivo no está disponible en ese horario');
      }

      // 3. Verificar que alumno no tenga otra reserva ese día CON LOCK
      final dailyRes = await tx.execute(
        r'''
          SELECT id FROM reservations
          WHERE student_id = $1 AND date = $2
            AND status IN ('pending', 'confirmed')
          FOR UPDATE
        ''',
        parameters: [studentId, date],
      );

      if (dailyRes.isNotEmpty) {
        throw Exception('El alumno ya tiene una reserva ese día');
      }

      // 4. Crear reservación (dentro de TX bloqueada)
      await tx.execute(
        r'''
          INSERT INTO reservations
            (id, booker_type, student_id, device_id, date, start_time, end_time, status)
          VALUES ($1, 'student', $2, $3, $4, $5, $6, 'pending')
        ''',
        parameters: [id, studentId, deviceId, date, startTime, endTime],
      );
    });

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

  Future<List<Map<String, dynamic>>> getAllWithFlowData() async {
    final conn = await getConnection();
    final result = await conn.execute(
      '''
        SELECT
          r.id, r.booker_type, r.student_id, r.teacher_id, r.device_id,
          d.number as device_number,
          d.type as device_type,
          r.date, r.start_time, r.end_time, r.status, r.created_at,
          s.full_name as student_name,
          t.full_name as teacher_name,
          c.id as checkout_id,
          c.checked_out_at,
          rt.id as return_id,
          rt.returned_at
        FROM reservations r
        LEFT JOIN students s ON r.student_id = s.id
        LEFT JOIN teachers t ON r.teacher_id = t.id
        LEFT JOIN devices d ON r.device_id = d.id
        LEFT JOIN checkouts c ON c.reservation_id = r.id
        LEFT JOIN returns rt ON rt.checkout_id = c.id
        ORDER BY r.date DESC, r.start_time DESC
      ''',
    );

    return result.map((row) {
      final date = row[7] as DateTime;
      final createdAt = row[11] as DateTime;
      final checkedOutAt = row[15] as DateTime?;
      final returnedAt = row[17] as DateTime?;

      return <String, dynamic>{
        'id': row[0] as String,
        'booker_type': row[1] as String,
        'student_id': row[2] as String?,
        'teacher_id': row[3] as String?,
        'device_id': row[4] as String,
        'device_number': row[5] as String?,
        'device_type': row[6] as String?,
        'date': date.toIso8601String().substring(0, 10),
        'start_time': _timeToString(row[8] as Time),
        'end_time': _timeToString(row[9] as Time),
        'status': row[10] as String,
        'created_at': createdAt.toIso8601String(),
        'student_name': row[12] as String?,
        'teacher_name': row[13] as String?,
        'checkout_id': row[14] as String?,
        'checked_out_at': checkedOutAt?.toIso8601String(),
        'return_id': row[16] as String?,
        'returned_at': returnedAt?.toIso8601String(),
      };
    }).toList();
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

  // ─── TEACHERS ─────────────────────────────────────────────────────────────

  Future<List<Reservation>> createForTeacher({
    required String teacherId,
    required List<String> deviceIds,
    required String date,
    required String startTime,
    required String endTime,
  }) async {
    final conn = await getConnection();
    final ids = <String>[];

    await conn.runTx((tx) async {
      for (final deviceId in deviceIds) {
        final locked = await tx.execute(
          r'SELECT id FROM devices WHERE id = $1 FOR UPDATE',
          parameters: [deviceId],
        );

        if (locked.isEmpty) {
          throw Exception('Dispositivo $deviceId no encontrado');
        }

        final conflict = await tx.execute(
          r'''
            SELECT id FROM reservations
            WHERE device_id = $1 AND date = $2
              AND status IN ('pending', 'confirmed')
              AND (
                (start_time <= $3 AND end_time > $3) OR
                (start_time < $4 AND end_time >= $4) OR
                (start_time >= $3 AND end_time <= $4)
              )
          ''',
          parameters: [deviceId, date, startTime, endTime],
        );

        if (conflict.isNotEmpty) {
          throw Exception(
            'El dispositivo $deviceId no está disponible en ese horario',
          );
        }

        final id = Ulid().toString();
        ids.add(id);

        await tx.execute(
          r'''
            INSERT INTO reservations
              (id, booker_type, teacher_id, device_id, date, start_time, end_time, status)
            VALUES ($1, 'teacher', $2, $3, $4, $5, $6, 'pending')
          ''',
          parameters: [id, teacherId, deviceId, date, startTime, endTime],
        );
      }
    });

    final reservations = <Reservation>[];
    for (final id in ids) {
      final r = await findById(id);
      if (r != null) reservations.add(r);
    }
    return reservations;
  }

  Future<Reservation> createTvForTeacher({
    required String teacherId,
    required String deviceId,
    required String date,
    required String startTime,
    required String endTime,
  }) async {
    final conn = await getConnection();
    final id = Ulid().toString();

    await conn.runTx((tx) async {
      final locked = await tx.execute(
        r'SELECT id FROM devices WHERE id = $1 FOR UPDATE',
        parameters: [deviceId],
      );

      if (locked.isEmpty) {
        throw Exception('Dispositivo no encontrado');
      }

      final conflict = await tx.execute(
        r'''
          SELECT id FROM reservations
          WHERE device_id = $1 AND date = $2
            AND status IN ('pending', 'confirmed')
            AND (
              (start_time <= $3 AND end_time > $3) OR
              (start_time < $4 AND end_time >= $4) OR
              (start_time >= $3 AND end_time <= $4)
            )
        ''',
        parameters: [deviceId, date, startTime, endTime],
      );

      if (conflict.isNotEmpty) {
        throw Exception('La TV no está disponible en ese horario');
      }

      await tx.execute(
        r'''
          INSERT INTO reservations
            (id, booker_type, teacher_id, device_id, date, start_time, end_time, status)
          VALUES ($1, 'teacher', $2, $3, $4, $5, $6, 'pending')
        ''',
        parameters: [id, teacherId, deviceId, date, startTime, endTime],
      );
    });

    return (await findById(id))!;
  }

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

  Future<bool> studentHasAnyReservation(String studentId) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id FROM reservations
        WHERE student_id = $1
          AND status IN ('pending', 'confirmed', 'completed')
        LIMIT 1
      ''',
      parameters: [studentId],
    );
    return result.isNotEmpty;
  }

  Future<int> expireOverdue() async {
    final conn = await getConnection();
    final now = DateTime.now();
    final currentDate = now.toIso8601String().split('T')[0];
    final currentTime =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:00';

    final result = await conn.execute(
      r'''
        UPDATE reservations
        SET status = 'expired'
        WHERE status IN ('pending', 'confirmed')
          AND (date < $1 OR (date = $1 AND end_time <= $2))
          AND id NOT IN (SELECT reservation_id FROM checkouts)
      ''',
      parameters: [currentDate, currentTime],
    );
    return result.affectedRows;
  }

  Future<List<Map<String, dynamic>>> countBySpecialty() async {
    final conn = await getConnection();
    final result = await conn.execute(
      '''
        SELECT
          COALESCE(s.specialty, 'ciclo_basico') AS specialty,
          COUNT(r.id)::int AS total
        FROM reservations r
        JOIN students s ON r.student_id = s.id
        WHERE r.booker_type = 'student'
        GROUP BY COALESCE(s.specialty, 'ciclo_basico')
        ORDER BY total DESC
      ''',
    );
    return result
        .map(
          (row) => {
            'specialty': row[0]! as String,
            'total': row[1]! as int,
          },
        )
        .toList();
  }
}

String _timeToString(Time t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
