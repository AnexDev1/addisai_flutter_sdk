# Addis AI Flutter SDK

Community-maintained Flutter and Dart SDK aligned with the official Addis AI
JavaScript and Python SDKs (`addisai` 0.2.0).

It supports OpenAI-style chat, streaming, personas, function calling, durable
voice clips, the voice catalog, speech-to-text, translation, legacy TTS, and
the realtime WebSocket API.

## Install

```yaml
dependencies:
  addis_ai_sdk: ^0.2.0
```

Create API keys at [Addis AI Platform](https://platform.addisassistant.com).
Never commit a key or ship a privileged key in a public client. For production
consumer apps, call Addis AI through your backend or use a suitably restricted
token.

```dart
import 'package:addis_ai_sdk/addis_ai_sdk.dart';

final addis = AddisAI(apiKey: const String.fromEnvironment('ADDIS_API_KEY'));
```

The client accepts `apiBaseUrl`, `timeout`, `maxRetries`, `defaultHeaders`, a
custom `http.Client`, and default query parameters. It sends API keys through
`x-api-key`; Supabase-style JWTs are sent through `Authorization: Bearer`.
Transient failures are retried with jittered exponential backoff.

## Chat

```dart
final completion = await addis.chat.completions.create(
  ChatCompletionCreateParams(
    messages: const [
      ChatCompletionMessage(
        role: ChatRole.user,
        content: 'ሰላም! አዲስ አበባን ግለጽልኝ።',
      ),
    ],
    language: Language.am,
    system: 'Answer concisely.',
    persona: 'A friendly Ethiopian travel guide',
    topP: 0.9,
    topK: 40,
  ),
);

print(completion.message.content);
```

Streaming uses standards-compliant SSE parsing:

```dart
await for (final chunk in addis.chat.completions.createStream(
  const ChatCompletionCreateParams(
    messages: [
      ChatCompletionMessage(role: ChatRole.user, content: 'Write a greeting'),
    ],
  ),
)) {
  print(chunk.content);
}
```

Use `addis.chat.runTools(...)` with `RunnableTool` for automatic local
function-call execution. Attachments and voice commands use `AddisFile`.

Uploaded files are returned as `UploadedAttachment` values. Put them in later
messages with `ChatMessagePart.file(...)` to continue a multimodal conversation
without uploading the same image or document again.

## Voice

The current voice API creates durable clips and uses idempotency keys so a
retry is not billed twice.

```dart
final voices = await addis.voices.list(language: Language.am);
final clip = await addis.voice.generate(
  VoiceGenerateParams(
    voiceId: voices.first.id,
    text: 'ሰላም ዓለም',
    language: Language.am,
    outputFormat: OutputFormat.mp3_44100,
  ),
);

print(clip.audioUrl);
final bytes = await addis.voice.clips.download(clip.id);
```

Also available:

- `addis.voice.estimate(...)` and `addis.voice.usage()`
- `addis.voice.clips.list/get/download/delete`
- `addis.voices.preview(...)`
- `addis.textToSpeechV2.convert(...)` for an ElevenLabs-style migration API

The old `textToSpeech`, `streamTextToSpeech`, `generateChat`, and realtime
methods remain available as a migration bridge.

## Speech and translation

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
```

## Errors and lifecycle

All failures extend `AddisAIException`. HTTP errors are mapped to specific
types including `AuthenticationException`, `InsufficientCreditsException`,
`PermissionDeniedException`, `IdempotencyConflictException`,
`GenerationInProgressException`, `ValidationException`,
`RateLimitException`, and `ServerException`. API errors expose the status,
code, details, request ID, and response headers.

Call `addis.close()` when the client is no longer needed.

For realtime sessions, await `session.ready` before calling `sendAudio`.
Audio frames include the documented `audio/pcm;rate=16000` MIME envelope.

## Development

```sh
flutter pub get
dart format --set-exit-if-changed lib test example/lib
dart analyze lib test
flutter test
dart pub publish --dry-run
```

This project is MIT licensed and is not the official SDK published by Addis AI.
