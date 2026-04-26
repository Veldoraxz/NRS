// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/auth/auth_user.dart';
import 'package:nrs_backend/repositories/device_repository.dart';
import 'package:nrs_backend/repositories/reservation_repository.dart';
import 'package:nrs_backend/repositories/student_repository.dart';
import 'package:nrs_backend/repositories/teacher_repository.dart';
import 'package:nrs_backend/repositories/watchlist_repository.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.post => _create(context),
    HttpMethod.get => _getMyReservations(context),
    _ => Future.value(Response(statusCode: HttpStatus.methodNotAllowed)),
  };
}

// ─── POST /reservations ───────────────────────────────────────────────────────

Future<Response> _create(RequestContext context) async {
  final user = context.read<AuthUser>();

  if (user.role == 'teacher') return _createForTeacher(context, user);
  if (user.role == 'student') return _createForStudent(context, user);

  return Response.json(
    statusCode: HttpStatus.forbidden,
    body: {'error': 'Rol no autorizado para crear reservas'},
  );
}

// ignore: lines_longer_than_80_chars
// ─── Lógica alumno ────────────────────────────────────────────────────────────

Future<Response> _createForStudent(
  RequestContext context,
  AuthUser user,
) async {
  final body = await context.request.json() as Map<String, dynamic>;

  final deviceId = body['device_id']?.toString().trim();
  final date = body['date']?.toString().trim();
  final startTime = body['start_time']?.toString().trim();
  final endTime = body['end_time']?.toString().trim();

  if (deviceId == null ||
      deviceId.isEmpty ||
      date == null ||
      date.isEmpty ||
      startTime == null ||
      startTime.isEmpty ||
      endTime == null ||
      endTime.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'device_id, date, start_time y end_time son requeridos'},
    );
  }

  final reservationDate = DateTime.tryParse(date);
  final timeError = _validateDateAndTime(reservationDate, startTime, endTime);
  if (timeError != null) return timeError;

  try {
    final student = await StudentRepository().findById(user.userId);
    if (student == null) {
      return Response.json(
        statusCode: HttpStatus.forbidden,
        body: {'error': 'Alumno no encontrado'},
      );
    }

    if (await WatchlistRepository().isBlocked(student.dni)) {
      return Response.json(
        statusCode: HttpStatus.forbidden,
        body: {
          'error':
              'Tu cuenta está bloqueada por roturas de dispositivos. '
              'Consultá con el administrador.',
        },
      );
    }

    if (!student.isActive) {
      final yaHizoReserva = await ReservationRepository()
          .studentHasAnyReservation(user.userId);
      if (yaHizoReserva) {
        return Response.json(
          statusCode: HttpStatus.forbidden,
          body: {
            'error':
                'Tu cuenta no está activa. '
                'Ya tenés una reserva pendiente de retiro presencial.',
          },
        );
      }
    }

    // Todas las validaciones de device, conflictos y horarios se hacen
    // dentro de la transacción en createForStudent()
    final reservation = await ReservationRepository().createForStudent(
      studentId: user.userId,
      deviceId: deviceId,
      date: date,
      startTime: startTime,
      endTime: endTime,
    );

    return Response.json(
      statusCode: HttpStatus.created,
      body: reservation.toJson(),
    );
  } catch (e) {
    final msg = e.toString().toLowerCase();

    if (msg.contains('no está disponible') ||
        msg.contains('conflict') ||
        msg.contains('dispositivo no encontrado')) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': e.toString()},
      );
    }

    if (msg.contains('ya tiene una reserva')) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': e.toString()},
      );
    }

    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}

// ignore: lines_longer_than_80_chars
// ─── Lógica profesor ──────────────────────────────────────────────────────────
//
// Body para notebooks:
// {
//   "device_type": "notebook",
//   "device_ids":  ["id1", "id2"],
//   "date":        "2025-05-10",
//   "start_time":  "08:00",
//   "end_time":    "10:00"
// }
//
// Body para TV:
// {
//   "device_type": "television",
//   "device_ids":  ["id_tv"],
//   "date":        "2025-05-10",
//   "start_time":  "08:00",
//   "end_time":    "10:00"
// }

