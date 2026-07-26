import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'constants.dart';
import 'exceptions.dart';
import 'official_models.dart';
import 'transport.dart';

class ChatResource {
  final AddisTransport _transport;
  late final ChatCompletionsResource completions = ChatCompletionsResource(
    _transport,
  );
  ChatResource(this._transport);

  Future<ChatCompletion> runTools(
    ChatCompletionCreateParams params, {
    required List<RunnableTool> tools,
    int maxToolRoundtrips = 5,
    AddisRequestOptions options = const AddisRequestOptions(),
  }) async {
    final handlers = {
      for (final tool in tools) tool.function.name: tool.handler,
    };
    final wireTools =
        tools.map((tool) => FunctionTool(function: tool.function)).toList();
    final messages = [...params.messages];
    for (var round = 0; round <= maxToolRoundtrips; round++) {
      final result = await completions.create(
        ChatCompletionCreateParams(
          messages: messages,
          language: params.language,
          model: params.model,
          system: params.system,
          persona: params.persona,
          temperature: params.temperature,
          maxTokens: params.maxTokens,
          topP: params.topP,
          topK: params.topK,
          tools: wireTools,
          toolChoice: params.toolChoice,
        ),
        options: options,
      );
      final calls = result.message.toolCalls ?? const [];
      if (calls.isEmpty || result.finishReason != 'tool_calls') return result;
      if (round == maxToolRoundtrips) {
        throw AddisAIException(
          message: 'runTools exceeded maxToolRoundtrips ($maxToolRoundtrips).',
        );
      }
      messages.add(result.message);
      for (final call in calls) {
        final handler = handlers[call.name];
        if (handler == null) {
          throw AddisAIException(
            message: 'No implementation provided for tool "${call.name}".',
          );
        }
        Object? arguments;
        try {
          arguments = jsonDecode(call.arguments);
        } on FormatException {
          arguments = call.arguments;
        }
        final output = await handler(arguments);
        messages.add(
          ChatCompletionMessage(
            role: ChatRole.tool,
            toolCallId: call.id,
            name: call.name,
            content: output is String ? output : jsonEncode(output),
          ),
        );
      }
    }
    throw const AddisAIException(message: 'Tool loop terminated unexpectedly.');
  }
}

class ChatCompletionsResource {
  final AddisTransport _transport;
  ChatCompletionsResource(this._transport);

  Future<ChatCompletion> create(
    ChatCompletionCreateParams params, {
    AddisRequestOptions options = const AddisRequestOptions(),
  }) async {
    if (params.stream) {
      throw const AddisAIException(
        message: 'Use createStream() when stream is true.',
      );
    }
    if (params.attachments?.isNotEmpty == true || params.audio != null) {
      for (final attachment in params.attachments ?? const <ChatAttachment>[]) {
        _validateUpload(attachment.file, maxBytes: 10 * 1024 * 1024);
      }
      if (params.audio != null) {
        _validateUpload(params.audio!, maxBytes: 10 * 1024 * 1024);
      }
      return _createMultipart(params, options);
    }
    final response = await _transport.request(
      'POST',
      '/api/v1/chat_generate',
      body: _nativeBody(params),
      options: options,
    );
    return _completion(_asMap(_transport.decode(response)));
  }

