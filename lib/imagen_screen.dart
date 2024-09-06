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
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/tts_helper.dart';
import "../utils/user_messages.dart";
import "../utils/sketch_painter_v2.dart";
import "../utils/camera_capture.dart";
import 'package:photo_manager/photo_manager.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/log.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'ai_prompts/imagen_prompts.dart';
import 'utils/child_skill_levels.dart';
import 'utils/api_key_manager.dart';

// StatefulWidget to handle the Imagen Screen UI and functionality.
class ImagenScreen extends StatefulWidget {
  const ImagenScreen({super.key});

  @override
  _ImagenScreenState createState() => _ImagenScreenState();
}

class _ImagenScreenState extends State<ImagenScreen>
    with SingleTickerProviderStateMixin {
  late String geminiApiKey;
  late String openaiApiKey;
  bool _isOpenaiAvailble = false;
  late String geminiEndpoint;

  List<ColoredPoint> points = []; // List to hold the points drawn on canvas.
  bool showSketch = true; // Flag to toggle display of the sketch.
  bool isErasing = false; // Flag to toggle eraser mode.

  GlobalKey repaintBoundaryKey =
      GlobalKey(); // Key for the widget used to capture image.
  bool isLoading = false; // Flag to show a loading indicator.
  ui.Image? generatedImage; // Variable to hold the generated image.
  String generatedStory = ""; // Story generated from the image.
  String generatedPoem = ""; // Poem generated from the image.

  double iconWidth = 80; // Icon width for buttons.
  double iconHeight = 80; // Icon height for buttons.

  final stt.SpeechToText _speechToText =
      stt.SpeechToText(); // Speech to text instance.
  bool _isListening = false; // Flag to check if listening.
  bool _speechEnabled = false; // Flag to check if speech is enabled.
  String _sttText = ""; // Text obtained from speech recognition.
  OverlayEntry? _overlayEntry; // Overlay entry for displaying speech text.

  AiMode _aiMode = AiMode.promptToImage; // Default AI mode for operations.

  late SharedPreferences prefs; // Shared preferences for storing data locally.
  String learnerName = "John"; // Default learner name.
  int learnerAge = 3; // Default learner age, used in prompts.
  bool _isWelcoming = false; // Flag to check if welcome message is active.

  TtsHelper ttsHelper = TtsHelper(); // Text to speech helper instance.
  late AnimationController _animationController; // Controller for animations.
  late Animation<double> _animation; // Animation details.
  Color selectedColor = Colors.black; // Default selected color for drawing.
  double currentStrokeWidth = 5.0; // Current stroke width for drawing.
  bool enablePictureZone =
      false; // Flag to enable interaction with the picture zone.

  // Define prompts for different AI modes based on the scenario and user interaction.
  String getVlmPrompt(AiMode mode) {
    String skillsSummary = getSkillsTextForPrompt(learnerAge);
    return ImagenPrompts.getVlmPrompt(
        mode, learnerAge, _sttText, skillsSummary);
  }

  // Generate prompts for image creation based on VLM (Visual Language Model) responses.
  String getImageGenPrompt(AiMode mode, String vlmResponse) {
    String skillsSummary = getSkillsTextForPrompt(learnerAge);
    return ImagenPrompts.getImageGenPrompt(
        mode, learnerAge, vlmResponse, skillsSummary);
  }

  // Return waiting messages to the user based on the current AI mode.
  String getWaitMessageToUser(AiMode mode) {
    switch (mode) {
      case AiMode.story:
        return "I am creating a story for you. Please wait";
      case AiMode.poetry:
        return "I am making a poem for you. Please wait";
      case AiMode.transform:
        return "I am transforming the image. Please wait";
      case AiMode.promptToImage:
        return "Generating the picture. Please wait";
      default:
        return ""; // Handle any other cases or throw an error if needed
    }
  }

  // Return specific messages for voice prompting based on AI mode.
  String getMessageForVoicePrompting(AiMode mode) {
    switch (mode) {
      case AiMode.transform:
        return "Tell me what to explore";
      case AiMode.promptToImage:
        return "Tell me about your imagination?";
      default:
        return ""; // Handle any other cases or throw an error if needed
    }
  }

  // Initialize state, set up animations, and load settings.
  @override
  void initState() {
    super.initState();
    _initializeKeys();
    loadSettings();
    //OpenAI.apiKey = widget.openaiApiKey;
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
    ttsHelper.stop();

    _removeOverlay();
    super.dispose();
  }

  Future<void> _initializeKeys() async {
    final apiKeyManager = await APIKeyManager.getInstance();
    setState(() {
      geminiApiKey = apiKeyManager.geminiApiKey;
      openaiApiKey = apiKeyManager.openaiApiKey;
      geminiEndpoint = apiKeyManager.geminiEndpoint;
    });
    OpenAI.apiKey = openaiApiKey; // Initialize OpenAI with the fetched API key.
    _isOpenaiAvailble = openaiApiKey.isNotEmpty;
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
    ttsHelper.speak(userMessageImagenScreen);
  }

  Future<void> _stopWelcome() async {
    _isWelcoming = false;
    await ttsHelper.astop();
  }

  void _msgSGeneratePicture() {
    ttsHelper.speak("First generate a picture");
  }

  // Initialize speech recognition capabilities.
  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    setState(() {});
  }

  // Initialize animation for interactive elements like the microphone icon.
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

  void _openCamera() async {
    ttsHelper.stop();
    _abortListening();

    final image = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CameraCapture()),
    );
    if (image != null) {
      final Uint8List imageData = await image.readAsBytes();
      decodeAndSetImage(imageData);
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
                    icon: Image.asset("assets/camera.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                    onPressed: _openCamera,
                    tooltip: 'Capture Image',
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
                    onPressed: generatedImage != null
                        ? _saveGeneratedImage
                        : _msgSGeneratePicture,
                    tooltip: 'Save Image',
                  ),
                ),
                Flexible(
                  child: IconButton(
                    color: Colors.white,
                    highlightColor: Colors.orange,
                    icon: Image.asset("assets/share.png",
                        width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                    onPressed: generatedImage != null
                        ? shareCanvas
                        : _msgSGeneratePicture,
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
        _isOpenaiAvailble
            ? Flexible(
                child: IconButton(
                  color: Colors.white,
                  highlightColor: Colors.orange,
                  icon: generatedImage == null
                      ? Image.asset("assets/imagen_square.png",
                          width: iconWidth,
                          height: iconHeight,
                          fit: BoxFit.fill)
                      : Image.asset("assets/explore.png",
                          width: iconWidth,
                          height: iconHeight,
                          fit: BoxFit.fill),
                  onPressed: generatedImage == null
                      ? () {
                          setState(() {
                            _aiMode = AiMode.promptToImage;
                          });
                          _listen();
                        }
                      : () {
                          setState(() {
                            _aiMode = AiMode.transform;
                          });
                          _listen();
                        },
                  tooltip: 'Imagen',
                ),
              )
            : Flexible(
                child: IconButton(
                  color: Colors.white,
                  highlightColor: Colors.orange,
                  icon: Image.asset("assets/explore.png",
                      width: iconWidth, height: iconHeight, fit: BoxFit.fill),
                  onPressed: () {
                    setState(() {
                      _aiMode = AiMode.transform;
                    });
                    _listen();
                  },
                  tooltip: 'Imagen',
                ),
              ),
        Flexible(
          child: IconButton(
            icon: Image.asset("assets/story.png",
                width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            color: Colors.white,
            highlightColor: Colors.orange,
            onPressed: generatedImage != null
                ? () {
                    takeSnapshotAndAnalyze(context, AiMode.story);
                  }
                : _msgSGeneratePicture,
            tooltip: 'Tell Story',
          ),
        ),
        Flexible(
          child: IconButton(
            icon: Image.asset("assets/poem.png",
                width: iconWidth, height: iconHeight, fit: BoxFit.fill),
            color: Colors.white,
            highlightColor: Colors.orange,
            onPressed: generatedImage != null
                ? () {
                    takeSnapshotAndAnalyze(context, AiMode.poetry);
                  }
                : _msgSGeneratePicture,
            tooltip: 'Tell a Poem',
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

  // Decode and set the image from byte data.
  void decodeAndSetImage(Uint8List imageData) async {
    final codec = await ui.instantiateImageCodec(imageData);
    final frame = await codec.getNextFrame();
    setState(() {
      generatedImage = frame.image;
      generatedStory = "";
      generatedPoem = "";
    });
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
          text:
              'Check out my Doodle Dragon creation!\n\nPoem:\n$generatedPoem\n\nStory:\n$generatedStory');
    } catch (e) {
      if (kDebugMode) {
        Log.d('Error sharing canvas: $e');
      }
    }
  }

  // Take a snapshot of the current drawing and analyze it using AI.
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

      String promptText = getVlmPrompt(selectedMode); //prompts[selectedMode]!;
      if (kDebugMode) {
        Log.d("Prompt to Gemini: $promptText");
      }
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
        Uri.parse('$geminiEndpoint?key=$geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonBody,
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> decodedResponse = jsonDecode(response.body);
        Map<String, dynamic> candidate = decodedResponse['candidates'][0];
        if (isContentSafe(candidate)) {
          String responseText = candidate['content']['parts'][0]['text'];
          if (kDebugMode) {
            Log.d("Response from Gemini: $responseText");
          }
          if (selectedMode == AiMode.story) {
            setState(() {
              generatedStory = responseText;
            });
            ttsHelper.speak(responseText);
          } else if (selectedMode == AiMode.poetry) {
            setState(() {
              generatedPoem = responseText;
            });
            ttsHelper.speak(responseText);
          } else if (selectedMode == AiMode.transform) {
            if (_isOpenaiAvailble) {
              // Generate an image from a text prompt
              try {
                final imageResponse = await OpenAI.instance.image.create(
                  model: 'dall-e-3',
                  prompt: getImageGenPrompt(selectedMode, responseText),
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
                    Log.d('No image returned from the API');
                  }
                  ttsHelper.speak("Failed to generate image. Try again");
                }
              } catch (e) {
                if (kDebugMode) {
                  Log.d('Error calling OpenAI image generation API: $e');
                }
                ttsHelper.speak("Failed to generate image. Try again");
              }
            } else {
              // Only text response
              ttsHelper.speak(responseText);
            }
          }
        } else {
          if (kDebugMode) {
            Log.d("Content is not safe for children.");
          }
          ttsHelper.speak("Sorry, content issue. Try again");
        }
      } else {
        if (kDebugMode) {
          Log.d("Failed to get response: ${response.body}");
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
      String promptText = getVlmPrompt(selectedMode);
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
        Uri.parse('$geminiEndpoint?key=$geminiApiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonBody,
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> decodedResponse = jsonDecode(response.body);
        Map<String, dynamic> candidate = decodedResponse['candidates'][0];
        if (isContentSafe(candidate)) {
          String responseText = candidate['content']['parts'][0]['text'];
          if (kDebugMode) {
            Log.d("Response from model: $responseText");
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
                Log.d('No image returned from the API');
              }
            }
          } catch (e) {
            if (kDebugMode) {
              Log.d('Error calling OpenAI image generation API: $e');
            }
          }
        } else {
          if (kDebugMode) {
            Log.d("Content is not safe for children.");
          }
          ttsHelper.speak("Sorry, content issue. Try again");
        }
      } else {
        if (kDebugMode) {
          Log.d("Failed to get response: ${response.body}");
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

  Future<void> requestPermissions() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      await Permission.storage.request();
    }
  }

  Future<bool> saveImage() async {
    try {
      ByteData? byteData =
          await generatedImage!.toByteData(format: ui.ImageByteFormat.png);
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

  void _saveGeneratedImage() async {
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

  Future<void> _loadImageFromLibrary() async {
    ttsHelper.stop();
    _abortListening();

    final ImagePicker _picker = ImagePicker();
    // Pick an image
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      File imageFile = File(image.path);
      _setImage(imageFile);
    }
  }

  void _setImage(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    decodeAndSetImage(bytes);
  }

  void _listen() async {
    if (_isWelcoming) await _stopWelcome();

    if (!_isListening) {
      await ttsHelper.speak(getMessageForVoicePrompting(_aiMode));
      await ttsHelper.speak(" ");
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
        if (_aiMode == AiMode.promptToImage) {
          generatePicture(context, AiMode.promptToImage);
        } else if (_aiMode == AiMode.transform) {
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
