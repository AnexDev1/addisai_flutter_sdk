import 'constants.dart';

// ---------------------------------------------------------------------------
// Chat Generation Models
// ---------------------------------------------------------------------------

/// Configuration for text generation behavior.
class GenerationConfig {
  /// Controls randomness of the output (0.0 – 1.0).
  final double temperature;

  /// Whether to use streaming responses.
  final bool stream;

  /// Maximum number of tokens in the generated response.
  final int? maxOutputTokens;

  const GenerationConfig({
    this.temperature = 0.7,
    this.stream = false,
    this.maxOutputTokens,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'temperature': temperature,
      'stream': stream,
    };
    if (maxOutputTokens != null) {
      map['maxOutputTokens'] = maxOutputTokens;
    }
    return map;
  }
}

/// A single message in a conversation history.
class ChatMessage {
  /// The role of the message author (`"user"` or `"assistant"`).
  final String role;

  /// The text content of the message.
  final String content;

  const ChatMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      role: json['role'] as String,
      content: json['content'] as String,
    );
  }
}

/// Request body for the `/chat_generate` endpoint.
class ChatRequest {
  /// The user's text prompt.
  final String? prompt;

  /// Target language for the response.
  final Language targetLanguage;

  /// Optional previous messages for multi-turn conversations.
  final List<ChatMessage>? conversationHistory;

  /// Optional generation configuration.
  final GenerationConfig? generationConfig;

  /// Field names of attached files (used with multipart requests).
  final List<String>? attachmentFieldNames;

  const ChatRequest({
    this.prompt,
    required this.targetLanguage,
    this.conversationHistory,
    this.generationConfig,
    this.attachmentFieldNames,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'target_language': targetLanguage.value,
    };
    if (prompt != null) {
      map['prompt'] = prompt;
    }
    if (conversationHistory != null && conversationHistory!.isNotEmpty) {
      map['conversation_history'] =
          conversationHistory!.map((m) => m.toJson()).toList();
    }
    if (generationConfig != null) {
      map['generation_config'] = generationConfig!.toJson();
    }
    if (attachmentFieldNames != null && attachmentFieldNames!.isNotEmpty) {
      map['attachment_field_names'] = attachmentFieldNames;
    }
    return map;
  }
}

// ---------------------------------------------------------------------------
// Chat Response Models
// ---------------------------------------------------------------------------

/// Token usage statistics returned by the API.
class UsageMetadata {
  final int promptTokenCount;
  final int candidatesTokenCount;
  final int totalTokenCount;

  const UsageMetadata({
    required this.promptTokenCount,
    required this.candidatesTokenCount,
    required this.totalTokenCount,
  });

  factory UsageMetadata.fromJson(Map<String, dynamic> json) {
    return UsageMetadata(
      promptTokenCount: json['prompt_token_count'] as int? ?? 0,
      candidatesTokenCount: json['candidates_token_count'] as int? ?? 0,
      totalTokenCount: json['total_token_count'] as int? ?? 0,
    );
  }
}

/// An uploaded attachment returned by the API.
class Attachment {
  final String uri;
  final String mimeType;

  const Attachment({required this.uri, required this.mimeType});

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      uri: json['uri'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? '',
    );
  }
}

/// Response from the `/chat_generate` endpoint.
class ChatResponse {
  /// The generated text.
  final String responseText;

  /// Reason why the model stopped generating (e.g. `"stop"`).
  final String? finishReason;

  /// Token usage statistics.
  final UsageMetadata? usageMetadata;

  /// Version of the model that generated the response.
  final String? modelVersion;

  /// List of attachments that were uploaded with the request.
  final List<Attachment> uploadedAttachments;

  /// Raw transcription of audio input (may include analysis tags).
  final String? transcriptionRaw;

  /// Clean transcription of audio input.
  final String? transcriptionClean;

  /// Whether this is the last chunk in a streaming response.
  final bool? isLastChunk;

  const ChatResponse({
    required this.responseText,
    this.finishReason,
    this.usageMetadata,
    this.modelVersion,
    this.uploadedAttachments = const [],
    this.transcriptionRaw,
    this.transcriptionClean,
    this.isLastChunk,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      responseText: json['response_text'] as String? ?? '',
      finishReason: json['finish_reason'] as String?,
      usageMetadata: json['usage_metadata'] != null
          ? UsageMetadata.fromJson(
              json['usage_metadata'] as Map<String, dynamic>)
          : null,
      modelVersion: json['modelVersion'] as String?,
      uploadedAttachments: (json['uploaded_attachments'] as List<dynamic>?)
              ?.map((a) => Attachment.fromJson(a as Map<String, dynamic>))
              .toList() ??
          const [],
      transcriptionRaw: json['transcription_raw'] as String?,
      transcriptionClean: json['transcription_clean'] as String?,
      isLastChunk: json['is_last_chunk'] as bool?,
    );
  }
}

