// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/database/connection.dart';
import 'package:nrs_backend/middleware/admin_auth.dart';

Handler middleware(Handler handler) {
  return adminAuthMiddleware(handler);
}

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: HttpStatus.methodNotAllowed);
  }

  final body    = await context.request.json() as Map<String, dynamic>;
  final confirm = body['confirm'];

  // Confirmación explícita obligatoria
  if (confirm != 'RESET_ANUAL_CONFIRMADO') {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {
        'error':
            'Debés confirmar la acción enviando '
            '"confirm": "RESET_ANUAL_CONFIRMADO" en el body',
      },
    );
  }

  try {
    final conn = await getConnection();

    await conn.runTx((tx) async {
      await tx.execute('DELETE FROM notifications');
      await tx.execute('DELETE FROM damages');
      await tx.execute('DELETE FROM returns');
      await tx.execute('DELETE FROM checkouts');
      await tx.execute('DELETE FROM teacher_tokens');
      await tx.execute('DELETE FROM reservations');
      await tx.execute('DELETE FROM students');
    });

    stderr.writeln(
      // ignore: lines_longer_than_80_chars
      '[annual_reset] Reset ejecutado: ${DateTime.now().toUtc().toIso8601String()}',
    );

    return Response.json(
      body: {
        'message': 'Reset anual ejecutado correctamente.',
        'deleted': [
          'notifications',
          'damages',
          'returns',
          'checkouts',
          'teacher_tokens',
          'reservations',
          'students',
        ],
        'preserved': ['admins', 'teachers', 'devices', 'watchlist'],
        'executed_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error durante el reset. Ningún cambio fue aplicado: $e'},
    );
  }
}
