import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:mime/mime.dart';

import 'constants.dart';
import 'exceptions.dart';
import 'models.dart';
import 'realtime_client.dart';
import 'resources.dart';
import 'transport.dart';

/// Client for the Addis AI API.
///
/// ```dart
/// final client = AddisAI(apiKey: 'YOUR_API_KEY');
///
/// final response = await client.generateChat(
///   ChatRequest(
///     prompt: 'ኢትዮጵያ ዋና ከተማ ማን ናት?',
///     targetLanguage: Language.am,
///   ),
/// );
/// print(response.responseText);
/// ```
class AddisAI {
  /// The API key used for authentication.
  final String apiKey;

  final http.Client _client;
  final bool _ownsClient;

  /// OpenAI-style chat resource (`client.chat.completions.create(...)`).
  late final ChatResource chat;

  /// Current durable voice generation and clip management API.
  late final VoiceResource voice;

  /// Addis AI voice catalog.
  late final VoicesResource voices;

  /// Speech-to-text API.
  late final SpeechResource speech;

  /// Translation API.
  late final TranslateResource translate;

  /// ElevenLabs-style alias for the current voice API.
  late final TextToSpeechResource textToSpeechV2;

  late final AddisTransport _transport;

  /// Creates an [AddisAI] client.
  ///
  /// If no [client] is provided, an internal [http.Client] is created and
  /// will be closed when [close] is called.
  AddisAI({
    required String apiKey,
    http.Client? client,
    String apiBaseUrl = defaultBaseUrl,
    Duration timeout = const Duration(seconds: 60),
    int maxRetries = 3,
    Map<String, String> defaultHeaders = const {},
    Map<String, String> defaultQuery = const {},
  })  : apiKey = _validateApiKey(apiKey),
        _client = client ?? http.Client(),
        _ownsClient = client == null {
    _transport = AddisTransport(
      apiKey: apiKey,
      baseUrl: _validateBaseUrl(apiBaseUrl),
      timeout: timeout,
      maxRetries: maxRetries,
      defaultHeaders: defaultHeaders,
      defaultQuery: defaultQuery,
      client: _client,
    );
    chat = ChatResource(_transport);
    voice = VoiceResource(_transport);
    voices = VoicesResource(_transport);
    speech = SpeechResource(_transport);
    translate = TranslateResource(_transport);
    textToSpeechV2 = TextToSpeechResource(voice);
  }

  // -------------------------------------------------------------------------
  // Realtime API
  // -------------------------------------------------------------------------

  /// Creates a Realtime WebSocket session for streaming PCM audio back and forth.
  Future<AddisAIRealtime> createRealtimeSession() {
    return AddisAIRealtime.connect(apiKey);
  }

  // -------------------------------------------------------------------------
  // Headers
  // -------------------------------------------------------------------------

  Map<String, String> get _jsonHeaders => {
        'X-API-Key': apiKey,
        'Content-Type': 'application/json',
      };

  Map<String, String> get _authHeaders => {'X-API-Key': apiKey};

  // -------------------------------------------------------------------------
  // Chat Generation
  // -------------------------------------------------------------------------

  /// Sends a text-only chat request and returns the full response.
  ///
  /// Throws [AddisAIException] (or a subclass) on API errors.
  Future<ChatResponse> generateChat(ChatRequest request) async {
    final uri = Uri.parse('$baseUrl/chat_generate');
    final body = jsonEncode(request.toJson());

    final response = await _client
        .post(uri, headers: _jsonHeaders, body: body)
        .timeout(const Duration(seconds: 30));

    return _handleChatResponse(response);
  }

