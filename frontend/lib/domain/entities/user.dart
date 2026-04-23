enum UserRole { student, teacher, admin }

class User {
  final String email;
  final String dni;
  final UserRole role;
  final bool isActive;

  const User({
    required this.email,
    required this.dni,
    required this.role,
    this.isActive = false,
  });

  User copyWith({
    String? email,
    String? dni,
    UserRole? role,
    bool? isActive,
  }) {
    return User(
      email: email ?? this.email,
      dni: dni ?? this.dni,
      role: role ?? this.role,
      isActive: isActive ?? this.isActive,
    );
  }
}
