// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';

// Token fijo por ahora, después lo reemplazamos con JWT
const _adminToken = 'admin-secret-token';

Handler adminAuthMiddleware(Handler handler) {
  return (context) async {
    final auth = context.request.headers['Authorization'];

    if (auth == null || auth != 'Bearer $_adminToken') {
      return Response.json(
        statusCode: HttpStatus.unauthorized,
        body: {'error': 'No autorizado'},
      );
    }

    return handler(context);
  };
}
