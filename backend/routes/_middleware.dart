// ignore_for_file: public_member_api_docs

import 'package:dart_frog/dart_frog.dart';
import 'package:nrs_backend/tasks/expire_reservations_task.dart';

bool _taskStarted = false;

Handler middleware(Handler handler) {
  return (context) async {
    if (!_taskStarted) {
      _taskStarted = true;
      startExpireReservationsTask();
    }
    return handler(context);
  };
}
