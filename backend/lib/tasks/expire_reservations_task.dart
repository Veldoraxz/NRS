// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:io';
import 'package:nrs_backend/repositories/reservation_repository.dart';

void startExpireReservationsTask() {
  Timer.periodic(const Duration(minutes: 1), (_) async {
    try {
      final expired = await ReservationRepository().expireOverdue();
      if (expired > 0) {
        stderr.writeln('[expire_task] Se expiraron $expired reservas');
      }
    } catch (e) {
      stderr.writeln('[expire_task] Error al expirar reservas: $e');
    }
  });
}
