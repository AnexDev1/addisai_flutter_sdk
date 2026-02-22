import 'dart:io';
import 'package:addis_assistant/providers/chat_provider.dart';
import 'package:addis_assistant/services/audio_service.dart';
import 'package:addis_assistant/widgets/chat_bubble.dart';
import 'package:addis_assistant/widgets/message_input.dart';
import 'package:addis_ai_sdk/addis_ai_sdk.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final AudioService _audioService = AudioService();
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _audioService.init();
  }

  @override
  void dispose() {
    _audioService.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleMicPressed() async {
    if (_isRecording) {
      final path = await _audioService.stopRecording();
      if (!mounted) return;
      setState(() => _isRecording = false);
      if (path != null && mounted) {
        final chatProvider = Provider.of<ChatProvider>(context, listen: false);
        chatProvider.sendVoiceMessage(File(path));
        _scrollToBottom();
      }
    } else {
      await _audioService.startRecording();
      setState(() => _isRecording = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Addis AI', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          DropdownButton<Language>(
            value: chatProvider.currentLanguage,
            underline: const SizedBox(),
            items: [
              const DropdownMenuItem(value: Language.am, child: Text('አማ')),
              const DropdownMenuItem(value: Language.en, child: Text('EN')),
              const DropdownMenuItem(value: Language.om, child: Text('OM')),
            ],
            onChanged: (lang) {
              if (lang != null) chatProvider.setLanguage(lang);
            },
          ),
          IconButton(
            icon: Icon(chatProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: chatProvider.toggleTheme,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => chatProvider.clearHistory(),
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          image: DecorationImage(
            image: const AssetImage('assets/patterns/culture_pattern.png'),
            opacity: chatProvider.isDarkMode ? 0.05 : 0.1,
            repeat: ImageRepeat.repeat,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: chatProvider.messages.length,
                itemBuilder: (context, index) {
                  final message = chatProvider.messages[index];
                  return ChatBubble(
                    message: message,
                    onPlayAudio: () async {
                      final audioBytes = await chatProvider.generateTTS(message.text);
                      if (audioBytes != null) {
                        await _audioService.playAudioFromBytes(audioBytes);
                      }
                    },
                  );
                },
              ),
            ),
            if (chatProvider.isLoading)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: SpinKitThreeBounce(
                  color: const Color(0xFF26A69A),
                  size: 20.0,
                ),
              ),
          ],
        ),
      ),
      bottomNavigationBar: MessageInput(
        onSend: (text) => context.read<ChatProvider>().sendMessage(text),
        onMicPressed: _handleMicPressed,
        isRecording: _isRecording,
      ),
    );
  }
}