  Stream<ChatCompletionChunk> createStream(
    ChatCompletionCreateParams params, {
    AddisRequestOptions options = const AddisRequestOptions(),
  }) async* {
    if (params.tools?.isNotEmpty == true) {
      throw const AddisAIException(
        message: 'Streaming is not supported with tool calling.',
      );
    }
    final request =
        http.Request('POST', _transport.uri('/api/v1/chat_generate', options))
          ..headers.addAll(_transport.headers(options))
          ..body = jsonEncode(_nativeBody(params, stream: true));
    final response = await _transport.client
        .send(request)
        .timeout(options.timeout ?? _transport.timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AddisAIException.fromHttpResponse(
        await http.Response.fromStream(response),
      );
    }
    final id = 'chatcmpl-${_randomId()}';
    final created = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final dataLines = <String>[];
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (dataLines.isNotEmpty) {
          final data = dataLines.join('\n').trim();
          dataLines.clear();
          if (data == '[DONE]') return;
          final chunk = _streamChunk(data, id, created);
          if (chunk != null) yield chunk;
        }
      } else if (!line.startsWith(':') && line.startsWith('data:')) {
        dataLines.add(line.substring(5).trimLeft());
      }
    }
    if (dataLines.isNotEmpty) {
      final chunk = _streamChunk(dataLines.join('\n'), id, created);
      if (chunk != null) yield chunk;
    }
  }

  Future<ChatCompletion> _createMultipart(
    ChatCompletionCreateParams params,
    AddisRequestOptions options,
  ) async {
    final boundary =
        '----addisai-dart-${DateTime.now().microsecondsSinceEpoch}';
    final bytes = BytesBuilder(copy: false);
    void text(String value) => bytes.add(utf8.encode(value));
    const crlf = '\r\n';
    void addFile(String field, AddisFile file) {
      final safeName = _safeFilename(file.filename);
      text('--$boundary$crlf');
      text('Content-Disposition: form-data; name="$field"; '
          'filename="$safeName"$crlf');
      text('Content-Type: ${file.contentType}$crlf$crlf');
      bytes.add(file.bytes);
      text(crlf);
    }

    final names = <String>[];
    for (var index = 0; index < (params.attachments?.length ?? 0); index++) {
      final attachment = params.attachments![index];
      final name = attachment.name ?? 'attachment_$index';
      names.add(name);
      addFile(name, attachment.file);
    }
    if (params.audio != null) {
      addFile('chat_audio_input', params.audio!);
    }
    final body = _nativeBody(params);
    if (names.isNotEmpty) body['attachment_field_names'] = names;
    text('--$boundary$crlf');
    text('Content-Disposition: form-data; name="request_data"$crlf$crlf');
    text(jsonEncode(body));
    text(crlf);
    text('--$boundary--$crlf');
    final request = http.Request(
      'POST',
      _transport.uri('/api/v1/chat_generate', options),
    )
      ..headers.addAll(_transport.headers(options, json: false))
      ..headers['Content-Type'] = 'multipart/form-data; boundary=$boundary'
      ..bodyBytes = bytes.takeBytes();
    final streamed = await _transport.client
        .send(request)
        .timeout(options.timeout ?? _transport.timeout);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AddisAIException.fromHttpResponse(response);
    }
    return _completion(_asMap(_transport.decode(response)));
  }
}

class VoiceResource {
  final AddisTransport _transport;
  late final ClipsResource clips = ClipsResource(_transport);
  VoiceResource(this._transport);

  Future<AddisClip> generate(
    VoiceGenerateParams params, {
    AddisRequestOptions options = const AddisRequestOptions(),
  }) async {
    final requestId = params.clientRequestId ?? _ulid();
    final response = await _transport.request(
      'POST',
      '/api/v1/voice/generations',
      body: {
        'text': params.text,
        'language': params.language.value,
        'voice_id': params.voiceId,
        'output_format': params.outputFormat.value,
        if (params.voiceSettings != null)
          'voice_settings': params.voiceSettings!.toJson(),
        'stream': false,
        'client_request_id': requestId,
      },
      options: AddisRequestOptions(
        timeout: options.timeout,
        maxRetries: options.maxRetries,
        idempotencyKey: options.idempotencyKey ?? requestId,
        headers: options.headers,
        query: options.query,
      ),
      timeoutFloor: const Duration(seconds: 95),
    );
    return AddisClip.fromJson(_asMap(_transport.decode(response)));
  }

  Future<JsonMap> estimate(
    VoiceGenerateParams params, {
    AddisRequestOptions options = const AddisRequestOptions(),
  }) async {
    final response = await _transport.request(
      'POST',
      '/api/v1/voice/estimate',
      body: {
        'text': params.text,
        'language': params.language.value,
        'voice_id': params.voiceId,
        'output_format': params.outputFormat.value,
      },
      options: options,
    );
    return _asMap(_transport.decode(response));
  }

  Future<JsonMap> usage({
    AddisRequestOptions options = const AddisRequestOptions(),
  }) async {
    final response = await _transport.request(
      'GET',
      '/api/v1/voice/usage',
      options: options,
    );
    return _asMap(_transport.decode(response));
  }

  Future<Stream<Uint8List>> stream(VoiceGenerateParams params) {
    throw const NotSupportedException(
      message:
          'Streaming voice synthesis is not enabled. Use voice.generate().',
    );
  }
}

