// ignore_for_file: public_member_api_docs

import 'dart:math';
import 'package:nrs_backend/database/connection.dart';
import 'package:nrs_backend/models/teacher_token.dart';
import 'package:ulid/ulid.dart';

class TeacherTokenRepository {
  /// Alfabeto sin caracteres ambiguos ('0', 'O', '1', 'I' permanecen porque
  /// el sistema permite ingresar el código con un teclado real, pero podríamos
  /// ajustarlo si fuera necesario).
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

  /// Token corto: 6 caracteres alfanuméricos en mayúscula.
  String _generateToken() {
    final random = Random.secure();
    final buf = StringBuffer();
    for (var i = 0; i < 6; i++) {
      buf.write(_alphabet[random.nextInt(_alphabet.length)]);
    }
    return buf.toString();
  }

  Future<TeacherToken?> findByToken(String token) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id, reservation_id, token, used, expires_at
        FROM teacher_tokens WHERE token = $1
      ''',
      parameters: [token],
    );
    if (result.isEmpty) return null;
    return TeacherToken.fromRow(result.first);
  }

  Future<TeacherToken?> findByReservation(String reservationId) async {
    final conn = await getConnection();
    final result = await conn.execute(
      r'''
        SELECT id, reservation_id, token, used, expires_at
        FROM teacher_tokens WHERE reservation_id = $1
      ''',
      parameters: [reservationId],
    );
    if (result.isEmpty) return null;
    return TeacherToken.fromRow(result.first);
  }

  /// Crea un token para la reserva.
  /// expires_at = date + start_time + 10 minutos.
Future<TeacherToken> create({
  required String reservationId,
  required DateTime reservationDate,
  required String startTime,
}) async {
  final conn = await getConnection();
  final id   = Ulid().toString();

  // startTime puede venir como "08:00" o "08:00:00" — tomamos solo HH y MM
  final parts  = startTime.split(':');
  final hour   = int.parse(parts[0].trim());
  final minute = int.parse(parts[1].trim());

  final startDt = DateTime.utc(
    reservationDate.year,
    reservationDate.month,
    reservationDate.day,
    hour,
    minute,
  );
  final expiresAt = startDt.add(const Duration(minutes: 10));

  // 36^6 ≈ 2.18B combinaciones: choque improbable pero posible. Reintentamos.
  for (var attempt = 0; attempt < 8; attempt++) {
    final token = _generateToken();
    try {
      await conn.execute(
        r'''
          INSERT INTO teacher_tokens
            (id, reservation_id, token, used, expires_at)
          VALUES ($1, $2, $3, false, $4)
        ''',
        parameters: [id, reservationId, token, expiresAt],
      );
      return (await findByToken(token))!;
    } catch (e) {
      // Choque de UNIQUE → reintentar con otro token.
      final msg = e.toString().toLowerCase();
      if (msg.contains('unique') || msg.contains('duplicate')) {
        continue;
      }
      rethrow;
    }
  }
  throw Exception('No se pudo generar un token único, intentá de nuevo.');
}

  /// Marca el token como usado.
  Future<void> markAsUsed(String id) async {
    final conn = await getConnection();
    await conn.execute(
      r'UPDATE teacher_tokens SET used = true WHERE id = $1',
      parameters: [id],
    );
  }
}
