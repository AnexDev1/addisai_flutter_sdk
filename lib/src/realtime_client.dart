import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'exceptions.dart';
import 'models.dart';

/// A client for the Addis AI Realtime WebSocket API.
///
/// Use [AddisAI.createRealtimeSession] to create an instance.
class AddisAIRealtime {
  final WebSocketChannel _channel;
  final StreamController<RealtimeMessage> _messageController =
      StreamController<RealtimeMessage>.broadcast();
  final Completer<void> _ready = Completer<void>();
  bool _closed = false;

  AddisAIRealtime._(this._channel) {
    _channel.stream.listen(
      (dynamic data) {
        if (data is String) {
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final message = RealtimeMessage.fromJson(json);
            if ((message is RealtimeReadyMessage ||
                    (message is RealtimeStatusMessage &&
                        message.message.toLowerCase().contains('ready'))) &&
                !_ready.isCompleted) {
              _ready.complete();
            }
            _messageController.add(message);
          } catch (e) {
            _messageController.addError(
              AddisAIException(message: 'Failed to parse realtime message: $e'),
            );
          }
        }
      },
      onError: (Object error) {
        _messageController.addError(
          AddisAIException(message: 'WebSocket error: $error'),
        );
      },
      onDone: () {
        if (!_ready.isCompleted) {
          _ready.completeError(
            const AddisAIException(
              message: 'Realtime connection closed before it became ready.',
            ),
          );
        }
        _messageController.close();
      },
      cancelOnError: false,
    );
  }

  /// Connects to the Realtime API and returns a session.
  static Future<AddisAIRealtime> connect(String apiKey) async {
    final uri = Uri.parse('wss://relay.addisassistant.com/ws?apiKey=$apiKey');
    final channel = WebSocketChannel.connect(uri);
    await channel.ready;
    return AddisAIRealtime._(channel);
  }

  /// A stream of parsed messages received from the server.
  Stream<RealtimeMessage> get messages => _messageController.stream;

  /// Completes after `setupComplete` (or the compatible ready status event).
  Future<void> get ready => _ready.future;

  /// Sends raw PCM audio data to the server.
  ///
  /// The audio should be 16kHz, 16-bit PCM, mono format.
  void sendAudio(
    List<int> pcmBytes, {
    int sampleRate = 16000,
  }) {
    if (!_ready.isCompleted) {
      throw const AddisAIException(
        message: 'Wait for realtime.ready before sending audio.',
      );
    }
    final base64Audio = base64Encode(pcmBytes);
    final payload = jsonEncode({
      'data': base64Audio,
      'mimeType': 'audio/pcm;rate=$sampleRate',
    });
    _channel.sink.add(payload);
  }

  /// Closes the WebSocket connection.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _channel.sink.close();
    if (!_messageController.isClosed) {
      await _messageController.close();
    }
  }
}
