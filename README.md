# Addis AI SDK for Flutter and Dart

[![pub package](https://img.shields.io/pub/v/addis_ai_sdk.svg)](https://pub.dev/packages/addis_ai_sdk)
[![pub points](https://img.shields.io/pub/points/addis_ai_sdk)](https://pub.dev/packages/addis_ai_sdk/score)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GitHub](https://img.shields.io/badge/source-GitHub-181717.svg)](https://github.com/AnexDev1/addisai_flutter_sdk)

A production-focused, community-maintained Flutter and Dart client for the
[Addis AI](https://addisassistant.com) platform. Build applications with
Amharic and Afan Oromo chat, streaming, multimodal understanding, durable
voice generation, transcription, translation, and realtime voice.

> This is an independent open-source project. It is not the official SDK
> published by Addis AI.

## Features

| Capability | SDK API |
| --- | --- |
| Chat and multi-turn context | `addis.chat.completions.create()` |
| Incremental SSE responses | `addis.chat.completions.createStream()` |
| System prompts and personas | `ChatCompletionCreateParams` |
| Images, documents, and audio | `ChatAttachment` and `AddisFile` |
| Reusable uploaded files | `UploadedAttachment` |
| Function calling | `addis.chat.runTools()` |
| Durable voice generation | `addis.voice.generate()` |
| Voice catalog and previews | `addis.voices` |
| Cost estimates and wallet usage | `addis.voice.estimate()` / `usage()` |
| Clip management | `addis.voice.clips` |
| Speech-to-text | `addis.speech.transcribe()` |
| Translation | `addis.translate.create()` |
| Realtime PCM voice | `addis.createRealtimeSession()` |

The package supports Android, iOS, macOS, Windows, and Linux.

## Installation

Run:

```sh
flutter pub add addis_ai_sdk
```

Or add the current release to `pubspec.yaml`:

```yaml
dependencies:
  addis_ai_sdk: ^0.2.1
```

Then import the public library:

```dart
import 'package:addis_ai_sdk/addis_ai_sdk.dart';
```

## Authentication

Create a key in the [Addis AI Platform](https://platform.addisassistant.com).
For local development, pass it using `--dart-define`:

```sh
flutter run --dart-define=ADDIS_API_KEY=sk_your_key
```

```dart
const apiKey = String.fromEnvironment('ADDIS_API_KEY');
final addis = AddisAI(apiKey: apiKey);
```

API keys are secrets. A compiled Flutter application cannot safely hide a
privileged key. Production consumer apps should call Addis AI through their
own authenticated backend or use a restricted, short-lived token.

The client accepts an API key or Supabase-style JWT. It also supports a custom
base URL, HTTP client, timeout, retry count, headers, and query parameters:

```dart
final addis = AddisAI(
  apiKey: apiKey,
  timeout: const Duration(seconds: 60),
  maxRetries: 3,
);
```

Transient failures use jittered exponential backoff. Voice-generation retries
reuse an idempotency key to avoid duplicate billing.

## Chat

```dart
final completion = await addis.chat.completions.create(
  const ChatCompletionCreateParams(
    messages: [
      ChatCompletionMessage(
        role: ChatRole.user,
        content: 'የአድዋ ጦርነትን በአጭሩ ግለጽ።',
      ),
    ],
    language: Language.am,
    system: 'Answer clearly and concisely.',
    persona: 'A thoughtful Ethiopian history teacher.',
    temperature: 0.3,
    maxTokens: 500,
  ),
);

print(completion.message.content);
```

### Streaming

```dart
await for (final chunk in addis.chat.completions.createStream(
  const ChatCompletionCreateParams(
    messages: [
      ChatCompletionMessage(
        role: ChatRole.user,
        content: 'Write a short greeting in Afan Oromo.',
      ),
    ],
    language: Language.om,
  ),
)) {
  print(chunk.content);
}
```

### Multimodal input

```dart
final completion = await addis.chat.completions.create(
  ChatCompletionCreateParams(
    messages: const [
      ChatCompletionMessage(
        role: ChatRole.user,
        content: 'Extract the text visible in this image.',
      ),
    ],
    attachments: [
      ChatAttachment(
        file: AddisFile(
          bytes: imageBytes,
          filename: 'document.png',
          contentType: 'image/png',
        ),
      ),
    ],
  ),
);

final uploaded = completion.uploadedAttachments.first;
```

Reuse `uploaded` in later turns with `ChatMessagePart.file(uploaded)` instead
of uploading the same file again.

## Voice

```dart
final voices = await addis.voices.list(language: Language.am);

final estimate = await addis.voice.estimate(
  VoiceGenerateParams(
    voiceId: voices.first.id,
    text: 'ሰላም ዓለም',
    language: Language.am,
  ),
);

final clip = await addis.voice.generate(
  VoiceGenerateParams(
    voiceId: voices.first.id,
    text: 'ሰላም ዓለም',
    language: Language.am,
    outputFormat: OutputFormat.mp3_44100,
  ),
);

print(clip.audioUrl);
```

Use `addis.voice.clips` to list, retrieve, download, or delete generated clips.
The legacy `/audio` methods remain available for migration.

## Speech-to-text and translation

```dart
final transcription = await addis.speech.transcribe(
  audio: AddisFile(
    bytes: wavBytes,
    filename: 'speech.wav',
    contentType: 'audio/wav',
  ),
  language: SttLanguage.am,
);

final translation = await addis.translate.create(
  text: transcription.text,
  from: TranslateLanguage.am,
  to: TranslateLanguage.en,
);

print(translation.text);
```

## Realtime voice

```dart
final session = await addis.createRealtimeSession();
await session.ready;

session.messages.listen((message) {
  if (message is RealtimeAudioResponse && message.audioBase64 != null) {
    // Decode and play 16 kHz, 16-bit, mono PCM audio.
  }
});

session.sendAudio(pcm16Bytes);
await session.close();
```

## Error handling

Every SDK failure extends `AddisAIException`. HTTP failures expose the status,
machine-readable code, details, request ID, and headers.

```dart
try {
  await addis.translate.create(
    text: 'ሰላም',
    from: TranslateLanguage.am,
    to: TranslateLanguage.en,
  );
} on AuthenticationException catch (error) {
  print('Authentication failed: ${error.message}');
} on RateLimitException catch (error) {
  print('Retry after: ${error.retryAfter}');
} on AddisAIException catch (error) {
  print(error.message);
} finally {
  addis.close();
}
```

## Compatibility

Version 0.2 keeps the original `generateChat`, `generateChatStream`,
`textToSpeech`, `streamTextToSpeech`, attachment, and realtime methods as a
migration bridge. New integrations should prefer the resource APIs shown
above.

## Links

- [Addis AI documentation](https://docs.addisassistant.com/docs/get-started/introduction)
- [API key dashboard](https://platform.addisassistant.com)
- [API reference](https://pub.dev/documentation/addis_ai_sdk/latest/)
- [Changelog](CHANGELOG.md)
- [Issue tracker](https://github.com/AnexDev1/addisai_flutter_sdk/issues)
- [Contributing guide](CONTRIBUTING.md)

## License

MIT. See [LICENSE](LICENSE).
