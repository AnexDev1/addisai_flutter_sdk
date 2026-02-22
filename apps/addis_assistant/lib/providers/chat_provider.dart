import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:addis_assistant/models/message.dart';
import 'package:addis_assistant/services/addis_service.dart';
import 'package:addis_ai_sdk/addis_ai_sdk.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatProvider with ChangeNotifier {
  final AddisService _addisService = AddisService();
  List<Message> _messages = [];
  Language _currentLanguage = Language.am;
  bool _isLoading = false;
  bool _isDarkMode = false;
  String? _apiKey;

  List<Message> get messages => _messages;
  Language get currentLanguage => _currentLanguage;
  bool get isLoading => _isLoading;
  bool get isDarkMode => _isDarkMode;
  bool get isInitialized => _addisService.isInitialized;

  ChatProvider() {
    _loadSettings();
    _loadHistory();
  }

  void setApiKey(String key) {
    _apiKey = key;
    _addisService.init(key);
    _saveSettings();
    notifyListeners();
  }

  void setLanguage(Language lang) {
    _currentLanguage = lang;
    notifyListeners();
  }

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    _saveSettings();
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _apiKey = prefs.getString('api_key');
    if (_apiKey != null) {
      _addisService.init(_apiKey!);
    }
    _isDarkMode = prefs.getBool('is_dark_mode') ?? false;
    notifyListeners();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (_apiKey != null) prefs.setString('api_key', _apiKey!);
    prefs.setBool('is_dark_mode', _isDarkMode);
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? historyJson = prefs.getString('chat_history');
    if (historyJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(historyJson);
        _messages = decoded.map((item) => Message.fromJson(item)).toList();
        notifyListeners();
      } catch (e) {
        debugPrint('Error loading history: $e');
      }
    }
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final historyToSave = _messages.length > 20 
        ? _messages.sublist(_messages.length - 20) 
        : _messages;
    final String encoded = jsonEncode(historyToSave.map((m) => m.toJson()).toList());
    prefs.setString('chat_history', encoded);
  }

  Future<void> sendVoiceMessage(File audioFile) async {
    final userMessage = Message(
      isUser: true,
      text: '🎤 [Voice Message]',
      timestamp: DateTime.now(),
      transcription: 'Transcribing...',
    );

    _messages.add(userMessage);
    _isLoading = true;
    notifyListeners();

    try {
      final history = _messages
          .where((m) => !m.isStreaming)
          .map((m) => ChatMessage(
                role: m.isUser ? 'user' : 'assistant',
                content: m.text,
              ))
          .toList();

      if (history.isNotEmpty) history.removeLast();

      final bytes = await audioFile.readAsBytes();
      final hex = bytes.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
      print('DEBUG PROVIDER: Audio bytes header (16b): $hex');
      
      final response = await _addisService.generateChatWithAttachments(
        prompt: null, 
        targetLanguage: _currentLanguage,
        files: {'chat_audio_input': bytes},
        fileNames: {'chat_audio_input': 'audio.wav'},
        filePaths: {'chat_audio_input': audioFile.path}, // More robust path-based upload
        history: history.isNotEmpty ? history : null,
      );
      
      print('DEBUG PROVIDER: Raw Transcription: "${response.transcriptionRaw}"');
      print('DEBUG PROVIDER: Clean Transcription: "${response.transcriptionClean}"');
      print('DEBUG PROVIDER: Response Text: "${response.responseText}"');
      
      // Update user message with transcription
      final lastIdx = _messages.indexOf(userMessage);
      if (lastIdx != -1) {
        _messages[lastIdx] = Message(
          isUser: true,
          text: response.transcriptionClean ?? userMessage.text,
          timestamp: userMessage.timestamp,
          transcription: response.transcriptionClean,
          transcriptionRaw: response.transcriptionRaw,
        );
      }

      // Add assistant response
      _messages.add(Message(
        isUser: false,
        text: response.responseText,
        timestamp: DateTime.now(),
      ));
      
      await _saveHistory();
    } catch (e) {
      debugPrint('Voice Chat Error: $e');
      _messages.add(Message(
        isUser: false,
        text: 'Error processing voice: ${e.toString()}',
        timestamp: DateTime.now(),
      ));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage(String text) async {
    if (text.isEmpty) return;

    final userMessage = Message(
      isUser: true,
      text: text,
      timestamp: DateTime.now(),
    );

    _messages.add(userMessage);
    _isLoading = true;
    notifyListeners();

    try {
      final history = _messages
          .where((m) => !m.isStreaming)
          .map((m) => ChatMessage(
                role: m.isUser ? 'user' : 'assistant',
                content: m.text,
              ))
          .toList();

      if (history.isNotEmpty) history.removeLast();

      // Streaming chat
      final assistantMessage = Message(
        isUser: false,
        text: '',
        timestamp: DateTime.now(),
        isStreaming: true,
      );
      _messages.add(assistantMessage);
      
      String fullResponse = '';
      final stream = _addisService.generateChatStream(
        prompt: text,
        targetLanguage: _currentLanguage,
        history: history,
      );

      await for (final chunk in stream) {
        fullResponse += chunk.responseText;
        final idx = _messages.length - 1;
        _messages[idx] = Message(
          isUser: false,
          text: fullResponse,
          timestamp: DateTime.now(),
          isStreaming: true,
        );
        notifyListeners();
      }

      // Finalize
      _messages[_messages.length - 1] = Message(
        isUser: false,
        text: fullResponse,
        timestamp: DateTime.now(),
        isStreaming: false,
      );
      
      await _saveHistory();
    } catch (e) {
      debugPrint('Chat Error: $e');
      _messages.add(Message(
        isUser: false,
        text: 'Error: ${e.toString()}',
        timestamp: DateTime.now(),
      ));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Uint8List?> generateTTS(String text) async {
    try {
      final response = await _addisService.textToSpeech(text, _currentLanguage);
      if (response.audioBase64 != null) {
        return base64Decode(response.audioBase64!);
      }
    } catch (e) {
      debugPrint('TTS Error: $e');
    }
    return null;
  }

  void clearHistory() async {
    _messages.clear();
    final prefs = await SharedPreferences.getInstance();
    prefs.remove('chat_history');
    notifyListeners();
  }
}
