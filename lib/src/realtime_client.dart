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

  AddisAIRealtime._(this._channel) {
    _channel.stream.listen(
      (dynamic data) {
        if (data is String) {
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            _messageController.add(RealtimeMessage.fromJson(json));
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

  /// Sends raw PCM audio data to the server.
  ///
  /// The audio should be 16kHz, 16-bit PCM, mono format.
  void sendAudio(List<int> pcmBytes) {
    final base64Audio = base64Encode(pcmBytes);
    final payload = jsonEncode({'data': base64Audio});
    _channel.sink.add(payload);
  }

  /// Closes the WebSocket connection.
  Future<void> close() async {
    await _channel.sink.close();
    await _messageController.close();
  }
}
