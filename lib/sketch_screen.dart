// Import necessary Dart and Flutter packages for the SketchScreen functionality.
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
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/tts_helper.dart';
import '../utils/user_messages.dart';
import '../utils/sketch_painter_v2.dart';
import '../utils/log.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';

// Define an enumeration for different AI modes available in the app.
enum AiMode { Analysis, SketchToImage }

// Define a StatefulWidget for handling the sketch screen with necessary dependencies.
class SketchScreen extends StatefulWidget {
  final String geminiApiKey;
  final String openaiApiKey;

  // Constructor for the SketchScreen which takes required API keys.
  const SketchScreen({
    super.key,
    required this.geminiApiKey,
    required this.openaiApiKey
  });

  @override
  _SketchScreenState createState() => _SketchScreenState();
}

// Private State class handling the logic and UI of SketchScreen.
class _SketchScreenState extends State<SketchScreen> {
  List<ColoredPoint> points = [];  // Stores the points drawn on the canvas.
  bool showSketch = true;          // Flag to toggle sketch visibility.
  bool isErasing = false;          // Flag to determine if the user is erasing.

  GlobalKey repaintBoundaryKey = GlobalKey(); // Key for capturing the canvas as an image.
  bool isLoading = false;                      // Flag to show a loading indicator when processing.
  final double canvasWidth = 1024;             // Define canvas width.
  final double canvasHeight = 1920;            // Define canvas height.
  ui.Image? generatedImage;                    // Store generated image from AI analysis.
  final List<double> _transparencyLevels = [0.0, 0.3, 0.7, 1.0];  // Transparency levels for UI components.
  final int _currentTransparencyLevel = 3;                         // Current transparency level index.

  double iconWidth = 80;          // Icon width in the UI.
  double iconHeight = 80;         // Icon height in the UI.
  Color selectedColor = Colors.black;  // Default drawing color.
  double currentStrokeWidth = 5.0;     // Default stroke width.
  List<Color> colorPalette = [         // Color palette for the drawing tool.
    Colors.black, Colors.red, Colors.green, Colors.blue, Colors.yellow,
    const Color(0xFFf4c7a6), const Color(0xFF852311), const Color(0xFFe9a885)
  ];

  late SharedPreferences prefs;    // SharedPreferences instance for local storage.
  String learnerName = "John";     // Default name used in interactions.
  int learnerAge = 3;              // Default age used in interactions.
  bool _isWelcoming = false;       // Flag to manage state of welcome message.
  bool _isAnalysing = false;       // Flag to manage state of analysis.
  List<Map<String, dynamic>> chatHistory = []; // History of interactions for context.

  TtsHelper ttsHelper = TtsHelper(); // Text-to-speech helper instance.

  // Generate appropriate prompts based on the current AI mode.
  String getPrompt(AiMode mode) {
    // Method to generate interaction prompts based on the selected AI mode.
    String historyContext = chatHistory.join(" ");
    switch (mode) {
      case AiMode.Analysis:
        historyContext = _buildHistoryContext();
        // Condition to tailor the prompt if the last interaction was from AI.
        if (chatHistory.isNotEmpty &&
            chatHistory.last['sender'] == 'AI' &&
            chatHistory.last['type'] == 'text') {
          return "$historyContext Did the child follow any of the suggestions from the previous drawing? If so, say to him few encouraging words to the child. Also provide some new suggestions based on this latest drawing. Only child's latest drawing is provided to you. You have to provide your feedback based on this drawing and attached history";
        } else {
          return "Describe this children's drawing in detail, imagining you are talking to a $learnerAge old child. Focus on the elements, colors (or lack thereof), and any potential story the drawing might tell. Then, offer a couple of specific, positive suggestions on how they could add even more to their amazing artwork!";
        }
      case AiMode.SketchToImage:
        return "Imagine you're telling a magical art fairy how to make a super cool picture from this drawing."
            "The picture for a $learnerAge old child."
            "Describe what you see: What colors should it use? Are there any shiny objects? Is it a happy picture or maybe a bit spooky? Be as creative as you can!";
      default:
        return ""; // Handle any other cases or throw an error if needed
    }
  }

  // Update the chat history with new entries.
  void updateChatHistory(String content, String sender, [String type = 'text']) {
    chatHistory.add({
      'content': content,
      'sender': sender,
      'type': type // 'text' or 'image'
    });
    if (chatHistory.length >
        20) { // Limit the history size to prevent overly long prompts
      chatHistory.removeAt(0); // Remove the oldest entry
    }
  }

  // Build a context string from the chat history for AI interactions.
  String _buildHistoryContext() {
    String context = "";
    for (var message in chatHistory) {
      if (message['type'] == 'image') {
        context += "User drew a picture. ";
      } else {
        context += "${message['sender']}: ${message['content']} ";
      }
    }
    return context;
  }

