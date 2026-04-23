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

Future<Response> _create(RequestContext context) async {
  final user = context.read<AuthUser>();
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

  // Validar que la fecha no sea pasada
  final reservationDate = DateTime.tryParse(date);
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

  // Validar que start_time < end_time
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

  try {
    // Validar que el dispositivo existe y está available
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

    // Validar que el alumno tiene is_active = true
    final student = await StudentRepository().findById(user.userId);

    if (student == null || !student.isActive) {
      return Response.json(
        statusCode: HttpStatus.forbidden,
        body: {
          'error': 'Tu cuenta no está activa. '
              'Realizá tu primer retiro en persona.',
        },
      );
    }

    final repo = ReservationRepository();

    // Un estudiante solo puede tener una reserva activa por día
    if (await repo.studentHasReservationOnDate(
      studentId: user.userId,
      date:      date,
    )) {
      return Response.json(
        statusCode: HttpStatus.conflict,
        body: {'error': 'Ya tenés una reserva para ese día'},
      );
    }

    // El dispositivo no puede estar reservado en ese horario
    if (await repo.hasConflict(
      deviceId:  deviceId,
      date:      date,
      startTime: startTime,
      endTime:   endTime,
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

Future<Response> _getMyReservations(RequestContext context) async {
  final user = context.read<AuthUser>();
  try {
    final reservations = await ReservationRepository()
        .getByStudent(user.userId);
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

DateTime? _parseTime(String time) {
  try {
    final parts = time.split(':');
    if (parts.length < 2) return null;
    return DateTime(0, 1, 1, int.parse(parts[0]), int.parse(parts[1]));
  } catch (_) {
    return null;
  }
}
