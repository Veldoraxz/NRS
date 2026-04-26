// lib/application/providers/auth_provider.dart
// POST /auth/login → { token, role, email }
// Luego POST /students/login (o /teachers/login) para obtener perfil completo.
// El token se inyecta en ApiClient.setAuthToken() para todos los calls futuros.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/user.dart';
import '../../infrastructure/api_client.dart';

class AuthNotifier extends Notifier<AsyncValue<User?>> {
  @override
  AsyncValue<User?> build() => const AsyncValue.data(null);

  Future<void> login(String email, String password, UserRole role) async {
    state = const AsyncValue.loading();
    try {
      // 1. POST /auth/login — requiere { email, password, role }
      final loginRes = await ApiClient.instance.post(
        '/auth/login',
        data: {'email': email, 'password': password, 'role': role.name},
      );
      final token = loginRes.data['token'] as String;
      ApiClient.setAuthToken(token);

      // 2. Obtener perfil completo según rol
      User user;
      if (role == UserRole.student) {
        user = await _fetchStudentProfile(email, password);
      } else if (role == UserRole.teacher) {
        user = await _fetchTeacherProfile(email, password);
      } else {
        // Admin: no tiene endpoint de perfil, construir con datos del login
        user = User(
          id: loginRes.data['id'] as String? ?? '',
          email: email,
          dni: password,
          fullName: 'Administrador',
          role: UserRole.admin,
          isActive: true,
        );
      }

      state = AsyncValue.data(user);
    } on DioException catch (e) {
      ApiClient.clearAuthToken();
      final msg = e.response?.data?['error'] as String? ?? 'Error de conexión';
      state = AsyncValue.error(msg, StackTrace.current);
      rethrow;
    }
  }

  Future<User> _fetchStudentProfile(String email, String password) async {
    // POST /students/login → objeto Student completo con is_active, year, specialty
    final res = await ApiClient.instance.post(
      '/students/login',
      data: {'email': email, 'dni': password},
    );
    final d = res.data as Map<String, dynamic>;
    return User(
      id: d['id'] as String,
      email: d['email'] as String,
      dni: password,
      fullName: d['full_name'] as String,
      role: UserRole.student,
      isActive: d['is_active'] as bool? ?? false,
      year: d['year'] as int?,
      division: d['division'] as int?,
      specialty: d['specialty'] as String?,
    );
  }

  Future<User> _fetchTeacherProfile(String email, String password) async {
    // POST /teachers/login
    final res = await ApiClient.instance.post(
      '/teachers/login',
      data: {'email': email, 'dni': password},
    );
    final d = res.data as Map<String, dynamic>;
    return User(
      id: d['id'] as String,
      email: d['email'] as String,
      dni: password,
      fullName: d['full_name'] as String,
      role: UserRole.teacher,
      isActive: true,
    );
  }

  void logout() {
    ApiClient.clearAuthToken();
    state = const AsyncValue.data(null);
  }

  /// Llamado cuando el admin aprueba el primer retiro del alumno.
  void activateAccount() {
    final user = state.value;
    if (user != null) {
      state = AsyncValue.data(user.copyWith(isActive: true));
    }
  }
}

final authProvider =
    NotifierProvider<AuthNotifier, AsyncValue<User?>>(() => AuthNotifier());