// ---------------------------------------------------------------------------
// Text-to-Speech Models
// ---------------------------------------------------------------------------

/// Request body for the `/audio` endpoint.
class TtsRequest {
  /// The text to convert to speech.
  final String text;

  /// Target language for the speech.
  final Language language;

  /// Whether to use streaming responses.
  final bool stream;

  const TtsRequest({
    required this.text,
    required this.language,
    this.stream = false,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'language': language.value,
        'stream': stream,
      };
}

/// Non-streaming response from the `/audio` endpoint.
class TtsResponse {
  /// Base64-encoded audio data (may include data URI prefix).
  final String audioBase64;

  const TtsResponse({required this.audioBase64});

  factory TtsResponse.fromJson(Map<String, dynamic> json) {
    return TtsResponse(audioBase64: json['audio'] as String? ?? '');
  }
}

// ---------------------------------------------------------------------------
// Realtime WebSocket Models
// ---------------------------------------------------------------------------

/// Base class for messages received from the Realtime API.
abstract class RealtimeMessage {
  const RealtimeMessage();

  /// Parse the JSON payload from the WebSocket and return a typed message.
  factory RealtimeMessage.fromJson(Map<String, dynamic> json) {
    if (json.containsKey('type') && json['type'] == 'status') {
      return RealtimeStatusMessage(message: json['message'] as String);
    }
    if (json.containsKey('type') && json['type'] == 'warning') {
      return RealtimeWarningMessage(message: json['message'] as String);
    }
    if (json.containsKey('serverContent')) {
      return RealtimeAudioResponse.fromJson(json);
    }
    if (json.containsKey('error')) {
      final err = json['error'] as Map<String, dynamic>;
      return RealtimeErrorMessage(
        message: err['message'] as String? ?? 'Unknown error',
        status: err['status'] as int?,
        timestamp: err['timestamp'] as String?,
      );
    }
    return const RealtimeUnknownMessage();
  }
}

/// A status or informational message from the server (e.g., "Ready to start").
class RealtimeStatusMessage extends RealtimeMessage {
  final String message;
  const RealtimeStatusMessage({required this.message});
}

/// A warning message from the server (e.g., "wallet balance is low").
class RealtimeWarningMessage extends RealtimeMessage {
  final String message;
  const RealtimeWarningMessage({required this.message});
}

/// An error message from the server.
class RealtimeErrorMessage extends RealtimeMessage {
  final String message;
  final int? status;
  final String? timestamp;

  const RealtimeErrorMessage({
    required this.message,
    this.status,
    this.timestamp,
  });
}

/// An unrecognized message type from the server.
class RealtimeUnknownMessage extends RealtimeMessage {
  const RealtimeUnknownMessage();
}

/// A chunk of audio or turn-complete signal from the server.
class RealtimeAudioResponse extends RealtimeMessage {
  /// Base64-encoded PCM audio response data from the AI.
  final String? audioBase64;

  /// True if the AI has completely finished generating the response for this turn.
  final bool isTurnComplete;

  /// Total billed audio duration for the turn, if available.
  final double? totalBilledSeconds;

  const RealtimeAudioResponse({
    this.audioBase64,
    this.isTurnComplete = false,
    this.totalBilledSeconds,
  });

  factory RealtimeAudioResponse.fromJson(Map<String, dynamic> json) {
    final serverContent = json['serverContent'] as Map<String, dynamic>?;
    final usageMetadata = json['usageMetadata'] as Map<String, dynamic>?;

    String? audio;
    bool turnComplete = false;

    if (serverContent != null) {
      if (serverContent['turnComplete'] == true) {
        turnComplete = true;
      }
      
      final modelTurn = serverContent['modelTurn'] as Map<String, dynamic>?;
      if (modelTurn != null && modelTurn['parts'] is List) {
        final parts = modelTurn['parts'] as List;
        if (parts.isNotEmpty) {
          final inlineData = parts.first['inlineData'] as Map<String, dynamic>?;
          if (inlineData != null) {
            audio = inlineData['data'] as String?;
          }
        }
      }
    }

    double? billedSeconds;
    if (usageMetadata != null && usageMetadata['totalBilledAudioDurationSeconds'] != null) {
      billedSeconds = (usageMetadata['totalBilledAudioDurationSeconds'] as num).toDouble();
    }

    return RealtimeAudioResponse(
      audioBase64: audio,
      isTurnComplete: turnComplete,
      totalBilledSeconds: billedSeconds,
    );
  }
}
