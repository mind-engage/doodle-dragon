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
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/tts_helper.dart';
import '../utils/trace_image_picker.dart';

enum AiMode { Analysis, ImageToTrace, PromptToImage }

class TraceScreen extends StatefulWidget {
  final String geminiApiKey;
  final String openaiApiKey;
  const TraceScreen(
      {super.key, required this.geminiApiKey, required this.openaiApiKey});

  @override
  _TraceScreenState createState() => _TraceScreenState();
}

class _TraceScreenState extends State<TraceScreen>
    with SingleTickerProviderStateMixin {
  List<ColoredPoint> points = [];
  bool showSketch = true;
  bool isErasing = false; // Add this line

  GlobalKey repaintBoundaryKey = GlobalKey();
  bool isLoading = false;
  final double canvasWidth = 1024;
  final double canvasHeight = 1920;
  ui.Image? generatedImage;
  List<double> _transparencyLevels = [0.0, 0.5, 1.0];
  int _currentTransparencyLevel = 2;

  double iconWidth = 80;
  double iconHeight = 80;

  stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isListening = false;
  bool _speechEnabled = false;
  String _sttText = "";
  OverlayEntry? _overlayEntry;

  Color selectedColor = Colors.black; // Default color
  List<Color> colorPalette = [
    Colors.black,
    Colors.red,
    Colors.green,
    Colors.blue,
    Colors.yellow
  ];
  AiMode _aiMode = AiMode.PromptToImage;
  int learnerAge = 3;
  late AnimationController _animationController;
  late Animation<double> _animation;

  late SharedPreferences prefs;
  String learnerName = "John";
  TtsHelper ttsHelper = TtsHelper();

  String getPrompt(AiMode mode, String userInput) {
    switch (mode) {
      case AiMode.Analysis:
        return "The attached sketch is traced by a $learnerAge old child based on the attached drawing. Find difference between original and traced drawings nd suggest improvements. The output is used to play to child using text to speech";
      case AiMode.PromptToImage:
        // TODO: Interactive prompting
        // return "You are an AI assistant collaborating with a $learnerAge-year-old child. Based on the child's input, '$userInput', craft a clear, simple prompt for a text-to-image model. The goal is to create a black and white outline image with basic shapes and minimal details. This outline should be easy for the child to trace. Use guiding questions to gather enough details to form simple shapes without color, ensuring the outline is engaging yet simple enough to enhance the child’s tracing skills.";
        return "You are an AI assistant collaborating with a $learnerAge year old child."
            "Based on the child's input, '$userInput', craft a clear, simple prompt for a text-to-image model."
            "The goal is to create a black and white outline image with basic shapes and minimal details appropriate for age  $learnerAge."
            "This outline should be easy for the child to trace.";
      default:
        return ""; // Handle any other cases or throw an error if needed
    }
  }

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

  String getTraceLibrary() {
    //int learnerAge
    return "https://storage.googleapis.com/storage/v1/b/doodle-dragon/o?prefix=tracing/alphabets-preschool/&delimiter=/";
  }

  @override
  void initState() {
    super.initState();
    loadSettings();
    OpenAI.apiKey = widget.openaiApiKey;
    _initSpeech();
    _initAnimation();
  }

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

  Future<void> loadSettings() async {
    prefs = await SharedPreferences.getInstance();
    setState(() {
      learnerName = prefs.getString('learnerName') ?? "";
      learnerAge = prefs.getInt('learnerAge') ?? 3;
    });
    _welcomeMessage();
  }

  void _welcomeMessage() {
    ttsHelper.speak("Welcome $learnerName! Get an image to trace");
  }

  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    setState(() {});
  }

  void _initAnimation() {
    _animationController = AnimationController(
      vsync: this,
      duration:
          Duration(milliseconds: 500), // Duration of half cycle of oscillation
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
            Text('Tracing',
                style: TextStyle(
                    color: Colors.white)), // Adjust text style as needed
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Flexible(
                  child: IconButton(
                    icon: Image.asset("assets/imagen_square.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                    onPressed: () {
                      setState(() {
                        _aiMode = AiMode.PromptToImage;
                      });
                      _listen();
                    },
                    tooltip: 'Clear Sketch',
                  ),
                ),
                Flexible(
                  child: IconButton(
                    icon: Image.asset("assets/library.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                    onPressed: _loadImageFromLibrary,
                    tooltip: 'Load Image',
                  ),
                ),
                IconButton(
                  icon: Image.asset("assets/share.png",
                      width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                  onPressed: shareCanvas,
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
      floatingActionButton: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Transform.rotate(
            angle: _animation.value,
            child: FloatingActionButton(
              onPressed: () {
                _listen();
              },
              backgroundColor: Colors.transparent,
              shape: CircleBorder(),
              child: Image.asset(_isListening
                  ? 'assets/robot_mic.png'
                  : 'assets/robot_mic.png'),
            ),
          );
        },
      ),
    );
  }

  void _animateMic(bool listening) {
    if (listening) {
      _animationController.forward();
    } else {
      _animationController.stop();
    }
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
        IconButton(
          icon: Image.asset("assets/analysis.png",
              width: iconWidth, height: iconHeight, fit: BoxFit.fill),
          color: Colors.white,
          onPressed: () {
            takeSnapshotAndAnalyze(context, AiMode.Analysis, "");
          },
        ),
        IconButton(
          icon: Image.asset("assets/transparency.png",
              width: iconWidth,
              height: iconHeight,
              fit: BoxFit.fill), // Example icon - you can customize
          color: Colors.deepPurple,
          onPressed: () {
            setState(() {
              _currentTransparencyLevel =
                  (_currentTransparencyLevel + 1) % _transparencyLevels.length;
            });
          },
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
    Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => TraceImagePicker(
            onSelect: (String imageUrl) async {
              // Download the image from the URL
              File imageFile =
                  await _downloadFile(imageUrl, 'selected_image.png');
              _setImage(imageFile);
            },
            folder: getTraceLibrary())));
  }

  void _setImage(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    decodeAndSetImage(bytes);
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

  void takeSnapshotAndAnalyze(
      BuildContext context, AiMode selectedMode, String userInput) async {
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

      Size size = boundary.size;
      double width = size.width;
      double height = size.height;
      /*
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();
      */
      ui.Image image = await drawPointsToImage(points, size);
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
          print("Response from model: $responseText");
          if (selectedMode == AiMode.Analysis) {
            ttsHelper.speak(responseText);
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

  void generatePicture(
      BuildContext context, AiMode selectedMode, userInput) async {
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
          print("Response from model: $responseText");
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

  void _listen() async {
    if (!_isListening) {
      _animateMic(true);
      await ttsHelper.speak("Can you tell me what you'd like to draw?");
      if (_speechEnabled) {
        setState(() => _isListening = true);
        _speechToText.listen(
          onResult: (result) {
            setState(() {
              _sttText = result.recognizedWords;
            });
            _overlayEntry?.markNeedsBuild(); // Rebuild overlay with new text
          },
          listenFor: Duration(seconds: 30),
          pauseFor: Duration(seconds: 5),
        );
        _showOverlay(context);
      }
    } else {
      _animateMic(false);
      _completeListening();
    }
  }

  void _completeListening() {
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

  Future<ui.Image> drawPointsToImage(
      List<ColoredPoint> points, Size size) async {
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
