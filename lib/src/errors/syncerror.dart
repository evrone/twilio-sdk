class SyncError extends Error {
  SyncError(String message, {int status = 0, int code = 0})
      : message = '$message (status: $status, code: $code)',
        status = status,
        code = code,
        super();
  static const name = 'SyncError';
  final int code;
  final int status;
  final String message;
}

class SyncNetworkError extends SyncError {
  SyncNetworkError(message, this.body, {int status = 0, int code = 0})
      : super(message, status: status, code: code);

  final body;
}
