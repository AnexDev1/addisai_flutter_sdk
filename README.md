# Addis AI Flutter SDK

![Pub Version](https://img.shields.io/pub/v/addis_ai_sdk)
![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Flutter](https://img.shields.io/badge/flutter-supported-02569B?logo=flutter)

<!-- display logo asset -->
![Addis AI Logo](apps/addis_assistant/assets/logo_icon.jpg)


A clean, robust, and asynchronous Dart SDK for the [Addis AI REST and Realtime API](https://platform.addisassistant.com/docs). 

Addis AI is purpose-built for Ethiopian languages, providing native-level generation, understanding, and speech synthesis for **Amharic (am)** and **Afan Oromo (om)**.

---

## Features

This SDK is 100% feature-complete with the Addis AI Platform:

* 💬 **Chat Generation**: Single and multi-turn text generation Native Ethiopian Languages.
* 🖼️ **Multimodal Chat**: Attach images/documents via `multipart/form-data` requests.
* 🌊 **Streaming Responses**: Real-time Server-Sent Events (SSE) chat generation.
* 🗣️ **Text-to-Speech (TTS)**: Convert Amharic/Afan Oromo text into natural human voice (Base64 WAV format).
* 📻 **Streaming TTS**: Parse chunked bytes on-the-fly to play audio instantly before the full payload arrives.
* 🎙️ **Realtime WebSockets (Duplex)**: Connect to `wss://relay.addisassistant.com/ws` to stream pure PCM audio natively for voice-to-voice agents.
* 🛡️ **Typed Exception Handling**: Full REST exception mapping (`AuthenticationException`, `RateLimitException`, etc.).
* 📱 **Mobile Ready**: Built-in generic timeouts, isolated JSON parsing handling, and optimized chunk delivery for Flutter apps.

---

## Installation

Add this to your package's `pubspec.yaml` file:

```yaml
dependencies:
  addis_ai_sdk: ^0.1.0
```

Or install from the command line:

```bash
flutter pub add addis_ai_sdk
```

---

## Quick Start
Initialize the SDK using your API key. (Get one at [platform.addisassistant.com](https://platform.addisassistant.com)).

```dart
import 'package:addis_ai_sdk/addis_ai_sdk.dart';

void main() async {
  // 1. Initialize the client
  final client = AddisAI(apiKey: 'YOUR_API_KEY');

  // 2. Make a request
  try {
    final response = await client.generateChat(
      ChatRequest(
        prompt: 'ኢትዮጵያ ውስጥ ያሉ ዋና ዋና ከተሞች እነማን ናቸው?',
        targetLanguage: Language.am,
      ),
    );
    print(response.responseText); 
    // Out: "ዋና ዋና ከተሞቿ አዲስ አበባ፣ ድሬዳዋ፣ አዳማ፣ ባህር ዳር፣ ሀዋሳ እና መቀሌ ናቸው።"

  } catch (e) {
    print('Failed: $e');
  } finally {
    // 3. Dispose HTTP resources when done
    client.close();
  }
}
```

---

## Comprehensive Usage Examples

### 1. Multi-turn Chat with Configs
Easily pass previous context to the model using `conversationHistory`. You can also tweak creativity parameters like `temperature`.

```dart
final response = await client.generateChat(
  ChatRequest(
    prompt: 'ስለነሱ አየር ንብረት አብራራልኝ (Explain their climate)',
    targetLanguage: Language.am,
    conversationHistory: [
      ChatMessage(role: 'user', content: 'ኢትዮጵያ ውስጥ ያሉ ዋና ዋና ከተሞች እነማን ናቸው?'),
      ChatMessage(role: 'assistant', content: 'ዋና ዋና ከተሞቿ አዲስ አበባ፣ ድሬዳዋ፣ አዳማ...'),
    ],
    generationConfig: GenerationConfig(
      temperature: 0.8,
      maxOutputTokens: 2000,
    ),
  ),
);
```

### 2. Streaming Chat (SSE)
Use Dart `Streams` to present typography typing effects to your users natively.

```dart
String fullResponse = '';

await for (final chunk in client.generateChatStream(
  ChatRequest(prompt: 'Tell me a story', targetLanguage: Language.am),
)) {
  // Yields tokens in real time
  print('Received token: ${chunk.responseText}');
  fullResponse += chunk.responseText;
}
```

### 3. Text-to-Speech (TTS)
Generate audio representations of Ethiopian languages. The SDK automatically unwraps the server data payload and returns decoded base64. 

```dart
final ttsResponse = await client.textToSpeech(
  TtsRequest(text: 'ሰላም ጤና ይስጥልኝ', language: Language.am),
);

// Decoded WAV bytes ready to be fed into any Flutter Audio Player or saved:
final audioBytes = base64Decode(ttsResponse.audioBase64);
```

### 4. Multimodal Inputs (Images & Documents)
Upload files natively to the REST API via flutter using `generateChatWithAttachments`.

```dart
import 'dart:io';

final imageBytes = await File('addis_ababa.jpg').readAsBytes();

final response = await client.generateChatWithAttachments(
  ChatRequest(
    prompt: 'Describe what you see in this image',
    targetLanguage: Language.am,
    attachmentFieldNames: ['context_image'], 
  ),
  files: {'context_image': imageBytes}, // Map corresponding field names
  fileNames: {'context_image': 'addis_ababa.jpg'}, // Auto-infers mime_type
);
```

### 5. Realtime Voice-to-Voice (WebSockets)
For interactive native voice agents, use the `createRealtimeSession` WebSocket wrapper. It parses binary Base64 inbound messages and routes them through a single Dart Stream.

```dart
// Connect to wss://relay.addisassistant.com/ws
final realtimeSession = await client.createRealtimeSession();

// Listen to inbound Audio/Status Streams
realtimeSession.messages.listen((message) {
  if (message is RealtimeAudioResponse) {
     if (message.audioBase64 != null) {
       final rawAudioBytes = base64Decode(message.audioBase64!);
       // Use a package like `just_audio` to play 16kHz, 16-bit PCM Mono audio
       print('Received Model Audio Fragment: ${rawAudioBytes.length} bytes');
     }
     if (message.isTurnComplete) print('Bot finished speaking.');
```

---

## Publishing to pub.dev
The SDK is ready to be published. Before you run the real publish command, make sure:

1. **Version bump** – update the `version` field in `pubspec.yaml` (e.g. `0.1.1`).
2. **Bundle size** – run `flutter pub publish --dry-run` from the project root to verify there are no errors.
3. **Documentation & changelog** – update `CHANGELOG.md` with your release notes.
4. **Assets** – only Dart code and necessary files are included; the example folder is ignored by default.
5. **Terms** – you have permission to publish any bundled assets (logo, etc.) under MIT license.

Once ready, publish with:

```bash
# from workspace root
cd addisai_flutter_sdk
flutter pub publish
# or for pure Dart packages: dart pub publish
```

Follow the interactive prompts. The dry run step will flag common mistakes (missing homepage, invalid version, etc.).

After publishing, update the version badge at the top of this README if desired:

```
![Pub Version](https://img.shields.io/pub/v/addis_ai_sdk)
```

Happy publishing!  
(You can also automate via GitHub Actions or another CI workflow.)
  } else if (message is RealtimeStatusMessage) {
     print('Server Status: ${message.message}');
  }
});

// Push 16kHz Mono PCM Audio bytes captured from the mic natively
List<int> pcmData = await captureMicrophone(); 
realtimeSession.sendAudio(pcmData);

await realtimeSession.close();
```

---

## 🛠️ Error Handling & Mobile Considerations

The SDK provides customized Exception handling based on HTTP status codes.

```dart
try {
  final response = await client.generateChat(request);
} on RateLimitException catch (e) {
  print('Too many requests [429]: ${e.message}');
} on AuthenticationException catch (e) {
  print('API Key Rejected [401/403]: ${e.message}');
} on ValidationException catch (e) {
  print('Bad Request [400/422]: ${e.message}'); 
} on AddisAIException catch (e) { // Catch-all generic block
  print('SDK Error: ${e.message}');
}
```

**Mobile Checkpoints**:
1. **Network Interruptions Check**: The SDK enforces `Duration(seconds: 30)` limits natively on standard HTTP calls and `60` seconds on attachment uploads to manage hanging sockets. Ensure you wrap network calls inside `try/catch` and anticipate Dart `TimeoutException` values.
2. **API Keys**: Make sure to NOT embed raw `.env` strings or constants holding the Addis AI API Key directly in your final production app binary to avoid reverse-engineering limits. Use a backend-driven relay.

---

## Example Applicaton
A fully implemented multi-tab UI Flutter App utilizing the full SDK capabilities (Chat, Speech Generation, and WebSockets UI logs) resides inside the `/example` directory of this repository! To test it out, add an API key inside `example/lib/main.dart` and hit `flutter run`!

---

## Contributing
If you'd like to improve the SDK, open a pull request!
Run formatting `dart format .` and tests `flutter test` before submitting.
