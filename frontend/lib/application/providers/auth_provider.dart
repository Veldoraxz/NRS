import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/user.dart';

class AuthNotifier extends Notifier<User?> {
  @override
  User? build() {
    return null; // Null means no user logged in
  }

  void login(String email, String dni, UserRole role) {
    // Alumnos inician como "Cuenta en Aire" (is_active: false)
    bool isActive = role == UserRole.student ? false : true;
    
    state = User(
      email: email,
      dni: dni,
      role: role,
      isActive: isActive,
    );
  }

  void logout() {
    state = null;
  }

  void activateAccount() {
    if (state != null) {
      state = state!.copyWith(isActive: true);
    }
  }
}

final authProvider = NotifierProvider<AuthNotifier, User?>(() {
  return AuthNotifier();
});
