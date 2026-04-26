// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/auth/auth_user.dart';

/// Permite solo los roles especificados.
/// Siempre usarlo después de authMiddleware.
Handler requireRoles(Handler handler, List<String> roles) {
  return (context) async {
    final user = context.read<AuthUser>();

    if (!roles.contains(user.role)) {
      return Response.json(
        statusCode: HttpStatus.forbidden,
        body: {'error': 'No tenés permisos para esto'},
      );
    }

    return handler(context);
  };
}
