// ignore_for_file: public_member_api_docs

import 'package:bcrypt/bcrypt.dart';
import 'package:nrs_backend/database/connection.dart';
import 'package:nrs_backend/models/teacher.dart';
import 'package:ulid/ulid.dart';

class TeacherRepository {
  Future<Teacher?> findById(String id) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id, full_name, email, dni, created_at, is_active
        FROM teachers WHERE id = $1
      ''',
      parameters: [id],
    );
    if (result.isEmpty) return null;
    return Teacher.fromRow(result.first);
  }

  Future<Teacher?> findByEmail(String email) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id, full_name, email, dni, created_at, is_active
        FROM teachers WHERE email = $1
      ''',
      parameters: [email],
    );
    if (result.isEmpty) return null;
    return Teacher.fromRow(result.first);
  }

  Future<bool> existsByEmail(String email) async {
    return (await findByEmail(email)) != null;
  }

  Future<bool> existsByDni(String dni) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'SELECT id FROM teachers WHERE dni = $1',
      parameters: [dni],
    );
    return result.isNotEmpty;
  }

  Future<Teacher> create({
    required String fullName,
    required String email,
    required String dni,
  }) async {
    final conn         = await getConnection();
    final id           = Ulid().toString();
    final passwordHash = BCrypt.hashpw(dni, BCrypt.gensalt());

    await conn.execute(
      r'''
        INSERT INTO teachers
          (id, full_name, email, dni, password_hash, is_active)
        VALUES ($1, $2, $3, $4, $5, true)
      ''',
      parameters: [id, fullName, email, dni, passwordHash],
    );

    return (await findByEmail(email))!;
  }

  Future<Teacher?> login({
    required String email,
    required String dni,
  }) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id, full_name, email, dni, created_at, is_active, password_hash
        FROM teachers WHERE email = $1
      ''',
      parameters: [email],
    );

    if (result.isEmpty) return null;

    final row          = result.first;
    final passwordHash = row[6]! as String;
    final isValid      = BCrypt.checkpw(dni, passwordHash);
    if (!isValid) return null;

    return Teacher(
      id:        row[0]! as String,
      fullName:  row[1]! as String,
      email:     row[2]! as String,
      dni:       row[3]! as String,
      createdAt: row[4]! as DateTime,
      isActive:  row[5]! as bool,
    );
  }

  Future<List<Teacher>> getAll() async {
    final conn = await getConnection();
    final result = await conn.execute(
      'SELECT id, full_name, email, dni, created_at, is_active FROM teachers',
    );
    return result.map(Teacher.fromRow).toList();
  }

  Future<Map<String, dynamic>?> loginForAuth({
    required String email,
    required String dni,
  }) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id, email, password_hash, is_active
        FROM teachers WHERE email = $1
      ''',
      parameters: [email],
    );

    if (result.isEmpty) return null;

    final row          = result.first;
    final passwordHash = row[2]! as String;
    final isValid      = BCrypt.checkpw(dni, passwordHash);
    if (!isValid) return null;

    // Bloquear login si está inactivo
    final isActive = row[3]! as bool;
    if (!isActive) return null;

    return {
      'id':    row[0]! as String,
      'email': row[1]! as String,
      'role':  'teacher',
    };
  }

  /// Desactiva el teacher y cancela sus reservas pending.
  Future<Teacher?> deactivate(String id) async {
    final conn = await getConnection();

    await conn.runTx((tx) async {
      // Cancelar reservas pending futuras
      await tx.execute(
        r'''
          UPDATE reservations
          SET status = 'cancelled'
          WHERE teacher_id = $1
            AND status = 'pending'
            AND date >= CURRENT_DATE
        ''',
        parameters: [id],
      );

      // Desactivar teacher
      await tx.execute(
        r'UPDATE teachers SET is_active = false WHERE id = $1',
        parameters: [id],
      );
    });

    return findById(id);
  }

  /// Reactiva el teacher.
  Future<Teacher?> activate(String id) async {
    final conn = await getConnection();
    await conn.execute(
      r'UPDATE teachers SET is_active = true WHERE id = $1',
      parameters: [id],
    );
    return findById(id);
  }
}
