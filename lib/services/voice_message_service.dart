// voice_message_service.dart
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

class VoiceMessageService {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  Future<void> startRecording() async {
    // Request microphone permission
    await Permission.microphone.request();

    await _recorder.openRecorder();
    await _recorder.startRecorder(
      toFile: 'audio_recording.wav',
      codec: Codec.pcm16WAV,
    );
  }

  Future<String?> stopRecording() async {
    String? path = await _recorder.stopRecorder();
    await _recorder.closeRecorder();
    return path;
  }

  Future<String> uploadVoiceMessage(String filePath) async {
    File file = File(filePath);

    try {
      // Upload to Firebase Storage
      Reference ref = FirebaseStorage.instance
          .ref()
          .child('voice_messages')
          .child('${DateTime.now().millisecondsSinceEpoch}.wav');

      UploadTask uploadTask = ref.putFile(file);
      TaskSnapshot snapshot = await uploadTask;

      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      print('Error uploading voice message: $e');
      return '';
    }
  }

  Future<void> playVoiceMessage(String url) async {
    await _player.openPlayer();
    await _player.startPlayer(
      fromURI: url,
      codec: Codec.pcm16WAV,
    );
  }
}
