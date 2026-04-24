enum ReservationStatus { active, cancelled, completed }

class Reservation {
  final String id;
  final String deviceId;
  final String userId;
  final DateTime startTime;
  final ReservationStatus status;

  const Reservation({
    required this.id,
    required this.deviceId,
    required this.userId,
    required this.startTime,
    required this.status,
  });

  Reservation copyWith({
    String? id,
    String? deviceId,
    String? userId,
    DateTime? startTime,
    ReservationStatus? status,
  }) {
    return Reservation(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      userId: userId ?? this.userId,
      startTime: startTime ?? this.startTime,
      status: status ?? this.status,
    );
  }
}
