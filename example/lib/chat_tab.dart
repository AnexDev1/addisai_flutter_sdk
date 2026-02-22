import 'dart:io';
import 'package:flutter/material.dart';
import 'package:addis_ai_sdk/addis_ai_sdk.dart';
import 'package:image_picker/image_picker.dart';

class ChatTab extends StatefulWidget {
  final AddisAI client;

  const ChatTab({super.key, required this.client});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;
  File? _selectedImage;

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

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add({
        'role': 'user',
        'content': text,
        'image': imageToUpload,
      });
      _isLoading = true;
      _selectedImage = null;
    });
    _controller.clear();
    _scrollToBottom();

    try {
    try {
      final history = _messages.sublist(0, _messages.length - 1).map((m) {
        return ChatMessage(role: m['role'], content: m['content']);
      }).toList();

      ChatResponse response;
      if (imageToUpload != null) {
        final bytes = await imageToUpload.readAsBytes();
        final fileName = imageToUpload.path.split('/').last;
        response = await widget.client.generateChatWithAttachments(
          ChatRequest(
            prompt: text.isEmpty ? 'Can you describe this image?' : text,
            targetLanguage: Language.am,
            attachmentFieldNames: ['context_image'],
            conversationHistory: history.isNotEmpty ? history : null,
          ),
          files: {'context_image': bytes},
          fileNames: {'context_image': fileName},
        );
      } else {
        response = await widget.client.generateChat(
          ChatRequest(
            prompt: text,
            targetLanguage: Language.am,
            conversationHistory: history,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _messages.add({
            'role': 'assistant',
            'content': response.responseText,
            'image': null,
          });
        });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      setState(() {
        _messages.removeLast();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppBar(
          title: const Text('Chat (Amharic)'),
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              final isUser = message['role'] == 'user';
              final File? image = message['image'] as File?;

              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isUser 
                      ? Theme.of(context).colorScheme.primaryContainer 
                      : Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (image != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            image,
                            height: 150,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (message['content'] != null && (message['content'] as String).isNotEmpty)
                        Text(
                          message['content'] as String,
                          style: const TextStyle(fontSize: 16),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        if (_isLoading)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: CircularProgressIndicator(),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                if (_selectedImage != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            _selectedImage!,
                            height: 48,
                            width: 48,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: -8,
                          right: -8,
                          child: GestureDetector(
                            onTap: () => setState(() => _selectedImage = null),
                            child: const CircleAvatar(
                              radius: 10,
                              backgroundColor: Colors.red,
                              child: Icon(Icons.close, size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.image),
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: _isLoading ? null : _pickImage,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'መልእክትዎን እዚህ ይፃፉ...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  color: Theme.of(context).colorScheme.primary,
                  onPressed: _isLoading ? null : _sendMessage,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
