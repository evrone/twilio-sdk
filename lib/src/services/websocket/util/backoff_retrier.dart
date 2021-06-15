import 'package:jotaro/jotaro.dart';
import 'package:twilio_conversations/src/vendor/operation-retrier/backoff_config.dart';
import 'package:twilio_conversations/src/vendor/operation-retrier/retrier.dart';

class BackoffRetrier extends Stendo {
  BackoffRetrier({this.config, this.newBackoff, this.retrier, this.usedBackoff})
      : super();

  final BackoffRetrierConfig config;
  int newBackoff;
  int usedBackoff;
  Retrier retrier;

  bool get inProgress => retrier != null;

  /// Should be called once per attempt series to start retrier.
  void start() {
    if (inProgress) {
      throw Exception(
          'Already waiting for next attempt, call finishAttempt(bool success) to finish it');
    }
    createRetrier();
  }

  /// Should be called to stop retrier entirely.
  void stop() {
    cleanRetrier();
    newBackoff = null;
    usedBackoff = null;
  }

  /// Modifies backoff for next attempt.
  /// Expected behavior:
  /// - If there was no backoff passed previously reschedulling next attempt to given backoff
  /// - If previous backoff was longer then ignoring this one.
  /// - If previous backoff was shorter then reschedulling with this one.
  /// With or without backoff retrier will keep growing normally.
  /// @param delay delay of next attempts in ms.
  void modifyBackoff(int delay) {
    newBackoff = delay;
  }

  /// Mark last emmited attempt as failed, initiating either next of fail if limits were hit.
  void attemptFailed() {
    if (!inProgress) {
      throw Exception('No attempt is in progress');
    }
    if (newBackoff != null) {
      final shouldUseNewBackoff =
          usedBackoff == null || usedBackoff < newBackoff;
      if (shouldUseNewBackoff) {
        createRetrier();
      } else {
        retrier.failed(Error());
      }
    } else {
      retrier.failed(Error());
    }
  }

  void cancel() {
    retrier?.cancel();
  }

  void cleanRetrier() {
    if (retrier != null) {
      retrier.removeAllListeners();
      retrier.cancel();
      retrier = null;
    }
  }

  BackoffRetrierConfig getRetryPolicy() {
    // As we're always skipping first attempt we should add one extra if limit is present
    return config.clone(
        maxAttemptsCount: config.maxAttemptsCount != null
            ? config.maxAttemptsCount + 1
            : null,
        min: newBackoff,
        max: config.max != null && config.max > newBackoff
            ? config.max
            : newBackoff);
  }

  void createRetrier() {
    cleanRetrier();
    final retryPolicy = getRetryPolicy();
    retrier = Retrier(
        initialDelay: retryPolicy.initial,
        randomness: retryPolicy.randomness,
        minDelay: retryPolicy.min,
        maxDelay: retryPolicy.max,
        maxAttemptsCount: config.maxAttemptsCount,
        maxAttemptsTime: config.maxAttemptsTime);
    retrier.once('attempt', (_) {
      retrier.on('attempt', (_) => emit('attempt'));
      retrier.failed(Exception('Skipping first attempt'));
    });
    retrier.on('failed', (err) => emit('failed', payload: err));
    usedBackoff = newBackoff;
    newBackoff = null;
    retrier.start();
  }
}
