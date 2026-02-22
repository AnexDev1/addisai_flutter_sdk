import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioService {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final AudioPlayer _player = AudioPlayer();
  bool _isRecorderInitialized = false;

  Future<void> init() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw Exception('Microphone permission not granted');
    }

    await _recorder.openRecorder();
    _isRecorderInitialized = true;
  }

  Future<void> startRecording() async {
    if (!_isRecorderInitialized) await init();

    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/temp_record.wav';

    await _recorder.startRecorder(
      toFile: path,
      codec: Codec.pcm16WAV,
      sampleRate: 16000,
      numChannels: 1,
    );
  }

  Future<String?> stopRecording() async {
    final path = await _recorder.stopRecorder();
    if (path != null) {
      await Future.delayed(
          const Duration(milliseconds: 200)); // Ensure file is flushed
    }
    return path;
  }

  Future<void> playAudioFromBytes(Uint8List bytes) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/temp_audio.mp3');
    await file.writeAsBytes(bytes);

    await _player.setFilePath(file.path);
    await _player.play();
  }

  Future<void> stopPlayback() async {
    await _player.stop();
  }

  void dispose() {
    _recorder.closeRecorder();
    _player.dispose();
  }
}