  /// Sends a multipart chat request with file attachments.
  ///
  /// [files] is a map of field name → file bytes (e.g. `{'image1': bytes}`).
  /// [fileNames] is an optional map of field name → file name for MIME
  /// detection (e.g. `{'image1': 'photo.jpg'}`).
  ///
  /// The matching field names should be listed in
  /// [ChatRequest.attachmentFieldNames].
  Future<ChatResponse> generateChatWithAttachments(
    ChatRequest request, {
    required Map<String, List<int>> files,
    Map<String, String>? fileNames,
    Map<String, String>? filePaths,
  }) async {
    final uri = Uri.parse('$baseUrl/chat_generate');

    // Prepare JSON metadata
    final requestJson = request.toJson();
    final requestJsonStr = jsonEncode(requestJson); // used below for logging

    // Build multipart body manually so we can control part order/headers exactly.
    final boundary =
        '----dart_form_boundary_${DateTime.now().millisecondsSinceEpoch}';
    const crlf = '\r\n';
    final bodyBytes = <int>[];

    void addString(String s) {
      bodyBytes.addAll(utf8.encode(s));
    }

    // Add file parts first
    for (final entry in files.entries) {
      final fieldName = entry.key;
      final providedBytes = entry.value;
      final fileName = fileNames?[fieldName] ??
          (fieldName == 'chat_audio_input' ? 'audio.wav' : fieldName);
      final filePath = filePaths?[fieldName];

      final isAudio = fieldName == 'chat_audio_input' || fieldName == 'audio';
      final mimeType = isAudio
          ? 'audio/wav'
          : (lookupMimeType(fileName) ?? 'application/octet-stream');

      final bytes =
          filePath != null ? await File(filePath).readAsBytes() : providedBytes;

      addString('--$boundary$crlf');
      addString(
        'Content-Disposition: form-data; name="$fieldName"; filename="$fileName"$crlf',
      );
      addString('Content-Type: $mimeType$crlf$crlf');
      bodyBytes.addAll(bytes);
      addString(crlf);
    }

    // Then append JSON metadata as its own part
    addString('--$boundary$crlf');
    addString('Content-Disposition: form-data; name="request_data"$crlf');
    addString('Content-Type: application/json$crlf$crlf');
    addString(requestJsonStr);
    addString(crlf);

    // Final boundary
    addString('--$boundary--$crlf');

    final httpRequest = http.Request('POST', uri)
      ..headers.addAll(_authHeaders)
      ..headers['Content-Type'] = 'multipart/form-data; boundary=$boundary'
      ..bodyBytes = Uint8List.fromList(bodyBytes);

    final streamedResponse =
        await _client.send(httpRequest).timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamedResponse);
    return _handleChatResponse(response);
  }

  /// Streams chat responses as Server-Sent Events (SSE).
  ///
  /// Each yielded [ChatResponse] represents one chunk. The last chunk
  /// typically has a non-null [ChatResponse.finishReason] or
  /// [ChatResponse.isLastChunk] set to `true`.
  Stream<ChatResponse> generateChatStream(ChatRequest request) async* {
    // Ensure stream is enabled in the generation config.
    final streamRequest = ChatRequest(
      prompt: request.prompt,
      targetLanguage: request.targetLanguage,
      conversationHistory: request.conversationHistory,
      generationConfig: GenerationConfig(
        temperature: request.generationConfig?.temperature ?? 0.7,
        stream: true,
        maxOutputTokens: request.generationConfig?.maxOutputTokens,
      ),
      attachmentFieldNames: request.attachmentFieldNames,
    );

    final uri = Uri.parse('$baseUrl/chat_generate');
    final multipart = http.MultipartRequest('POST', uri)
      ..headers.addAll(_authHeaders);

    multipart.files.add(
      http.MultipartFile.fromString(
        'request_data',
        jsonEncode(streamRequest.toJson()),
        contentType: http_parser.MediaType('application', 'json'),
      ),
    );

    final streamedResponse =
        await _client.send(multipart).timeout(const Duration(seconds: 30));

    if (streamedResponse.statusCode != 200) {
      final body = await streamedResponse.stream.bytesToString();
      _throwFromBody(streamedResponse.statusCode, body);
    }

    // Parse the SSE stream. Lines are prefixed with "data: ".
    await for (final line in streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      String jsonStr;
      if (trimmed.startsWith('data: ')) {
        jsonStr = trimmed.substring(6);
      } else {
        jsonStr = trimmed;
      }

      try {
        var json = jsonDecode(jsonStr) as Map<String, dynamic>;

        // Check for error in the stream chunk.
        if (json.containsKey('error')) {
          final error = json['error'] as Map<String, dynamic>?;
          throw AddisAIException(
            code: error?['code'] as String?,
            message: error?['message'] as String? ?? 'Stream error',
          );
        }

        // Handle the "data" wrapper if present.
        if (json.containsKey('data') && json['data'] is Map<String, dynamic>) {
          json = json['data'] as Map<String, dynamic>;
        }

        yield ChatResponse.fromJson(json);
      } on FormatException {
        // Skip lines that are not valid JSON (e.g. SSE comments).
        continue;
      }
    }
  }

  // -------------------------------------------------------------------------
  // Text-to-Speech
  // -------------------------------------------------------------------------

  /// Converts text to speech and returns the base64-encoded audio.
  Future<TtsResponse> textToSpeech(TtsRequest request) async {
    final uri = Uri.parse('$baseUrl/audio');
    final body = jsonEncode(request.toJson());

    final response = await _client
        .post(uri, headers: _jsonHeaders, body: body)
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      _throwFromBody(response.statusCode, response.body);
    }

    var json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json.containsKey('data') && json['data'] is Map<String, dynamic>) {
      json = json['data'] as Map<String, dynamic>;
    }
    return TtsResponse.fromJson(json);
  }

  /// Streams text-to-speech audio as decoded byte chunks.
  ///
  /// Each yielded `List<int>` is a decoded audio chunk. Concatenate all
  /// chunks to get the complete audio file.
  Stream<List<int>> streamTextToSpeech(TtsRequest request) async* {
    final streamRequest = TtsRequest(
      text: request.text,
      language: request.language,
      stream: true,
    );

    final uri = Uri.parse('$baseUrl/audio');
    final httpRequest = http.Request('POST', uri)
      ..headers.addAll(_jsonHeaders)
      ..body = jsonEncode(streamRequest.toJson());

    final streamedResponse =
        await _client.send(httpRequest).timeout(const Duration(seconds: 30));

    if (streamedResponse.statusCode != 200) {
      final body = await streamedResponse.stream.bytesToString();
      _throwFromBody(streamedResponse.statusCode, body);
    }

    await for (final line in streamedResponse.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      try {
        var json = jsonDecode(trimmed) as Map<String, dynamic>;

        if (json.containsKey('error')) {
          final error = json['error'] as Map<String, dynamic>?;
          throw AddisAIException(
            code: error?['code'] as String?,
            message: error?['message'] as String? ?? 'TTS stream error',
          );
        }

        if (json.containsKey('data') && json['data'] is Map<String, dynamic>) {
          json = json['data'] as Map<String, dynamic>;
        }

        if (json.containsKey('audio_chunk')) {
          final chunk = json['audio_chunk'] as String;
          yield base64Decode(chunk);
        }
      } on FormatException {
        continue;
      }
    }
  }

  // -------------------------------------------------------------------------
  // Lifecycle
  // -------------------------------------------------------------------------

  /// Closes the underlying HTTP client.
  ///
  /// If the client was provided externally, it is **not** closed.
  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  ChatResponse _handleChatResponse(http.Response response) {
    if (response.statusCode != 200) {
      _throwFromBody(response.statusCode, response.body);
    }
    var json = jsonDecode(response.body) as Map<String, dynamic>;
    if (json.containsKey('data') && json['data'] is Map<String, dynamic>) {
      json = json['data'] as Map<String, dynamic>;
    }
    return ChatResponse.fromJson(json);
  }

  Never _throwFromBody(int statusCode, String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      throw AddisAIException.fromResponse(statusCode, json);
    } on FormatException {
      throw AddisAIException(
        statusCode: statusCode,
        message:
            body.isNotEmpty ? body : 'Request failed with status $statusCode',
      );
    }
  }

  /// Parses a MIME type string like `"image/jpeg"` into an [http.MediaType]
  /// compatible object used by [http.MultipartFile].
}

String _validateApiKey(String value) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, 'apiKey', 'must not be empty');
  }
  return value;
}

String _validateBaseUrl(String value) {
  final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(normalized);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw ArgumentError.value(value, 'apiBaseUrl', 'must be a valid URL');
  }
  final local = uri.host == 'localhost' || uri.host == '127.0.0.1';
  if (uri.scheme != 'https' && !local) {
    throw ArgumentError.value(value, 'apiBaseUrl', 'must use HTTPS');
  }
  if (uri.host.endsWith('.supabase.co') || uri.host.endsWith('.supabase.in')) {
    throw ArgumentError.value(
      value,
      'apiBaseUrl',
      'raw Supabase hosts are not supported; use $defaultBaseUrl',
    );
  }
  return normalized;
}
