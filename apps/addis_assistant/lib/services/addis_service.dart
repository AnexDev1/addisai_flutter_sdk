import 'package:addis_ai_sdk/addis_ai_sdk.dart';

class AddisService {
  late AddisAI _client;
  bool _isInitialized = false;

  void init(String apiKey) {
    _client = AddisAI(apiKey: apiKey);
    _isInitialized = true;
  }

  bool get isInitialized => _isInitialized;

  Future<ChatResponse> generateChat({
    required String prompt,
    required Language targetLanguage,
    List<ChatMessage>? history,
  }) async {
    return await _client.generateChat(
      ChatRequest(
        prompt: prompt,
        targetLanguage: targetLanguage,
        conversationHistory: history,
      ),
    );
  }

  Stream<ChatResponse> generateChatStream({
    required String prompt,
    required Language targetLanguage,
    List<ChatMessage>? history,
  }) {
    return _client.generateChatStream(
      ChatRequest(
        prompt: prompt,
        targetLanguage: targetLanguage,
        conversationHistory: history,
      ),
    );
  }

  Future<ChatResponse> generateChatWithAttachments({
    String? prompt,
    required Language targetLanguage,
    required Map<String, List<int>> files,
    Map<String, String>? fileNames,
    Map<String, String>? filePaths,
    List<ChatMessage>? history,
  }) async {
    return await _client.generateChatWithAttachments(
      ChatRequest(
        prompt: prompt,
        targetLanguage: targetLanguage,
        conversationHistory: history,
        attachmentFieldNames: files.keys.toList(),
      ),
      files: files,
      fileNames: fileNames,
      filePaths: filePaths,
    );
  }

  Future<TtsResponse> textToSpeech(String text, Language language) async {
    return await _client.textToSpeech(
      TtsRequest(text: text, language: language),
    );
  }

  void dispose() {
    _client.close();
  }
}
