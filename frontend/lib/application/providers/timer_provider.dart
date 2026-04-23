import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TimerNotifier extends Notifier<int> {
  Timer? _timer;
  static const int expirationTimeInSeconds = 10 * 60; // 10 minutes

  @override
  int build() {
    return 0;
  }

  void startReservationTimer(void Function() onTimeout) {
    state = expirationTimeInSeconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state > 0) {
        state--;
      } else {
        timer.cancel();
        onTimeout();
      }
    });
  }

  void cancelTimer() {
    _timer?.cancel();
    state = 0;
  }
}

final timerProvider = NotifierProvider<TimerNotifier, int>(() {
  return TimerNotifier();
});
