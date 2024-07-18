import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:dart_openai/dart_openai.dart';

enum AiMode { Analysis, ImageToTrace, SketchToImage }

class SketchScreen extends StatefulWidget {
  final String geminiApiKey;
  final String openaiApiKey;
  const SketchScreen({super.key, required this.geminiApiKey, required this.openaiApiKey});

  @override
  _SketchScreenState createState() => _SketchScreenState();
}

class _SketchScreenState extends State<SketchScreen> {
  List<Offset?> points = [];
  bool showSketch = true;

  GlobalKey repaintBoundaryKey = GlobalKey();
  AiMode selectedMode = AiMode.Analysis;
  FlutterTts flutterTts = FlutterTts();
  bool isLoading = false;
  final double canvasWidth = 1024;
  final double canvasHeight = 1920;
  ui.Image? generatedImage;
  BoxFit boxFit = BoxFit.cover; // Default value
  double _transparency = 1.0; // Default transparency

  String getPrompt(AiMode mode, double canvasWidth, double canvasHeight) {
    switch (mode) {
      case AiMode.Analysis:
        return "The attached sketch is drawn by a child. Analyze and suggest improvements. The output is used to play to child using text to speech";
      case AiMode.SketchToImage:
        return "Generate a creative and detailed prompt describing this children's drawing to be used for text-to-image generation.";
      case AiMode.ImageToTrace:
        return "Generate a creative and detailed prompt describing this children's drawing to be used for text-to-image generation. The generate image will be used to learn drawing by tracing over. Generate a suitable prompt with length below 1000 characters";
      default:
        return ""; // Handle any other cases or throw an error if needed
    }
  }

  @override
  void initState() {
    super.initState();
    flutterTts.setLanguage("en-US");
    flutterTts.setSpeechRate(0.5);
    OpenAI.apiKey = widget.openaiApiKey;
  }

