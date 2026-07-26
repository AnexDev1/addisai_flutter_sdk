import 'dart:convert';
import 'dart:typed_data';

import 'package:addis_ai_sdk/addis_ai_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('OpenAI-style chat maps messages to the native API', () async {
    late http.Request captured;
    final client = AddisAI(
      apiKey: 'test-key',
      maxRetries: 0,
      client: MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'data': {
              'response_text': 'ሰላም',
              'finish_reason': 'STOP',
              'usage_metadata': {
                'prompt_token_count': 2,
                'candidates_token_count': 1,
                'total_token_count': 3,
              },
            },
          })),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await client.chat.completions.create(
      const ChatCompletionCreateParams(
        system: 'Be brief',
        topP: 0.9,
        topK: 20,
        messages: [
          ChatCompletionMessage(role: ChatRole.user, content: 'Earlier'),
          ChatCompletionMessage(role: ChatRole.assistant, content: 'Okay'),
          ChatCompletionMessage(role: ChatRole.user, content: 'Hello'),
        ],
      ),
    );

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(captured.url.path, '/api/v1/chat_generate');
    expect(captured.headers['x-api-key'], 'test-key');
    expect(captured.headers['x-addis-client'], 'addisai-dart/0.2.0');
    expect(body['prompt'], 'Hello');
    expect(body['system'], 'Be brief');
    expect(body['conversation_history'], hasLength(2));
    expect(body['generation_config']['topP'], 0.9);
    expect(body['generation_config']['topK'], 20);
    expect(result.message.content, 'ሰላም');
    expect(result.finishReason, 'stop');
    expect(result.usage?.totalTokens, 3);
    client.close();
  });

  test('JWT authentication never sends x-api-key', () async {
    late http.Request captured;
    final client = AddisAI(
      apiKey: 'eyHeader.payload.signature',
      maxRetries: 0,
      client: MockClient((request) async {
        captured = request;
        return http.Response(
            jsonEncode({
              'data': {'voices': []}
            }),
            200);
      }),
    );

    await client.voices.list();
    expect(
        captured.headers['authorization'], 'Bearer eyHeader.payload.signature');
    expect(captured.headers.containsKey('x-api-key'), isFalse);
  });

  test('voice generation uses current endpoint and idempotency key', () async {
    late http.Request captured;
    final client = AddisAI(
      apiKey: 'key',
      maxRetries: 0,
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': {
              'id': 'clip_1',
              'text': 'hello',
              'voice_id': 'voice_1',
              'voice_name': 'Voice',
              'language': 'am',
              'output_format': 'mp3_44100',
              'audio_url': 'https://example.test/audio.mp3',
              'mime_type': 'audio/mpeg',
              'download_name': 'clip.mp3',
              'created_at': '2026-07-27T00:00:00Z',
            },
          }),
          200,
        );
      }),
    );

    final clip = await client.voice.generate(
      const VoiceGenerateParams(
        voiceId: 'voice_1',
        text: 'hello',
        language: Language.am,
        clientRequestId: 'request_123',
      ),
    );

    expect(captured.url.path, '/api/v1/voice/generations');
    expect(captured.headers['idempotency-key'], 'request_123');
    expect(
        (jsonDecode(captured.body)
            as Map<String, dynamic>)['client_request_id'],
        'request_123');
    expect(clip.id, 'clip_1');
  });

  test('translation maps official response', () async {
    final client = AddisAI(
      apiKey: 'key',
      maxRetries: 0,
      client: MockClient((request) async => http.Response(
            jsonEncode({
              'data': {
                'translation': 'Hello',
                'source_language': 'am',
                'target_language': 'en',
                'quality': 'high',
              },
            }),
            200,
          )),
    );
    final result = await client.translate.create(
      text: 'ሰላም',
      from: TranslateLanguage.am,
      to: TranslateLanguage.en,
    );
    expect(result.text, 'Hello');
    expect(result.quality, 'high');
  });

  test('normalizes idempotency conflict errors', () async {
    final client = AddisAI(
      apiKey: 'key',
      maxRetries: 0,
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'error': {
                'code': 'IDEMPOTENCY_CONFLICT',
                'message': 'Inputs changed',
              },
            }),
            409,
          )),
    );
    expect(
      () => client.voice.usage(),
      throwsA(isA<IdempotencyConflictException>()),
    );
  });

  test('reuses uploaded file URIs in multimodal history', () async {
    late http.Request captured;
    final client = AddisAI(
      apiKey: 'key',
      maxRetries: 0,
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': {'response_text': 'answer'}
          }),
          200,
        );
      }),
    );
    await client.chat.completions.create(
      const ChatCompletionCreateParams(
        messages: [
          ChatCompletionMessage(
            role: ChatRole.user,
            parts: [
              ChatMessagePart.file(
                UploadedAttachment(
                  fileUri: 'files/reusable',
                  mimeType: 'application/pdf',
                ),
              ),
              ChatMessagePart.text('Describe this attachment'),
            ],
          ),
          ChatCompletionMessage(
            role: ChatRole.assistant,
            content: 'Initial description',
          ),
          ChatCompletionMessage(
            role: ChatRole.user,
            content: 'Summarize it',
          ),
        ],
      ),
    );
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    final history = body['conversation_history'] as List;
    expect(
        history.first['parts'].first['fileData']['fileUri'], 'files/reusable');
  });

  test('rejects oversized and unsupported uploads before a request', () async {
    final client = AddisAI(
      apiKey: 'key',
      client: MockClient((_) async => fail('request should not be sent')),
    );
    expect(
      () => client.speech.transcribe(
        audio: AddisFile(
          bytes: Uint8List(1),
          filename: 'audio.txt',
          contentType: 'text/plain',
        ),
        language: SttLanguage.am,
      ),
      throwsArgumentError,
    );
  });
}
