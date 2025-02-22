import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'custom_recording_button.dart';
import 'custom_recording_wave_widget.dart';

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  bool isRecording = false;
  late final AudioRecorder _audioRecorder;
  String? _audioPath;
  // Queue to track pending uploads
  final List<String> _uploadQueue = [];

  @override
  void initState() {
    _audioRecorder = AudioRecorder();
    super.initState();
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<String> _generateNextFileName() async {
    // Get the app's documents directory.
    final appDir = await getApplicationDocumentsDirectory();

    // Construct the path to the "uploads" folder.
    final uploadsDir = Directory(path.join(appDir.path, 'uploads'));

    // Ensure the directory exists.
    if (!await uploadsDir.exists()) {
      await uploadsDir.create(recursive: true);
    }

    // List all files in the directory.
    final List<FileSystemEntity> entities = await uploadsDir.list().toList();

    // Extract numeric parts of file names and find the highest number.
    int maxNumber = 0;
    final RegExp filePattern = RegExp(r'audio_(\d+)\.wav');

    for (var entity in entities) {
      if (entity is File) {
        final fileName = path.basename(entity.path);
        final match = filePattern.firstMatch(fileName);
        if (match != null) {
          final int num = int.tryParse(match.group(1) ?? '0') ?? 0;
          if (num > maxNumber) {
            maxNumber = num;
          }
        }
      }
    }

    // Generate the next file name.
    return 'audio_${maxNumber + 1}.wav';
  }

  Future<void> _startRecording() async {
    try {
    debugPrint('=========>>>>>>>>>>> RECORDING!!!!!!!!!!!!!!! <<<<<<===========');

    // Generate a new file name
    String fileName = await _generateNextFileName();
    
    // Get the full file path
    final appDir = await getApplicationDocumentsDirectory();
    String filePath = path.join(appDir.path, 'uploads', fileName);
    debugPrint('filepath $filePath');

    await _audioRecorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
      ),
      path: filePath,
    );
  } catch (e) {
    debugPrint('ERROR WHILE RECORDING: $e');
  }
}

  // Background upload processor
  Future<void> _processUploads() async {
    while (_uploadQueue.isNotEmpty) {
      final String audioPath = _uploadQueue.first;
      try {
        await _uploadAudio(audioPath);
        _uploadQueue.removeAt(0); // Remove after successful upload
      } catch (e) {
        debugPrint('Upload failed for $audioPath: $e');
        // Optional: Implement retry logic here
        await Future.delayed(const Duration(seconds: 5)); // Wait before retry
      }
    }
  }


  Future<void> _uploadAudio(String audioPath) async {
    try {
      final uri = Uri.parse('http://192.168.29.157:5000/upload-audio');  // Use this URL for Android emulator
      // For iOS simulator, use: 'http://localhost:5000/upload-audio'
      // For real devices, use your computer's IP address: 'http://192.168.1.xxx:5000/upload-audio'
      
      final request = http.MultipartRequest('POST', uri);
      final file = await http.MultipartFile.fromPath(
        'audio',
        audioPath,
      );
      
      request.files.add(file);
      
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        debugPrint('Upload successful: $responseBody');
      } else {
        debugPrint('Upload failed: $responseBody');
      }
    } catch (e) {
      debugPrint('Error uploading audio: $e');
    }
  } 

  Future<void> _stopRecording() async {
    try {
      String? path = await _audioRecorder.stop();
      setState(() {
        _audioPath = path!;
      });

      // Update UI state immediately after stopping the recording
      setState(() {
      _audioPath = path!;
      isRecording = false;  // Add this line if you want to update here instead
      });

      debugPrint('=========>>>>>> PATH: $_audioPath <<<<<<===========');
      
      // Upload the audio file after recording stops
     if (_audioPath != null) {
        _uploadQueue.add(_audioPath!);
        // Start processing uploads in the background
        _processUploads().catchError((e) => debugPrint('Upload processor error: $e'));
      }
    } catch (e) {
      debugPrint('ERROR WHILE STOP RECORDING: $e');
    }
  } 

  void _record() async {
    if (isRecording == false) {
      final status = await Permission.microphone.request();

      if (status == PermissionStatus.granted) {
        setState(() {
          isRecording = true;
        });
        await _startRecording();
        debugPrint('Recording started: done');
      } else if (status == PermissionStatus.permanentlyDenied) {
        debugPrint('Permission permanently denied');
        // TODO: handle this case (e.g., show a dialog or navigate to settings)
      }
    } else {
      await _stopRecording();

      //setState(() {
      //  isRecording = false;
      //});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          if (isRecording) const CustomRecordingWaveWidget(),
          const SizedBox(height: 16),
          CustomRecordingButton(
            isRecording: isRecording,
            onPressed: _record,
          ),
        ],
      ),
    );
  }
}

