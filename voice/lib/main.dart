import 'package:flutter/material.dart';
import 'recording_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Recording App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const RecordingScreen(),
    );
  }
}