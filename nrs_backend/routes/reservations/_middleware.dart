// ignore_for_file: public_member_api_docs

import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/middleware/auth_middleware.dart';
import 'package:nrs_backend/middleware/role_middleware.dart';

Handler middleware(Handler handler) {
  return (context) async {
    final roled  = requireRoles(handler, ['student', 'teacher', 'admin']);
    final authed = authMiddleware(roled);
    return authed(context);
  };
}
