import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'custom_recording_button.dart';
import 'custom_recording_wave_widget.dart';

//String host = "192.168.29.157";
String port = "80";
String host = "https://chatbot-flutter.replit.app";

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key});

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  bool isRecording = false;
  bool isUploading = false; // New state for upload status
  late final AudioRecorder _audioRecorder;
  String? _audioPath;
  final List<String> _uploadQueue = [];

  final TextEditingController _messageController = TextEditingController();
  final List<ChatMessage> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    _audioRecorder = AudioRecorder();
    super.initState();
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    _messageController.dispose();
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
      debugPrint(
          '=========>>>>>>>>>>> RECORDING!!!!!!!!!!!!!!! <<<<<<===========');

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

  Future<void> _uploadAudio(String audioPath) async {
    setState(() {
      isUploading = true;
      // Add system message about upload
      _messages.add(ChatMessage(
        text: "Storing the audio, please wait ...",
        isUser: false,
        isSystem: true,
      ));
    });

    try {
      final uri = Uri.parse('$host/upload-audio');

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
        setState(() {
          // Update the system message to indicate completion
          _messages.add(ChatMessage(
            text: "Audio processed successfully!",
            isUser: false,
            isSystem: true,
          ));
        });
      } else {
        debugPrint('Upload failed: $responseBody');
        setState(() {
          _messages.add(ChatMessage(
            text: "Failed to process audio. Please try again.",
            isUser: false,
            isSystem: true,
          ));
        });
      }
    } catch (e) {
      debugPrint('Error uploading audio: $e');
      setState(() {
        _messages.add(ChatMessage(
          text: "Error processing audio: $e",
          isUser: false,
          isSystem: true,
        ));
      });
    } finally {
      setState(() {
        isUploading = false;
      });
    }
  }

  Future<void> _processUploads() async {
    while (_uploadQueue.isNotEmpty) {
      final String audioPath = _uploadQueue.first;
      try {
        await _uploadAudio(audioPath);
        _uploadQueue.removeAt(0);
      } catch (e) {
        debugPrint('Upload failed for $audioPath: $e');
        await Future.delayed(const Duration(seconds: 5));
      }
    }
  }

  Future<void> _stopRecording() async {
    try {
      String? path = await _audioRecorder.stop();
      setState(() {
        _audioPath = path!;
        isRecording = false;
      });

      debugPrint('=========>>>>>> PATH: $_audioPath <<<<<<===========');

      if (_audioPath != null) {
        _uploadQueue.add(_audioPath!);
        _processUploads()
            .catchError((e) => debugPrint('Upload processor error: $e'));
      }
    } catch (e) {
      debugPrint('ERROR WHILE STOP RECORDING: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final String message = _messageController.text;
    setState(() {
      _messages.add(ChatMessage(
        text: message,
        isUser: true,
      ));
      _messageController.clear();
      _isLoading = true;
    });

    try {
      debugPrint('=========>>>>>> SENDING MESSAGE: $message <<<<<<===========');
      final response = await http.get(
        Uri.parse('$host/query-memory').replace(
          queryParameters: {
            'query': message,
            'user_id': 'default_user',
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _messages.add(ChatMessage(
            text: data['assistant_response'],
            isUser: false,
          ));
        });
      } else {
        setState(() {
          _messages.add(ChatMessage(
            text: 'Failed to get response. Please try again.',
            isUser: false,
          ));
        });
      }
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          text: 'Error: $e',
          isUser: false,
        ));
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
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
      body: SafeArea(
        // Added SafeArea
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16.0), // Added bottom padding
          child: Column(
            children: [
              const SizedBox(height: 32), // Added top spacing
              Expanded(
                flex: 1, // Reduced flex from 2 to 1
                child: Column(
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
              ),
              Expanded(
                flex: 2, // Reduced flex from 3 to 2
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message =
                              _messages[_messages.length - 1 - index];
                          return ChatBubble(message: message);
                        },
                      ),
                    ),
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8.0,
                        vertical: 4.0, // Reduced vertical padding
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              decoration: const InputDecoration(
                                hintText: 'Type your message...',
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical:
                                      8, // Made input field slightly smaller
                                ),
                              ),
                              enabled: !isUploading,
                              onSubmitted: (_) =>
                                  !isUploading ? _sendMessage() : null,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.send),
                            onPressed: isUploading ? null : _sendMessage,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isSystem; // New field to identify system messages

  ChatMessage({
    required this.text,
    required this.isUser,
    this.isSystem = false,
  });
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: message.isSystem
              ? Colors.orange[100] // System messages get a distinct color
              : message.isUser
                  ? Colors.blue
                  : Colors.grey[300],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message.text,
          style: TextStyle(
            color: message.isUser ? Colors.white : Colors.black,
            fontStyle: message.isSystem ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
  }
}
