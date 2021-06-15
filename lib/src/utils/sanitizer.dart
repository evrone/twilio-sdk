import '../errors/syncerror.dart';

void validateTtl(ttl, optional) {
  if (optional != null && ttl == null) {
    return;
  }
  if (ttl is! int || !isNonNegativeInteger(ttl)) {
    final providedValue = ttl.runtimeType == Object
        ? 'object'
        : '$ttl of type ${ttl.runtimeType}';
    throw SyncError(
        'Invalid TTL, expected a positive integer of type number, was $providedValue',
        status: 400,
        code: 54011);
  }
}

void validateId(id) {
  if (id is! String) {
    throw Exception(
        'Invalid ID type, expected a string, got ${id.runtimeType}');
  }
}

void validateOptionalTtl(ttl) {
  validateTtl(ttl, true);
}

void validateMandatoryTtl(ttl) {
  validateTtl(ttl, false);
}

void validatePageSize(int pageSize) {
  final validPageSize = isPositiveInteger(pageSize);
  if (!validPageSize) {
    throw SyncError(
        'Invalid pageSize parameter. Expected a positive integer, was $pageSize.',
        status: 400,
        code: 20007);
  }
}

void validateMode(mode) {
  if (!['open_or_create', 'open_existing', 'create_new'].contains(mode)) {
    throw Exception(
        "Invalid open mode. Expected one of { 'create_new', 'open_or_create', 'open_existing' }");
  }
}

bool isInteger(number) {
  return int.tryParse(number) is int && number.isFinite;
}

bool isPositiveInteger(number) {
  return isInteger(number) && number > 0;
}

bool isNonNegativeInteger(number) {
  return isInteger(number) && number >= 0;
}
