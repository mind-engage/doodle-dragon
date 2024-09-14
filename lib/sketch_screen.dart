// Import necessary Dart and Flutter packages for the SketchScreen functionality.
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:dart_openai/dart_openai.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/tts_helper.dart';
import '../utils/user_messages.dart';
import '../utils/sketch_painter_v3.dart';
import '../utils/log.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';
import "ai_prompts/sketch_prompts.dart";
import 'utils/child_skill_levels.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';
import 'utils/gemini_proxy.dart'; // Import GeminiProxy
import 'utils/openai_proxy.dart'; // Import GeminiProxy

// Define a StatefulWidget for handling the sketch screen with necessary dependencies.
class SketchScreen extends StatefulWidget {
  final GeminiProxy geminiProxy;
  final OpenAiProxy? openaiProxy;

  // Constructor for the SketchScreen which takes required API keys.
  const SketchScreen({super.key, required this.geminiProxy, this.openaiProxy});

  @override
  _SketchScreenState createState() => _SketchScreenState();
}

// Private State class handling the logic and UI of SketchScreen.
class _SketchScreenState extends State<SketchScreen> {
  late String openaiApiKey;
  bool _isOpenaiAvailable = false;

  List<SketchPath> paths = [];
  SketchPath? currentPath;
  bool showSketch = true; // Flag to toggle sketch visibility.
  bool isErasing = false; // Flag to determine if the user is erasing.

  List<SketchPath> animatedPaths = []; // For animation
  bool _isAnimating = false;
  Timer? _timer;

  bool _isRecording = false;
  final int pointsPerFrame = 5;

  GlobalKey repaintBoundaryKey =
  GlobalKey(); // Key for capturing the canvas as an image.
  bool isLoading = false; // Flag to show a loading indicator when processing.
  final double encodeWidth = 1080; // Define encode width.
  final double encodeHeight = 1920; // Define encode height.
  ui.Image? generatedImage; // Store generated image from AI analysis.
  final List<double> _transparencyLevels = [
    0.0,
    0.3,
    0.7,
    1.0
  ]; // Transparency levels for UI components.
  final int _currentTransparencyLevel = 3; // Current transparency level index.

  double iconWidth = 80; // Icon width in the UI.
  double iconHeight = 80; // Icon height in the UI.
  Color selectedColor = Colors.black; // Default drawing color.
  double currentStrokeWidth = 5.0; // Default stroke width.
  List<Color> colorPalette = [
    // Color palette for the drawing tool.
    Colors.black, Colors.red, Colors.green, Colors.blue, Colors.yellow,
    const Color(0xFFf4c7a6), const Color(0xFF852311), const Color(0xFFe9a885)
  ];

  late SharedPreferences prefs; // SharedPreferences instance for local storage.
  String learnerName = "John"; // Default name used in interactions.
  int learnerAge = 3; // Default age used in interactions.
  bool _isWelcoming = false; // Flag to manage state of welcome message.
  bool _isAnalysing = false; // Flag to manage state of analysis.
  List<Map<String, dynamic>> chatHistory =
      []; // History of interactions for context.

  TtsHelper ttsHelper = TtsHelper(); // Text-to-speech helper instance.

  // Generate appropriate prompts based on the current AI mode.
  String getPrompt(AiMode mode, String skillsSummary) {
    return SketchPrompts.getPrompt(
        mode, learnerAge, chatHistory, skillsSummary);
  }

  // Update the chat history with new entries.
  void updateChatHistory(String content, String sender) {
    chatHistory.add({'content': content, 'sender': sender});
    if (chatHistory.length > 20) {
      // Limit the history size to prevent overly long prompts
      chatHistory.removeAt(0); // Remove the oldest entry
    }
  }

  // Generate a message to the user based on the AI mode.
  String getMessageToUser(AiMode mode) {
    switch (mode) {
      case AiMode.analysis:
        return "$learnerName I am looking at your drawing. Please wait";
      case AiMode.sketchToImage:
        return "$learnerName I will convert your sketch to an image. Please wait";
      default:
        return "";
    }
  }

