// ignore_for_file: public_member_api_docs

import 'package:postgres/postgres.dart';

class Reservation {
  Reservation({
    required this.id,
    required this.bookerType,
    required this.deviceId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.status,
    required this.createdAt,
    this.studentId,
    this.teacherId,
    this.studentName,
    this.teacherName,
  });

  factory Reservation.fromRow(List<dynamic> row) {
    return Reservation(
      id:          row[0] as String,
      bookerType:  row[1] as String,
      studentId:   row[2] as String?,
      teacherId:   row[3] as String?,
      deviceId:    row[4] as String,
      date:        row[5] as DateTime,
      startTime:   _timeToString(row[6] as Time),
      endTime:     _timeToString(row[7] as Time),
      status:      row[8] as String,
      createdAt:   row[9] as DateTime,
      studentName: row[10] as String?,
      teacherName: row[11] as String?,
    );
  }

  final String   id;
  final String   bookerType;
  final String?  studentId;
  final String?  teacherId;
  final String   deviceId;
  final DateTime date;
  final String   startTime;
  final String   endTime;
  final String   status;
  final DateTime createdAt;
  final String?  studentName;
  final String?  teacherName;

  Map<String, dynamic> toJson() => {
    'id':           id,
    'booker_type':  bookerType,
    'student_id':   studentId,
    'teacher_id':   teacherId,
    'student_name': studentName,
    'teacher_name': teacherName,
    'device_id':    deviceId,
    'date':         date.toIso8601String().substring(0, 10),
    'start_time':   startTime,
    'end_time':     endTime,
    'status':       status,
    'created_at':   createdAt.toIso8601String(),
  };
}

String _timeToString(Time t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}
