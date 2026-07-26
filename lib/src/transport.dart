import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'exceptions.dart';

class AddisRequestOptions {
  final Duration? timeout;
  final int? maxRetries;
  final String? idempotencyKey;
  final Map<String, String> headers;
  final Map<String, Object?> query;

  const AddisRequestOptions({
    this.timeout,
    this.maxRetries,
    this.idempotencyKey,
    this.headers = const {},
    this.query = const {},
  });
}

class AddisTransport {
  final String apiKey;
  final String baseUrl;
  final Duration timeout;
  final int maxRetries;
  final Map<String, String> defaultHeaders;
  final Map<String, String> defaultQuery;
  final http.Client client;
  final Random _random = Random.secure();

  AddisTransport({
    required this.apiKey,
    required this.baseUrl,
    required this.timeout,
    required this.maxRetries,
    required this.defaultHeaders,
    required this.defaultQuery,
    required this.client,
  });

  Map<String, String> headers(AddisRequestOptions options, {bool json = true}) {
    final auth = _looksLikeJwt(apiKey)
        ? {'Authorization': 'Bearer $apiKey'}
        : {'x-api-key': apiKey};
    return {
      'Accept': 'application/json',
      'X-Addis-Client': 'addisai-dart/0.2.0',
      ...auth,
      ...defaultHeaders,
      ...options.headers,
      if (options.idempotencyKey != null)
        'Idempotency-Key': options.idempotencyKey!,
      if (json) 'Content-Type': 'application/json',
    };
  }

  Uri uri(
    String path,
    AddisRequestOptions options, [
    Map<String, Object?> query = const {},
  ]) {
    final values = <String, String>{
      ...defaultQuery,
      for (final entry in {...query, ...options.query}.entries)
        if (entry.value != null) entry.key: '${entry.value}',
    };
    return Uri.parse('$baseUrl$path')
        .replace(queryParameters: values.isEmpty ? null : values);
  }

  Future<http.Response> request(
    String method,
    String path, {
    Object? body,
    Map<String, Object?> query = const {},
    AddisRequestOptions options = const AddisRequestOptions(),
    Duration? timeoutFloor,
  }) async {
    final retries = options.maxRetries ?? maxRetries;
    var effectiveTimeout = options.timeout ?? timeout;
    if (timeoutFloor != null &&
        options.timeout == null &&
        effectiveTimeout < timeoutFloor) {
      effectiveTimeout = timeoutFloor;
    }
    Object? lastError;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        final request = http.Request(method, uri(path, options, query))
          ..headers.addAll(headers(options))
          ..body = body == null ? '' : jsonEncode(body);
        final streamed = await client.send(request).timeout(effectiveTimeout);
        final response = await http.Response.fromStream(streamed);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
        if (attempt < retries && _retryable(response)) {
          await Future<void>.delayed(_retryDelay(attempt, response.headers));
          continue;
        }
        throw AddisAIException.fromHttpResponse(response);
      } on TimeoutException catch (error) {
        lastError = APIConnectionTimeoutException(
          message:
              'Request timed out after ${effectiveTimeout.inMilliseconds}ms.',
          cause: error,
        );
      } on http.ClientException catch (error) {
        lastError = APIConnectionException(
          message: 'Connection error.',
          cause: error,
        );
      }
      if (attempt < retries) {
        await Future<void>.delayed(_retryDelay(attempt, const {}));
      }
    }
    throw lastError ??
        const APIConnectionException(message: 'Connection error.');
  }

  dynamic decode(http.Response response) {
    if (response.bodyBytes.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
    return decoded;
  }

  bool _retryable(http.Response response) =>
      response.statusCode == 408 ||
      response.statusCode == 425 ||
      response.statusCode == 429 ||
      (response.statusCode == 409 &&
          response.headers.containsKey('retry-after')) ||
      response.statusCode >= 500;

  Duration _retryDelay(int attempt, Map<String, String> headers) {
    final retryAfter = double.tryParse(headers['retry-after'] ?? '');
    if (retryAfter != null) {
      return Duration(milliseconds: min(retryAfter * 1000, 60000).round());
    }
    final base = min(500 * pow(2, attempt), 8000).toDouble();
    return Duration(
      milliseconds: (base * (0.5 + _random.nextDouble() / 2)).round(),
    );
  }

  bool _looksLikeJwt(String key) =>
      key.startsWith('ey') && key.split('.').length == 3;
}
