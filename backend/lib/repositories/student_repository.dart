// ignore_for_file: public_member_api_docs

import 'package:nrs_backend/database/connection.dart';
import 'package:nrs_backend/models/student.dart';
import 'package:ulid/ulid.dart';

class StudentRepository {
  Future<Student?> findByEmail(String email) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT
          id, full_name, email, dni,
          year, division, is_active, created_at, specialty
        FROM students WHERE email = $1
      ''',
      parameters: [email],
    );
    if (result.isEmpty) return null;
    return Student.fromRow(result.first);
  }

  Future<bool> existsByEmail(String email) async {
    return (await findByEmail(email)) != null;
  }

  Future<bool> existsByDni(String dni) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'SELECT id FROM students WHERE dni = $1',
      parameters: [dni],
    );
    return result.isNotEmpty;
  }

  Future<Student?> register({
    required String fullName,
    required String email,
    required String dni,
    required int year,
    required int division,
    String? specialty,
  }) async {
    final conn = await getConnection();
    final id   = Ulid().toString();

    await conn.execute(
      r'''
        INSERT INTO students
          (id, full_name, email, dni, year, division, is_active, specialty)
        VALUES ($1, $2, $3, $4, $5, $6, false, $7)
      ''',
      parameters: [id, fullName, email, dni, year, division, specialty],
    );

    return findByEmail(email);
  }

  Future<Student?> login({
    required String email,
    required String dni,
  }) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT
          id, full_name, email, dni,
          year, division, is_active, created_at, specialty
        FROM students
        WHERE email = $1 AND dni = $2
      ''',
      parameters: [email, dni],
    );
    if (result.isEmpty) return null;
    return Student.fromRow(result.first);
  }

  Future<Map<String, dynamic>?> loginForAuth({
    required String email,
    required String dni,
  }) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id, email
        FROM students
        WHERE email = $1 AND dni = $2
      ''',
      parameters: [email, dni],
    );
    if (result.isEmpty) return null;
    return {
      'id':    result.first[0]! as String,
      'email': result.first[1]! as String,
      'role':  'student',
    };
  }

  Future<Student?> findById(String id) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT
          id, full_name, email, dni,
          year, division, is_active, created_at, specialty
        FROM students WHERE id = $1
      ''',
      parameters: [id],
    );
    if (result.isEmpty) return null;
    return Student.fromRow(result.first);
  }

  Future<bool> existsByEmailExcludingId(String email, String excludeId) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'SELECT id FROM students WHERE email = $1 AND id <> $2',
      parameters: [email, excludeId],
    );
    return result.isNotEmpty;
  }

  Future<bool> existsByDniExcludingId(String dni, String excludeId) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'SELECT id FROM students WHERE dni = $1 AND id <> $2',
      parameters: [dni, excludeId],
    );
    return result.isNotEmpty;
  }

  Future<Student?> update({
    required String id,
    required String fullName,
    required String email,
    required String dni,
    required int year,
    required int division,
    String? specialty,
  }) async {
    final conn = await getConnection();
    await conn.execute(
      r'''
        UPDATE students
        SET full_name = $2,
            email     = $3,
            dni       = $4,
            year      = $5,
            division  = $6,
            specialty = $7
        WHERE id = $1
      ''',
      parameters: [id, fullName, email, dni, year, division, specialty],
    );
    return findById(id);
  }

  Future<void> activate(String id) async {
    final conn = await getConnection();
    await conn.execute(
      r'UPDATE students SET is_active = true WHERE id = $1',
      parameters: [id],
    );
  }

  Future<void> deactivate(String id) async {
    final conn = await getConnection();
    await conn.execute(
      r'UPDATE students SET is_active = false WHERE id = $1',
      parameters: [id],
    );
  }

  Future<void> reactivate(String id) async {
    final conn = await getConnection();
    await conn.execute(
      r'UPDATE students SET is_active = true WHERE id = $1',
      parameters: [id],
    );
  }

  Future<bool> hasCheckoutHistory(String id) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT 1
        FROM checkouts c
        JOIN reservations r ON r.id = c.reservation_id
        WHERE r.student_id = $1
        LIMIT 1
      ''',
      parameters: [id],
    );
    return result.isNotEmpty;
  }

  /// Elimina al alumno y sus reservas (las cancelaciones por checkout
  /// previo se manejan a nivel de ruta — si fallan por FK, abortamos).
  Future<void> delete(String id) async {
    final conn = await getConnection();
    await conn.runTx((tx) async {
      // Borra reservas del alumno (cascada de teacher_tokens).
      await tx.execute(
        r'DELETE FROM reservations WHERE student_id = $1',
        parameters: [id],
      );
      // Borra al alumno.
      await tx.execute(
        r'DELETE FROM students WHERE id = $1',
        parameters: [id],
      );
    });
  }
}
