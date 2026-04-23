// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/auth/auth_user.dart';
import 'package:nrs_backend/repositories/device_repository.dart';
import 'package:nrs_backend/repositories/reservation_repository.dart';
import 'package:nrs_backend/repositories/student_repository.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.post => _create(context),
    HttpMethod.get  => _getMyReservations(context),
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

// ─── Lógica alumno (sin cambios) ─────────────────────────────────────────────

Future<Response> _createForStudent(
  RequestContext context,
  AuthUser user,
) async {
  final body = await context.request.json() as Map<String, dynamic>;

  final deviceId  = body['device_id']?.toString().trim();
  final date      = body['date']?.toString().trim();
  final startTime = body['start_time']?.toString().trim();
  final endTime   = body['end_time']?.toString().trim();

  if (deviceId  == null || deviceId.isEmpty  ||
      date      == null || date.isEmpty       ||
      startTime == null || startTime.isEmpty  ||
      endTime   == null || endTime.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'device_id, date, start_time y end_time son requeridos'},
    );
  }

  final reservationDate = DateTime.tryParse(date);
  final timeError = _validateDateAndTime(reservationDate, startTime, endTime);
  if (timeError != null) return timeError;

  try {
    final device = await DeviceRepository().findById(deviceId);
    if (device == null) {
      return Response.json(
        statusCode: HttpStatus.notFound,
        body: {'error': 'El dispositivo no existe'},
      );
    }
    if (device.status != 'available') {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'El dispositivo no está disponible'},
      );
    }

    final student = await StudentRepository().findById(user.userId);
    if (student == null || !student.isActive) {
      return Response.json(
        statusCode: HttpStatus.forbidden,
        body: {
          'error':
              'Tu cuenta no está activa. Realizá tu primer retiro en persona.',
        },
      );
    }

    final repo = ReservationRepository();

    if (await repo.studentHasReservationOnDate(
      studentId: user.userId,
      date: date,
    )) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'Ya tenés una reserva para ese día'},
      );
    }

    if (await repo.hasConflict(
      deviceId: deviceId,
      date: date,
      startTime: startTime,
      endTime: endTime,
    )) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'El dispositivo no está disponible en ese horario'},
      );
    }

    final reservation = await repo.createForStudent(
      studentId: user.userId,
      deviceId:  deviceId,
      date:      date,
      startTime: startTime,
      endTime:   endTime,
    );

    return Response.json(
      statusCode: HttpStatus.created,
      body: reservation.toJson(),
    );
  } catch (e) {
    return Response.json(
      statusCode: HttpStatus.internalServerError,
      body: {'error': 'Error interno: $e'},
    );
  }
}

// ─── Lógica profesor ─────────────────────────────────────────────────────────
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
  final date       = body['date']?.toString().trim();
  final startTime  = body['start_time']?.toString().trim();
  final endTime    = body['end_time']?.toString().trim();

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

  if (date == null || date.isEmpty ||
      startTime == null || startTime.isEmpty ||
      endTime == null || endTime.isEmpty) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'date, start_time y end_time son requeridos'},
    );
  }

  final reservationDate = DateTime.tryParse(date);
  final timeError = _validateDateAndTime(reservationDate, startTime, endTime);
  if (timeError != null) return timeError;

  final dbDeviceType = deviceType;

  try {
    final deviceRepo = DeviceRepository();
    final repo       = ReservationRepository();

    // Validar cada dispositivo
    for (final deviceId in deviceIds) {
      final device = await deviceRepo.findById(deviceId);

      if (device == null) {
        return Response.json(
          statusCode: HttpStatus.notFound,
          body: {'error': 'El dispositivo $deviceId no existe'},
        );
      }

      if (device.type != dbDeviceType) {
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

      if (await repo.hasConflict(
        deviceId: deviceId,
        date: date,
        startTime: startTime,
        endTime: endTime,
      )) {
        return Response.json(
          statusCode: HttpStatus.conflict,
          body: {
            'error':
                'El dispositivo $deviceId no está disponible en ese horario',
          },
        );
      }
    }

    // TV: verificar que el profe no tenga otra TV en ese bloque
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
        deviceId:  deviceIds.first,
        date:      date,
        startTime: startTime,
        endTime:   endTime,
      );

      return Response.json(
        statusCode: HttpStatus.created,
        body: reservation.toJson(),
      );
    }

    // Notebooks: múltiples
    final reservations = await repo.createForTeacher(
      teacherId: user.userId,
      deviceIds: deviceIds,
      date:      date,
      startTime: startTime,
      endTime:   endTime,
    );

    return Response.json(
      statusCode: HttpStatus.created,
      body: reservations.map((r) => r.toJson()).toList(),
    );
  } catch (e) {
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

  final today     = DateTime.now();
  final todayOnly = DateTime(today.year, today.month, today.day);
  if (reservationDate.isBefore(todayOnly)) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'No podés reservar en una fecha pasada'},
    );
  }

  final start = _parseTime(startTime);
  final end   = _parseTime(endTime);

  if (start == null || end == null) {
    return Response.json(
      statusCode: HttpStatus.badRequest,
      body: {'error': 'Formato de hora inválido, usá HH:MM'},
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
