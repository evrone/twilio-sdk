import 'dart:async';
import 'dart:math';

import 'package:jotaro/jotaro.dart';

bool isDef(value) {
  return value != null;
}

class Backoff extends Stendo {
  Backoff(
      {this.factor = 2,
      this.initialDelay = 100,
      this.maxDelay = 10000,
      this.randomisationFactor = 0,
      this.maxNumberOfRetry = -1})
      : super() {
    if (isDef(initialDelay) && initialDelay < 1) {
      throw Exception(
          'The initial timeout must be equal to or greater than 1.');
    } else if (isDef(maxDelay) && maxDelay <= 1) {
      throw Exception('The maximal timeout must be greater than 1.');
    } else if (isDef(randomisationFactor) &&
        (randomisationFactor < 0 || randomisationFactor > 1)) {
      throw Exception('The randomisation factor must be between 0 and 1.');
    } else if (isDef(factor) && factor <= 1) {
      throw Exception('Exponential factor should be greater than 1.');
    }

    if (maxDelay <= initialDelay) {
      throw Exception(
          'The maximal backoff delay must be greater than the initial backoff delay.');
    }
    reset();
  }

  int initialDelay;
  int maxDelay;
  double randomisationFactor;
  int factor;
  Timer timer;
  int maxNumberOfRetry;
  int backoffDelay;

  int nextBackoffDelay;
  int backoffNumber;

  static Backoff exponential(
      {int factor = 2,
      int initialDelay,
      int maxDelay,
      double randomisationFactor,
      int maxNumberOfRetry}) {
    return Backoff(
        initialDelay: initialDelay,
        maxDelay: maxDelay,
        randomisationFactor: randomisationFactor,
        factor: factor);
  }

  void backoff({Error err}) {
    if (timer == null) {
      if (backoffNumber == maxNumberOfRetry) {
        emit('fail', payload: err);
        reset();
      } else {
        backoffDelay = next();
        timer = Timer(Duration(milliseconds: backoffDelay), () {
          onBackoff();
        });
        emit('backoff', payload: {
          'backoffNumber': backoffNumber,
          'backoffDelay': backoffDelay,
          'error': err
        });
      }
    }
  }

  void reset() {
    backoffDelay = 0;
    nextBackoffDelay = initialDelay;
    backoffNumber = 0;
    timer.cancel();
    timer = null;
  }

  void failAfter(maxNumberOfRetry) {
    if (maxNumberOfRetry <= 0) {
      throw Exception(
          'Expected a maximum number of retry greater than 0 but got $maxNumberOfRetry');
    }
    this.maxNumberOfRetry = maxNumberOfRetry;
  }

  int next() {
    backoffDelay = min<int>(nextBackoffDelay, maxDelay);
    nextBackoffDelay = backoffDelay * factor;
    final randomisationMultiple = 1 + Random().nextInt(2) * randomisationFactor;
    return min<int>(maxDelay, (backoffDelay * randomisationMultiple).round());
  }

  void onBackoff() {
    timer = null;
    emit('ready', payload: {
      'backoffNumber': backoffNumber,
      'backoffDelay': backoffDelay
    });
    backoffNumber++;
  }
}
