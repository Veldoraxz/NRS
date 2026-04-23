

// ignore_for_file: public_member_api_docs

import 'package:nrs_backend/database/connection.dart';
import 'package:nrs_backend/models/device.dart';
import 'package:ulid/ulid.dart';

class DeviceRepository {
  Future<Device?> findById(String id) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT
          id, number, type, status, status_notes, created_at
        FROM devices WHERE id = $1
      ''',
      parameters: [id],
    );
    if (result.isEmpty) return null;
    return Device.fromRow(result.first);
  }

  Future<bool> existsByNumber(String number, String type) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'SELECT id FROM devices WHERE number = $1 AND type = $2',
      parameters: [number, type],
    );
    return result.isNotEmpty;
  }

  Future<List<Device>> getAll({
    String? type,
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    final conn = await getConnection();

    var query = '''
      SELECT id, number, type, status, status_notes, created_at
      FROM devices
      WHERE 1=1
    ''';

    final params = <dynamic>[];
    var paramIndex = 1;

    if (type != null && type.isNotEmpty) {
      query += ' AND type = \$${paramIndex++}';
      params.add(type);
    }

    if (status != null && status.isNotEmpty) {
      query += ' AND status = \$${paramIndex++}';
      params.add(status);
    }

    query +=
        ' ORDER BY created_at DESC LIMIT \$${paramIndex++} '
        'OFFSET \$${paramIndex++}';
    params.addAll([limit, offset]);

    final result = await conn.execute(query, parameters: params);
    return result.map(Device.fromRow).toList();
  }

  Future<int> count({String? type, String? status}) async {
    final conn = await getConnection();

    var query = 'SELECT COUNT(*) FROM devices WHERE 1=1';
    final params = <dynamic>[];
    var paramIndex = 1;

    if (type != null && type.isNotEmpty) {
      query += ' AND type = \$${paramIndex++}';
      params.add(type);
    }

    if (status != null && status.isNotEmpty) {
      query += ' AND status = \$${paramIndex++}';
      params.add(status);
    }

    final result = await conn.execute(query, parameters: params);
    return (result.first[0] as int?) ?? 0;
  }

  Future<Device> create({
    required String number,
    required String type,
    required String status,
    String? statusNotes,
  }) async {
    final conn = await getConnection();
    final id = Ulid().toString();
    final now = DateTime.now().toUtc();

    await conn.execute(
      r'''
        INSERT INTO devices
          (id, number, type, status, status_notes, created_at)
        VALUES ($1, $2, $3, $4, $5, $6)
      ''',
      parameters: [id, number, type, status, statusNotes, now],
    );

    return (await findById(id))!;
  }

  Future<Device?> updateStatus(String id, String newStatus) async {
    final conn = await getConnection();

    final result = await conn.execute(
      r'''
        UPDATE devices
        SET status = $1
        WHERE id = $2
        RETURNING id, number, type, status, status_notes, created_at
      ''',
      parameters: [newStatus, id],
    );

    if (result.isEmpty) return null;
    return Device.fromRow(result.first);
  }

  Future<bool> delete(String id) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'DELETE FROM devices WHERE id = $1',
      parameters: [id],
    );
    return result.affectedRows > 0;
  }

  
}
