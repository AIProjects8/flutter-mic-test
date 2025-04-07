import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    await dotenv.load(fileName: ".env");
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice to Text',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const VoiceToTextScreen(),
    );
  }
}

class VoiceToTextScreen extends StatefulWidget {
  const VoiceToTextScreen({super.key});

  @override
  State<VoiceToTextScreen> createState() => _VoiceToTextScreenState();
}

class _VoiceToTextScreenState extends State<VoiceToTextScreen> {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  bool _isRecording = false;
  String _transcribedText = '';
  String? _tempPath;
  String _statusMessage = 'Ready to record';
  String? _apiKey;

  @override
  void initState() {
    super.initState();
    _initRecorder();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    if (kIsWeb) {
      // For web, you'll need to set this value in your web/index.html
      // or through some other secure method
      _apiKey = const String.fromEnvironment('OPENAI_API_KEY');
    } else {
      _apiKey = dotenv.env['OPENAI_API_KEY'];
    }
    
    if (_apiKey == null || _apiKey!.isEmpty) {
      setState(() {
        _statusMessage = 'OpenAI API key not found. Please set OPENAI_API_KEY environment variable.';
      });
    }
  }

  Future<void> _initRecorder() async {
    try {
      if (!kIsWeb) {
        final status = await Permission.microphone.request();
        if (status != PermissionStatus.granted) {
          setState(() {
            _statusMessage = 'Microphone permission not granted';
          });
          return;
        }
      }
      await _recorder.openRecorder();
      setState(() {
        _statusMessage = 'Ready to record';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error initializing recorder: $e';
      });
    }
  }

  Future<void> _startRecording() async {
    try {
      if (kIsWeb) {
        _tempPath = 'temp_audio.m4a';
      } else {
        final directory = await getTemporaryDirectory();
        _tempPath = '${directory.path}/temp_audio.m4a';
      }
      
      await _recorder.startRecorder(
        toFile: _tempPath,
        codec: Codec.aacADTS,
      );
      setState(() {
        _isRecording = true;
        _statusMessage = 'Recording...';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'Error starting recording: $e';
      });
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _recorder.stopRecorder();
      setState(() {
        _isRecording = false;
        _statusMessage = 'Processing...';
      });
      await _transcribeAudio();
    } catch (e) {
      setState(() {
        _statusMessage = 'Error stopping recording: $e';
      });
    }
  }

  Future<void> _transcribeAudio() async {
    if (_tempPath == null) return;

    try {
      final file = File(_tempPath!);
      if (!await file.exists()) {
        setState(() {
          _statusMessage = 'No audio file found';
        });
        return;
      }

      final bytes = await file.readAsBytes();
      final base64Audio = base64Encode(bytes);

      if (_apiKey == null || _apiKey!.isEmpty) {
        setState(() {
          _statusMessage = 'OpenAI API key not found';
        });
        return;
      }

      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/audio/transcriptions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: {
          'file': base64Audio,
          'model': 'whisper-1',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _transcribedText = response.body;
          _statusMessage = 'Transcription complete';
        });
      } else {
        setState(() {
          _statusMessage = 'Error transcribing audio: ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'Error during transcription: $e';
      });
    }
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice to Text'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              readOnly: true,
              maxLines: 5,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Transcribed text will appear here',
              ),
              controller: TextEditingController(text: _transcribedText),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTapDown: (_) => _startRecording(),
              onTapUp: (_) => _stopRecording(),
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording ? Colors.red : Colors.blue,
                ),
                child: Icon(
                  _isRecording ? Icons.mic : Icons.mic_none,
                  color: Colors.white,
                  size: 50,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _statusMessage,
              style: const TextStyle(fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
} 