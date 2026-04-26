// lib/domain/entities/user.dart
// Alineado con el modelo Student/Teacher/Admin del backend.

enum UserRole { student, teacher, admin }

class User {
  final String id;
  final String email;
  final String dni;
  final String fullName;
  final UserRole role;
  final bool isActive;
  // Solo para students
  final int? year;
  final int? division;
  final String? specialty; // 'programacion' | 'electronica' | 'construcciones' | null

  const User({
    required this.id,
    required this.email,
    required this.dni,
    required this.fullName,
    required this.role,
    required this.isActive,
    this.year,
    this.division,
    this.specialty,
  });

  bool get isPendingActivation => role == UserRole.student && !isActive;

  User copyWith({bool? isActive}) => User(
        id: id,
        email: email,
        dni: dni,
        fullName: fullName,
        role: role,
        isActive: isActive ?? this.isActive,
        year: year,
        division: division,
        specialty: specialty,
      );
}