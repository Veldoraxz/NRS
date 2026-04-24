// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'package:logging/logging.dart';
import 'package:nrs_backend/repositories/reservation_repository.dart';

final _logger = Logger('expire_reservations_task');

void startExpireReservationsTask() {
  Logger.root.level = Level.INFO;

  Timer.periodic(const Duration(minutes: 1), (_) async {
    try {
      final expired = await ReservationRepository().expireOverdue();
      if (expired > 0) {
        _logger.info('Se expiraron $expired reservas');
      }
    } catch (e) {
      _logger.severe('Error al expirar reservas: $e');
    }
  });
}
