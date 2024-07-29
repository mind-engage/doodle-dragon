import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:dart_openai/dart_openai.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/tts_helper.dart';
import '../utils/user_messages.dart';
import '../utils/sketch_painter_v2.dart';

enum AiMode { Analysis, SketchToImage }

class SketchScreen extends StatefulWidget {
  final String geminiApiKey;
  final String openaiApiKey;
  const SketchScreen(
      {super.key, required this.geminiApiKey, required this.openaiApiKey});

  @override
  _SketchScreenState createState() => _SketchScreenState();
}

class _SketchScreenState extends State<SketchScreen> {
  List<ColoredPoint> points = [];
  bool showSketch = true;
  bool isErasing = false; // Add this line

  GlobalKey repaintBoundaryKey = GlobalKey();
  bool isLoading = false;
  final double canvasWidth = 1024;
  final double canvasHeight = 1920;
  ui.Image? generatedImage;
  List<double> _transparencyLevels = [0.0, 0.3, 0.7, 1.0];
  int _currentTransparencyLevel = 3;

  double iconWidth = 80;
  double iconHeight = 80;

  Color selectedColor = Colors.black; // Default color
  double currentStrokeWidth = 5.0;
  List<Color> colorPalette = [
    Colors.black,
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.yellow
  ];

  late SharedPreferences prefs;
  String learnerName = "John";
  int learnerAge = 3;
  bool _isWelcoming = false;

  TtsHelper ttsHelper = TtsHelper();

  String getPrompt(AiMode mode) {
    switch (mode) {
      case AiMode.Analysis:
        return "Describe this children's drawing in detail, imagining you are talking to a $learnerAge old child."
            "Focus on the elements, colors (or lack thereof), and any potential story the drawing might tell."
            "Then, offer a couple of specific, positive suggestions on how they could add even more to their amazing artwork!";
      case AiMode.SketchToImage:
        return "Imagine you're telling a magical art fairy how to make a super cool picture from this drawing."
            "The picture for a $learnerAge old child."
            "Describe what you see: What colors should it use? Are there any shiny objects? Is it a happy picture or maybe a bit spooky? Be as creative as you can!";
      default:
        return ""; // Handle any other cases or throw an error if needed
    }
  }

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

  @override
  void initState() {
    super.initState();
    loadSettings();
    OpenAI.apiKey = widget.openaiApiKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _welcomeMessage();
    });
  }

  @override
  void dispose() {
    ttsHelper.stop();
    super.dispose();
  }

  Future<void> loadSettings() async {
    prefs = await SharedPreferences.getInstance();
    setState(() {
      learnerName = prefs.getString('learnerName') ?? "";
      learnerAge = prefs.getInt('learnerAge') ?? 3;
    });
  }

  void _welcomeMessage() {
    _isWelcoming = true;
    ttsHelper.speak(userMessageSketchScreen);
  }

  void _stopWelcome() {
    _isWelcoming = false;
    ttsHelper.stop();
  }

  @override
  Widget build(BuildContext context) {
    bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle(
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
            Text('Sketching',
                style: TextStyle(
                    color: Colors.white)), // Adjust text style as needed
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Flexible(
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
                ),
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

  Widget buildBody() => Column(
        children: [
          Expanded(
            child: GestureDetector(
              onPanUpdate: (details) {
                if (_isWelcoming) _stopWelcome();
                setState(() {
                  RenderBox renderBox = context.findRenderObject() as RenderBox;
                  double appBarHeight =
                      150; // Update this if the AppBar height changes
                  double topPadding = MediaQuery.of(context).padding.top;

                  Offset adjustedPosition = details.globalPosition -
                      Offset(0, appBarHeight + topPadding);
                  Offset localPosition =
                      renderBox.globalToLocal(adjustedPosition);

                  if (!isErasing) {
                    points.add(ColoredPoint(
                        localPosition, selectedColor, currentStrokeWidth));
                  } else {
                    // Erasing could be refined to work with paths if necessary
                    points = points
                        .where((p) =>
                            p.point == null ||
                            (p.point! - localPosition).distance >
                                20) // Adjust distance as needed
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
              return [5.0, 10.0, 20.0, 40.0].map((double size) {
                return PopupMenuItem<double>(
                  value: size,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40, // This width is proportional to the brush size
                        height: size, // Fixed height for the visual representation
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

  bool isContentSafe(Map<String, dynamic> candidate) {
    List<dynamic> safetyRatings = candidate['safetyRatings'];
    return safetyRatings
        .every((rating) => rating['probability'] == 'NEGLIGIBLE');
  }

  void decodeAndSetImage(Uint8List imageData) async {
    final codec = await ui.instantiateImageCodec(imageData);
    final frame = await codec.getNextFrame();
    setState(() {
      generatedImage = frame.image;
    });
  }

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
      print('Error sharing canvas: $e');
    }
  }

  void takeSnapshotAndAnalyze(BuildContext context, AiMode selectedMode) async {
    setState(() =>
        isLoading = true); // Set loading to true when starting the analysis

    ttsHelper.speak(getMessageToUser(selectedMode));

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) =>
          Center(child: CircularProgressIndicator()), // Show a loading spinner
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
          print("Response from model: $responseText");
          if (selectedMode == AiMode.Analysis) {
            ttsHelper.speak(responseText);
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
                print('No image returned from the API');
              }
            } catch (e) {
              print('Error calling OpenAI image generation API: $e');
            }
          }
        } else {
          print("Content is not safe for children.");
          ttsHelper.speak("Sorry, content issue. Try again");
        }
      } else {
        print("Failed to get response: ${response.body}");
        ttsHelper.speak("Sorry, network issue. Try again");
      }
    } finally {
      setState(() =>
          isLoading = false); // Reset loading state after operation completes
      Navigator.of(context).pop();
    }
  }

  void generatePicture(BuildContext context, AiMode selectedMode) async {
    setState(() =>
        isLoading = true); // Set loading to true when starting the analysis

    ttsHelper.speak(getMessageToUser(selectedMode));

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) =>
          Center(child: CircularProgressIndicator()), // Show a loading spinner
    );
    try {
      String promptText = getPrompt(selectedMode);
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
          print("Response from model: $responseText");
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
              });
            } else {
              print('No image returned from the API');
            }
          } catch (e) {
            print('Error calling OpenAI image generation API: $e');
          }
        } else {
          print("Content is not safe for children.");
          ttsHelper.speak("Sorry, content issue. Try again");
        }
      } else {
        print("Failed to get response: ${response.body}");
        ttsHelper.speak("Sorry, network issue. Try again");
      }
    } finally {
      setState(() =>
          isLoading = false); // Reset loading state after operation completes
      Navigator.of(context).pop();
    }
  }
}
