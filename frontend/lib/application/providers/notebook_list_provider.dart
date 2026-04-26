// lib/application/providers/notebook_list_provider.dart
// GET /notebooks  → alumno/docente (sin auth requerida)
// GET /devices    → admin (con auth, devuelve { data:[...], total, limit, offset })
// PUT /devices/{id}/status → admin (válido: available | in_use | out_of_service)
// POST /reservations → alumno/docente

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/device.dart';
import '../../infrastructure/api_client.dart';

class NotebookListNotifier extends AsyncNotifier<List<Device>> {
  @override
  Future<List<Device>> build() => _fetchDevices();

  Future<List<Device>> _fetchDevices() async {
    try {
      // Intentar GET /devices (admin). Si falla 401/403 → usar /notebooks
      final res = await ApiClient.instance.get(
        '/devices',
        queryParameters: {'limit': 100, 'offset': 0},
      );
      final list = res.data['data'] as List<dynamic>;
      return list
          .map((j) => Device.fromJson(j as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      // No es admin o no tiene auth → usar endpoint público
      if (e.response?.statusCode == 401 ||
          e.response?.statusCode == 403 ||
          e.response == null) {
        return _fetchNotebooks();
      }
      rethrow;
    }
  }

  Future<List<Device>> _fetchNotebooks() async {
    final res = await ApiClient.instance.get('/notebooks');
    final list = res.data as List<dynamic>;
    return list.map((j) => Device.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  // ─── Admin: crear dispositivo ────────────────────────────────────────────────
  // POST /devices — { number, type, status?, status_notes? }
  Future<Device> createDevice({
    required String number,
    required String type,
    String? statusNotes,
  }) async {
    try {
      final res = await ApiClient.instance.post(
        '/devices',
        data: {
          'number': number,
          'type': type,
          if (statusNotes case final notes?) 'status_notes': notes,
        },
      );
      ref.invalidateSelf();
      return Device.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(
        ((e.response?.data as Map?)?['error'] as String?) ??
            'Error al crear dispositivo',
      );
    }
  }

  // ─── Admin: editar dispositivo ───────────────────────────────────────────────
  // PUT /devices/{id} — { number?, status_notes? }
  Future<Device> updateDevice({
    required String id,
    String? number,
    String? statusNotes,
  }) async {
    try {
      final res = await ApiClient.instance.put(
        '/devices/$id',
        data: {
          if (number case final n?) 'number': n,
          if (statusNotes case final notes?) 'status_notes': notes,
        },
      );
      ref.invalidateSelf();
      return Device.fromJson(res.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw Exception(
        ((e.response?.data as Map?)?['error'] as String?) ??
            'Error al actualizar dispositivo',
      );
    }
  }

  // ─── Admin: eliminar dispositivo ─────────────────────────────────────────────
  // DELETE /devices/{id}
  Future<void> deleteDevice(String id) async {
    try {
      await ApiClient.instance.delete('/devices/$id');
      ref.invalidateSelf();
    } on DioException catch (e) {
      throw Exception(
        ((e.response?.data as Map?)?['error'] as String?) ??
            'Error al eliminar dispositivo',
      );
    }
  }

  // ─── Admin: cambiar estado ───────────────────────────────────────────────────
  // PUT /devices/{id}/status — válido: available | in_use | out_of_service
  Future<void> updateDeviceStatus(String id, DeviceStatus status) async {
    final apiStatus = Device.statusToApi(status);
    // El backend no acepta 'maintenance' — solo lo usamos en UI local
    if (apiStatus == 'maintenance') {
      // Actualización optimista local
      final current = state.value ?? [];
      state = AsyncValue.data(
        current
            .map(
              (d) =>
                  d.id == id ? d.copyWith(status: DeviceStatus.maintenance) : d,
            )
            .toList(),
      );
      return;
    }
    try {
      await ApiClient.instance.put(
        '/devices/$id/status',
        data: {'status': apiStatus},
      );
      ref.invalidateSelf();
    } on DioException catch (e) {
      throw Exception(
        ((e.response?.data as Map?)?['error'] as String?) ??
            'Error al actualizar estado',
      );
    }
  }

  Future<void> returnDevice(String id) async {
    await updateDeviceStatus(id, DeviceStatus.available);
  }

  // ─── POST /reservations (alumno) ─────────────────────────────────────────────
  // Body: { device_id, date, start_time, end_time }
  // Restricciones del backend:
  //   - Máx 14 días adelante (no 30)
  //   - No sábado ni domingo
  //   - Horario: 07:30 – 22:00
  //   - Un alumno: 1 reserva por día
  Future<void> reserveDevice(
    String deviceId,
    DateTime date,
    String startTime, // 'HH:MM'
    String endTime, // 'HH:MM'
  ) async {
    try {
      await ApiClient.instance.post(
        '/reservations',
        data: {
          'device_id': deviceId,
          'date': '${date.year}-${_p(date.month)}-${_p(date.day)}',
          'start_time': startTime,
          'end_time': endTime,
        },
      );
      ref.invalidateSelf();
    } on DioException catch (e) {
      throw Exception(
        ((e.response?.data as Map?)?['error'] as String?) ??
            'Error al reservar',
      );
    }
  }

  // ─── POST /reservations (docente — múltiples notebooks o TV) ─────────────────
  // Body: { device_type, device_ids:[...], date, start_time, end_time }
  Future<void> reserveForTeacher({
    required String deviceType,
    required List<String> deviceIds,
    required DateTime date,
    required String startTime,
    required String endTime,
  }) async {
    try {
      await ApiClient.instance.post(
        '/reservations',
        data: {
          'device_type': deviceType,
          'device_ids': deviceIds,
          'date': '${date.year}-${_p(date.month)}-${_p(date.day)}',
          'start_time': startTime,
          'end_time': endTime,
        },
      );
      ref.invalidateSelf();
    } on DioException catch (e) {
      throw Exception(
        ((e.response?.data as Map?)?['error'] as String?) ??
            'Error al reservar',
      );
    }
  }

  // ─── POST /reservations/{id}/cancel ──────────────────────────────────────────
  Future<void> cancelReservation(String reservationId) async {
    try {
      await ApiClient.instance.post('/reservations/$reservationId/cancel');
      ref.invalidateSelf();
    } on DioException catch (e) {
      throw Exception(
        ((e.response?.data as Map?)?['error'] as String?) ??
            'Error al cancelar',
      );
    }
  }

  // ─── GET /reservations/all (admin/teacher) ────────────────────────────────────
  Future<List<Map<String, dynamic>>> getAllReservations() async {
    final res = await ApiClient.instance.get('/reservations/all');
    final list = res.data as List<dynamic>;
    return list.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  // ─── Slots bloqueados para un dispositivo en un día ──────────────────────────
  // Usado por el slot picker para deshabilitar horarios ocupados.
  Future<Set<String>> getBlockedSlots(String deviceId, DateTime day) async {
    try {
      final all = await getAllReservations();
      final dayStr = '${day.year}-${_p(day.month)}-${_p(day.day)}';
      return all
          .where(
            (r) =>
                r['device_id'] == deviceId &&
                r['date'] == dayStr &&
                (r['status'] == 'pending' || r['status'] == 'confirmed'),
          )
          .map((r) => r['start_time'] as String)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  // ─── POST /checkouts (admin aprueba retiro) ───────────────────────────────────
  // Body: { reservation_id, device_notes?, confirm? }
  // Si alumno inactivo → HTTP 202 { requires_confirmation: true }
  // Con confirm:true   → HTTP 201 + activa cuenta
  Future<Map<String, dynamic>> approveCheckout({
    required String reservationId,
    String? deviceNotes,
    bool confirm = false,
  }) async {
    try {
      final res = await ApiClient.instance.post(
        '/checkouts',
        data: {
          'reservation_id': reservationId,
          if (deviceNotes case final notes?) 'device_notes': notes,
          'confirm': confirm,
        },
      );
      ref.invalidateSelf();
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception(
        ((e.response?.data as Map?)?['error'] as String?) ??
            'Error en checkout',
      );
    }
  }

  // ─── POST /returns (admin registra devolución) ────────────────────────────────
  // Body: { checkout_id, device_notes?, has_damage, damage_description? }
  Future<void> processReturn({
    required String checkoutId,
    String? deviceNotes,
    bool hasDamage = false,
    String? damageDescription,
  }) async {
    try {
      await ApiClient.instance.post(
        '/returns',
        data: {
          'checkout_id': checkoutId,
          if (deviceNotes case final notes?) 'device_notes': notes,
          'has_damage': hasDamage,
          if (hasDamage && damageDescription != null)
            'damage_description': damageDescription,
        },
      );
      ref.invalidateSelf();
    } on DioException catch (e) {
      throw Exception(
        ((e.response?.data as Map?)?['error'] as String?) ??
            'Error al registrar devolución',
      );
    }
  }

  String _p(int n) => n.toString().padLeft(2, '0');
}

final notebookListProvider =
    AsyncNotifierProvider<NotebookListNotifier, List<Device>>(
      () => NotebookListNotifier(),
    );
