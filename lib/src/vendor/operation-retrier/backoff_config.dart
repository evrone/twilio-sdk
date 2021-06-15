class BackoffRetrierConfig {
  BackoffRetrierConfig({
    this.maxAttemptsCount,
    this.maxAttemptsTime,
    this.randomness,
    this.max,
    this.min,
    this.initial,
  });
  int min;
  int max;
  int initial;
  int maxAttemptsCount;
  int maxAttemptsTime;
  double randomness;

  BackoffRetrierConfig clone({
    int min,
    int max,
    int initial,
    int maxAttemptsCount,
    int maxAttemptsTime,
    double randomness,
  }) =>
      BackoffRetrierConfig(
          maxAttemptsCount: maxAttemptsCount ?? this.maxAttemptsCount,
          maxAttemptsTime: maxAttemptsTime ?? this.maxAttemptsTime,
          min: min ?? this.min,
          max: max ?? this.max,
          randomness: randomness ?? this.randomness,
          initial: initial ?? this.initial);

  Map<String, dynamic> get toMap => {
        'min': min,
        'max': max,
        'initial': initial,
        'maxAttemptsCount': maxAttemptsCount,
        'maxAttemptsTime': maxAttemptsTime,
        'randomness': randomness
      };
}
