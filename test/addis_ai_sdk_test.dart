import 'dart:convert';

import 'package:addis_ai_sdk/addis_ai_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Creates a [MockClient] that returns [body] with [statusCode].
  /// Uses UTF-8 encoding to support Amharic/Oromo text.
  http.Client mockClient(String body, {int statusCode = 200}) {
    return MockClient((_) async => http.Response(
      body,
      statusCode,
      headers: {'content-type': 'application/json; charset=utf-8'},
    ));
  }

  /// Standard successful chat response JSON.
  final chatResponseJson = jsonEncode({
    'response_text': 'የኢትዮጵያ ዋና ከተማ አዲስ አበባ ናት።',
    'finish_reason': 'stop',
    'usage_metadata': {
      'prompt_token_count': 10,
      'candidates_token_count': 12,
      'total_token_count': 22,
    },
    'modelVersion': 'Addis-፩-አሌፍ',
    'uploaded_attachments': [],
  });

  /// Standard successful TTS response JSON.
  final ttsResponseJson = jsonEncode({
    'audio': 'dGVzdCBhdWRpbw==', // "test audio" in base64
  });

  // ---------------------------------------------------------------------------
  // Chat Generation Tests
  // ---------------------------------------------------------------------------

  group('generateChat', () {
    test('returns ChatResponse on success', () async {
      final client = AddisAI(
        apiKey: 'test-key',
        client: mockClient(chatResponseJson),
      );

      final response = await client.generateChat(
        ChatRequest(prompt: 'Hello', targetLanguage: Language.am),
      );

      expect(response.responseText, contains('አዲስ አበባ'));
      expect(response.finishReason, 'stop');
      expect(response.usageMetadata?.totalTokenCount, 22);
      expect(response.modelVersion, 'Addis-፩-አሌፍ');
    });

    test('sends correct headers and body', () async {
      late http.Request capturedRequest;
      final client = AddisAI(
        apiKey: 'my-api-key',
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(chatResponseJson, 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );

      await client.generateChat(
        ChatRequest(
          prompt: 'Test',
          targetLanguage: Language.om,
          generationConfig:
              const GenerationConfig(temperature: 0.5, maxOutputTokens: 500),
        ),
      );

      expect(capturedRequest.headers['X-API-Key'], 'my-api-key');
      expect(capturedRequest.headers['Content-Type'], 'application/json');

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body['prompt'], 'Test');
      expect(body['target_language'], 'om');
      expect(body['generation_config']['temperature'], 0.5);
      expect(body['generation_config']['maxOutputTokens'], 500);
    });

    test('includes conversation history when provided', () async {
      late http.Request capturedRequest;
      final client = AddisAI(
        apiKey: 'key',
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(chatResponseJson, 200,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }),
      );

      await client.generateChat(
        ChatRequest(
          prompt: 'Follow-up',
          targetLanguage: Language.am,
          conversationHistory: [
            ChatMessage(role: 'user', content: 'Hello'),
            ChatMessage(role: 'assistant', content: 'Hi there!'),
          ],
        ),
      );

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      final history = body['conversation_history'] as List;
      expect(history.length, 2);
      expect(history[0]['role'], 'user');
      expect(history[1]['role'], 'assistant');
    });
  });

  // ---------------------------------------------------------------------------
  // Text-to-Speech Tests
  // ---------------------------------------------------------------------------

  group('textToSpeech', () {
    test('returns TtsResponse on success', () async {
      final client = AddisAI(
        apiKey: 'key',
        client: mockClient(ttsResponseJson),
      );

      final response = await client.textToSpeech(
        TtsRequest(text: 'ሰላም', language: Language.am),
      );

      expect(response.audioBase64, 'dGVzdCBhdWRpbw==');
      // Verify the base64 decodes correctly.
      expect(utf8.decode(base64Decode(response.audioBase64)), 'test audio');
    });

    test('sends correct request body', () async {
      late http.Request capturedRequest;
      final client = AddisAI(
        apiKey: 'key',
        client: MockClient((request) async {
          capturedRequest = request;
          return http.Response(ttsResponseJson, 200);
        }),
      );

      await client.textToSpeech(
        TtsRequest(text: 'Hello', language: Language.om, stream: false),
      );

      final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(body['text'], 'Hello');
      expect(body['language'], 'om');
      expect(body['stream'], false);
    });
  });

  // ---------------------------------------------------------------------------
  // Error Handling Tests
  // ---------------------------------------------------------------------------

  group('error handling', () {
    test('throws AuthenticationException on 401', () async {
      final client = AddisAI(
        apiKey: 'bad-key',
        client: mockClient(
          jsonEncode({
            'status': 'error',
            'error': {'code': 'UNAUTHORIZED', 'message': 'Invalid API key'},
          }),
          statusCode: 401,
        ),
      );

      expect(
        () => client.generateChat(
          ChatRequest(prompt: 'Hi', targetLanguage: Language.am),
        ),
        throwsA(isA<AuthenticationException>()),
      );
    });

    test('throws AuthenticationException on 403', () async {
      final client = AddisAI(
        apiKey: 'key',
        client: mockClient(
          jsonEncode({
            'status': 'error',
            'error': {'code': 'FORBIDDEN', 'message': 'Access denied'},
          }),
          statusCode: 403,
        ),
      );

      expect(
        () => client.generateChat(
          ChatRequest(prompt: 'Hi', targetLanguage: Language.am),
        ),
        throwsA(isA<AuthenticationException>()),
      );
    });

    test('throws ValidationException on 422', () async {
      final client = AddisAI(
        apiKey: 'key',
        client: mockClient(
          jsonEncode({
            'status': 'error',
            'error': {
              'code': 'UNSUPPORTED_LANGUAGE',
              'message': 'Language not supported',
            },
          }),
          statusCode: 422,
        ),
      );

      expect(
        () => client.generateChat(
          ChatRequest(prompt: 'Hi', targetLanguage: Language.am),
        ),
        throwsA(isA<ValidationException>()),
      );
    });

    test('throws RateLimitException on 429', () async {
      final client = AddisAI(
        apiKey: 'key',
        client: mockClient(
          jsonEncode({
            'status': 'error',
            'error': {
              'code': 'RATE_LIMIT',
              'message': 'Too many requests',
            },
          }),
          statusCode: 429,
        ),
      );

      expect(
        () => client.generateChat(
          ChatRequest(prompt: 'Hi', targetLanguage: Language.am),
        ),
        throwsA(isA<RateLimitException>()),
      );
    });

    test('throws ServerException on 500', () async {
      final client = AddisAI(
        apiKey: 'key',
        client: mockClient(
          jsonEncode({
            'status': 'error',
            'error': {
              'code': 'INTERNAL_ERROR',
              'message': 'Server error',
            },
          }),
          statusCode: 500,
        ),
      );

      expect(
        () => client.textToSpeech(
          TtsRequest(text: 'Hi', language: Language.am),
        ),
        throwsA(isA<ServerException>()),
      );
    });

    test('throws AddisAIException for unknown status codes', () async {
      final client = AddisAI(
        apiKey: 'key',
        client: mockClient(
          jsonEncode({
            'status': 'error',
            'error': {'code': 'UNKNOWN', 'message': 'Something happened'},
          }),
          statusCode: 418,
        ),
      );

      expect(
        () => client.generateChat(
          ChatRequest(prompt: 'Hi', targetLanguage: Language.am),
        ),
        throwsA(isA<AddisAIException>()),
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Model Serialization Tests
  // ---------------------------------------------------------------------------

  group('model serialization', () {
    test('ChatRequest.toJson omits null fields', () {
      final request = ChatRequest(
        prompt: 'Hello',
        targetLanguage: Language.am,
      );
      final json = request.toJson();

      expect(json['prompt'], 'Hello');
      expect(json['target_language'], 'am');
      expect(json.containsKey('conversation_history'), false);
      expect(json.containsKey('generation_config'), false);
      expect(json.containsKey('attachment_field_names'), false);
    });

    test('ChatRequest.toJson includes all fields when set', () {
      final request = ChatRequest(
        prompt: 'Hello',
        targetLanguage: Language.om,
        conversationHistory: [
          ChatMessage(role: 'user', content: 'Hi'),
        ],
        generationConfig: const GenerationConfig(
          temperature: 0.9,
          stream: true,
          maxOutputTokens: 1000,
        ),
        attachmentFieldNames: ['image1'],
      );
      final json = request.toJson();

      expect(json['target_language'], 'om');
      expect(json['conversation_history'], isA<List>());
      expect(json['generation_config']['stream'], true);
      expect(json['generation_config']['maxOutputTokens'], 1000);
      expect(json['attachment_field_names'], ['image1']);
    });

    test('ChatResponse.fromJson parses full response', () {
      final response = ChatResponse.fromJson({
        'response_text': 'Test response',
        'finish_reason': 'stop',
        'usage_metadata': {
          'prompt_token_count': 5,
          'candidates_token_count': 3,
          'total_token_count': 8,
        },
        'modelVersion': 'v1',
        'uploaded_attachments': [
          {'uri': 'gs://bucket/file', 'mimeType': 'image/jpeg'},
        ],
        'transcription_raw': 'raw text',
        'transcription_clean': 'clean text',
      });

      expect(response.responseText, 'Test response');
      expect(response.finishReason, 'stop');
      expect(response.usageMetadata!.promptTokenCount, 5);
      expect(response.uploadedAttachments.length, 1);
      expect(response.uploadedAttachments.first.mimeType, 'image/jpeg');
      expect(response.transcriptionRaw, 'raw text');
      expect(response.transcriptionClean, 'clean text');
    });

    test('TtsRequest.toJson produces correct output', () {
      final request = TtsRequest(
        text: 'ሰላም',
        language: Language.am,
        stream: true,
      );
      final json = request.toJson();

      expect(json['text'], 'ሰላም');
      expect(json['language'], 'am');
      expect(json['stream'], true);
    });
  });

  // ---------------------------------------------------------------------------
  // Streaming Chat Tests
  // ---------------------------------------------------------------------------

  group('generateChatStream', () {
    test('yields ChatResponse chunks from SSE data', () async {
      final chunk1 = jsonEncode({'response_text': 'Hello '});
      final chunk2 = jsonEncode({
        'response_text': 'World!',
        'finish_reason': 'stop',
        'is_last_chunk': true,
      });
      final sseBody = 'data: $chunk1\n\ndata: $chunk2\n\n';

      final client = AddisAI(
        apiKey: 'key',
        client: MockClient((request) async {
          return http.Response(sseBody, 200);
        }),
      );

      final chunks = await client
          .generateChatStream(
            ChatRequest(prompt: 'Hi', targetLanguage: Language.am),
          )
          .toList();

      expect(chunks.length, 2);
      expect(chunks[0].responseText, 'Hello ');
      expect(chunks[1].responseText, 'World!');
      expect(chunks[1].finishReason, 'stop');
    });
  });

  // ---------------------------------------------------------------------------
  // Streaming TTS Tests
  // ---------------------------------------------------------------------------

  group('streamTextToSpeech', () {
    test('yields decoded audio byte chunks', () async {
      final audioData1 = base64Encode(utf8.encode('chunk1'));
      final audioData2 = base64Encode(utf8.encode('chunk2'));
      final body =
          '${jsonEncode({'audio_chunk': audioData1, 'index': 0})}\n'
          '${jsonEncode({'audio_chunk': audioData2, 'index': 1})}\n';

      final client = AddisAI(
        apiKey: 'key',
        client: MockClient((request) async {
          return http.Response(body, 200);
        }),
      );

      final chunks = await client
          .streamTextToSpeech(
            TtsRequest(text: 'Test', language: Language.am),
          )
          .toList();

      expect(chunks.length, 2);
      expect(utf8.decode(chunks[0]), 'chunk1');
      expect(utf8.decode(chunks[1]), 'chunk2');
    });
  });

  // ---------------------------------------------------------------------------
  // Client Lifecycle Tests
  // ---------------------------------------------------------------------------

  group('lifecycle', () {
    test('close does not throw when using default client', () {
      final client = AddisAI(apiKey: 'key');
      expect(() => client.close(), returnsNormally);
    });

    test('close does not close externally provided client', () {
      final httpClient = MockClient((_) async => http.Response('', 200));
      final client = AddisAI(apiKey: 'key', client: httpClient);
      client.close();
      // The external client should still work.
      expect(
        () async =>
            httpClient.get(Uri.parse('https://example.com')),
        returnsNormally,
      );
    });
  });
}
