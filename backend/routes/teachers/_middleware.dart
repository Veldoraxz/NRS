// ignore_for_file: public_member_api_docs

import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/middleware/admin_auth.dart';
import 'package:nrs_backend/middleware/auth_middleware.dart';
import 'package:nrs_backend/middleware/role_middleware.dart';

Handler middleware(Handler handler) {
  return (context) async {
    final path = context.request.uri.path;

    // Login es público — el profe obtiene su JWT acá
    if (path.endsWith('/login')) return handler(context);

    // POST requiere admin auth
    if (context.request.method.toString() == 'HttpMethod.post') {
      return adminAuthMiddleware(handler)(context);
    }

    // GET requiere auth. Permitimos admin y teacher
    final roled  = requireRoles(handler, ['admin', 'teacher']);
    final authed = authMiddleware(roled);
    return authed(context);
  };
}
