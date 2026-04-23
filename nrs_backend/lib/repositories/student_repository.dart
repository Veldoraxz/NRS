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
          year, division, is_active, created_at
        FROM students WHERE email = $1
      ''',
      parameters: [email],
    );
    if (result.isEmpty) return null;
    return Student.fromRow(result.first);
  }

  Future<bool> existsByEmail(String email) async {
    final student = await findByEmail(email);
    return student != null;
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
  }) async {
    final conn = await getConnection();
    final id = Ulid().toString();

    await conn.execute(
      r'''
        INSERT INTO students
          (id, full_name, email, dni, year, division, is_active)
        VALUES ($1, $2, $3, $4, $5, $6, false)
      ''',
      parameters: [id, fullName, email, dni, year, division],
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
          year, division, is_active, created_at
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
}
