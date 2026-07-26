import 'dart:typed_data';

import 'constants.dart';

typedef JsonMap = Map<String, dynamic>;
typedef ToolHandler = Future<Object?> Function(Object? arguments);

enum ChatRole {
  system,
  developer,
  user,
  assistant,
  tool;

  String get value => name;
}

class ToolFunction {
  final String name;
  final String? description;
  final JsonMap? parameters;

  const ToolFunction({required this.name, this.description, this.parameters});

  JsonMap toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (parameters != null) 'parameters': parameters,
      };
}

class FunctionTool {
  final ToolFunction function;
  const FunctionTool({required this.function});
  JsonMap toJson() => {'type': 'function', 'function': function.toJson()};
}

class RunnableTool extends FunctionTool {
  final ToolHandler handler;
  const RunnableTool({required super.function, required this.handler});
}

class ToolCall {
  final String id;
  final String name;
  final String arguments;
  final String? addisToolState;

  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    this.addisToolState,
  });

  factory ToolCall.fromJson(JsonMap json) {
    final function = (json['function'] as Map?)?.cast<String, dynamic>() ?? {};
    return ToolCall(
      id: json['id'] as String? ?? '',
      name: function['name'] as String? ?? '',
      arguments: function['arguments'] as String? ?? '{}',
      addisToolState: json['addis_tool_state'] as String?,
    );
  }

  JsonMap toJson() => {
        'id': id,
        'type': 'function',
        'function': {'name': name, 'arguments': arguments},
        if (addisToolState != null) 'addis_tool_state': addisToolState,
      };
}

class ChatCompletionMessage {
  final ChatRole role;
  final String? content;
  final String? name;
  final List<ToolCall>? toolCalls;
  final String? toolCallId;
  final List<ChatMessagePart>? parts;

  const ChatCompletionMessage({
    required this.role,
    this.content,
    this.name,
    this.toolCalls,
    this.toolCallId,
    this.parts,
  });

  JsonMap toJson() => {
        'role': role.value,
        if (content != null) 'content': content,
        if (name != null) 'name': name,
        if (toolCalls != null)
          'tool_calls': toolCalls!.map((call) => call.toJson()).toList(),
        if (toolCallId != null) 'tool_call_id': toolCallId,
        if (parts != null)
          'parts': parts!.map((part) => part.toJson()).toList(),
      };
}

/// A text or previously uploaded file in multimodal conversation history.
class ChatMessagePart {
  final String? text;
  final UploadedAttachment? file;

  const ChatMessagePart.text(String value)
      : text = value,
        file = null;
  const ChatMessagePart.file(this.file) : text = null;

  JsonMap toJson() => {
        if (text != null) 'text': text,
        if (file != null) 'fileData': file!.toJson(),
      };
}

/// Reusable metadata returned after a successful file upload.
class UploadedAttachment {
  final String fileUri;
  final String mimeType;

  const UploadedAttachment({required this.fileUri, required this.mimeType});

  factory UploadedAttachment.fromJson(JsonMap json) => UploadedAttachment(
        fileUri: json['fileUri'] as String? ?? '',
        mimeType: json['mimeType'] as String? ?? '',
      );

  JsonMap toJson() => {'fileUri': fileUri, 'mimeType': mimeType};
}

class AddisFile {
  final Uint8List bytes;
  final String filename;
  final String contentType;

  const AddisFile({
    required this.bytes,
    required this.filename,
    this.contentType = 'application/octet-stream',
  });
}

class ChatAttachment {
  final String? name;
  final AddisFile file;
  const ChatAttachment({this.name, required this.file});
}

class ChatCompletionCreateParams {
  final List<ChatCompletionMessage> messages;
  final Language language;
  final String? model;
  final String? system;
  final String? persona;
  final double? temperature;
  final int? maxTokens;
  final double? topP;
  final int? topK;
  final List<FunctionTool>? tools;
  final Object? toolChoice;
  final bool stream;
  final List<ChatAttachment>? attachments;
  final AddisFile? audio;

  const ChatCompletionCreateParams({
    required this.messages,
    this.language = Language.am,
    this.model,
    this.system,
    this.persona,
    this.temperature,
    this.maxTokens,
    this.topP,
    this.topK,
    this.tools,
    this.toolChoice,
    this.stream = false,
    this.attachments,
    this.audio,
  });
}