  // Generate a message to the user based on the AI mode.
  String getMessageToUser(AiMode mode) {
    switch (mode) {
      case AiMode.Analysis:
        return "$learnerName, I am looking at your drawing. Please wait";
      case AiMode.SketchToImage:
        return "$learnerName, I will convert your sketch to an image. Please wait";
      default:
        return ""; // Handle any other cases or throw an error if needed
    }
  }

  // Initialize settings and configure initial state.
  @override
  void initState() {
    super.initState();
    loadSettings();
    OpenAI.apiKey = widget.openaiApiKey; // Set OpenAI API key from widget property.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _welcomeMessage(); // Display a welcome message after the frame build is complete.
    });
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
                widget.openaiApiKey.isNotEmpty ?  Flexible(
                  child: IconButton(
                    icon: Image.asset("assets/sketch_to_image.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                    color: Colors.white,
                    highlightColor: Colors.orange,
                    onPressed: () {
                      takeSnapshotAndAnalyze(context, AiMode.SketchToImage);
                    },
                    tooltip: 'Sketch to Picture',
                  ),
                ) : Container(),
                Flexible(
                  child: IconButton(
                    icon: Image.asset("assets/delete.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                    color: Colors.white,
                    highlightColor: Colors.orange,
                    onPressed: () {
                      setState(() {
                        showSketch = true;
                        generatedImage = null;
                      });
                    },
                    tooltip: 'Clear Sketch',
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

  // Build the drawing area of the application.
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
                Offset localPosition = renderBox.globalToLocal(adjustedPosition);

                // Distance threshold for rejecting distant points within a path
                const double maxDistanceThreshold = 20.0; // Adjust as needed

                if (!isErasing) {
                  // Check if starting a new path or continuing an existing one
                  if (points.isEmpty || points.last.point == null) {
                    // New path - add the point unconditionally
                    points.add(ColoredPoint(
                        localPosition, selectedColor, currentStrokeWidth));
                  } else {
                    // Continuing path - apply distance threshold
                    if ((localPosition - points.last.point!).distance <=
                        maxDistanceThreshold) {
                      points.add(ColoredPoint(
                          localPosition, selectedColor, currentStrokeWidth));
                    }
                  }
                } else {
                  // Erasing logic (you can keep this as is)
                  points = points
                      .where((p) =>
                  p.point == null ||
                      (p.point! - localPosition).distance > 20)
                      .toList();
                }
              });
          },
          onPanEnd: (details) {
            // Add a null point to signal the end of a path
            setState(() => points.add(
                ColoredPoint(null, selectedColor, currentStrokeWidth)));
          },
          child: RepaintBoundary(
            key: repaintBoundaryKey,
            child: CustomPaint(
              painter: SketchPainter(points, showSketch, generatedImage,
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
              takeSnapshotAndAnalyze(context, AiMode.Analysis);
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
      await image!.toByteData(format: ui.ImageByteFormat.png);
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
    // First, request permissions
    await requestPermissions();

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible:
      false, // User must not dismiss the dialog by tapping outside of it
      builder: (BuildContext context) {
        return Dialog(
          child: Container(
            padding: EdgeInsets.all(20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text("Saving image..."),
              ],
            ),
          ),
        );
      },
    );

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
      builder: (context) =>
      const Center(child: CircularProgressIndicator()), // Show a loading spinner
    );
    try {
      RenderRepaintBoundary boundary = repaintBoundaryKey.currentContext!
          .findRenderObject()! as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData =
      await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      // String base64String = await capturePng();
      // Get the size of the boundary to pass to getPrompt
      Size size = boundary.size;
      double width = size.width;
      double height = size.height;

      String base64String = base64Encode(pngBytes);

      String promptText = getPrompt(selectedMode); //prompts[selectedMode]!;
      String jsonBody = jsonEncode({
        "contents": [
          {
            "parts": [
              {"text": promptText},
              {
                "inlineData": {"mimeType": "image/png", "data": base64String}
              }
            ]
          }
        ]
      });

      var response = await http.post(
        Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro-latest:generateContent?key=${widget.geminiApiKey}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonBody,
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> decodedResponse = jsonDecode(response.body);
        Map<String, dynamic> candidate = decodedResponse['candidates'][0];
        if (isContentSafe(candidate)) {
          String responseText = candidate['content']['parts'][0]['text'];
          Log.d("Response from model: $responseText");
          if (selectedMode == AiMode.Analysis) {
            updateChatHistory('', 'User', 'image');
            updateChatHistory(responseText, 'AI');
            _analysisMessage(responseText);
          } else if (selectedMode == AiMode.SketchToImage) {
            // Generate an image from a text prompt
            try {
              final imageResponse = await OpenAI.instance.image.create(
                model: 'dall-e-3',
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
      } else {
        Log.d("Failed to get response: ${response.body}");
        ttsHelper.speak("Sorry, network issue. Try again");
      }
    } finally {
      setState(() =>
      isLoading = false);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}
