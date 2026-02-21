import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:addis_ai_sdk/addis_ai_sdk.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

class TtsTab extends StatefulWidget {
  final AddisAI client;
  const TtsTab({super.key, required this.client});

  @override
  State<TtsTab> createState() => _TtsTabState();
}

class _TtsTabState extends State<TtsTab> {
  final TextEditingController _controller = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  bool _isLoading = false;
  String _statusMessage = 'Ready';

  @override
  void dispose() {
    _controller.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playTts() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _statusMessage = 'Generating Audio...';
    });

    try {
      final ttsResponse = await widget.client.textToSpeech(
        TtsRequest(
          text: text,
          language: Language.am,
        )
      );

      final decodedBytes = base64Decode(ttsResponse.audioBase64);
      
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/tts_audio.wav');
      await tempFile.writeAsBytes(decodedBytes);

      setState(() => _statusMessage = 'Playing Audio...');
      
      await _audioPlayer.setFilePath(tempFile.path);
      await _audioPlayer.play();

      setState(() => _statusMessage = 'Finished playing.');
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Text to Speech (Amharic)',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _controller,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Enter Amharic text here...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _playTts,
            icon: _isLoading 
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.volume_up),
            label: const Text('Generate & Play'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _statusMessage,
            style: TextStyle(color: Theme.of(context).colorScheme.primary),
          ),
        ],
      ),
    );
  }
}
