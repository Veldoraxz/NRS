// lib/domain/entities/device.dart
// El backend tiene: id, number, type (notebook|television),
// status (available|in_use|out_of_service), status_notes.
// NO hay specialty en devices — la especialidad es del alumno.

enum DeviceModel { notebook, tv }
enum DeviceStatus { available, inUse, maintenance, outOfService }

class Device {
  final String id;
  final String number;
  final DeviceModel model;
  final DeviceStatus status;
  final String? statusNotes;

  const Device({
    required this.id,
    required this.number,
    required this.model,
    required this.status,
    this.statusNotes,
  });

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: json['id'] as String,
      number: json['number'] as String,
      model: json['type'] == 'television'
          ? DeviceModel.tv
          : DeviceModel.notebook,
      status: _mapStatus(json['status'] as String),
      statusNotes: json['status_notes'] as String?,
    );
  }

  static DeviceStatus _mapStatus(String s) {
    switch (s) {
      case 'in_use':
        return DeviceStatus.inUse;
      case 'out_of_service':
        return DeviceStatus.outOfService;
      case 'maintenance':
        return DeviceStatus.maintenance;
      default:
        return DeviceStatus.available;
    }
  }

  static String statusToApi(DeviceStatus s) {
    switch (s) {
      case DeviceStatus.inUse:
        return 'in_use';
      case DeviceStatus.outOfService:
        return 'out_of_service';
      case DeviceStatus.maintenance:
        return 'maintenance'; // solo UI, el backend no acepta este valor en PUT
      case DeviceStatus.available:
        return 'available';
    }
  }

  static String statusLabel(DeviceStatus s) {
    switch (s) {
      case DeviceStatus.available:
        return 'Disponible';
      case DeviceStatus.inUse:
        return 'En Uso';
      case DeviceStatus.maintenance:
        return 'Mantenimiento';
      case DeviceStatus.outOfService:
        return 'Fuera de Servicio';
    }
  }

  Device copyWith({DeviceStatus? status, String? statusNotes}) {
    return Device(
      id: id,
      number: number,
      model: model,
      status: status ?? this.status,
      statusNotes: statusNotes ?? this.statusNotes,
    );
  }
}