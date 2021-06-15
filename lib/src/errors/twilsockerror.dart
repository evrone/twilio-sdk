class TwilsockError implements Error {
  TwilsockError([this.description]);

  final dynamic description;

  @override
  String toString() {
    Object description = this.description;
    if (description == null) return 'Exception';
    return 'Exception: $description';
  }

  @override
  StackTrace get stackTrace => null;
}
