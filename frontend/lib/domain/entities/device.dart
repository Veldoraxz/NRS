enum DeviceModel { conectarIgualdad, cx, tv }
enum DeviceStatus { available, inUse, maintenance, outOfService }

class Device {
  final String id;
  final DeviceModel model;
  final String type;
  final String specialty;
  final DeviceStatus status;
  final String? currentUserEmail;

  const Device({
    required this.id,
    required this.model,
    required this.type,
    required this.specialty,
    required this.status,
    this.currentUserEmail,
  });

  Device copyWith({
    String? id,
    DeviceModel? model,
    String? type,
    String? specialty,
    DeviceStatus? status,
    String? currentUserEmail,
  }) {
    return Device(
      id: id ?? this.id,
      model: model ?? this.model,
      type: type ?? this.type,
      specialty: specialty ?? this.specialty,
      status: status ?? this.status,
      currentUserEmail: currentUserEmail ?? this.currentUserEmail,
    );
  }
}
