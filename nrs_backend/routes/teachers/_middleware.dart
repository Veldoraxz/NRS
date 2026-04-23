// ignore_for_file: public_member_api_docs

import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/middleware/auth_middleware.dart';
import 'package:nrs_backend/middleware/role_middleware.dart';

Handler middleware(Handler handler) {
  return (context) async {
    final path = context.request.uri.path;

    // Login es público — el profe obtiene su JWT acá
    if (path.endsWith('/login')) return handler(context);

    // El resto requiere auth. Permitimos admin y teacher;
    // la lógica fina (ej: solo admin puede crear) se resuelve en el handler.
    final roled  = requireRoles(handler, ['admin', 'teacher']);
    final authed = authMiddleware(roled);
    return authed(context);
  };
}
