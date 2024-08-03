import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'log.dart';

class CameraCapture extends StatefulWidget {
  const CameraCapture({Key? key}) : super(key: key);

  @override
  _CameraCaptureState createState() => _CameraCaptureState();
}

class _CameraCaptureState extends State<CameraCapture> {
  List<CameraDescription> cameras = [];
  CameraController? _cameraController;
  Future<void>? _initializeControllerFuture;
  int selectedCameraIndex = 0;

  @override
  void initState() {
    super.initState();
    _initCamera(selectedCameraIndex);
  }

  void _initCamera(int cameraIndex) async {
    cameras = await availableCameras();
    if (cameras.isEmpty) {
      Log.d('No cameras are available');
      return;
    }
    if (cameraIndex >= cameras.length) {
      cameraIndex = 0; // reset to first camera if specified index is out of range
    }
    _cameraController = CameraController(
      cameras[cameraIndex],
      ResolutionPreset.medium,
    );
    _initializeControllerFuture = _cameraController!.initialize().then((_) {
      if (!mounted) return;
      setState(() {}); // refresh the UI when camera is initialized
    });
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    try {
      await _initializeControllerFuture;
      final image = await _cameraController!.takePicture();
      Navigator.pop(context, image); // Pass the image back to the previous screen
    } catch (e) {
      Log.d('Error taking picture: $e');
    }
  }

  void _switchCamera() {
    selectedCameraIndex++;
    if (selectedCameraIndex >= cameras.length) {
      selectedCameraIndex = 0; // cycle back to first camera
    }
    _initCamera(selectedCameraIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Take a Picture'),
        backgroundColor: Colors.lightBlue,
      ),
      body: FutureBuilder<void>(
        future: _initializeControllerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            // If the Future is complete, display the preview.
            return CameraPreview(_cameraController!);
          } else {
            // Otherwise, display a loading indicator.
            return const Center(child: CircularProgressIndicator());
          }
        },
      ),

      bottomNavigationBar: BottomAppBar(
        color: Colors.blue, // Set the color of the bottom area here
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[
            IconButton(
              icon: Icon(Icons.photo_camera),
              onPressed: _takePicture,
            ),
            IconButton(
              icon: Icon(Icons.switch_camera),
              onPressed: cameras.length > 1 ? _switchCamera : null, // only enable if multiple cameras are available
            ),
          ],
        ),
      ),
    );
  }
}
