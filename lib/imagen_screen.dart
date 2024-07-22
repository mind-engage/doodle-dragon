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
import 'dart:async';
import 'image_picker_screen.dart';

enum AiMode { Story, Explore, Poetry, PromptToImage }

class ImagenScreen extends StatefulWidget {
  final String geminiApiKey;
  final String openaiApiKey;
  const ImagenScreen({super.key, required this.geminiApiKey, required this.openaiApiKey});

  @override
  _ImagenScreenState createState() => _ImagenScreenState();
}

class _ImagenScreenState extends State<ImagenScreen> {
  List<Offset?> points = [];
  bool showSketch = true;
  bool isErasing = false; // Add this line

  GlobalKey repaintBoundaryKey = GlobalKey();
  FlutterTts flutterTts = FlutterTts();
  bool isLoading = false;
  ui.Image? generatedImage;

  double iconWidth = 80;
  double iconHeight = 80;

  stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isListening = false;
  bool _speechEnabled = false;
  String _sttText = "";
  OverlayEntry? _overlayEntry;
  int learnerAge = 3;

  String getPrompt(AiMode mode) {
    switch (mode) {
      case AiMode.Story:
        return "The attached image is generate by a $learnerAge year child using text to image. Analyze the image and tell a story. Your output is used by the application to play to child using text to speech";
      case AiMode.Poetry:
        return "The attached image is generate by a $learnerAge year child using text to image. Analyze the image and tell a poem.";
      case AiMode.Explore:
        return "Generate a creative and detailed prompt describing this children's drawing to be used for text-to-image generation. The generated image will be used to learn drawing by tracing over. Instruct the model to generate black and traceable line drawing. Generate a suitable prompt with length below 1000 characters";
      case AiMode.PromptToImage:
        return "You are an AI agent helping a 3 year old child to generate a creative and detailed prompt to be passed to text to image generation model."
            "Elaborate the child's requirement $_sttText and  generate the prompt to create the image";
      default:
        return ""; // Handle any other cases or throw an error if needed
    }
  }

  String getMessageToUser(AiMode mode) {
    switch (mode) {
      case AiMode.Story:
        return "I am creating a story for you. Please wait";
      case AiMode.Poetry:
        return "I am making a poem for you. Please wait";
      case AiMode.Explore:
        return "I am finding answer";
      case AiMode.PromptToImage:
        return "Generating the picture. Please wait";
      default:
        return ""; // Handle any other cases or throw an error if needed
    }
  }

  @override
  void initState() {
    super.initState();
    _initTts();
    OpenAI.apiKey = widget.openaiApiKey;
    _initSpeech();
  }

