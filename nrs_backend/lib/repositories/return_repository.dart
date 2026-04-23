// ignore_for_file: public_member_api_docs

import 'package:nrs_backend/database/connection.dart';
import 'package:nrs_backend/models/return_model.dart';
import 'package:ulid/ulid.dart';

class ReturnRepository {
  Future<bool> existsByCheckout(String checkoutId) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'SELECT id FROM returns WHERE checkout_id = $1',
      parameters: [checkoutId],
    );
    return result.isNotEmpty;
  }

  Future<ReturnModel> create({
    required String checkoutId,
    required String adminId,
    required bool   hasDamage,
    String? deviceNotes,
  }) async {
    final conn = await getConnection();
    final id   = Ulid().toString();

    await conn.execute(
      r'''
        INSERT INTO returns
          (id, checkout_id, admin_id, device_notes, has_damage)
        VALUES ($1, $2, $3, $4, $5)
      ''',
      parameters: [id, checkoutId, adminId, deviceNotes, hasDamage],
    );

    final result = await conn.execute(
      r'''
        SELECT id, checkout_id, admin_id, device_notes, has_damage, returned_at
        FROM returns WHERE id = $1
      ''',
      parameters: [id],
    );

    return ReturnModel.fromRow(result.first);
  }
}
