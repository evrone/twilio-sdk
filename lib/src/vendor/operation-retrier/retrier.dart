import 'dart:async';
import 'dart:math';

import 'package:jotaro/jotaro.dart';

class Retrier extends Stendo {
  int minDelay;

  int maxDelay;

  int initialDelay;

  int maxAttemptsCount;

  int maxAttemptsTime;

  final double randomness;

  bool inProgress;

  int attemptNum;

  int prevDelay;

  int currDelay;

  DateTime startTimestamp;

  Timer timeout;

  /// Creates a new Retrier instance
  Retrier({
    this.minDelay,
    this.maxDelay,
    this.initialDelay = 0,
    this.maxAttemptsCount = 0,
    this.maxAttemptsTime = 0,
    this.randomness = 0,
    this.inProgress = false,
    this.attemptNum = 0,
    this.prevDelay = 0,
    this.currDelay = 0,
  }) : super();

  void attempt() {
    timeout.cancel();
    attemptNum++;
    timeout = null;
    emit('attempt', payload: this);
  }

  int nextDelay({int delayOverride}) {
    if (delayOverride != null) {
      prevDelay = 0;
      currDelay = delayOverride;
      return delayOverride;
    }
    if (attemptNum == 0) {
      return initialDelay;
    }
    if (attemptNum == 1) {
      currDelay = minDelay;
      return currDelay;
    }
    prevDelay = currDelay;
    var delay = currDelay + prevDelay;
    if (maxDelay != null && delay > maxDelay) {
      currDelay = maxDelay;
      delay = maxDelay;
    }

    currDelay = delay;
    return delay;
  }

  int randomize(delay) {
    final area = delay * randomness;
    final corr = (Random().nextInt(2) * area * 2 - area).round();
    return max<int>(0, delay + corr);
  }

  void scheduleAttempt(int delayOverride) {
    if (maxAttemptsCount != null && attemptNum >= maxAttemptsCount) {
      cleanup();
      emit('failed', payload: Exception('Maximum attempt count limit reached'));
      //this.reject(new Error('Maximum attempt count reached'));
      return;
    }
    var delay = nextDelay(delayOverride: delayOverride);
    delay = randomize(delay);
    if (maxAttemptsTime != null &&
        (startTimestamp
            .add(Duration(milliseconds: maxAttemptsTime))
            .isBefore(DateTime.now().add(Duration(milliseconds: delay))))) {
      cleanup();
      emit('failed', payload: Exception('Maximum attempt time limit reached'));
      //this.reject(new Error('Maximum attempt time limit reached'));
      return;
    }
    timeout = Timer(Duration(milliseconds: delay), attempt);
  }

  void cleanup() {
    timeout.cancel();
    timeout = null;
    inProgress = false;
    attemptNum = 0;
    prevDelay = 0;
    currDelay = 0;
  }

  //Stream<Map<String, dynamic>>
  void start() {
    if (inProgress) {
      throw Exception('Retrier is already in progress');
    }
    startTimestamp = DateTime.now();
    scheduleAttempt(initialDelay);

    inProgress = true;
    // return _controller.stream;
  }

  void cancel() {
    if (timeout != null) {
      timeout.cancel();
      timeout = null;
      inProgress = false;
      emit('cancelled', payload: null);
      //this.reject(new Error('Cancelled'));
    }
  }

  void succeeded(arg) {
    emit('succeeded', payload: arg);
    //this.resolve(arg);
  }

  void failed(err, {nextAttemptDelayOverride}) {
    if (timeout != null) {
      throw Exception('Retrier attempt is already in progress');
    }
    scheduleAttempt(nextAttemptDelayOverride);
  }

  void run(Function handler) async {
    on('attempt', (_) async {
      try {
        var result = handler();
        if (result is Future) {
          result = await result;
        }
        succeeded(result);
      } catch (e) {
        failed(e);
      }
    });
    start();
  }
}
