import 'twilsockerror.dart';

class TwilsockUpstreamError extends TwilsockError {
  TwilsockUpstreamError(this.status, this.description, this.body)
      : super(description);

  final int status;
  @override
  final String description;
  final body;
}
