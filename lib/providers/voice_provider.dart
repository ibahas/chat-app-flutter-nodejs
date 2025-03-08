import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart' as dio;

class VoiceMessageProvider with ChangeNotifier {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isRecording = false;
  bool _isPlaying = false;
  String? _recordedFilePath;
  String? _uploadedVoiceUrl;
  String? _playbackUrl;

  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  String? get recordedFilePath => _recordedFilePath;
  String? get uploadedVoiceUrl => _uploadedVoiceUrl;
  String? get playbackUrl => _playbackUrl;

  VoiceMessageProvider() {
    _init();
  }

  Future<void> _init() async {
    await _recorder.openRecorder();
    await _player.openPlayer();
  }

  Future<void> startRecording() async {
    // Request microphone permission
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      throw RecordingPermissionException('Microphone permission not granted');
    }

    Directory appDocDir = await getApplicationDocumentsDirectory();
    String path = "${appDocDir.path}/voice_message.aac";

    try {
      await _recorder.startRecorder(
        toFile: path,
        codec: Codec.aacADTS,
      );
      _recordedFilePath = path;
      _isRecording = true;
      notifyListeners();
    } catch (e) {
      print('Error starting recording: $e');
    }
  }

  Future<void> stopRecording() async {
    try {
      await _recorder.stopRecorder();
      _isRecording = false;
      notifyListeners();
    } catch (e) {
      print('Error stopping recording: $e');
    }
  }

  Future<void> uploadVoiceMessage() async {
    if (_recordedFilePath == null) return;

    try {
      dio.Dio dioClient = dio.Dio();
      dioClient.options.headers['Content-Type'] = 'multipart/form-data';

      dio.FormData formData = dio.FormData.fromMap({
        'file': await dio.MultipartFile.fromFile(_recordedFilePath!,
            filename: 'voice_message.aac'),
      });

      dio.Response response = await dioClient.post(
        'http://localhost:3000/upload', // Replace with your upload endpoint
        data: formData,
      );

      if (response.statusCode == 200) {
        _uploadedVoiceUrl =
            response.data['url']; // Assuming the server returns a URL
        notifyListeners();
      } else {
        print('Upload failed with status: ${response.statusCode}');
      }
    } catch (e) {
      print('Error uploading voice message: $e');
    }
  }

  Future<void> playVoiceMessage(String url) async {
    try {
      if (_isPlaying) {
        await _player.stopPlayer();
        _isPlaying = false;
        notifyListeners();
        return;
      }

      await _player.startPlayer(
        fromURI: url,
        codec: Codec.aacADTS,
        whenFinished: () {
          _isPlaying = false;
          notifyListeners();
        },
      );
      _playbackUrl = url;
      _isPlaying = true;
      notifyListeners();
    } catch (e) {
      print('Error playing voice message: $e');
    }
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    _player.closePlayer();
    super.dispose();
  }

  initialize() {}
}
