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
                    onPressed: () {
                      takeSnapshotAndAnalyze(context, AiMode.SketchToImage);
                    },
                  ),
                ),

                Flexible(
                  child: IconButton(
                    icon: Image.asset("assets/delete.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
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
                setState(() {
                  RenderBox renderBox = context.findRenderObject() as RenderBox;
                  double appBarHeight = 150; //AppBar().toolbarHeight!;
                  double topPadding = MediaQuery.of(context).padding.top;

                  Offset adjustedPosition = details.globalPosition -
                      Offset(0, appBarHeight + topPadding);
                  Offset localPosition =
                      renderBox.globalToLocal(adjustedPosition);

                  if (!isErasing) {
                    points.add(ColoredPoint(localPosition, selectedColor));
                  } else {
                    points = points
                        .where((p) =>
                            p.point == null ||
                            (p.point! - localPosition).distance > 20)
                        .toList();
                  }
                });
              },
              onPanEnd: (details) =>
                  setState(() => points.add(ColoredPoint(null, selectedColor))),
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
        SizedBox(width: 16),
        PopupMenuButton<Color>(
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
        Flexible(
          child: IconButton(
            icon: isErasing
                ? Image.asset("assets/eraser.png",
                    width: iconWidth, height: iconHeight, fit: BoxFit.fill)
                : Image.asset("assets/eraser.png",
                    width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            onPressed: () {
              setState(() {
                isErasing = true;
              });
            },
            tooltip: 'Toggle Erase',
          ),
        ),
        Flexible(
          child: IconButton(
            icon: Image.asset("assets/analysis.png",
                width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            color: Colors.white,
            onPressed: () {
              takeSnapshotAndAnalyze(context, AiMode.Analysis);
            },
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

class ColoredPoint {
  Offset? point;
  Color color;

  ColoredPoint(this.point, this.color);
}

class SketchPainter extends CustomPainter {
  final List<ColoredPoint> points;
  final bool showSketch;
  final ui.Image? image;
  final double transparency;
  SketchPainter(this.points, this.showSketch, this.image, this.transparency);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the white background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.white);

    // Draw hints or the image overlay
    if (image != null) {
      // Draw the image as an overlay if available
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTWH(0, 0, size.width, size.height),
        image: image!,
        fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(
            Colors.white.withOpacity(transparency), BlendMode.dstIn),
      );
    }
    if (showSketch) {
      Paint paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5.0;

      for (int i = 0; i < points.length - 1; i++) {
        if (points[i].point != null && points[i + 1].point != null) {
          paint.color =
              points[i].color; // Use the color associated with the point
          canvas.drawLine(points[i].point!, points[i + 1].point!, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant SketchPainter oldDelegate) => true;
}
