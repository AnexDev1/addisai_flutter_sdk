import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:addis_ai_sdk/addis_ai_sdk.dart';

Future<void> main() async {
  final key = Platform.environment['ADDIS_API_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('Set ADDIS_API_KEY to run live smoke tests.');
    exitCode = 64;
    return;
  }

  final client = AddisAI(apiKey: key, maxRetries: 1);
  final completed = <String>[];
  try {
    final chat = await client.chat.completions.create(
      const ChatCompletionCreateParams(
        messages: [
          ChatCompletionMessage(
            role: ChatRole.user,
            content: 'Reply with only the Amharic word for hello.',
          ),
        ],
        language: Language.am,
        temperature: 0.1,
        topP: 0.8,
        topK: 20,
        maxTokens: 20,
      ),
    );
    _require(chat.message.content?.isNotEmpty == true, 'empty chat response');
    completed.add('chat');

    final chunks = await client.chat.completions
        .createStream(
          const ChatCompletionCreateParams(
            messages: [
              ChatCompletionMessage(
                role: ChatRole.user,
                content: 'Say hello in one short sentence.',
              ),
            ],
            maxTokens: 30,
          ),
        )
        .toList();
    _require(chunks.any((chunk) => chunk.content.isNotEmpty), 'empty stream');
    completed.add('chat-stream');

    final toolResult = await client.chat.runTools(
      const ChatCompletionCreateParams(
        toolChoice: 'required',
        messages: [
          ChatCompletionMessage(
            role: ChatRole.user,
            content:
                'Use get_test_status once, then report the returned status.',
          ),
        ],
      ),
      tools: [
        RunnableTool(
          function: const ToolFunction(
            name: 'get_test_status',
            description: 'Returns the live SDK test status.',
            parameters: {
              'type': 'object',
              'properties': <String, Object?>{},
              'additionalProperties': false,
            },
          ),
          handler: (_) async => {'status': 'working'},
        ),
      ],
    );
    if (toolResult.message.content?.isNotEmpty == true) {
      completed.add('tools');
    } else {
      completed.add('tools-backend-unavailable');
    }

    final image = AddisFile(
      bytes: base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=',
      ),
      filename: 'pixel.png',
      contentType: 'image/png',
    );
    final multimodal = await client.chat.completions.create(
      ChatCompletionCreateParams(
        messages: const [
          ChatCompletionMessage(
            role: ChatRole.user,
            content: 'Briefly describe this image.',
          ),
        ],
        attachments: [ChatAttachment(file: image)],
      ),
    );
    _require(
      multimodal.message.content?.isNotEmpty == true,
      'empty multimodal response',
    );
    _require(
      multimodal.uploadedAttachments.isNotEmpty,
      'missing uploaded attachment metadata',
    );
    completed.add('multimodal-upload');

    final reused = multimodal.uploadedAttachments.first;
    final followUp = await client.chat.completions.create(
      ChatCompletionCreateParams(
        messages: [
          ChatCompletionMessage(
            role: ChatRole.user,
            parts: [
              ChatMessagePart.file(reused),
              const ChatMessagePart.text('What color is this image?'),
            ],
          ),
          ChatCompletionMessage(
            role: ChatRole.assistant,
            content: multimodal.message.content,
          ),
          const ChatCompletionMessage(
            role: ChatRole.user,
            content: 'Answer in one word.',
          ),
        ],
      ),
    );
    _require(
      followUp.message.content?.isNotEmpty == true,
      'empty reused-attachment response',
    );
    completed.add('multimodal-reuse');

    final translation = await client.translate.create(
      text: 'ሰላም',
      from: TranslateLanguage.am,
      to: TranslateLanguage.en,
    );
    _require(translation.text.isNotEmpty, 'empty translation');
    completed.add('translation');

    final voices = await client.voices.list(language: Language.am);
    _require(voices.isNotEmpty, 'empty voice catalog');
    completed.add('voices');

    await client.voices.preview(voices.first.id);
    completed.add('voice-preview');

    await client.voice.usage();
    completed.add('voice-usage');

    final voiceParams = VoiceGenerateParams(
      voiceId: voices.first.id,
      text: 'ሰላም',
      language: Language.am,
      clientRequestId: 'addisai-flutter-live-smoke-v1',
    );
    await client.voice.estimate(voiceParams);
    completed.add('voice-estimate');

    final clip = await client.voice.generate(voiceParams);
    _require(clip.id.isNotEmpty && clip.audioUrl.isNotEmpty, 'invalid clip');
    completed.add('voice-generate');

    final audio = await client.voice.clips.download(clip.id);
    _require(audio.isNotEmpty, 'empty clip download');
    completed.add('clip-download');

    final fetched = await client.voice.clips.get(clip.id);
    _require(fetched.id == clip.id, 'clip lookup mismatch');
    completed.add('clip-get');

    final clips = await client.voice.clips.list(limit: 5);
    _require(clips.any((item) => item.id == clip.id), 'clip missing from list');
    completed.add('clip-list');

    final transcription = await client.speech.transcribe(
      audio: AddisFile(
        bytes: Uint8List.fromList(audio),
        filename: clip.downloadName.isEmpty ? 'speech.mp3' : clip.downloadName,
        contentType: clip.mimeType.isEmpty ? 'audio/mpeg' : clip.mimeType,
      ),
      language: SttLanguage.am,
    );
    _require(transcription.text.isNotEmpty, 'empty transcription');
    completed.add('speech');

    final legacy = await client.textToSpeech(
      const TtsRequest(text: 'ሰላም', language: Language.am),
    );
    _require(legacy.audioBase64.isNotEmpty, 'empty legacy audio');
    completed.add('legacy-tts');

    final realtime = await client
        .createRealtimeSession()
        .timeout(const Duration(seconds: 20));
    await realtime.ready.timeout(const Duration(seconds: 20));
    await realtime.close();
    completed.add('realtime');

    stdout.writeln('Live smoke tests passed: ${completed.join(', ')}');
  } on Object catch (error, stackTrace) {
    stderr.writeln('Live smoke test failed after: ${completed.join(', ')}');
    stderr.writeln(error);
    stderr.writeln(stackTrace);
    exitCode = 1;
  } finally {
    client.close();
  }
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
