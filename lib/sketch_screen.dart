import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:dart_openai/dart_openai.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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
  bool isErasing = false; // Add this line

  GlobalKey repaintBoundaryKey = GlobalKey();
  FlutterTts flutterTts = FlutterTts();
  bool isLoading = false;
  final double canvasWidth = 1024;
  final double canvasHeight = 1920;
  ui.Image? generatedImage;
  List<double> _transparencyLevels = [0.0, 0.3, 0.7, 1.0];
  int _currentTransparencyLevel = 0;

  double iconWidth = 80;
  double iconHeight = 80;

  stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isListening = false;
  bool _speechEnabled = false;
  String _sttText = "Press the button and start speaking";
  OverlayEntry? _overlayEntry;

  String getPrompt(AiMode mode, double canvasWidth, double canvasHeight) {
    switch (mode) {
      case AiMode.Analysis:
        return "The attached sketch is drawn by a child. Analyze and suggest improvements. The output is used to play to child using text to speech";
      case AiMode.SketchToImage:
        return "Generate a creative and detailed prompt describing this children's drawing to be used for text-to-image generation. The generated image should closely resemble the drawing, but colorful";
      case AiMode.ImageToTrace:
        return "Generate a creative and detailed prompt describing this children's drawing to be used for text-to-image generation. The generated image will be used to learn drawing by tracing over. Instruct the model to generate black and traceable line drawing. Generate a suitable prompt with length below 1000 characters";
      default:
        return ""; // Handle any other cases or throw an error if needed
    }
  }

  String getMessageToUser(AiMode mode) {
    switch (mode) {
      case AiMode.Analysis:
        return "I will be analyzing your drawing. Please wait";
      case AiMode.SketchToImage:
        return "I will convert your sketch to an image. Please wait";
      case AiMode.ImageToTrace:
        return "I will convert the image to traceable sketch. Please wait";
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
    _initSpeech();
  }

  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    bool isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        systemOverlayStyle: SystemUiOverlayStyle(
          // Status bar color
          statusBarColor: Colors.deepPurple,

          // Status bar brightness (optional)
          statusBarIconBrightness: Brightness.dark, // For Android (dark icons)
          statusBarBrightness: Brightness.light, // For iOS (dark icons)
        ),
        title: Text('Doodle Dragon'),
        backgroundColor: Colors.lightBlue,
        foregroundColor: Colors.red,
        toolbarHeight: isLandscape ? 0 : 150,

        actions: <Widget>[
          IconButton(
            icon: Image.asset("assets/delete.png", width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            onPressed: () {
              setState(() {
                points.clear(); // Clear all points
              });
            },
            tooltip: 'Clear Sketch',
          ),
          IconButton(
            icon: showSketch ? Image.asset("assets/visibility_on.png", width: iconWidth, height: iconHeight, fit: BoxFit.fill) :
              Image.asset("assets/visibility_off.png", width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            onPressed: () {
              setState(() {
                showSketch = !showSketch;
              });
            },
          ),
          IconButton(
            icon: isErasing ? Image.asset("assets/brush.png", width: iconWidth, height: iconHeight, fit: BoxFit.fill) :
              Image.asset("assets/eraser.png", width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            onPressed: () {
              setState(() {
                isErasing = !isErasing;
              });
            },
            tooltip: 'Toggle Erase',
          ),
          IconButton(
            icon: Image.asset("assets/share.png", width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            onPressed: shareCanvas,
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
        color: Colors.lightBlue,
        height: 180,
        child: controlPanelPortrait(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _listen,
        child: Icon(_isListening ? Icons.mic : Icons.mic_none),
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
              double appBarHeight = 150;//AppBar().toolbarHeight!;
              double topPadding = MediaQuery.of(context).padding.top;

              Offset adjustedPosition = details.globalPosition - Offset(0, appBarHeight + topPadding);
              Offset localPosition = renderBox.globalToLocal(adjustedPosition);

              if (!isErasing) {
                points.add(localPosition);
              } else {
                points = points.where((p) => p == null || (p - localPosition).distance > 20).toList();
              }
            });
          },
          onPanEnd: (details) => setState(() => points.add(null)),
          child: RepaintBoundary(
            key: repaintBoundaryKey,
            child: CustomPaint(
              painter: SketchPainter(points, showSketch, generatedImage, _transparencyLevels[_currentTransparencyLevel]),
              child: Container(),
            ),
          ),
        ),
      ),
    ],
  );


  Widget controlPanelLandscape() {
    return  Container(
      width: 80, // Adjust width as needed
      color: Theme.of(context).primaryColor,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget controlPanelPortrait() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(width: 16),

        IconButton(
          icon: Image.asset("assets/analysis.png", width: iconWidth, height: iconHeight, fit: BoxFit.fill),
          color: Colors.white,
          onPressed: () {
            takeSnapshotAndAnalyze(context,  AiMode.Analysis);
          },
        ),
        IconButton(
          icon: Image.asset("assets/sketch_to_image.png", width: iconWidth, height: iconHeight, fit: BoxFit.fill),
          color: Colors.white,
          onPressed: () {
            takeSnapshotAndAnalyze(context,  AiMode.SketchToImage);
          },
        ),
        IconButton(
          icon: Image.asset("assets/image_to_trace.png", width: iconWidth, height: iconHeight, fit: BoxFit.fill),
          color: Colors.white,
          onPressed: () {
            takeSnapshotAndAnalyze(context,  AiMode.ImageToTrace);
          },
        ),
        IconButton(
          icon: Image.asset("assets/transparency.png", width: iconWidth, height: iconHeight, fit: BoxFit.fill),  // Example icon - you can customize
          color: Colors.deepPurple,
          onPressed: () {
            setState(() {
              _currentTransparencyLevel = (_currentTransparencyLevel + 1) % _transparencyLevels.length;
            });
          },
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

  void shareCanvas() async {
    try {
      RenderRepaintBoundary boundary = repaintBoundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final directory = (await getApplicationDocumentsDirectory()).path;
      File imgFile = File('$directory/sketch.png');
      await imgFile.writeAsBytes(pngBytes);

      // Using Share.shareXFiles from share_plus
      await Share.shareXFiles([XFile(imgFile.path)], text: 'Check out my sketch!');
    } catch (e) {
      print('Error sharing canvas: $e');
    }
  }
  void takeSnapshotAndAnalyze(BuildContext context, AiMode selectedMode) async {
    setState(() => isLoading = true); // Set loading to true when starting the analysis

    _speak(getMessageToUser(selectedMode));

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) => Center(child: CircularProgressIndicator()), // Show a loading spinner
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
                size: OpenAIImageSize.size1024,
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
                model: 'dall-e-3',
                prompt: responseText,
                n: 1,
                size: OpenAIImageSize.size1024,
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
      setState(() => isLoading = false); // Reset loading state after operation completes
      Navigator.of(context).pop();
    }
  }

  void _speak(String text) async {
    if (text.isNotEmpty) {
      await flutterTts.speak(text);
    }
  }

  void _listen() async {
    if (!_isListening) {
      _speak("Tell what you want draw");
      if (_speechEnabled) {
        setState(() => _isListening = true);
        _speechToText.listen(
          onResult: (result) {
            setState(() {
              _sttText = result.recognizedWords;
            });
            _overlayEntry?.markNeedsBuild();  // Rebuild overlay with new text
          },
        );
        _showOverlay(context);  // Show overlay when starting to listen
      }
    } else {
      setState(() => _isListening = false);
      _speechToText.stop();
      _removeOverlay();  // Remove overlay when not listening
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
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _sttText,
              style: TextStyle(color: Colors.white, fontSize: 16),
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
}

class SketchPainter extends CustomPainter {
  final List<Offset?> points;
  final bool showSketch;
  final ui.Image? image;
  final double transparency;

  SketchPainter(this.points, this.showSketch, this.image, this.transparency);

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
        fit: BoxFit.contain,
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
