// ignore_for_file: public_member_api_docs

import 'package:nrs_backend/database/connection.dart';
import 'package:nrs_backend/models/damage.dart';
import 'package:ulid/ulid.dart';

class DamageRepository {
  Future<Damage> create({
    required String dni,
    required String returnId,
    required String description,
  }) async {
    final conn = await getConnection();
    final id   = Ulid().toString();

    await conn.execute(
      r'''
        INSERT INTO damages (id, dni, return_id, description)
        VALUES ($1, $2, $3, $4)
      ''',
      parameters: [id, dni, returnId, description],
    );

    return (await findById(id))!;
  }

  Future<Damage?> findById(String id) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id, dni, return_id, description, created_at
        FROM damages WHERE id = $1
      ''',
      parameters: [id],
    );
    if (result.isEmpty) return null;
    return Damage.fromRow(result.first);
  }

  Future<List<Damage>> getByDni(String dni) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id, dni, return_id, description, created_at
        FROM damages WHERE dni = $1
        ORDER BY created_at DESC
      ''',
      parameters: [dni],
    );
    return result.map(Damage.fromRow).toList();
  }
}
