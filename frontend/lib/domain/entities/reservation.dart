// lib/domain/entities/reservation.dart
// Alineado con Reservation.toJson() del backend:
// { id, booker_type, student_id, teacher_id, student_name, teacher_name,
//   device_id, date, start_time, end_time, status, created_at }

enum ReservationStatus { pending, confirmed, cancelled, expired, completed }
enum BookerType { student, teacher }

class Reservation {
  final String id;
  final BookerType bookerType;
  final String? studentId;
  final String? teacherId;
  final String? studentName;
  final String? teacherName;
  final String deviceId;
  final String date;       // 'YYYY-MM-DD'
  final String startTime;  // 'HH:MM'
  final String endTime;    // 'HH:MM'
  final ReservationStatus status;

  const Reservation({
    required this.id,
    required this.bookerType,
    required this.deviceId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.status,
    this.studentId,
    this.teacherId,
    this.studentName,
    this.teacherName,
  });

  factory Reservation.fromJson(Map<String, dynamic> j) {
    return Reservation(
      id: j['id'] as String,
      bookerType: j['booker_type'] == 'teacher'
          ? BookerType.teacher
          : BookerType.student,
      studentId: j['student_id'] as String?,
      teacherId: j['teacher_id'] as String?,
      studentName: j['student_name'] as String?,
      teacherName: j['teacher_name'] as String?,
      deviceId: j['device_id'] as String,
      date: j['date'] as String,
      startTime: j['start_time'] as String,
      endTime: j['end_time'] as String,
      status: _mapStatus(j['status'] as String),
    );
  }

  static ReservationStatus _mapStatus(String s) {
    switch (s) {
      case 'confirmed': return ReservationStatus.confirmed;
      case 'cancelled': return ReservationStatus.cancelled;
      case 'expired':   return ReservationStatus.expired;
      case 'completed': return ReservationStatus.completed;
      default:          return ReservationStatus.pending;
    }
  }

  bool get isActive =>
      status == ReservationStatus.pending ||
      status == ReservationStatus.confirmed;
}