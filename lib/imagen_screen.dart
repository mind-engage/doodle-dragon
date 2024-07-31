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
import 'utils/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/tts_helper.dart';
import "../utils/user_messages.dart";
import "../utils/sketch_painter_v2.dart";

enum AiMode { Story, Explore, Poetry, PromptToImage }

class ImagenScreen extends StatefulWidget {
  final String geminiApiKey;
  final String openaiApiKey;
  const ImagenScreen(
      {super.key, required this.geminiApiKey, required this.openaiApiKey});

  @override
  _ImagenScreenState createState() => _ImagenScreenState();
}

class _ImagenScreenState extends State<ImagenScreen>
    with SingleTickerProviderStateMixin {
  List<ColoredPoint> points = [];
  bool showSketch = true;
  bool isErasing = false; // Add this line

  GlobalKey repaintBoundaryKey = GlobalKey();
  bool isLoading = false;
  ui.Image? generatedImage;

  double iconWidth = 80;
  double iconHeight = 80;

  final stt.SpeechToText _speechToText = stt.SpeechToText();
  bool _isListening = false;
  bool _speechEnabled = false;
  String _sttText = "";
  OverlayEntry? _overlayEntry;

  // Default mode for voice listen commands
  AiMode _aiMode = AiMode.PromptToImage;

  late SharedPreferences prefs;
  String learnerName = "John";
  int learnerAge = 3;
  bool _isWelcoming = false;

  TtsHelper ttsHelper = TtsHelper();
  late AnimationController _animationController;
  late Animation<double> _animation;
  Color selectedColor = Colors.black;
  double currentStrokeWidth = 5.0;
  bool enablePictureZone = false;

  String getPrompt(AiMode mode) {
    switch (mode) {
      case AiMode.Story:
        return "The attached image is generate by a $learnerAge year child using text to image. Analyze the image and tell a story. Your output is used by the application to play to child using text to speech";
      case AiMode.Poetry:
        return "The attached image is generate by a $learnerAge year child using text to image. Analyze the image and tell a poem.";
      case AiMode.Explore:
        return "The attached image is generate by a $learnerAge year child using text to image."
            "The child wants to explore more about the contents in this image. and has an enquiry."
            "child's enquiry: $_sttText"
            "Generate a reply to the child in the context of supplied image. The answer should help child's exploration curiosity. Your answer also will be used to generate an image";
      case AiMode.PromptToImage:
        return "You are an AI agent helping a 3 year old child to generate a creative and detailed prompt to be passed to text to image generation model."
            "Elaborate the child's requirement $_sttText and  generate the prompt to create the image";
      default:
        return ""; // Handle any other cases or throw an error if needed
    }
  }

  String getWaitMessageToUser(AiMode mode) {
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

  String getMessageForVoicePrompting(AiMode mode) {
    switch (mode) {
      case AiMode.Explore:
        return "Tell me what to explore";
      case AiMode.PromptToImage:
        return "Can you tell me what you'd like to draw?";
      default:
        return ""; // Handle any other cases or throw an error if needed
    }
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
    ttsHelper.stop();

    _removeOverlay();
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
    _isWelcoming = true;
    ttsHelper.speak(userMessageImagenScreen);
  }

  void _stopWelcome() {
    _isWelcoming = false;
    ttsHelper.stop();
  }

  void _msgSGeneratePicture() {
    ttsHelper.speak("First generate a picture");
  }

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
        titleSpacing: 0,
        toolbarHeight: 150,
        title: Column(
          children: <Widget>[
            const Text('Imagening',
                style: TextStyle(
                    color: Colors.white)), // Adjust text style as needed
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Flexible(
                  child: IconButton(
                    color: Colors.white,
                    highlightColor: Colors.orange,
                    icon: Image.asset("assets/imagen_square.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                    onPressed: () {
                      setState(() {
                        _aiMode = AiMode.PromptToImage;
                      });
                      _listen();
                    },
                    tooltip: 'Prompt to Image',
                  ),
                ),

                Flexible(
                  child: IconButton(
                    color: Colors.white,
                    highlightColor: Colors.orange,
                    icon: Image.asset("assets/library.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                    onPressed: _loadImageFromLibrary,
                    tooltip: 'Load Image',
                  ),
                ),
                Flexible(
                  child: IconButton(
                    color: Colors.white,
                    highlightColor: Colors.orange,
                    icon: Image.asset("assets/save.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                    onPressed: generatedImage != null ? _saveGeneratedImage : _msgSGeneratePicture,
                    tooltip: 'Save Image',
                  ),
                ),
                Flexible(
                  child: IconButton(
                    color: Colors.white,
                    highlightColor: Colors.orange,
                    icon: Image.asset("assets/share.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                    onPressed: generatedImage != null ? shareCanvas : _msgSGeneratePicture,
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
              onPanUpdate: enablePictureZone
                  ? (details) {
                      // Only listen to pan updates when enablePictureZone is true
                      setState(() {
                        RenderBox renderBox =
                            context.findRenderObject() as RenderBox;
                        double appBarHeight = 150;
                        double topPadding = MediaQuery.of(context).padding.top;

                        Offset adjustedPosition = details.globalPosition -
                            Offset(0, appBarHeight + topPadding);
                        Offset localPosition =
                            renderBox.globalToLocal(adjustedPosition);

                        if (!isErasing) {
                          points.add(ColoredPoint(localPosition, selectedColor,
                              currentStrokeWidth));
                        } else {
                          points = points
                              .where((p) =>
                                  p.point == null ||
                                  (p.point! - localPosition).distance > 20)
                              .toList();
                        }
                      });
                    }
                  : null,
              onPanEnd: enablePictureZone
                  ? (details) => setState(() => points.add(
                      ColoredPoint(null, selectedColor, currentStrokeWidth)))
                  : null,
              child: RepaintBoundary(
                key: repaintBoundaryKey,
                child: CustomPaint(
                  painter:
                      SketchPainter(points, showSketch, generatedImage, 1.0),
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
          child: IconButton(
            icon: Image.asset("assets/story.png",
                width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            color: Colors.white,
            highlightColor: Colors.orange,
            onPressed: generatedImage != null ? () {
              takeSnapshotAndAnalyze(context, AiMode.Story);
            } : _msgSGeneratePicture,
            tooltip: 'Tell Story',
          ),
        ),
        Flexible(
          child: IconButton(
            icon: Image.asset("assets/poem.png",
                width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            color: Colors.white,
            highlightColor: Colors.orange,
            onPressed: generatedImage != null ? () {
              takeSnapshotAndAnalyze(context, AiMode.Poetry);
            } : _msgSGeneratePicture,
            tooltip: 'Tell a Poem',
          ),
        ),
        Flexible(
          child: IconButton(
            icon: Image.asset("assets/explore.png",
                width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            color: Colors.white,
            highlightColor: Colors.orange,
            onPressed: generatedImage != null ? () {
              setState(() {
                _aiMode = AiMode.Explore;
              });
              _listen();
            } : _msgSGeneratePicture,
            tooltip: 'Explore',
          ),
        ),
        Flexible(
          child: IconButton(
            icon: Image.asset("assets/stop_voice.png",
                width: iconWidth,
                height: iconHeight,
                fit: BoxFit.fill), // Example icon - you can customize
            color: Colors.white,
            highlightColor: Colors.orange,
            onPressed: () {
              ttsHelper.stop();
              _abortListening();
            },
            tooltip: 'Stop Voice',
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
      if (kDebugMode) {
        print('Error sharing canvas: $e');
      }
    }
  }

  void takeSnapshotAndAnalyze(BuildContext context, AiMode selectedMode) async {
    setState(() =>
        isLoading = true); // Set loading to true when starting the analysis

    ttsHelper.speak(getWaitMessageToUser(selectedMode));

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
          if (kDebugMode) {
            print("Response from model: $responseText");
          }
          if (selectedMode == AiMode.Story) {
            ttsHelper.speak(responseText);
          } else if (selectedMode == AiMode.Poetry) {
            ttsHelper.speak(responseText);
          } else if (selectedMode == AiMode.Explore) {
            //ttsHelper.speak(responseText);
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
                ttsHelper.speak(responseText);
              } else {
                if (kDebugMode) {
                  print('No image returned from the API');
                }
                ttsHelper.speak("Failed to generate image. Try again");
              }
            } catch (e) {
              if (kDebugMode) {
                print('Error calling OpenAI image generation API: $e');
              }
              ttsHelper.speak("Failed to generate image. Try again");
            }
          }
        } else {
          if (kDebugMode) {
            print("Content is not safe for children.");
          }
          ttsHelper.speak("Sorry, content issue. Try again");
        }
      } else {
        if (kDebugMode) {
          print("Failed to get response: ${response.body}");
        }
        ttsHelper.speak("Sorry, network issue. Try again");
      }
    } finally {
      setState(() =>
          isLoading = false); // Reset loading state after operation completes
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void generatePicture(BuildContext context, AiMode selectedMode) async {
    setState(() =>
        isLoading = true); // Set loading to true when starting the analysis

    ttsHelper.speak(getWaitMessageToUser(selectedMode));

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) => const Center(
          child: CircularProgressIndicator()), // Show a loading spinner
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
          if (kDebugMode) {
            print("Response from model: $responseText");
          }
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
              if (kDebugMode) {
                print('No image returned from the API');
              }
            }
          } catch (e) {
            if (kDebugMode) {
              print('Error calling OpenAI image generation API: $e');
            }
          }
        } else {
          if (kDebugMode) {
            print("Content is not safe for children.");
          }
          ttsHelper.speak("Sorry, content issue. Try again");
        }
      } else {
        if (kDebugMode) {
          print("Failed to get response: ${response.body}");
        }
        ttsHelper.speak("Sorry, network issue. Try again");
      }
    } finally {
      setState(() => isLoading = false);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _saveGeneratedImage() async {
    if (generatedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No image to save')),
      );
      return;
    }

    try {
      ByteData? byteData =
          await generatedImage!.toByteData(format: ui.ImageByteFormat.png);
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final directory = (await getApplicationDocumentsDirectory()).path;
      String filename =
          'generated_image_${DateTime.now().millisecondsSinceEpoch}.png';
      File imgFile = File('$directory/$filename');
      await imgFile.writeAsBytes(pngBytes);

      // Optionally, show a message that the file has been saved.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image saved to $filename')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving generated image: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save image')),
        );
      }
    }
  }

  Future<void> _loadImageFromLibrary() async {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => ImagePicker(onSelect: (File file) {
              _setImage(file);
            })));
  }

  void _setImage(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    decodeAndSetImage(bytes);
  }

  void _listen() async {
    if (_isWelcoming) _stopWelcome();

    if (!_isListening) {
      await ttsHelper.speak(getMessageForVoicePrompting(_aiMode));
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
        if (_aiMode == AiMode.PromptToImage) {
          generatePicture(context, AiMode.PromptToImage);
        } else if (_aiMode == AiMode.Explore) {
          takeSnapshotAndAnalyze(context, _aiMode);
        }
      }
    }
  }

  void _abortListening() {
    if (_isListening) {
      setState(() => _isListening = false);
      _speechToText.stop();
      _removeOverlay();
      _sttText = "";
      _animateMic(false);
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
}
