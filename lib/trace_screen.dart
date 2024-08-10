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

// Enumeration to define various AI modes for the application's functionality.
enum AiMode { Analysis, ImageToTrace, PromptToImage }

// StatefulWidget to handle the Trace Screen UI and functionality.
class TraceScreen extends StatefulWidget {
  final String geminiApiKey;
  final String openaiApiKey;
  const TraceScreen(
      {super.key, required this.geminiApiKey, required this.openaiApiKey});

  @override
  _TraceScreenState createState() => _TraceScreenState();
}

// State class for TraceScreen with additional functionality from SingleTickerProviderStateMixin for animations.
class _TraceScreenState extends State<TraceScreen>
    with SingleTickerProviderStateMixin {
  List<SketchPath> paths = [];
  SketchPath? currentPath;
  bool showSketch = true;          // Flag to toggle display of the sketch.
  bool isErasing = false;          // Flag to toggle eraser mode.

  GlobalKey repaintBoundaryKey = GlobalKey();  // Key for the widget used to capture image.
  bool isLoading = false;                      // Flag to show a loading indicator.
  final double canvasWidth = 1024;             // Canvas width.
  final double canvasHeight = 1920;            // Canvas height.
  ui.Image? generatedImage;                    // Variable to hold the generated image.
  final List<double> _transparencyLevels = [0.0, 0.5, 1.0];  // Transparency levels for display.
  int _currentTransparencyLevel = 2;                           // Current transparency level.

  double iconWidth = 80;  // Icon width for buttons.
  double iconHeight = 80; // Icon height for buttons.

  final stt.SpeechToText _speechToText = stt.SpeechToText();  // Speech to text instance.
  bool _isListening = false;                                  // Flag to check if listening.
  bool _speechEnabled = false;                                // Flag to check if speech is enabled.
  String _sttText = "";                                       // Text obtained from speech recognition.
  OverlayEntry? _overlayEntry;                                // Overlay entry for displaying speech text.

  Color selectedColor = Colors.black;   // Default selected color for drawing.
  double currentStrokeWidth = 5.0;      // Current stroke width for drawing.
  List<Color> colorPalette = [          // Color palette for selection.
    Colors.black, Colors.red, Colors.green, Colors.blue, Colors.yellow
  ];
  AiMode _aiMode = AiMode.PromptToImage;  // Default AI mode.
  int learnerAge = 3;                      // Default learner age, used in prompts.

  late AnimationController _animationController;  // Controller for animations.
  late Animation<double> _animation;              // Animation details.

  late SharedPreferences prefs;  // Shared preferences for storing data locally.
  String learnerName = "John";   // Default learner name.
  bool _isWelcoming = false;     // Flag to check if welcome message is active.

  TtsHelper ttsHelper = TtsHelper();  // Text to speech helper instance.

  // Function to get prompt based on AI mode and user input.
  String getPrompt(AiMode mode, String userInput) {
    String tracingPrompt = """
You are a friendly and encouraging art teacher talking to a $learnerAge year old child. You are comparing the child's tracing of a drawing to the original drawing. 

Here's what to look for:

1. **Overall Similarity:**  Does the tracing generally follow the lines and shapes of the original drawing? 
2. **Specific Differences:** Identify any parts where the tracing deviates significantly from the original. For example:
    - Are some parts missed completely? 
    - Are lines shaky or wobbly in places?
    - Are there places where the tracing went outside the lines?
3. **Tracing Technique:**  Consider if the differences suggest the child might need help with tracing techniques:
    - Did they keep their hand steady?
    - Did they press hard enough to make a clear line?
    - Did they try to rush? 

Now, give your feedback to the child:

* **Start with encouragement!**  Praise their effort and any parts they traced well. 
* **Point out one or two specific areas for improvement.** Be gentle and use positive language.  For example:
    * "Wow, you did a great job tracing the flower!  It looks like you kept your hand super steady there."
    * "I see you traced the whole line of the car! Maybe next time we can try going a little slower to keep the car on the road."
* **If you think they need help with tracing technique, offer a fun tip or two.** For example: 
    *  "Remember, tracing is like magic! You have to keep your pencil close to the lines like you're casting a spell." 
    * "Let's pretend our pencils are little race cars.  We want them to stay right on the track!"

Remember, no markup or special formatting. Keep it conversational and easy for a child to understand. 
""";

    String imagePromptGuidance = """
You are an AI assistant collaborating with a $learnerAge year old child. The child wants to create a simple black and white outline image for tracing. 

Here's the child's idea: '$userInput'

Create a prompt for a text-to-image model that will generate a suitable outline based on the child's idea. 

The prompt should:

* Be very specific about the desired image. 
* Avoid any request for text in the image.
* Not include any requests for tiled or repeating patterns.
* Ensure the image is a single, self-contained subject, and not a collection of multiple objects or a scene.
* Focus on basic shapes and minimal detail, appropriate for a $learnerAge year old to trace.

Example of the kind of prompt you should generate: "A simple black and white outline of a object based on the child's idea with minimal details, suitable for tracing." 
""";

    switch (mode) {
      case AiMode.Analysis:
        return tracingPrompt;
      case AiMode.PromptToImage:
        return imagePromptGuidance;
      default:
        return ""; // Handle any other cases or throw an error if needed
    }
  }

  // Function to get a message to the user based on the AI mode.
  String getMessageToUser(AiMode mode) {
    switch (mode) {
      case AiMode.Analysis:
        return "$learnerName, I am looking at your tracing. Please wait";
      case AiMode.PromptToImage:
        return "$learnerName, Generating the picture. Please wait";
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
    loadSettings();
    OpenAI.apiKey = widget.openaiApiKey;
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
                widget.openaiApiKey.isNotEmpty ? Flexible(
                  child: IconButton(
                    icon: Image.asset("assets/imagen_square.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                    color: Colors.white,
                    highlightColor: Colors.orange,
                    onPressed: () {
                      setState(() {
                        _aiMode = AiMode.PromptToImage;
                      });
                      _listen();
                    },
                    tooltip: 'Voice to Image',
                  ),
                ) : Container(),
                Flexible(
                  child: IconButton(
                    icon: Image.asset("assets/analysis.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                    color: Colors.white,
                    highlightColor: Colors.orange,
                    onPressed: generatedImage != null
                        ? () {
                            takeSnapshotAndAnalyze(
                                context, AiMode.Analysis, "");
                          }
                        : _msgSelectPicture,
                    tooltip: 'Feedback',
                  ),
                ),
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

  Widget buildBody() => Column(
        children: [
          Expanded(
            child: GestureDetector(
              onPanUpdate: (details) {
                if (_isWelcoming) _stopWelcome();
                if (generatedImage != null) {
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
                        currentPath = SketchPath(selectedColor, currentStrokeWidth);
                        paths.add(currentPath!);
                      }
                      if (currentPath!.points.isEmpty ||
                          (localPosition - currentPath!.points.last).distance <=
                              maxDistanceThreshold) {
                        currentPath!.points.add(localPosition);
                      }
                    } else {
                      paths = paths.where((path) {
                        return !path.points.any((point) =>
                        (point - localPosition).distance <= 20);
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
                  painter: SketchPainter(paths, showSketch, generatedImage,
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
            icon: Image.asset("assets/transparency.png",
                width: iconWidth,
                height: iconHeight,
                fit: BoxFit.fill), // Example icon - you can customize
            color: Colors.white,
            highlightColor: Colors.orange,
            onPressed: generatedImage != null
                ? () {
                    setState(() {
                      _currentTransparencyLevel =
                          (_currentTransparencyLevel + 1) %
                              _transparencyLevels.length;
                    });
                  }
                : _msgSelectPicture,
            tooltip: 'Transparency',
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
        generatePicture(context, AiMode.PromptToImage, _sttText);
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
/*
  Future<ui.Image> drawPointsToImage(
      List<SketchPath> paths, Size size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Draw the white background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.white);

    // Your painting logic
    final paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i].point != null && points[i + 1].point != null) {
        canvas.drawLine(points[i].point!, points[i + 1].point!, paint);
      }
    }

    final picture = recorder.endRecording();
    return picture.toImage(size.width.toInt(), size.height.toInt());
  }
 */
}
