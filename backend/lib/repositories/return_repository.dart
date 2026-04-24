// ignore_for_file: public_member_api_docs

import 'package:nrs_backend/database/connection.dart';
import 'package:nrs_backend/models/return_model.dart';

class ReturnRepository {
  Future<bool> existsByCheckout(String checkoutId) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'SELECT id FROM returns WHERE checkout_id = $1',
      parameters: [checkoutId],
    );
    return result.isNotEmpty;
  }

  Future<ReturnModel?> findByCheckout(String checkoutId) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id, checkout_id, admin_id, device_notes, has_damage, returned_at
        FROM returns
        WHERE checkout_id = $1
      ''',
      parameters: [checkoutId],
    );
    if (result.isEmpty) return null;
    return ReturnModel.fromRow(result.first);
  }
}