  @override
  Widget build(BuildContext context) {
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        title: Text('Doodle Dragon'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.clear),
            onPressed: () {
              setState(() {
                points.clear(); // Clear all points
              });
            },
            tooltip: 'Clear Sketch',
          ),
          IconButton(
            icon: Icon(Icons.aspect_ratio),
            onPressed: () {
              setState(() {
                boxFit = boxFit == BoxFit.cover ? BoxFit.contain : BoxFit.cover;
              });
            },
            tooltip: 'Toggle BoxFit',
          ),
          IconButton(
            icon: Icon(Icons.visibility),
            onPressed: () {
              setState(() {
                showSketch = !showSketch;
              });
            },
          ),
        ],
      ),
      body: Row( // Use Row for main layout
        children: [
          Expanded( // Canvas takes the available space
            child: buildBody(),
          ),
          if(isLandscape) controlPanelLandscape(),
        ],
      ),
      bottomNavigationBar: isLandscape ? null : BottomAppBar(
        color: Colors.deepPurple,
        child: controlPanelPortrait(),
      ),
      floatingActionButtonLocation: isLandscape
          ? FloatingActionButtonLocation.endFloat // Position FAB at the bottom right in landscape
          : FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget buildBody() => Column(
    children: [
      Expanded(
        child: GestureDetector(
          onPanUpdate: (details) {
            setState(() {
              RenderBox renderBox = context.findRenderObject() as RenderBox;
              double appBarHeight = AppBar().preferredSize.height;
              double topPadding = MediaQuery.of(context).padding.top;

              Offset adjustedPosition = details.globalPosition - Offset(0, appBarHeight + topPadding);
              Offset localPosition = renderBox.globalToLocal(adjustedPosition);

              points.add(localPosition);
            });
          },
          onPanEnd: (details) => setState(() => points.add(null)),
          child: RepaintBoundary(
            key: repaintBoundaryKey,
            child: CustomPaint(
              painter: SketchPainter(points, showSketch, generatedImage, boxFit, _transparency),
              child: Container(),
            ),
          ),
        ),
      ),
    ],
  );

  Widget modeSelection() {
    return PopupMenuButton<AiMode>(
      // Replace with a more visually appealing mode selector for younger kids (e.g., large, tappable icons)
      icon: Icon(
        Icons.brush,
        size: 40,
      ), //  Replace with a more appropriate icon (e.g., a palette)
      iconColor: Colors.white,
      onSelected: (AiMode newValue) {
        setState(() => selectedMode = newValue);
      },
      itemBuilder: (BuildContext context) =>
      <PopupMenuEntry<AiMode>>[
        const PopupMenuItem<AiMode>(
          value: AiMode.Analysis,
          child: Row(
            children: [
              Icon(
                Icons.analytics,
                color: Colors.red,
              ), // Replace with a custom icon representing 'analysis'
              SizedBox(width: 8),
              Text('Analyze'),
            ],
          ),
        ),
        const PopupMenuItem<AiMode>(
          value: AiMode.ImageToTrace,
          child: Row(
            children: [
              Icon(
                Icons.notes,
                color: Colors.green,
              ), // Replace with a custom icon representing 'tracing'
              SizedBox(width: 8),
              Text('Easy Trace'),
            ],
          ),
        ),
        const PopupMenuItem<AiMode>(
          value: AiMode.SketchToImage,
          child: Row(
            children: [
              Icon(
                Icons.image,
                color: Colors.blue,
              ), // Replace with a custom icon representing 'image generation'
              SizedBox(width: 8),
              Text('Magic Background'),
            ],
          ),
        ),
      ]
    );
  }

  Widget controlPanelLandscape() {
    return  Container(
      width: 80, // Adjust width as needed
      color: Theme.of(context).primaryColor,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          modeSelection(),
          SizedBox(height: 16),
          RotatedBox( // Rotate the Slider 90 degrees
            quarterTurns: 3, // 3 quarter turns for vertical orientation
            child: Slider(
              value: _transparency,
              min: 0.0,
              max: 1.0,
              divisions: 10,
              activeColor: Colors.white,
              label: "${(_transparency * 100).toStringAsFixed(0)}%",
              onChanged: (double value) {
                setState(() {
                  _transparency = value;
                });
              },
            ),
          ),
          SizedBox(height: 16),
          FloatingActionButton(
            onPressed: () => takeSnapshotAndAnalyze(context),
            tooltip: 'Analyze',
            child: isLoading
                ? CircularProgressIndicator(
              color: Colors.black,
            ) : Icon(Icons.engineering),
          ),
        ],
      ),
    );
  }

  Widget controlPanelPortrait() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        modeSelection(),
        SizedBox(width: 16),
        Expanded( // Rotate the Slider 90 degrees
          child: Slider(
            value: _transparency,
            min: 0.0,
            max: 1.0,
            divisions: 10,
            activeColor: Colors.white,
            label: "${(_transparency * 100).toStringAsFixed(0)}%",
            onChanged: (double value) {
              setState(() {
                _transparency = value;
              });
            },
          ),
        ),
        SizedBox(width: 16),
        FloatingActionButton(
          onPressed: () => takeSnapshotAndAnalyze(context),
          tooltip: 'Analyze',
          child: isLoading
              ? CircularProgressIndicator(
            color: Colors.black,
          ) : Icon(Icons.engineering),
        ),
      ],
    );
  }

  bool isContentSafe(Map<String, dynamic> candidate) {
    List<dynamic> safetyRatings = candidate['safetyRatings'];
    return safetyRatings.every((rating) => rating['probability'] == 'NEGLIGIBLE');
  }

  void decodeAndSetImage(Uint8List imageData) async {
    final codec = await ui.instantiateImageCodec(imageData);
    final frame = await codec.getNextFrame();
    setState(() {
      generatedImage = frame.image;
    });
  }

  void takeSnapshotAndAnalyze(BuildContext context) async {
    setState(() => isLoading = true); // Set loading to true when starting the analysis
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

      String promptText = getPrompt(selectedMode, width,
          height); //prompts[selectedMode]!;
      String jsonBody = jsonEncode({
        "contents": [
          {
            "parts": [
              {"text": promptText},
              {
                "inlineData": {
                  "mimeType": "image/png",
                  "data": base64String
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
          print("Response from model: $responseText");
          if (selectedMode == AiMode.Analysis) {
            _speak(responseText);
          } else if (selectedMode == AiMode.SketchToImage) {
            // Generate an image from a text prompt
            try {
              final imageResponse = await OpenAI.instance.image.create(
                model: 'dall-e-3',
                prompt: responseText,
                n: 1,
                responseFormat: OpenAIImageResponseFormat.b64Json,
              );

              if (imageResponse.data.isNotEmpty) {
                setState(() {
                  Uint8List bytesImage = base64Decode(
                      imageResponse.data.first.b64Json!); // Assuming URL points to a base64 image string
                  decodeAndSetImage(bytesImage!);
                });
              } else {
                print('No image returned from the API');
              }
            } catch (e) {
              print('Error calling OpenAI image generation API: $e');
            }
          } else if (selectedMode == AiMode.ImageToTrace) {
            // Generate an image from a text prompt
            try {
              final imageResponse = await OpenAI.instance.image.create(
                model: 'dall-e-2',
                prompt: responseText,
                n: 1,
                responseFormat: OpenAIImageResponseFormat.b64Json,
              );

              if (imageResponse.data.isNotEmpty) {
                setState(() {
                  Uint8List bytesImage = base64Decode(
                      imageResponse.data.first.b64Json!); // Assuming URL points to a base64 image string
                  decodeAndSetImage(bytesImage!);
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
          _speak("Sorry, content issue. Try again");
        }
      } else {
        print("Failed to get response: ${response.body}");
        _speak("Sorry, network issue. Try again");
      }
    } finally {
      setState(() =>
      isLoading = false); // Reset loading state after operation completes
    }
  }

  void _speak(String text) async {
    if (text.isNotEmpty) {
      await flutterTts.speak(text);
    }
  }
}

class SketchPainter extends CustomPainter {
  final List<Offset?> points;
  final bool showSketch;
  final ui.Image? image;
  final BoxFit boxFit;
  final double transparency;

  SketchPainter(this.points, this.showSketch, this.image, this.boxFit,
      this.transparency);

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the white background
    canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.white);

    // Draw hints or the image overlay
    if (image != null) {
      // Draw the image as an overlay if available
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTWH(0, 0, size.width, size.height),
        image: image!,
        fit: boxFit,
        colorFilter: ColorFilter.mode(
            Colors.white.withOpacity(transparency), BlendMode.dstIn),
      );
    }

    // Draw the sketch
    if (showSketch) {
      Paint paint = Paint()
        ..color = Colors.black
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 5.0;
      for (int i = 0; i < points.length - 1; i++) {
        if (points[i] != null && points[i + 1] != null) {
          canvas.drawLine(points[i]!, points[i + 1]!, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant SketchPainter oldDelegate) => true;
}
