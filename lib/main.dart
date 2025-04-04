import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  final firstCamera = cameras.first;

  runApp(MaterialApp(
    home: VideoRecorderScreen(camera: firstCamera),
    debugShowCheckedModeBanner: false,
  ));
}

class VideoRecorderScreen extends StatefulWidget {
  final CameraDescription camera;
  const VideoRecorderScreen({required this.camera});

  @override
  State<VideoRecorderScreen> createState() => _VideoRecorderScreenState();
}

class _VideoRecorderScreenState extends State<VideoRecorderScreen> {
  late CameraController _controller;
  bool _isRecording = false;
  String? _videoPath;

  @override
  void initState() {
    super.initState();
    print("[INIT] Initializing camera...");
    _initializeCamera();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    print("[PERMISSION] Requesting permissions...");
    await Permission.camera.request();
    await Permission.microphone.request();
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
    print("[PERMISSION] Permissions granted!");
  }

  Future<void> _initializeCamera() async {
    print("[CAMERA] Initializing...");
    _controller = CameraController(widget.camera, ResolutionPreset.high);
    await _controller.initialize();
    setState(() {});
    print("[CAMERA] Camera initialized successfully!");
  }

  Future<void> _startRecording() async {
    print("[RECORD] Starting video recording...");
    await _controller.startVideoRecording();
    setState(() {
      _isRecording = true;
      _videoPath = null;
    });
    print("[RECORD] Recording started!");
  }

  Future<void> _stopRecording() async {
    print("[RECORD] Stopping video recording...");
    final file = await _controller.stopVideoRecording();
    setState(() {
      _isRecording = false;
      _videoPath = file.path;
    });
    print("[RECORD] Recording stopped! Video saved at: $_videoPath");

    if (_videoPath != null) {
      print("[UPLOAD] Sending video to API...");
      await _sendVideoToApi(File(_videoPath!));
    } else {
      print("[ERROR] Recording failed. No video file found.");
      _showSnackBar("Recording failed. No video file found.");
    }
  }

  Future<void> _sendVideoToApi(File videoFile) async {
    final uri = Uri.parse('http://192.168.47.202:8000/process-video/'); // Update with your server IP
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('file', videoFile.path));

    print("[UPLOAD] Uploading video...");
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    print("[UPLOAD] Server response received!");

    final dir = Directory('/storage/emulated/0/Download'); // Downloads folder
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    if (response.statusCode == 200 && response.headers['content-type'] == 'video/mp4') {
      final filePath = path.join(dir.path, 'blurred_video_$timestamp.mp4');
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      print("[RESULT] NSFW detected! Blurred video saved: $filePath");
      _showSnackBar('NSFW detected! Blurred video saved to Downloads.');
    } else {
      final filePath = path.join(dir.path, 'original_video_$timestamp.mp4');
      await videoFile.copy(filePath);
      print("[RESULT] No NSFW content. Original video saved: $filePath");
      _showSnackBar('No NSFW content. Original video saved to Downloads.');
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    print("[UI] Snackbar shown: $message");
  }

  @override
  void dispose() {
    print("[DISPOSE] Disposing camera controller...");
    _controller.dispose();
    super.dispose();
    print("[DISPOSE] Camera controller disposed.");
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('NSFW Video Filter')),
      body: Stack(
        children: [
          CameraPreview(_controller),
          Positioned(
            bottom: 30,
            left: MediaQuery.of(context).size.width / 2 - 35,
            child: FloatingActionButton(
              onPressed: _isRecording ? _stopRecording : _startRecording,
              backgroundColor: _isRecording ? Colors.red : Colors.green,
              child: Icon(_isRecording ? Icons.stop : Icons.videocam),
            ),
          ),
        ],
      ),
    );
  }
}