Future<Response> _createForTeacher(
  RequestContext context,
  AuthUser user,
) async {
  final body = await context.request.json() as Map<String, dynamic>;

  final deviceType = body['device_type']?.toString().trim();
  final date = body['date']?.toString().trim();
  final startTime = body['start_time']?.toString().trim();
  final endTime = body['end_time']?.toString().trim();

  final rawIds = body['device_ids'];
  List<String>? deviceIds;
  if (rawIds is List) {
    deviceIds = rawIds.map((e) => e.toString().trim()).toList();
  }

  if (deviceType == null || deviceType.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'device_type es requerido ("notebook" o "television")'},
    );
  }

  if (deviceType != 'notebook' && deviceType != 'television') {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'device_type debe ser "notebook" o "television"'},
    );
  }

  if (deviceIds == null || deviceIds.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'device_ids es requerido y no puede estar vacío'},
    );
  }

  if (deviceType == 'television' && deviceIds.length > 1) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Solo podés reservar una TV por vez'},
    );
  }

  if (date == null ||
      date.isEmpty ||
      startTime == null ||
      startTime.isEmpty ||
      endTime == null ||
      endTime.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'date, start_time y end_time son requeridos'},
    );
  }

  final reservationDate = DateTime.tryParse(date);
  final timeError = _validateDateAndTime(reservationDate, startTime, endTime);
  if (timeError != null) return timeError;

  try {
    final teacher = await TeacherRepository().findById(user.userId);
    if (teacher == null) {
      return Response.json(
        statusCode: HttpStatus.forbidden,
        body: {'error': 'Profesor no encontrado'},
      );
    }

    if (await WatchlistRepository().isBlocked(teacher.dni)) {
      return Response.json(
        statusCode: HttpStatus.forbidden,
        body: {
          'error':
              'Tu cuenta está bloqueada por watchlist. '
              'Consultá con el administrador.',
        },
      );
    }

    final deviceRepo = DeviceRepository();
    final repo = ReservationRepository();

    for (final deviceId in deviceIds) {
      final device = await deviceRepo.findById(deviceId);

      if (device == null) {
        return Response.json(
          statusCode: HttpStatus.notFound,
          body: {'error': 'El dispositivo $deviceId no existe'},
        );
      }

      if (device.type != deviceType) {
        return Response.json(
          statusCode: HttpStatus.badRequest,
          body: {
            'error': 'El dispositivo $deviceId no es de tipo "$deviceType"',
          },
        );
      }

      if (device.status != 'available') {
        return Response.json(
          statusCode: HttpStatus.conflict,
          body: {'error': 'El dispositivo $deviceId no está disponible'},
        );
      }
    }

    if (deviceType == 'television') {
      if (await repo.teacherHasTvReservationOnDateAndTime(
        teacherId: user.userId,
        date: date,
        startTime: startTime,
        endTime: endTime,
      )) {
        return Response.json(
          statusCode: HttpStatus.conflict,
          body: {'error': 'Ya tenés una TV reservada en ese horario'},
        );
      }

      final reservation = await repo.createTvForTeacher(
        teacherId: user.userId,
        deviceId: deviceIds.first,
        date: date,
        startTime: startTime,
        endTime: endTime,
      );

      return Response.json(
        statusCode: HttpStatus.created,
        body: reservation.toJson(),
      );
    }

    final reservations = await repo.createForTeacher(
      teacherId: user.userId,
      deviceIds: deviceIds,
      date: date,
      startTime: startTime,
      endTime: endTime,
    );

    return Response.json(
      statusCode: HttpStatus.created,
      body: reservations.map((r) => r.toJson()).toList(),
    );
  } catch (e) {
    final msg = e.toString();
    if (msg.contains('no está disponible en ese horario')) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': msg.replaceAll('Exception: ', '')},
      );
    }
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}

// ─── GET /reservations ────────────────────────────────────────────────────────

Future<Response> _getMyReservations(RequestContext context) async {
  final user = context.read<AuthUser>();
  try {
    final repo = ReservationRepository();
    final reservations = user.role == 'teacher'
        ? await repo.getByTeacher(user.userId)
        : await repo.getByStudent(user.userId);

    return Response.json(
      body: reservations.map((r) => r.toJson()).toList(),
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

Response? _validateDateAndTime(
  DateTime? reservationDate,
  String startTime,
  String endTime,
) {
  if (reservationDate == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Formato de fecha inválido, usá YYYY-MM-DD'},
    );
  }

  final today = DateTime.now();
  final todayOnly = DateTime(today.year, today.month, today.day);

  // No permitir fechas pasadas
  if (reservationDate.isBefore(todayOnly)) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'No podés reservar en una fecha pasada'},
    );
  }

  // No permitir más de 14 días hacia adelante
  final maxDate = todayOnly.add(const Duration(days: 14));
  if (reservationDate.isAfter(maxDate)) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      // ignore: lines_longer_than_80_chars
      body: {
        'error':
            'Solo podés reservar con un máximo de 2 semanas de anticipación',
      },
    );
  }

  // No permitir sábado (6) ni domingo (7)
  if (reservationDate.weekday == DateTime.saturday ||
      reservationDate.weekday == DateTime.sunday) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'No se pueden hacer reservas los fines de semana'},
    );
  }

  final start = _parseTime(startTime);
  final end = _parseTime(endTime);

  if (start == null || end == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Formato de hora inválido, usá HH:MM'},
    );
  }

  // Rango permitido: 07:30 a 22:00
  final minTime = DateTime(0, 1, 1, 7, 30);
  // ignore: avoid_redundant_argument_values
  final maxTime = DateTime(0, 1, 1, 22, 0);

  if (start.isBefore(minTime)) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'El horario de inicio no puede ser anterior a las 07:30'},
    );
  }

  if (end.isAfter(maxTime)) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'El horario de fin no puede ser posterior a las 22:00'},
    );
  }

  if (!start.isBefore(end)) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'start_time debe ser anterior a end_time'},
    );
  }

  return null;
}

DateTime? _parseTime(String time) {
  try {
    final parts = time.split(':');
    if (parts.length < 2) return null;
    return DateTime(0, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
  } catch (_) {
    return null;
  }
}
