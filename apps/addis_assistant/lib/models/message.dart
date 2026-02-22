class Message {
  final bool isUser;
  final String text;
  final DateTime timestamp;
  final String? audioUrl; // for TTS generated audio
  final bool isStreaming;
  final String? transcription; // Localized transcription (e.g. Amharic)
  final String? transcriptionRaw; // Raw transcription if available

  Message({
    required this.isUser,
    required this.text,
    required this.timestamp,
    this.audioUrl,
    this.isStreaming = false,
    this.transcription,
    this.transcriptionRaw,
  });

  Map<String, dynamic> toJson() {
    return {
      'isUser': isUser,
      'text': text,
      'timestamp': timestamp.toIso8601String(),
      'audioUrl': audioUrl,
      'isStreaming': isStreaming,
      'transcription': transcription,
      'transcriptionRaw': transcriptionRaw,
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      isUser: json['isUser'],
      text: json['text'],
      timestamp: DateTime.parse(json['timestamp']),
      audioUrl: json['audioUrl'],
      isStreaming: json['isStreaming'] ?? false,
      transcription: json['transcription'],
      transcriptionRaw: json['transcriptionRaw'],
    );
  }
}