  // Initialize settings and configure initial state.
  @override
  void initState() {
    super.initState();
    loadSettings();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _welcomeMessage(); // Display a welcome message after the frame build is complete.
    });
    _isOpenaiAvailable = widget.openaiProxy != null;
  }

  // Dispose of resources when the widget is removed from the tree.
  @override
  void dispose() {
    ttsHelper.stop(); // Stop any ongoing TTS playback.
    super.dispose();
  }

  // Load settings from shared preferences.
  Future<void> loadSettings() async {
    prefs = await SharedPreferences.getInstance();
    setState(() {
      learnerName = prefs.getString('learnerName') ?? "";
      learnerAge = prefs.getInt('learnerAge') ?? 3;
    });
  }

  // Display a welcome message to the user.
  void _welcomeMessage() {
    _isWelcoming = true;
    ttsHelper.speak(userMessageSketchScreen);
  }

  // Stop the welcome message.
  void _stopWelcome() {
    _isWelcoming = false;
    ttsHelper.stop();
  }

  // Play an analysis message.
  void _analysisMessage(String message) {
    _isAnalysing = true;
    ttsHelper.speak(message);
  }

  // Stop the analysis message.
  void _stopAnalysis() {
    _isAnalysing = false;
    ttsHelper.stop();
  }

  // Stop TTS playback based on the current state.
  void _stopTts() {
    if (_isAnalysing) _stopAnalysis();
    if (_isWelcoming) _stopWelcome();
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

  // Build the main UI for the sketch screen.
  @override
  Widget build(BuildContext context) {
    bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.deepPurple,
          statusBarIconBrightness: Brightness.dark, // For Android (dark icons)
          statusBarBrightness: Brightness.light, // For iOS (dark icons)
        ),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.red,
        toolbarHeight: 150,
        titleSpacing: 0,
        title: Column(
          children: <Widget>[
            const Text('Sketching',
                style: TextStyle(
                    color: Colors.white)), // Adjust text style as needed
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _isOpenaiAvailable ? Flexible(
                        child: IconButton(
                          icon: Image.asset("assets/sketch_to_image.png",
                              width: iconWidth,
                              height: iconHeight,
                              fit: BoxFit.fill),
                          color: Colors.white,
                          highlightColor: Colors.orange,
                          onPressed: () {
                            takeSnapshotAndAnalyze(
                                context, AiMode.sketchToImage);
                          },
                          tooltip: 'Sketch to Picture',
                        ),
                      )
                    : Container(),
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
                        value: 'delImage',
                        child: Row(
                          children: <Widget>[
                            Icon(Icons.exit_to_app, color: Colors.black),
                            SizedBox(width: 10),
                            Text('Delete Image'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: IconButton(
                    color: Colors.white,
                    highlightColor: Colors.orange,
                    icon: Image.asset("assets/save.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                    onPressed: _saveCanvas,
                    tooltip: 'Save Image',
                  ),
                ),
                Flexible(
                  child: IconButton(
                    icon: Image.asset("assets/share.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                    onPressed: shareCanvas,
                    color: Colors.white,
                    highlightColor: Colors.orange,
                    tooltip: 'Share Image',
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
      case 'delImage':
        setState(() {
          showSketch = true;
          generatedImage = null;
        });
        Log.d('Logging out');
        // Handle user logout
        break;
    }
  }

  // Build the drawing area of the application.
  @override
  Widget buildBody() => Column(
        children: [
          Expanded(
            child: GestureDetector(
              onPanUpdate: (details) {
                if (_isWelcoming) _stopWelcome();
                if (_isAnalysing) _stopAnalysis();
                setState(() {
                  RenderBox renderBox = context.findRenderObject() as RenderBox;
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
              },
              onPanEnd: (details) {
                setState(() {
                  currentPath = null; // End the current path
                });
              },
              child: RepaintBoundary(
                key: repaintBoundaryKey, // Keep your existing key
                child: CustomPaint(
                  painter: SketchPainter(
                      _isAnimating
                          ? animatedPaths
                          : paths, // Use animatedPaths during animation
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

  // Build the control panel for portrait orientation.
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
            onPressed: () {
              setState(() {
                isErasing = true;
              });
            },
            tooltip: 'Erase',
          ),
        ),
        Flexible(
          child: IconButton(
            icon: Image.asset("assets/analysis.png",
                width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            color: Colors.white,
            highlightColor: Colors.orange,
            onPressed: () {
              takeSnapshotAndAnalyze(context, AiMode.analysis);
            },
            tooltip: 'Feedback',
          ),
        ),
      ],
    );
  }

  // Check if the content generated by AI is safe for display to children.
  bool isContentSafe(Map<String, dynamic> candidate) {
    List<dynamic> safetyRatings = candidate['safetyRatings'];
    return safetyRatings
        .every((rating) => rating['probability'] == 'NEGLIGIBLE');
  }

  // Decode and set the image from byte data for display.
  void decodeAndSetImage(Uint8List imageData) async {
    final codec = await ui.instantiateImageCodec(imageData);
    final frame = await codec.getNextFrame();
    setState(() {
      generatedImage = frame.image;
    });
  }

  // Share the canvas image with others.
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

  // Request necessary permissions for storage.
  Future<void> requestPermissions() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      await Permission.storage.request();
    }
  }

  // Save the image to the device gallery.
  Future<bool> saveImage() async {
    try {
      RenderRepaintBoundary boundary = repaintBoundaryKey.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);

      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final result = await ImageGallerySaver.saveImage(pngBytes,
          quality: 60, name: "hello");
      Log.d(result);
      return true;
    } catch (e) {
      // You can handle errors internally or rethrow them to be caught by catchError where this function is called
      Log.d("Error saving image: $e"); // Rethrow the error
      return false;
    }
  }

  // Method to save the canvas image and manage UI feedback.
  void _saveCanvas() async {
    // First, request permissions to support legacy modes
    await requestPermissions();

    // Show loading dialog
    if (!context.mounted) return;
    showLoadingDialog(context, "Saving image...");

    // Then try to save the image
    saveImage().then((success) {
      Navigator.of(context).pop(); // Dismiss the progress dialog
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image saved successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save image')),
        );
      }
    }).catchError((error) {
      Navigator.of(context)
          .pop(); // Ensure the progress dialog is dismissed even on error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An error occurred: $error')),
      );
    });
  }

  // Take a snapshot of the canvas and initiate an analysis or image generation based on the selected mode.
  void takeSnapshotAndAnalyze(BuildContext context, AiMode selectedMode) async {
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
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      String base64String = base64Encode(pngBytes);

      // String promptText = getPrompt(selectedMode); //prompts[selectedMode]!;
      String skillsSummary =
          getSkillsTextForPrompt(learnerAge); // Get skills summary
      String promptText = getPrompt(selectedMode, skillsSummary);
      List<Map<String, dynamic>> contentParts = [];

      if (selectedMode == AiMode.analysis) {
        for (var message in chatHistory) {
          contentParts.add({
            "role": message['sender'],
            "parts": [
              {"text": message['content']}
            ]
          });
        }
      }
      contentParts.add({
        "role": "user",
        "parts": [
          {"text": promptText},
          {
            "inlineData": {"mimeType": "image/png", "data": base64String}
          }
        ]
      });

      String jsonBody = jsonEncode({
        "contents": contentParts,
      });

      // Use GeminiProxy to process the request
      var response = await widget.geminiProxy.process(jsonBody);
      Log.d("History: $chatHistory");
      Log.d("Prompt: $promptText");
      if (response.statusCode == 200) {
        Map<String, dynamic> decodedResponse = jsonDecode(response.body);
        Map<String, dynamic> candidate = decodedResponse['candidates'][0];
        if (isContentSafe(candidate)) {
          String responseText = candidate['content']['parts'][0]['text'];
          Log.d("Response from model: $responseText");
          if (selectedMode == AiMode.analysis) {
            updateChatHistory('User drew a picture', 'user');
            updateChatHistory(responseText, 'model');
            _analysisMessage(responseText);
          } else if (selectedMode == AiMode.sketchToImage) {
            // Generate an image from a text prompt
            try {
              final imageResponse = await widget.openaiProxy!.process('dall-e-3', responseText, OpenAIImageSize.size1024);

              if (imageResponse.data.isNotEmpty) {
                setState(() {
                  Uint8List bytesImage = base64Decode(imageResponse.data.first
                      .b64Json!); // Assuming URL points to a base64 image string
                  decodeAndSetImage(bytesImage!);
                  showSketch = false;
                });
              } else {
                Log.d('No image returned from the API');
              }
            } catch (e) {
              Log.d('Error calling OpenAI image generation API: $e');
            }
          }
        } else {
          Log.d("Content is not safe for children.");
          ttsHelper.speak("Sorry, content issue. Try again");
        }
      } else if (response.statusCode == 403) {
        Log.d("Failed to get response: ${response.body}");
        ttsHelper.speak("Sorry, network issue. Check Gemini API Key");
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
}
