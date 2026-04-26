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

    // Preflight OPTIONS
    if (context.request.method == HttpMethod.options) {
      return Response(
        statusCode: 204,
        headers: {
          'Access-Control-Allow-Origin': '*',
          // ignore: lines_longer_than_80_chars
          'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
          'Access-Control-Max-Age': '86400',
        },
      );
    }

    final response = await handler(context);
    final headers = Map<String, String>.from(response.headers);
    headers['Access-Control-Allow-Origin'] = '*';
    // ignore: lines_longer_than_80_chars
    headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, PATCH, DELETE, OPTIONS';
    headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization';

    return response.copyWith(headers: headers);
  };
}