class ClipsResource {
  final AddisTransport _transport;
  ClipsResource(this._transport);

  Future<List<AddisClip>> list({
    int? limit,
    String? cursor,
    Language? language,
    String? voiceId,
    AddisRequestOptions options = const AddisRequestOptions(),
  }) async {
    final response = await _transport.request(
      'GET',
      '/api/v1/voice/clips',
      query: {
        'limit': limit,
        'cursor': cursor,
        'language': language?.value,
        'voice_id': voiceId,
      },
      options: options,
    );
    final data = _transport.decode(response);
    final values = data is Map ? data['data'] ?? data['items'] : data;
    return (values as List? ?? const [])
        .whereType<Map>()
        .map((item) => AddisClip.fromJson(item.cast<String, dynamic>()))
        .toList();
  }

  Future<AddisClip> get(
    String clipId, {
    AddisRequestOptions options = const AddisRequestOptions(),
  }) async {
    final response = await _transport.request(
      'GET',
      '/api/v1/voice/clips/${Uri.encodeComponent(clipId)}',
      options: options,
    );
    return AddisClip.fromJson(_asMap(_transport.decode(response)));
  }

  Future<Uint8List> download(
    String clipId, {
    AddisRequestOptions options = const AddisRequestOptions(),
  }) async {
    final clip = await get(clipId, options: options);
    final response = await _transport.client.get(Uri.parse(clip.audioUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AddisAIException.fromHttpResponse(response);
    }
    return response.bodyBytes;
  }

  Future<void> delete(
    String clipId, {
    AddisRequestOptions options = const AddisRequestOptions(),
  }) async {
    await _transport.request(
      'DELETE',
      '/api/v1/voice/clips/${Uri.encodeComponent(clipId)}',
      options: options,
    );
  }
}

class VoicesResource {
  final AddisTransport _transport;
  VoicesResource(this._transport);

  Future<List<VoiceCatalogEntry>> list({
    Language? language,
    String? gender,
    String? search,
    bool? includeUnavailable,
    AddisRequestOptions options = const AddisRequestOptions(),
  }) async {
    final response = await _transport.request(
      'GET',
      '/api/v1/voice/voices',
      query: {
        'language': language?.value,
        'gender': gender,
        'search': search,
        'include_unavailable': includeUnavailable,
      },
      options: options,
    );
    final decoded = _transport.decode(response);
    final values =
        decoded is Map ? decoded['voices'] ?? decoded['data'] : decoded;
    return (values as List? ?? const []).whereType<Map>().map((item) {
      final json = item.cast<String, dynamic>();
      return VoiceCatalogEntry(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        descriptor: json['descriptor'] as String? ?? '',
        language: Language.values.firstWhere(
          (value) => value.name == json['language'],
          orElse: () => Language.am,
        ),
        gender: json['gender'] as String? ?? '',
        style: json['style'] as String? ?? '',
        isDefault: json['is_default'] as bool? ?? false,
        isAvailable: json['is_available'] as bool? ?? true,
        raw: json,
      );
    }).toList();
  }

  Future<JsonMap> preview(
    String voiceId, {
    AddisRequestOptions options = const AddisRequestOptions(),
  }) async {
    final response = await _transport.request(
      'GET',
      '/api/v1/voice/voices/${Uri.encodeComponent(voiceId)}/preview',
      options: options,
    );
    return _asMap(_transport.decode(response));
  }
}

class SpeechResource {
  final AddisTransport _transport;
  SpeechResource(this._transport);

