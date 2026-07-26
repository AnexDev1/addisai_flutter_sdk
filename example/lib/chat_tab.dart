import 'package:addis_ai_sdk/addis_ai_sdk.dart';
import 'package:flutter/material.dart';

class ChatTab extends StatefulWidget {
  final AddisAI client;
  const ChatTab({super.key, required this.client});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _controller = TextEditingController(text: 'ስለ ኢትዮጵያ ንገረኝ');
  String _answer = '';
  bool _loading = false;

  Future<void> _send() async {
    setState(() => _loading = true);
    try {
      final completion = await widget.client.chat.completions.create(
        ChatCompletionCreateParams(
          messages: [
            ChatCompletionMessage(
              role: ChatRole.user,
              content: _controller.text,
            ),
          ],
          language: Language.am,
          system: 'Be concise and helpful.',
        ),
      );
      if (mounted) {
        setState(() => _answer = completion.message.content ?? '');
      }
    } on AddisAIException catch (error) {
      if (mounted) setState(() => _answer = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextField(
          controller: _controller,
          decoration: const InputDecoration(
            labelText: 'Message',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _loading ? null : _send,
          child: Text(_loading ? 'Generating…' : 'Send'),
        ),
        const SizedBox(height: 24),
        SelectableText(_answer),
      ],
    ),
  );
}
