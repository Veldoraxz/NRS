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

  Future<void> activate(String id) async {
    final conn = await getConnection();
    await conn.execute(
      r'UPDATE students SET is_active = true WHERE id = $1',
      parameters: [id],
    );
  }
}
