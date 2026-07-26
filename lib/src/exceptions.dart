import 'dart:convert';

import 'package:http/http.dart' as http;

class ErrorDetail {
  final String? field;
  final String? code;
  final String? message;
  const ErrorDetail({this.field, this.code, this.message});

  factory ErrorDetail.fromJson(Map<String, dynamic> json) => ErrorDetail(
        field: json['field'] as String?,
        code: json['code'] as String?,
        message: json['message'] as String?,
      );
}

/// Base exception for configuration, usage, transport, and API failures.
class AddisAIException implements Exception {
  final int? statusCode;
  final String? code;
  final String message;
  final List<ErrorDetail> details;
  final String? requestId;
  final Map<String, String> headers;

  const AddisAIException({
    this.statusCode,
    this.code,
    required this.message,
    this.details = const [],
    this.requestId,
    this.headers = const {},
  });

  factory AddisAIException.fromHttpResponse(http.Response response) {
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      body = null;
    }
    return AddisAIException.fromResponse(
      response.statusCode,
      body is Map<String, dynamic> ? body : const {},
      headers: response.headers,
      rawBody: response.body,
    );
  }

  factory AddisAIException.fromResponse(
    int statusCode,
    Map<String, dynamic> body, {
    Map<String, String> headers = const {},
    String rawBody = '',
  }) {
    final rawError = body['error'];
    final error = rawError is Map
        ? rawError.cast<String, dynamic>()
        : <String, dynamic>{};
    final code = (error['code'] ?? error['type'] ?? body['code']) as String?;
    final message = (error['message'] ?? body['message']) as String? ??
        (rawBody.isNotEmpty
            ? rawBody.substring(0, rawBody.length.clamp(0, 500))
            : 'Request failed with status $statusCode.');
    final details = error['details'] is List
        ? (error['details'] as List)
            .whereType<Map>()
            .map((item) => ErrorDetail.fromJson(item.cast<String, dynamic>()))
            .toList()
        : const <ErrorDetail>[];
    final normalizedHeaders = {
      for (final entry in headers.entries) entry.key.toLowerCase(): entry.value,
    };
    final values = (
      statusCode: statusCode,
      code: code,
      message: message,
      details: details,
      requestId:
          normalizedHeaders['x-request-id'] ?? normalizedHeaders['cf-ray'],
      headers: normalizedHeaders,
    );
    switch (statusCode) {
      case 400:
        return BadRequestException.from(values);
      case 401:
        return AuthenticationException.from(values);
      case 402:
        return InsufficientCreditsException.from(values);
      case 403:
        return PermissionDeniedException.from(values);
      case 404:
        return NotFoundException.from(values);
      case 409:
        if ((code ?? '').toUpperCase() == 'IDEMPOTENCY_CONFLICT') {
          return IdempotencyConflictException.from(values);
        }
        if ((code ?? '').toUpperCase() == 'GENERATION_IN_PROGRESS') {
          return GenerationInProgressException.from(values);
        }
        return ConflictException.from(values);
      case 413:
      case 422:
        return ValidationException.from(values);
      case 429:
        return RateLimitException.from(values);
      default:
        if (statusCode >= 500) return ServerException.from(values);
        return AddisAIException(
          statusCode: statusCode,
          code: code,
          message: message,
          details: details,
          requestId: values.requestId,
          headers: normalizedHeaders,
        );
    }
  }

  @override
  String toString() =>
      '$runtimeType(statusCode: $statusCode, code: $code, message: $message)';
}

typedef ErrorValues = ({
  int statusCode,
  String? code,
  String message,
  List<ErrorDetail> details,
  String? requestId,
  Map<String, String> headers,
});

class NotSupportedException extends AddisAIException {
  const NotSupportedException({required super.message});
}

class APIConnectionException extends AddisAIException {
  final Object? cause;
  const APIConnectionException({required super.message, this.cause});
}

class APIConnectionTimeoutException extends APIConnectionException {
  const APIConnectionTimeoutException({required super.message, super.cause});
}

class APIException extends AddisAIException {
  const APIException({
    required super.statusCode,
    required super.message,
    super.code,
    super.details,
    super.requestId,
    super.headers,
  });
}

mixin _HeaderValues on AddisAIException {
  int? headerInt(String name) =>
      int.tryParse(headers[name.toLowerCase()] ?? '');
}

class BadRequestException extends APIException {
  BadRequestException.from(ErrorValues v)
      : super(
          statusCode: v.statusCode,
          message: v.message,
          code: v.code,
          details: v.details,
          requestId: v.requestId,
          headers: v.headers,
        );
}

class AuthenticationException extends APIException {
  AuthenticationException.from(ErrorValues v)
      : super(
          statusCode: v.statusCode,
          message: v.message,
          code: v.code,
          details: v.details,
          requestId: v.requestId,
          headers: v.headers,
        );
}

class InsufficientCreditsException extends APIException {
  InsufficientCreditsException.from(ErrorValues v)
      : super(
          statusCode: v.statusCode,
          message: v.message,
          code: v.code,
          details: v.details,
          requestId: v.requestId,
          headers: v.headers,
        );

  double? get availableBalance {
    final matches = details
        .where((detail) => detail.code == 'balance_too_low')
        .expand(
          (detail) => RegExp(r'\d+(?:\.\d+)?').allMatches(detail.message ?? ''),
        )
        .toList();
    return matches.isEmpty ? null : double.tryParse(matches.last.group(0)!);
  }
}

class PermissionDeniedException extends AuthenticationException {
  PermissionDeniedException.from(super.v) : super.from();
}

class NotFoundException extends APIException {
  NotFoundException.from(ErrorValues v)
      : super(
          statusCode: v.statusCode,
          message: v.message,
          code: v.code,
          details: v.details,
          requestId: v.requestId,
          headers: v.headers,
        );
}

class ConflictException extends APIException {
  ConflictException.from(ErrorValues v)
      : super(
          statusCode: v.statusCode,
          message: v.message,
          code: v.code,
          details: v.details,
          requestId: v.requestId,
          headers: v.headers,
        );
}

class IdempotencyConflictException extends ConflictException {
  IdempotencyConflictException.from(super.v) : super.from();
}

class GenerationInProgressException extends ConflictException
    with _HeaderValues {
  GenerationInProgressException.from(super.v) : super.from();
  int? get retryAfter => headerInt('retry-after');
}

class ValidationException extends APIException {
  ValidationException.from(ErrorValues v)
      : super(
          statusCode: v.statusCode,
          message: v.message,
          code: v.code,
          details: v.details,
          requestId: v.requestId,
          headers: v.headers,
        );
}

class RateLimitException extends APIException with _HeaderValues {
  RateLimitException.from(ErrorValues v)
      : super(
          statusCode: v.statusCode,
          message: v.message,
          code: v.code,
          details: v.details,
          requestId: v.requestId,
          headers: v.headers,
        );
  int? get retryAfter => headerInt('retry-after');
  int? get limit => headerInt('x-ratelimit-limit');
  int? get remaining => headerInt('x-ratelimit-remaining');
  int? get reset => headerInt('x-ratelimit-reset');
}

class ServerException extends APIException {
  ServerException.from(ErrorValues v)
      : super(
          statusCode: v.statusCode,
          message: v.message,
          code: v.code,
          details: v.details,
          requestId: v.requestId,
          headers: v.headers,
        );
}
