// ignore_for_file: public_member_api_docs

import 'package:nrs_backend/database/connection.dart';
import 'package:nrs_backend/models/watchlist.dart';
import 'package:ulid/ulid.dart';

class WatchlistRepository {
  Future<Watchlist?> findByDni(String dni) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id, dni, full_name, damage_count, active, updated_at
        FROM watchlist WHERE dni = $1
      ''',
      parameters: [dni],
    );
    if (result.isEmpty) return null;
    return Watchlist.fromRow(result.first);
  }

  Future<Watchlist?> findById(String id) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id, dni, full_name, damage_count, active, updated_at
        FROM watchlist WHERE id = $1
      ''',
      parameters: [id],
    );
    if (result.isEmpty) return null;
    return Watchlist.fromRow(result.first);
  }

  Future<bool> isBlocked(String dni) async {
    final entry = await findByDni(dni);
    if (entry == null) return false;
    return entry.active && entry.damageCount >= 3;
  }

  Future<List<Watchlist>> getAll() async {
    final conn = await getConnection();
    final result = await conn.execute(
      '''
        SELECT id, dni, full_name, damage_count, active, updated_at
        FROM watchlist
        ORDER BY updated_at DESC
      ''',
    );
    return result.map(Watchlist.fromRow).toList();
  }

  /// Incrementa damage_count de forma atómica (sin race condition).
  /// Si no existe la fila, la crea con damage_count = 1.
  /// Usa ON CONFLICT para garantizar idempotencia.
  Future<Watchlist> incrementDamage({
    required String dni,
    required String fullName,
  }) async {
    final conn = await getConnection();

    // ON CONFLICT hace el upsert de forma atómica en la BD
    await conn.execute(
      r'''
        INSERT INTO watchlist (id, dni, full_name, damage_count, active, updated_at)
        VALUES ($1, $2, $3, 1, true, NOW())
        ON CONFLICT(dni) DO UPDATE SET
          damage_count = watchlist.damage_count + 1,
          active       = true,
          updated_at   = NOW()
      ''',
      parameters: [Ulid().toString(), dni, fullName],
    );

    return (await findByDni(dni))!;
  }

  /// Agrega manualmente un alumno al watchlist con damage_count = 3
  /// (bloqueado). Usa ON CONFLICT para garantizar atomicidad.
  Future<Watchlist> addManually({
    required String dni,
    required String adminId,
  }) async {
    final conn = await getConnection();

    // Buscar nombre en students
    final studentResult = await conn.execute(
      r'SELECT full_name FROM students WHERE dni = $1',
      parameters: [dni],
    );

    if (studentResult.isEmpty) {
      throw Exception('No existe un alumno registrado con el DNI $dni');
    }

    // ignore: cast_nullable_to_non_nullable
    final fullName = studentResult.first[0] as String;

    // Upsert: si no existe lo crea con damage_count=3, si existe lo setea a 3
    await conn.execute(
      r'''
        INSERT INTO watchlist (id, dni, full_name, damage_count, active, updated_at)
        VALUES ($1, $2, $3, 3, true, NOW())
        ON CONFLICT(dni) DO UPDATE SET
          damage_count = 3,
          active       = true,
          updated_at   = NOW()
      ''',
      parameters: [Ulid().toString(), dni, fullName],
    );

    return (await findByDni(dni))!;
  }


  /// Elimina la entrada — para alumnos que ya no están en el colegio.
  Future<bool> delete(String id) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'DELETE FROM watchlist WHERE id = $1',
      parameters: [id],
    );
    return result.affectedRows > 0;
  }
}