  @override
  void dispose() {
    if (_isListening) {
      _speechToText.stop();
    }

    _removeOverlay();
    flutterTts.stop();
    super.dispose();
  }

  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    setState(() {});
  }

  void _initTts() {
    flutterTts.setLanguage("en-US");
    flutterTts.setPitch(1.0); // Higher pitch often perceived as friendlier by children
    flutterTts.setSpeechRate(0.4); // Slower rate for better comprehension by young children
    flutterTts.awaitSpeakCompletion(true); // Wait for spoken feedback to complete
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
            icon: Image.asset("assets/imagen_square.png", width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            onPressed: () {
                _listen();
            },
            tooltip: 'Clear Sketch',
          ),
          IconButton(
            icon:  Image.asset("assets/save.png", width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            onPressed: _saveGeneratedImage,
          ),
          IconButton(
            icon: Image.asset("assets/library.png", width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            onPressed: _loadImageFromLibrary,
            tooltip: 'Load Image',
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
        ],
      ),
      bottomNavigationBar: isLandscape ? null : BottomAppBar(
        color: Colors.lightBlue,
        height: 180,
        child: controlPanelPortrait(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _listen,
        child: _isListening ? Image.asset('assets/robot_mic.png') : Image.asset('assets/robot_mic.png'),
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
              painter: SketchPainter(points, showSketch, generatedImage),
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

        IconButton(
          icon: Image.asset("assets/story.png", width: iconWidth, height: iconHeight, fit: BoxFit.fill),
          color: Colors.white,
          onPressed: () {
            takeSnapshotAndAnalyze(context,  AiMode.Story);
          },
        ),
        IconButton(
          icon: Image.asset("assets/poem.png", width: iconWidth, height: iconHeight, fit: BoxFit.fill),
          color: Colors.white,
          onPressed: () {
            takeSnapshotAndAnalyze(context,  AiMode.Poetry);
          },
        ),
        IconButton(
          icon: Image.asset("assets/explore.png", width: iconWidth, height: iconHeight, fit: BoxFit.fill),
          color: Colors.white,
          onPressed: () {
            takeSnapshotAndAnalyze(context,  AiMode.Explore);
          },
        ),
        IconButton(
          icon: Image.asset("assets/stop_voice.png", width: iconWidth, height: iconHeight, fit: BoxFit.fill),  // Example icon - you can customize
          color: Colors.deepPurple,
          onPressed: () {
            _stop_speech();
            _abortListening();
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
    setState(() => isLoading = true);   // Set loading to true when starting the analysis

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

      String promptText = getPrompt(selectedMode); //prompts[selectedMode]!;
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
          if (selectedMode == AiMode.Story) {
            _speak(responseText);
          } else if (selectedMode == AiMode.Poetry) {
            _speak(responseText);
          } else if (selectedMode == AiMode.Explore) {
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

  void generatePicture(BuildContext context, AiMode selectedMode) async {
    setState(() => isLoading = true); // Set loading to true when starting the analysis

    _speak(getMessageToUser(selectedMode));

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) => Center(child: CircularProgressIndicator()), // Show a loading spinner
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

  void _saveGeneratedImage() async {
    if (generatedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No image to save')),
      );
      return;
    }

    try {
      ByteData? byteData = await generatedImage!.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final directory = (await getApplicationDocumentsDirectory()).path;
      String filename = 'generated_image_${DateTime.now().millisecondsSinceEpoch}.png';
      File imgFile = File('$directory/$filename');
      await imgFile.writeAsBytes(pngBytes);

      // Optionally, show a message that the file has been saved.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image saved to $filename')),
      );
    } catch (e) {
      print('Error saving generated image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save image')),
      );
    }
  }

  Future<void> _loadImageFromLibrary() async {
    Navigator.of(context).push(MaterialPageRoute(builder: (context) => ImagePickerScreen(onSelect: (File file) {
      _setImage(file);
    })));
  }

  void _setImage(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    decodeAndSetImage(bytes);
  }

  Future<void> _speak(String text) async {
    if (text.isNotEmpty) {
      var completion = Completer<void>();
      flutterTts.setCompletionHandler(() {
        completion.complete();
      });
      await flutterTts.speak(text);
      return completion.future; // Waits until speaking is completed
    }
  }

  void _stop_speech() async {
      await flutterTts.stop();
  }
  void _listen() async {
    if (!_isListening) {
      await _speak("Can you tell me what you'd like to draw?");
      if (_speechEnabled) {
        setState(() => _isListening = true);
        _speechToText.listen(
          onResult: (result) {
            setState(() {
              _sttText = result.recognizedWords;
            });
            _overlayEntry?.markNeedsBuild();  // Rebuild overlay with new text
          },
          listenFor: Duration(seconds: 30),
          pauseFor: Duration(seconds: 5),
        );
        _showOverlay(context);
      }
    } else {
      _stopListening();
    }
  }

  void _stopListening() {
    if (_isListening) {
      setState(() => _isListening = false);
      _speechToText.stop();
      _removeOverlay();
      if(_sttText.isNotEmpty) {
        generatePicture(context, AiMode.PromptToImage);
      }
    }
  }

  void _abortListening() {
    if (_isListening) {
      setState(() => _isListening = false);
      _speechToText.stop();
      _removeOverlay();
      _sttText = "";
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

  SketchPainter(this.points, this.showSketch, this.image);

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
