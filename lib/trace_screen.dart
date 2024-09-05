import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:dart_openai/dart_openai.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/tts_helper.dart';
import '../utils/trace_image_picker.dart';
import "../utils/user_messages.dart";
import "../utils/sketch_painter_v3.dart";
import '../utils/log.dart';
import "../ai_prompts/trace_prompts.dart";
import 'utils/child_skill_levels.dart';
import 'utils/api_key_manager.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';

// StatefulWidget to handle the Trace Screen UI and functionality.
class TraceScreen extends StatefulWidget {
  const TraceScreen({super.key});

  @override
  _TraceScreenState createState() => _TraceScreenState();
}

// State class for TraceScreen with additional functionality from SingleTickerProviderStateMixin for animations.
class _TraceScreenState extends State<TraceScreen>
    with SingleTickerProviderStateMixin {
  late String geminiApiKey;
  late String openaiApiKey;
  bool _isOpenaiAvailble = false;
  late String geminiEndpoint;

  List<SketchPath> paths = [];
  SketchPath? currentPath;
  bool showSketch = true; // Flag to toggle display of the sketch.
  bool isErasing = false; // Flag to toggle eraser mode.

  List<SketchPath> animatedPaths = []; // For animation
  bool _isAnimating = false;
  Timer? _timer;

  bool _isRecording = false;
  final int pointsPerFrame = 5;
  final double encodeWidth = 1080; // Define encode width.
  final double encodeHeight = 1920; // Define encode height.

  GlobalKey repaintBoundaryKey =
      GlobalKey(); // Key for the widget used to capture image.
  bool isLoading = false; // Flag to show a loading indicator.
  final double canvasWidth = 1024; // Canvas width.
  final double canvasHeight = 1920; // Canvas height.
  ui.Image? generatedImage; // Variable to hold the generated image.
  final List<double> _transparencyLevels = [
    0.0,
    0.5,
    1.0
  ]; // Transparency levels for display.
  int _currentTransparencyLevel = 2; // Current transparency level.

  double iconWidth = 80; // Icon width for buttons.
  double iconHeight = 80; // Icon height for buttons.

  final stt.SpeechToText _speechToText =
      stt.SpeechToText(); // Speech to text instance.
  bool _isListening = false; // Flag to check if listening.
  bool _speechEnabled = false; // Flag to check if speech is enabled.
  String _sttText = ""; // Text obtained from speech recognition.
  OverlayEntry? _overlayEntry; // Overlay entry for displaying speech text.

  Color selectedColor = Colors.black; // Default selected color for drawing.
  double currentStrokeWidth = 5.0; // Current stroke width for drawing.
  List<Color> colorPalette = [
    // Color palette for selection.
    Colors.black, Colors.red, Colors.green, Colors.blue, Colors.yellow
  ];
  AiMode _aiMode = AiMode.promptToImage; // Default AI mode.
  int learnerAge = 3; // Default learner age, used in prompts.

  late AnimationController _animationController; // Controller for animations.
  late Animation<double> _animation; // Animation details.

  late SharedPreferences prefs; // Shared preferences for storing data locally.
  String learnerName = "John"; // Default learner name.
  bool _isWelcoming = false; // Flag to check if welcome message is active.

  TtsHelper ttsHelper = TtsHelper(); // Text to speech helper instance.

  // Function to get prompt based on AI mode and user input.
  String getPrompt(AiMode mode, String userInput) {
    String skillsSummary = getSkillsTextForPrompt(learnerAge);
    return TracePrompts.getPrompt(mode, userInput, learnerAge, skillsSummary);
  }

  // Function to get a message to the user based on the AI mode.
  String getMessageToUser(AiMode mode) {
    switch (mode) {
      case AiMode.analysis:
        return "$learnerName I am looking at your tracing. Please wait";
      case AiMode.promptToImage:
        return "$learnerName Generating the picture. Please wait";
      default:
        return ""; // Handle any other cases or throw an error if needed
    }
  }

  // Function to get the appropriate library URL based on the learner's age.
  String getTraceLibrary() {
    const baseFolder =
        "https://storage.googleapis.com/storage/v1/b/doodle-dragon/o?prefix=tracing/";
    if (learnerAge < 4) {
      return "${baseFolder}alphabets-preschool/&delimiter=/";
    } else if (learnerAge < 6) {
      return "${baseFolder}alphabets-animals/&delimiter=/";
    } else {
      return "${baseFolder}coloring/&delimiter=/";
    }
  }

  // Initialize state, set up animations, and load settings.
  @override
  void initState() {
    super.initState();
    _initializeKeys();
    loadSettings();
    // OpenAI.apiKey = widget.openaiApiKey;
    _initSpeech();
    _initAnimation();
  }

  // Dispose resources when the widget is removed from the tree.
  @override
  void dispose() {
    if (_isListening) {
      _speechToText.stop();
    }
    _animationController.dispose();
    _removeOverlay();
    ttsHelper.stop();
    super.dispose();
  }

  Future<void> _initializeKeys() async {
    final apiKeyManager = await APIKeyManager.getInstance();
    setState(() {
      geminiApiKey = apiKeyManager.geminiApiKey;
      openaiApiKey = apiKeyManager.openaiApiKey;
      geminiEndpoint = apiKeyManager.geminiEndpoint;
    });
    OpenAI.apiKey = openaiApiKey; // Initialize OpenAI with the fetched API key.
    _isOpenaiAvailble = openaiApiKey.isNotEmpty;
  }

  // Load settings from shared preferences and welcome the user.
  Future<void> loadSettings() async {
    prefs = await SharedPreferences.getInstance();
    setState(() {
      learnerName = prefs.getString('learnerName') ?? "";
      learnerAge = prefs.getInt('learnerAge') ?? 3;
    });
    _welcomeMessage();
  }

  void _welcomeMessage() {
    _isWelcoming = true;
    ttsHelper.speak(userMessageTraceScreen);
  }

  void _stopWelcome() {
    _isWelcoming = false;
    ttsHelper.stop();
  }

  void _msgSelectPicture() {
    ttsHelper.speak("Select a picture to trace");
  }

  // Initial speech setup.
  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    setState(() {});
  }

  void _initAnimation() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(
          milliseconds: 500), // Duration of half cycle of oscillation
    );
    _animation = Tween<double>(
            begin: -0.523599, end: 0.523599) // +/- 30 degrees in radians
        .animate(CurvedAnimation(
            parent: _animationController, curve: Curves.easeInOut))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _animationController.reverse();
        } else if (status == AnimationStatus.dismissed) {
          _animationController.forward();
        }
      });
  }

  void _animateMic(bool listening) {
    if (listening) {
      _animationController.forward();
    } else {
      _animationController.stop();
    }
  }

  void toggleAnimation() {
    if (_isAnimating) {
      stopAnimation();
    } else {
      startAnimation();
    }
  }

  void startAnimation() {
    const duration =
        Duration(milliseconds: 10); // Control the speed of animation
    _timer?.cancel();

    // Clear existing animated paths and prepare for new animation
    animatedPaths = List.generate(paths.length,
        (index) => SketchPath(paths[index].color, paths[index].strokeWidth));
    int pathIndex = 0;
    int pointIndex = 0;

    // Start a periodic timer to animate the sketch
    _timer = Timer.periodic(duration, (timer) {
      if (pathIndex < paths.length) {
        if (pointIndex < paths[pathIndex].points.length) {
          setState(() {
            // Add point by point to the corresponding path in animatedPaths
            animatedPaths[pathIndex]
                .points
                .add(paths[pathIndex].points[pointIndex]);
          });
          pointIndex++;
        } else {
          // Move to the next path once all points of the current path are drawn
          pathIndex++;
          pointIndex = 0;
        }
      } else {
        // Stop the animation once all paths are completely drawn
        stopAnimation();
      }
    });
    _isAnimating = true;
  }

  void stopAnimation() {
    _timer?.cancel();
    setState(() {
      _isAnimating = false;
    });
  }

  void startRecording() async {
    if (!context.mounted) return;
    showLoadingDialog(context, "Saving Video...");

    // Initialize the video encoder with desired settings
    await FlutterQuickVideoEncoder.setup(
      width: encodeWidth.toInt(), //image.width,
      height: encodeHeight.toInt(), //image.height,
      filepath:
          '${(await getTemporaryDirectory()).path}/output_${DateTime.now().millisecondsSinceEpoch}.mp4',
      fps: 30, // Frame rate of the video
      videoBitrate: 1000000,
      profileLevel: ProfileLevel.any,
      audioBitrate: 0,
      audioChannels: 0,
      sampleRate: 0,
    );

    setState(() {
      _isRecording = true;
    });

    // Start capturing frames
    frameByFrameCapture();
  }

  // Request necessary permissions for storage.
  Future<void> requestPermissions() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      await Permission.storage.request();
    }
  }

  Future<void> saveVideoToGallery(String videoPath) async {
    if (!context.mounted) return;
    // For legacy mode
    await requestPermissions();

    try {
      // Save video to gallery
      await ImageGallerySaver.saveFile(videoPath);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image saved successfully')),
      );
    } catch (e) {
      // You can handle errors internally or rethrow them to be caught by catchError where this function is called
      Log.d("Error saving image: $e"); // Rethrow the error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save Image')),
      );
    }
  }

  void stopRecording() async {
    if (!context.mounted || !_isRecording) return;
    await FlutterQuickVideoEncoder.finish();
    // Finalize the video encoding
    String outputPath = FlutterQuickVideoEncoder.filepath;

    saveVideoToGallery(outputPath);
    Navigator.of(context).pop(); // Close the loading dialog

    setState(() {
      _isRecording = false;
    });
  }

  void frameByFrameCapture() async {
    RenderRepaintBoundary boundary = repaintBoundaryKey.currentContext!
        .findRenderObject() as RenderRepaintBoundary;
    List<SketchPath> recordPaths = List.generate(paths.length,
        (index) => SketchPath(paths[index].color, paths[index].strokeWidth));

    int pathIndex = 0;
    int pointIndex = 0;

    while (_isRecording && pathIndex < paths.length) {
      for (int i = 0; i < pointsPerFrame; ++i) {
        if (pointIndex < paths[pathIndex].points.length) {
          recordPaths[pathIndex]
              .points
              .add(paths[pathIndex].points[pointIndex]);
          pointIndex++;
        } else {
          pathIndex++;
          pointIndex = 0;
          if (pathIndex >= paths.length) {
            break;
          }
        }
      }
      Uint8List frameData = await generateFrame(
          recordPaths, boundary.size, Size(encodeWidth, encodeHeight));
      await FlutterQuickVideoEncoder.appendVideoFrame(frameData);
    }
    if (pathIndex >= paths.length) {
      stopRecording(); // Automatically stop when finished
    }
  }

  // Build the main UI for the trace screen.
  @override
  Widget build(BuildContext context) {
    bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        systemOverlayStyle: const SystemUiOverlayStyle(
          // Status bar color
          statusBarColor: Colors.deepPurple,

          // Status bar brightness (optional)
          statusBarIconBrightness: Brightness.dark, // For Android (dark icons)
          statusBarBrightness: Brightness.light, // For iOS (dark icons)
        ),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.red,
        toolbarHeight: 150,
        titleSpacing: 0,
        title: Column(
          children: <Widget>[
            const Text('Tracing',
                style: TextStyle(
                    color: Colors.white)), // Adjust text style as needed
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Flexible(
                  child: IconButton(
                    icon: Image.asset("assets/library.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                    color: Colors.white,
                    highlightColor: Colors.orange,
                    onPressed: _loadImageFromLibrary,
                    tooltip: 'Load Image',
                  ),
                ),
                _isOpenaiAvailble
                    ? Flexible(
                        child: IconButton(
                          icon: Image.asset("assets/imagen_square.png",
                              width: iconWidth,
                              height: iconHeight,
                              fit: BoxFit.fill),
                          color: Colors.white,
                          highlightColor: Colors.orange,
                          onPressed: () {
                            setState(() {
                              _aiMode = AiMode.promptToImage;
                            });
                            _listen();
                          },
                          tooltip: 'Voice to Image',
                        ),
                      )
                    : Container(),
                Flexible(
                  child: IconButton(
                    icon: Image.asset("assets/share.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                    color: Colors.white,
                    highlightColor: Colors.orange,
                    onPressed: shareCanvas,
                    tooltip: 'Share Image',
                  ),
                ),
                Flexible(
                  child: PopupMenuButton<String>(
                    icon: Image.asset("assets/delete.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                    onSelected:
                        handleMenuItemClick, // Handling the menu item selection
                    itemBuilder: (BuildContext context) =>
                        <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'animate',
                        child: Row(
                          children: <Widget>[
                            Icon(_isAnimating ? Icons.stop : Icons.play_arrow,
                                color: Colors.blue),
                            SizedBox(width: 10), // Space between icon and text
                            Text('Animate'),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'record',
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.videocam),
                            SizedBox(width: 10),
                            Text('Record'),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'transparency',
                        child: Row(
                          children: <Widget>[
                            Image.asset("assets/transparency.png",
                                width: 20, height: 20),
                            SizedBox(width: 10),
                            Text('Transparency'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: Row(
        // Use Row for main layout
        children: [
          Expanded(
            // Canvas takes the available space
            child: buildBody(),
          ),
        ],
      ),
      bottomNavigationBar: isLandscape
          ? null
          : BottomAppBar(
              color: Colors.lightBlue,
              height: 180,
              child: controlPanelPortrait(),
            ),
      floatingActionButton: _isListening
          ? AnimatedBuilder(
              animation: _animation,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _animation.value,
                  child: FloatingActionButton(
                    onPressed: _completeListening,
                    backgroundColor: Colors.transparent,
                    shape: const CircleBorder(),
                    child: Image.asset('assets/doodle_mic_on.png'),
                  ),
                );
              },
            )
          : null,
    );
  }

  void handleMenuItemClick(String value) {
    Log.d("Selected: $value");
    // Execute different actions based on the value selected
    switch (value) {
      case 'animate':
        toggleAnimation();
        Log.d('Animation');
        // Navigate to the profile page or show profile info
        break;
      case 'record':
        if (!_isRecording) {
          startRecording();
        } else {
          stopRecording();
        }
        Log.d('Record');
        // Open settings dialog or navigate to settings page
        break;
      case 'transparency':
        if (generatedImage != null) {
          setState(() {
            _currentTransparencyLevel =
                (_currentTransparencyLevel + 1) % _transparencyLevels.length;
          });
        } else {
          _msgSelectPicture();
        }
        Log.d('Transparency');
        // Open settings dialog or navigate to settings page
        break;
    }
  }

  Widget buildBody() => Column(
        children: [
          Expanded(
            child: GestureDetector(
              onPanUpdate: (details) {
                if (_isWelcoming) _stopWelcome();
                if (generatedImage != null) {
                  setState(() {
                    RenderBox renderBox =
                        context.findRenderObject() as RenderBox;
                    double appBarHeight = 150; //AppBar().toolbarHeight!;
                    double topPadding = MediaQuery.of(context).padding.top;

                    Offset adjustedPosition = details.globalPosition -
                        Offset(0, appBarHeight + topPadding);
                    Offset localPosition =
                        renderBox.globalToLocal(adjustedPosition);

                    const double maxDistanceThreshold = 20.0;

                    if (!isErasing) {
                      if (currentPath == null) {
                        currentPath =
                            SketchPath(selectedColor, currentStrokeWidth);
                        paths.add(currentPath!);
                      }
                      if (currentPath!.points.isEmpty ||
                          (localPosition - currentPath!.points.last).distance <=
                              maxDistanceThreshold) {
                        currentPath!.points.add(localPosition);
                      }
                    } else {
                      paths = paths.where((path) {
                        return !path.points.any(
                            (point) => (point - localPosition).distance <= 20);
                      }).toList();
                    }
                  });
                }
              },
              onPanEnd: (details) {
                if (generatedImage != null) {
                  currentPath = null;
                }
              },
              child: RepaintBoundary(
                key: repaintBoundaryKey,
                child: CustomPaint(
                  painter: SketchPainter(
                      _isAnimating ? animatedPaths : paths,
                      showSketch,
                      generatedImage,
                      _transparencyLevels[_currentTransparencyLevel]),
                  child: Container(),
                ),
              ),
            ),
          ),
        ],
      );

  Widget controlPanelPortrait() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: PopupMenuButton<Color>(
            icon: Image.asset("assets/brush.png",
                width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            itemBuilder: (BuildContext context) {
              return colorPalette.map((Color color) {
                return PopupMenuItem<Color>(
                  value: color,
                  child: Container(
                    width: 24,
                    height: 24,
                    color: color,
                  ),
                );
              }).toList();
            },
            onSelected: (Color color) {
              selectedColor = color;
              setState(() {
                isErasing = false;
                showSketch = true;
              });
            },
            enabled: generatedImage != null,
          ),
        ),
        Flexible(
          child: PopupMenuButton<double>(
            icon: Image.asset("assets/brush_size.png",
                width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            itemBuilder: (BuildContext context) {
              return [1.0, 2.0, 5.0, 10.0, 20.0, 40.0].map((double size) {
                return PopupMenuItem<double>(
                  value: size,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width:
                            40, // This width is proportional to the brush size
                        height:
                            size, // Fixed height for the visual representation
                        color: Colors.black, // Change the color if needed
                      ),
                    ],
                  ),
                );
              }).toList();
            },
            onSelected: (double size) {
              setState(() {
                currentStrokeWidth = size;
                isErasing = false; // Ensure the eraser is not active
              });
            },
            enabled: generatedImage != null,
          ),
        ),
        Flexible(
          child: IconButton(
            icon: isErasing
                ? Image.asset("assets/eraser.png",
                    width: iconWidth, height: iconHeight, fit: BoxFit.fill)
                : Image.asset("assets/eraser.png",
                    width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            color: Colors.white,
            highlightColor: Colors.orange,
            onPressed: generatedImage != null
                ? () {
                    setState(() {
                      isErasing = true;
                    });
                  }
                : _msgSelectPicture,
            tooltip: 'Erase',
          ),
        ),
        Flexible(
          child: IconButton(
            icon: Image.asset("assets/analysis.png",
                width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            color: Colors.white,
            highlightColor: Colors.orange,
            onPressed: generatedImage != null
                ? () {
                    takeSnapshotAndAnalyze(context, AiMode.analysis, "");
                  }
                : _msgSelectPicture,
            tooltip: 'Feedback',
          ),
        ),
      ],
    );
  }

  // Check if the content generated by AI is safe for display.
  bool isContentSafe(Map<String, dynamic> candidate) {
    List<dynamic> safetyRatings = candidate['safetyRatings'];
    return safetyRatings
        .every((rating) => rating['probability'] == 'NEGLIGIBLE');
  }

  // Decode and set the image from byte data.
  void decodeAndSetImage(Uint8List imageData) async {
    final codec = await ui.instantiateImageCodec(imageData);
    final frame = await codec.getNextFrame();
    setState(() {
      generatedImage = frame.image;
    });
  }

  // Helper function to download file from URL
  Future<File> _downloadFile(String url, String fileName) async {
    var response = await http.get(Uri.parse(url));
    var bytes = response.bodyBytes;
    String dir = (await getApplicationDocumentsDirectory()).path;
    File file = File('$dir/$fileName');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> _loadImageFromLibrary() async {
    if (_isWelcoming) _stopWelcome();
    if (_isListening) _abortListening();

    Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => TraceImagePicker(
            onSelect: (String imagePath) async {
              if (imagePath.startsWith('http') ||
                  imagePath.startsWith('https')) {
                // If the selected image is from a URL
                File imageFile =
                    await _downloadFile(imagePath, 'selected_image.png');
                _setImage(imageFile);
              } else {
                // If the selected image is from the local gallery
                File localImageFile = File(imagePath);
                _setImage(localImageFile);
              }
            },
            folder: getTraceLibrary())));
  }

  void _setImage(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    decodeAndSetImage(bytes);
  }

  // Method to handle image sharing.
  void shareCanvas() async {
    try {
      RenderRepaintBoundary boundary = repaintBoundaryKey.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final directory = (await getApplicationDocumentsDirectory()).path;
      File imgFile = File('$directory/sketch.png');
      await imgFile.writeAsBytes(pngBytes);

      // Using Share.shareXFiles from share_plus
      await Share.shareXFiles([XFile(imgFile.path)],
          text: 'Check out my sketch!');
    } catch (e) {
      Log.d('Error sharing canvas: $e');
    }
  }

  // Take a snapshot of the current drawing and analyze it using Gemini.
  void takeSnapshotAndAnalyze(
      BuildContext context, AiMode selectedMode, String userInput) async {
    if (generatedImage == null) {
      ttsHelper.speak("Create or select a picture for tracing");
      return;
    }
    if (paths.isEmpty) {
      ttsHelper.speak("Trace the picture and try again");
      return;
    }

    setState(() =>
        isLoading = true); // Set loading to true when starting the analysis

    ttsHelper.speak(getMessageToUser(selectedMode));

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) => const Center(
          child: CircularProgressIndicator()), // Show a loading spinner
    );
    try {
      RenderRepaintBoundary boundary = repaintBoundaryKey.currentContext!
          .findRenderObject()! as RenderRepaintBoundary;

      Size size = boundary.size;
      double width = size.width;
      double height = size.height;

      ui.Image image = await drawPointsToImage(paths, size);
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      ByteData? byteDataBase =
          await generatedImage!.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytesBase = byteDataBase!.buffer.asUint8List();

      String base64String = base64Encode(pngBytes);
      String base64StringBase = base64Encode(pngBytesBase);

      String promptText =
          getPrompt(selectedMode, userInput); //prompts[selectedMode]!;
      String jsonBody = jsonEncode({
        "contents": [
          {
            "parts": [
              {"text": promptText},
              {
                "inlineData": {"mimeType": "image/png", "data": base64String}
              },
              {
                "inlineData": {
                  "mimeType": "image/png",
                  "data": base64StringBase
                }
              }
            ]
          }
        ]
      });

      var response = await http.post(
        Uri.parse('$geminiEndpoint?key=$geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonBody,
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> decodedResponse = jsonDecode(response.body);
        Map<String, dynamic> candidate = decodedResponse['candidates'][0];
        if (isContentSafe(candidate)) {
          String responseText = candidate['content']['parts'][0]['text'];
          Log.d("Response from model: $responseText");
          if (selectedMode == AiMode.analysis) {
            ttsHelper.speak(responseText);
          }
        } else {
          Log.d("Content is not safe for children.");
          ttsHelper.speak("Sorry, content issue. Try again");
        }
      } else {
        Log.d("Failed to get response: ${response.body}");
        ttsHelper.speak("Sorry, network issue. Try again");
      }
    } finally {
      setState(() => isLoading = false);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void generatePicture(
      BuildContext context, AiMode selectedMode, userInput) async {
    setState(() =>
        isLoading = true); // Set loading to true when starting the analysis

    ttsHelper.speak(getMessageToUser(selectedMode));

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) => const Center(
          child: CircularProgressIndicator()), // Show a loading spinner
    );
    try {
      String promptText = getPrompt(selectedMode, userInput);
      String jsonBody = jsonEncode({
        "contents": [
          {
            "parts": [
              {"text": promptText},
            ]
          }
        ]
      });

      var response = await http.post(
        Uri.parse('$geminiEndpoint?key=$geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonBody,
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> decodedResponse = jsonDecode(response.body);
        Map<String, dynamic> candidate = decodedResponse['candidates'][0];
        if (isContentSafe(candidate)) {
          String responseText = candidate['content']['parts'][0]['text'];
          Log.d("Response from model: $responseText");
          // Generate an image from a text prompt
          try {
            final imageResponse = await OpenAI.instance.image.create(
              model: 'dall-e-2',
              prompt: responseText,
              n: 1,
              size: OpenAIImageSize.size1024,
              responseFormat: OpenAIImageResponseFormat.b64Json,
            );

            if (imageResponse.data.isNotEmpty) {
              setState(() {
                Uint8List bytesImage = base64Decode(imageResponse.data.first
                    .b64Json!); // Assuming URL points to a base64 image string
                decodeAndSetImage(bytesImage!);
              });
            } else {
              Log.d('No image returned from the API');
            }
          } catch (e) {
            Log.d('Error calling OpenAI image generation API: $e');
          }
        } else {
          Log.d("Content is not safe for children.");
          ttsHelper.speak("Sorry, content issue. Try again");
        }
      } else {
        Log.d("Failed to get response: ${response.body}");
        ttsHelper.speak("Sorry, network issue. Try again");
      }
    } finally {
      setState(() => isLoading = false);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _listen() async {
    if (_isWelcoming) _stopWelcome();
    if (_isListening) await _abortListening();

    if (!_isListening) {
      await ttsHelper.speak("Can you tell me what you'd like to draw?");
      _animateMic(true);
      if (_speechEnabled) {
        setState(() => _isListening = true);
        _speechToText.listen(
          onResult: (result) {
            setState(() {
              _sttText = result.recognizedWords;
            });
            _overlayEntry?.markNeedsBuild(); // Rebuild overlay with new text
          },
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 5),
        );
        if (mounted) {
          _showOverlay(context);
        }
      }
    }
  }

  void _completeListening() async {
    if (_isListening) {
      setState(() => _isListening = false);
      _speechToText.stop();
      _removeOverlay();
      if (_sttText.isNotEmpty) {
        generatePicture(context, AiMode.promptToImage, _sttText);
        setState(() {
          _sttText = "";
        });
      }
    }
  }

  Future<void> _abortListening() async {
    if (_isListening) {
      setState(() => _isListening = false);
      _speechToText.stop();
      _removeOverlay();
    }
  }

  void _showOverlay(BuildContext context) {
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 200,
        right: 80,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _sttText,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context)?.insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void showLoadingDialog(BuildContext context, String loadingMessage) {
    showDialog(
      context: context,
      barrierDismissible:
          false, // User must not dismiss the dialog by tapping outside of it
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 20),
                Text(loadingMessage),
              ],
            ),
          ),
        );
      },
    );
  }
}
