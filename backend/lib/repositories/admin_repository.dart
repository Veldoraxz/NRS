// ignore_for_file: public_member_api_docs

import 'package:bcrypt/bcrypt.dart';
import 'package:nrs_backend/database/connection.dart';

class AdminRepository {
  Future<Map<String, dynamic>?> loginByEmail({
    required String email,
    required String password,
  }) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id, email, password_hash
        FROM admins WHERE email = $1
      ''',
      parameters: [email],
    );

    if (result.isEmpty) return null;

    final row          = result.first;
    final passwordHash = row[2]! as String;
    final isValid      = BCrypt.checkpw(password, passwordHash);

    if (!isValid) return null;

    return {
      'id':    row[0]! as String,
      'email': row[1]! as String,
      'role':  'admin',
    };
  }
}