  Future<Transcription> transcribe({
    required AddisFile audio,
    required SttLanguage language,
    AddisRequestOptions options = const AddisRequestOptions(),
  }) async {
    _validateUpload(
      audio,
      maxBytes: 10 * 1024 * 1024,
      allowedTypes: const {
        'audio/wav',
        'audio/x-wav',
        'audio/wave',
        'audio/mpeg',
        'audio/mp3',
        'audio/mp4',
        'audio/x-m4a',
        'audio/webm',
      },
    );
    final boundary =
        '----addisai-dart-${DateTime.now().microsecondsSinceEpoch}';
    final body = BytesBuilder(copy: false);
    void text(String value) => body.add(utf8.encode(value));
    const crlf = '\r\n';
    final safeName = _safeFilename(audio.filename);
    text('--$boundary$crlf');
    text('Content-Disposition: form-data; name="audio"; '
        'filename="$safeName"$crlf');
    text('Content-Type: ${audio.contentType}$crlf$crlf');
    body.add(audio.bytes);
    text(crlf);
    text('--$boundary$crlf');
    text('Content-Disposition: form-data; name="request_data"$crlf$crlf');
    text(jsonEncode({'language_code': language.value}));
    text(crlf);
    text('--$boundary--$crlf');

    final request = http.Request('POST', _transport.uri('/api/v2/stt', options))
      ..headers.addAll(_transport.headers(options, json: false))
      ..headers['Content-Type'] = 'multipart/form-data; boundary=$boundary'
      ..bodyBytes = body.takeBytes();
    final streamed = await _transport.client
        .send(request)
        .timeout(options.timeout ?? _transport.timeout);
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AddisAIException.fromHttpResponse(response);
    }
    final root = _asMap(jsonDecode(utf8.decode(response.bodyBytes)));
    final data = root['data'] is Map
        ? (root['data'] as Map).cast<String, dynamic>()
        : root;
    return Transcription(
      text: data['transcription'] as String? ?? '',
      confidence:
          ((data['confidence'] ?? root['confidence']) as num?)?.toDouble(),
      usage: data['usage_metadata'],
    );
  }
}

class TranslateResource {
  final AddisTransport _transport;
  TranslateResource(this._transport);

  Future<Translation> create({
    required String text,
    required TranslateLanguage from,
    required TranslateLanguage to,
    AddisRequestOptions options = const AddisRequestOptions(),
  }) async {
    final response = await _transport.request(
      'POST',
      '/api/v1/translate',
      body: {
        'text': text,
        'source_language': from.value,
        'target_language': to.value,
      },
      options: options,
    );
    final data = _asMap(_transport.decode(response));
    return Translation(
      text: data['translation'] as String? ?? '',
      sourceLanguage: from,
      targetLanguage: to,
      quality: data['quality'] as String?,
      usage: data['usage_metadata'],
    );
  }
}

class TextToSpeechResource {
  final VoiceResource _voice;
  TextToSpeechResource(this._voice);
  Future<AddisClip> convert(
    String voiceId, {
    required String text,
    required Language language,
    OutputFormat outputFormat = OutputFormat.mp3_44100,
    VoiceSettings? voiceSettings,
    String? clientRequestId,
    AddisRequestOptions options = const AddisRequestOptions(),
  }) =>
      _voice.generate(
        VoiceGenerateParams(
          voiceId: voiceId,
          text: text,
          language: language,
          outputFormat: outputFormat,
          voiceSettings: voiceSettings,
          clientRequestId: clientRequestId,
        ),
        options: options,
      );
}

JsonMap _nativeBody(ChatCompletionCreateParams params, {bool stream = false}) {
  final system = <String>[
    if (params.system?.trim().isNotEmpty == true) params.system!,
  ];
  final messages = <ChatCompletionMessage>[];
  for (final message in params.messages) {
    if (message.role == ChatRole.system || message.role == ChatRole.developer) {
      if (message.content?.trim().isNotEmpty == true) {
        system.add(message.content!);
      }
    } else {
      messages.add(message);
    }
  }
  var lastUser = -1;
  for (var index = messages.length - 1; index >= 0; index--) {
    if (messages[index].role == ChatRole.user &&
        messages[index].content?.trim().isNotEmpty == true) {
      lastUser = index;
      break;
    }
  }
  final historySource = lastUser >= 0 ? messages.take(lastUser) : messages;
  final history = historySource
      .where(
        (message) =>
            message.content?.isNotEmpty == true ||
            message.parts?.isNotEmpty == true,
      )
      .map(
        (message) => {
          'role': message.role == ChatRole.assistant ? 'assistant' : 'user',
          if (message.parts?.isNotEmpty == true)
            'parts': message.parts!.map((part) => part.toJson()).toList()
          else
            'content': message.content,
        },
      )
      .toList();
  final generation = <String, dynamic>{
    if (params.temperature != null) 'temperature': params.temperature,
    if (params.maxTokens != null) 'maxOutputTokens': params.maxTokens,
    if (params.topP != null) 'topP': params.topP,
    if (params.topK != null) 'topK': params.topK,
    if (stream) 'stream': true,
  };
  return {
    'target_language': params.language.value,
    if (lastUser >= 0) 'prompt': messages[lastUser].content,
    if (history.isNotEmpty) 'conversation_history': history,
    if (system.isNotEmpty) 'system': system.join('\n\n'),
    if (params.persona != null) 'persona': params.persona,
    if (params.tools != null)
      'tools': params.tools!.map((tool) => tool.toJson()).toList(),
    if (params.toolChoice != null) 'tool_choice': params.toolChoice,
    if (generation.isNotEmpty) 'generation_config': generation,
  };
}

