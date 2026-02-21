/// Base exception for all Addis AI API errors.
class AddisAIException implements Exception {
  /// HTTP status code (if available).
  final int? statusCode;

  /// Machine-readable error code from the API (e.g. `UNAUTHORIZED`).
  final String? code;

  /// Human-readable error message.
  final String message;

  const AddisAIException({
    this.statusCode,
    this.code,
    required this.message,
  });

  @override
  String toString() =>
      'AddisAIException(statusCode: $statusCode, code: $code, message: $message)';

  /// Parse the standard API error JSON envelope and return a typed exception.
  ///
  /// Expected format:
  /// ```json
  /// { "status": "error", "error": { "code": "...", "message": "..." } }
  /// ```
  factory AddisAIException.fromResponse(
      int statusCode, Map<String, dynamic> body) {
    final error = body['error'] as Map<String, dynamic>?;
    final code = error?['code'] as String?;
    final message =
        error?['message'] as String? ?? body['message'] as String? ?? 'Unknown error';

    if (statusCode == 401 || statusCode == 403) {
      return AuthenticationException(
          statusCode: statusCode, code: code, message: message);
    }
    if (statusCode == 422 || statusCode == 400) {
      return ValidationException(
          statusCode: statusCode, code: code, message: message);
    }
    if (statusCode == 429) {
      return RateLimitException(
          statusCode: statusCode, code: code, message: message);
    }
    if (statusCode >= 500) {
      return ServerException(
          statusCode: statusCode, code: code, message: message);
    }
    return AddisAIException(
        statusCode: statusCode, code: code, message: message);
  }
}

/// Thrown when the API key is missing or invalid (HTTP 401/403).
class AuthenticationException extends AddisAIException {
  const AuthenticationException({
    super.statusCode,
    super.code,
    required super.message,
  });
}

/// Thrown when input validation fails (HTTP 400/422).
class ValidationException extends AddisAIException {
  const ValidationException({
    super.statusCode,
    super.code,
    required super.message,
  });
}

/// Thrown when the rate limit is exceeded (HTTP 429).
class RateLimitException extends AddisAIException {
  const RateLimitException({
    super.statusCode,
    super.code,
    required super.message,
  });
}

/// Thrown for server-side errors (HTTP 5xx).
class ServerException extends AddisAIException {
  const ServerException({
    super.statusCode,
    super.code,
    required super.message,
  });
}