class ChatUsage {
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;
  const ChatUsage(this.promptTokens, this.completionTokens, this.totalTokens);
}

class ChatCompletion {
  final String id;
  final int created;
  final String model;
  final ChatCompletionMessage message;
  final String? finishReason;
  final ChatUsage? usage;
  final String? transcriptionRaw;
  final String? transcriptionClean;
  final List<UploadedAttachment> uploadedAttachments;

  const ChatCompletion({
    required this.id,
    required this.created,
    required this.model,
    required this.message,
    this.finishReason,
    this.usage,
    this.transcriptionRaw,
    this.transcriptionClean,
    this.uploadedAttachments = const [],
  });
}

class ChatCompletionChunk {
  final String id;
  final int created;
  final String model;
  final String content;
  final String? finishReason;
  const ChatCompletionChunk({
    required this.id,
    required this.created,
    required this.model,
    required this.content,
    this.finishReason,
  });
}

class VoiceSettings {
  final double? speed;
  final double? stability;
  final double? similarity;
  final double? style;
  const VoiceSettings({
    this.speed,
    this.stability,
    this.similarity,
    this.style,
  });
  JsonMap toJson() => {
        if (speed != null) 'speed': speed,
        if (stability != null) 'stability': stability,
        if (similarity != null) 'similarity': similarity,
        if (style != null) 'style': style,
      };
}

class VoiceGenerateParams {
  final String voiceId;
  final String text;
  final Language language;
  final OutputFormat outputFormat;
  final VoiceSettings? voiceSettings;
  final String? clientRequestId;
  const VoiceGenerateParams({
    required this.voiceId,
    required this.text,
    required this.language,
    this.outputFormat = OutputFormat.mp3_44100,
    this.voiceSettings,
    this.clientRequestId,
  });
}

class AddisClip {
  final String id;
  final String text;
  final String voiceId;
  final String voiceName;
  final String language;
  final String outputFormat;
  final String audioUrl;
  final String mimeType;
  final double? durationSeconds;
  final String downloadName;
  final String createdAt;
  final JsonMap raw;

  const AddisClip({
    required this.id,
    required this.text,
    required this.voiceId,
    required this.voiceName,
    required this.language,
    required this.outputFormat,
    required this.audioUrl,
    required this.mimeType,
    required this.durationSeconds,
    required this.downloadName,
    required this.createdAt,
    required this.raw,
  });

  factory AddisClip.fromJson(JsonMap json) => AddisClip(
        id: json['id'] as String? ?? '',
        text: json['text'] as String? ?? '',
        voiceId:
            json['voice_id'] as String? ?? json['voiceId'] as String? ?? '',
        voiceName:
            json['voice_name'] as String? ?? json['voiceName'] as String? ?? '',
        language: json['language'] as String? ?? '',
        outputFormat: json['output_format'] as String? ??
            json['outputFormat'] as String? ??
            '',
        audioUrl:
            json['audio_url'] as String? ?? json['audioUrl'] as String? ?? '',
        mimeType:
            json['mime_type'] as String? ?? json['mimeType'] as String? ?? '',
        durationSeconds:
            (json['duration_seconds'] ?? json['durationSeconds'] as num?)
                ?.toDouble(),
        downloadName: json['download_name'] as String? ??
            json['downloadName'] as String? ??
            'audio',
        createdAt:
            json['created_at'] as String? ?? json['createdAt'] as String? ?? '',
        raw: json,
      );
}

class VoiceCatalogEntry {
  final String id;
  final String name;
  final String descriptor;
  final Language language;
  final String gender;
  final String style;
  final bool isDefault;
  final bool isAvailable;
  final JsonMap raw;
  const VoiceCatalogEntry({
    required this.id,
    required this.name,
    required this.descriptor,
    required this.language,
    required this.gender,
    required this.style,
    required this.isDefault,
    required this.isAvailable,
    required this.raw,
  });
}

class Transcription {
  final String text;
  final double? confidence;
  final Object? usage;
  const Transcription({required this.text, this.confidence, this.usage});
}

class Translation {
  final String text;
  final TranslateLanguage sourceLanguage;
  final TranslateLanguage targetLanguage;
  final String? quality;
  final Object? usage;
  const Translation({
    required this.text,
    required this.sourceLanguage,
    required this.targetLanguage,
    this.quality,
    this.usage,
  });
}
