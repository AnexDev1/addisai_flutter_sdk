import 'package:flutter/material.dart';
import 'package:addis_ai_sdk/addis_ai_sdk.dart';

class RealtimeTab extends StatefulWidget {
  final AddisAI client;

  const RealtimeTab({super.key, required this.client});

  @override
  State<RealtimeTab> createState() => _RealtimeTabState();
}

class _RealtimeTabState extends State<RealtimeTab> {
  AddisAIRealtime? _realtimeSession;
  final List<String> _logs = [];
  bool _isConnected = false;

  @override
  void dispose() {
    _realtimeSession?.close();
    super.dispose();
  }

  void _addLog(String message) {
    if (mounted) {
      setState(() {
        _logs.insert(0, message);
      });
    }
  }

  Future<void> _toggleConnection() async {
    if (_isConnected) {
      await _realtimeSession?.close();
      setState(() {
        _isConnected = false;
        _realtimeSession = null;
      });
      _addLog('Disconnected.');
      return;
    }

    try {
      setState(() => _isConnected = true);
      _addLog('Connecting...');
      
      _realtimeSession = await widget.client.createRealtimeSession();
      _addLog('Connected successfully.');

      _realtimeSession!.messages.listen(
        (message) {
          if (message is RealtimeStatusMessage) {
            _addLog('Status: ${message.message}');
          } else if (message is RealtimeAudioResponse) {
            final audioLength = message.audioBase64?.length ?? 0;
            _addLog('Received Model Audio: $audioLength chars (base64)');
            if (message.isTurnComplete) {
              _addLog('--- Turn Complete ---');
            }
          } else if (message is RealtimeWarningMessage) {
            _addLog('Warning: ${message.message}');
          } else if (message is RealtimeErrorMessage) {
            _addLog('Error: ${message.message}');
          }
        },
        onError: (error) => _addLog('WebSocket Error: $error'),
        onDone: () {
          _addLog('WebSocket Closed from server.');
          setState(() {
            _isConnected = false;
            _realtimeSession = null;
          });
        },
      );
    } catch (e) {
      _addLog('Failed to connect: $e');
      setState(() => _isConnected = false);
    }
  }

  void _simulateAudioSend() {
    if (_realtimeSession == null) return;
    _addLog('Simulating 16kHz PCM audio upload...');
    // Real implementation would use record package: e.g. record.startStream(pcm_16khz)
    final dummyWavBytes = List<int>.filled(1024, 0); 
    _realtimeSession!.sendAudio(dummyWavBytes);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text(
            'Realtime WebSockets API',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: _toggleConnection,
                icon: Icon(_isConnected ? Icons.stop : Icons.play_arrow),
                label: Text(_isConnected ? 'Disconnect' : 'Connect WebSocket'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isConnected ? Colors.red.shade100 : null,
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: _isConnected ? _simulateAudioSend : null,
                icon: const Icon(Icons.mic),
                label: const Text('Send (Dummy) PCM'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const Text('Session Logs', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                reverse: true,
                itemCount: _logs.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      _logs[index],
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
