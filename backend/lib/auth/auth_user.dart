// ignore_for_file: public_member_api_docs

class AuthUser {
  AuthUser({required this.userId, required this.role});

  final String userId;
  final String role;

  bool get isAdmin   => role == 'admin';
  bool get isTeacher => role == 'teacher';
}
