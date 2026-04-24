import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/device.dart';

class NotebookListNotifier extends AsyncNotifier<List<Device>> {
  @override
  Future<List<Device>> build() async {
    return _generateInventory();
  }

  List<Device> _generateInventory() {
    final List<Device> inventory = [];
    
    // 20 unidades "Conectar Igualdad"
    for (int i = 1; i <= 20; i++) {
      inventory.add(
        Device(
          id: 'CI-${i.toString().padLeft(2, '0')}',
          model: DeviceModel.conectarIgualdad,
          type: 'Notebook',
          specialty: 'General',
          status: DeviceStatus.available,
        ),
      );
    }

    // 4 unidades "CX"
    for (int i = 1; i <= 4; i++) {
      inventory.add(
        Device(
          id: 'CX-${i.toString().padLeft(2, '0')}',
          model: DeviceModel.cx,
          type: 'Notebook',
          specialty: 'Diseño/Programación',
          status: DeviceStatus.available,
        ),
      );
    }

    // 4 unidades "TV"
    for (int i = 1; i <= 4; i++) {
      inventory.add(
        Device(
          id: 'TV-${i.toString().padLeft(2, '0')}',
          model: DeviceModel.tv,
          type: 'Televisor',
          specialty: 'Uso Docente',
          status: DeviceStatus.available,
        ),
      );
    }

    return inventory;
  }

  Future<void> updateDeviceStatus(String id, DeviceStatus status, {String? userEmail}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final currentList = state.value ?? [];
      return currentList.map((device) {
        if (device.id == id) {
          return device.copyWith(status: status, currentUserEmail: userEmail);
        }
        return device;
      }).toList();
    });
  }

  Future<void> returnDevice(String id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final currentList = state.value ?? [];
      return currentList.map((device) {
        if (device.id == id) {
          // No hay copyWith que reciba null explícitamente y borre un valor no null,
          // así que creamos un nuevo objeto basado en el actual pero con currentUserEmail nulo.
          return Device(
            id: device.id,
            model: device.model,
            type: device.type,
            specialty: device.specialty,
            status: DeviceStatus.available,
            currentUserEmail: null,
          );
        }
        return device;
      }).toList();
    });
  }
}

final notebookListProvider = AsyncNotifierProvider<NotebookListNotifier, List<Device>>(() {
  return NotebookListNotifier();
});
