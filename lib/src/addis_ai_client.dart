import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import 'constants.dart';
import 'exceptions.dart';
import 'models.dart';
import 'realtime_client.dart';

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

  /// Creates an [AddisAI] client.
  ///
  /// If no [client] is provided, an internal [http.Client] is created and
  /// will be closed when [close] is called.
  AddisAI({required this.apiKey, http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

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

  Map<String, String> get _authHeaders => {
        'X-API-Key': apiKey,
      };

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
    final crlf = '\r\n';
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
          'Content-Disposition: form-data; name="${fieldName}"; filename="${fileName}"$crlf');
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

    // DEBUG LOG
    print('DEBUG SDK REQ: Endpoint: $uri');
    print(
        'DEBUG SDK REQ: Files: ${files.keys.map((k) => '$k (${files[k]?.length ?? 0} bytes)').join(', ')}');
    print('DEBUG SDK REQ: request_data: $requestJsonStr');
    final preview =
        utf8.decode(bodyBytes.take(1024).toList(), allowMalformed: true);
    print('DEBUG SDK REQ BODY PREVIEW:\n$preview\n---');

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

    // 1. Prepare Request JSON
    final requestJson = streamRequest.toJson();
    // no need to stringify for streaming path unless debugging

    // NOTE: Add any file parts here if needed (this streaming path currently
    // does not attach files in examples). Then append `request_data` as the
    // last multipart part with application/json content type.

    final streamedResponse =
        await _client.send(multipart).timeout(const Duration(seconds: 30));

    if (streamedResponse.statusCode != 200) {
      final body = await streamedResponse.stream.bytesToString();
      _throwFromBody(streamedResponse.statusCode, body);
    }

    // Parse the SSE stream. Lines are prefixed with "data: ".
    await for (final line
        in streamedResponse.stream.transform(utf8.decoder).transform(
              const LineSplitter(),
            )) {
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

        print('DEBUG SDK JSON: $json');
        print('DEBUG SDK CHUNK JSON: $json');
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

    await for (final line
        in streamedResponse.stream.transform(utf8.decoder).transform(
              const LineSplitter(),
            )) {
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
    final chatRes = ChatResponse.fromJson(json);
    if (chatRes.uploadedAttachments.isNotEmpty) {
      print(
          'DEBUG SDK RES: Attachments: ${chatRes.uploadedAttachments.length}');
    }
    if (chatRes.transcriptionClean != null) {
      print('DEBUG SDK RES: Transcription: "${chatRes.transcriptionClean}"');
    }
    return chatRes;
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