ChatCompletion _completion(JsonMap data) {
  final toolCalls = (data['tool_calls'] as List? ?? const [])
      .whereType<Map>()
      .map((call) => ToolCall.fromJson(call.cast<String, dynamic>()))
      .toList();
  final usage = data['usage_metadata'] is Map
      ? (data['usage_metadata'] as Map).cast<String, dynamic>()
      : null;
  return ChatCompletion(
    id: 'chatcmpl-${_randomId()}',
    created: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    model: addisChatModel,
    message: ChatCompletionMessage(
      role: ChatRole.assistant,
      content: data['response_text'] as String? ?? '',
      toolCalls: toolCalls.isEmpty ? null : toolCalls,
    ),
    finishReason: toolCalls.isNotEmpty
        ? 'tool_calls'
        : _finishReason(data['finish_reason']),
    usage: usage == null
        ? null
        : ChatUsage(
            usage['prompt_token_count'] as int? ?? 0,
            usage['candidates_token_count'] as int? ?? 0,
            usage['total_token_count'] as int? ?? 0,
          ),
    transcriptionRaw: data['transcription_raw'] as String?,
    transcriptionClean: data['transcription_clean'] as String?,
    uploadedAttachments: (data['uploaded_attachments'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => UploadedAttachment.fromJson(item.cast<String, dynamic>()),
        )
        .toList(),
  );
}

ChatCompletionChunk? _streamChunk(String raw, String id, int created) {
  try {
    final data = _asMap(jsonDecode(raw));
    if (data['type'] == 'metadata') return null;
    final content =
        data['text'] as String? ?? data['response_text'] as String? ?? '';
    final finish = _finishReason(data['finish_reason']);
    if (content.isEmpty && finish == null) return null;
    return ChatCompletionChunk(
      id: id,
      created: created,
      model: addisChatModel,
      content: content,
      finishReason: finish,
    );
  } on FormatException {
    return null;
  }
}

String? _finishReason(Object? reason) {
  if (reason is! String || reason.isEmpty) return null;
  return switch (reason.toUpperCase()) {
    'STOP' => 'stop',
    'MAX_TOKENS' => 'length',
    'SAFETY' || 'RECITATION' => 'content_filter',
    'TOOL_CALLS' => 'tool_calls',
    _ => reason.toLowerCase(),
  };
}

JsonMap _asMap(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

String _randomId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random.secure().nextInt(1 << 32).toRadixString(36)}';

String _ulid() {
  const encoding = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  var time = DateTime.now().millisecondsSinceEpoch;
  final chars = List<String>.filled(26, '0');
  for (var i = 9; i >= 0; i--) {
    chars[i] = encoding[time % 32];
    time ~/= 32;
  }
  final random = Random.secure();
  for (var i = 10; i < 26; i++) {
    chars[i] = encoding[random.nextInt(32)];
  }
  return chars.join();
}

void _validateUpload(
  AddisFile file, {
  required int maxBytes,
  Set<String>? allowedTypes,
}) {
  if (file.bytes.length > maxBytes) {
    throw ArgumentError.value(
      file.bytes.length,
      'file',
      'exceeds the ${maxBytes ~/ (1024 * 1024)} MB API limit',
    );
  }
  final type = file.contentType.toLowerCase().split(';').first.trim();
  if (allowedTypes != null && !allowedTypes.contains(type)) {
    throw ArgumentError.value(
      file.contentType,
      'contentType',
      'unsupported audio format',
    );
  }
}

String _safeFilename(String value) => value
    .replaceAll(RegExp(r'[\r\n"]'), '_')
    .replaceAll(RegExp(r'[^\x20-\x7E]'), '_');
