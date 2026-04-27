// lib/application/providers/auth_provider.dart
// POST /auth/login → { token, role, email, user:{...} }
// El backend autodetecta el rol probando student → teacher → admin.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/user.dart';
import '../../infrastructure/api_client.dart';

class AuthNotifier extends Notifier<AsyncValue<User?>> {
  @override
  AsyncValue<User?> build() => const AsyncValue.data(null);

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final res = await ApiClient.instance.post(
        '/auth/login',
        data: {'email': email, 'password': password},
      );

      final data  = res.data as Map<String, dynamic>;
      final token = data['token'] as String;
      ApiClient.setAuthToken(token);

      final roleStr  = (data['role'] as String?) ?? 'student';
      final role     = _parseRole(roleStr);
      final userData = data['user'] as Map<String, dynamic>? ?? {};

      state = AsyncValue.data(_userFromPayload(
        role: role,
        dni:  password,
        userData: userData,
        emailFallback: data['email']?.toString() ?? email,
      ));
    } on DioException catch (e) {
      ApiClient.clearAuthToken();
      final status = e.response?.statusCode;
      final String msg;
      if (status == 401 || status == 403) {
        msg = 'Datos incorrectos';
      } else if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.response == null) {
        msg = 'No se pudo conectar con el servidor';
      } else {
        msg = (e.response?.data is Map)
            ? ((e.response!.data['error'] as String?) ?? 'Datos incorrectos')
            : 'Datos incorrectos';
      }
      state = AsyncValue.error(msg, StackTrace.current);
      throw Exception(msg);
    }
  }

  UserRole _parseRole(String s) {
    switch (s) {
      case 'admin':
        return UserRole.admin;
      case 'teacher':
        return UserRole.teacher;
      default:
        return UserRole.student;
    }
  }

  User _userFromPayload({
    required UserRole role,
    required String dni,
    required Map<String, dynamic> userData,
    required String emailFallback,
  }) {
    final id        = userData['id']?.toString() ?? '';
    final email     = userData['email']?.toString() ?? emailFallback;
    final fullName  = userData['full_name']?.toString()
        ?? (role == UserRole.admin ? 'Administrador' : email.split('@').first);

    return User(
      id:        id,
      email:     email,
      dni:       dni,
      fullName:  fullName,
      role:      role,
      isActive:  userData['is_active'] as bool? ?? true,
      year:      userData['year'] as int?,
      division:  userData['division'] as int?,
      specialty: userData['specialty'] as String?,
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
