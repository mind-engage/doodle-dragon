import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

enum FeedbackMode { Analysis, Hints, DesignFeedback }

class SketchScreen extends StatefulWidget {
  final String apiKey;
  const SketchScreen({super.key, required this.apiKey});

  @override
  _SketchScreenState createState() => _SketchScreenState();
}

class _SketchScreenState extends State<SketchScreen> {
  List<Offset?> points = [];
  List<DrawingElement> missingElements = [];
  bool showHints = false; // Flag to toggle hint visibility

  GlobalKey repaintBoundaryKey = GlobalKey();
  FeedbackMode selectedMode = FeedbackMode.Analysis;
  FlutterTts flutterTts = FlutterTts();
  bool isLoading = false;  // Add a boolean state variable to track loading
  final double canvasWidth = 1024;
  final double canvasHeight = 1920;

  String getPrompt(FeedbackMode mode) {
    switch (mode) {
      case FeedbackMode.Analysis:
        return "The attached sketch is drawn by a child. Analyze and suggest improvements. The output is used to play to child using text to speech";
      case FeedbackMode.Hints:
          return '''You are a helpful AI assistant that can analyze images of children's drawings and provide feedback..
                    As a model, you analyze and suggest missing elements yet to be drawn or modified.
                    Analyze the provided image of a child's drawing. Identify any common facial features that are missing. 
                    Provide a list of the missing element names and their estimated bounding boxes in the image
                    The image has width $canvasWidth and height $canvasHeight.
                    Use the following JSON format to represent your response:

                    ```json
                    [{"element": "element_name", "bounds": [[x_min, y_min], [x_max, y_max]]}, ...]
                    
                    
                  **Where:**
                  
                  * `"element_name"` is the name of the missing element (e.g., "hair", "ears", "eyebrows", "nose", leg, trunk, handle). 
                  * `[x_min, y_min]` represents the top-left corner coordinates of the bounding box.
                  * `[x_max, y_max]` represents the bottom-right corner coordinates of the bounding box.
                  
                  Ensure the bounding box coordinates are within the image's dimensions. You can assume the top-left corner of the image is at coordinates [0, 0].
                 ''';

      case FeedbackMode.DesignFeedback:
        return "Provide feedback on the design elements of the attached sketch.";
    }
  }

  @override
  void initState() {
    super.initState();
    flutterTts.setLanguage("en-US");
    flutterTts.setSpeechRate(0.5);
  }

  List<DrawingElement> parseModelResponse(String response) {
    // Remove any non-JSON prefix like ```json
    int startIndex = response.indexOf('[');  // Assuming the JSON always starts with an array
    if (startIndex == -1) {
      print("No JSON array found in response.");
      return [];
    }
    // Assuming the JSON is well-formed and ends with ']', trim anything after the last ']'
    int endIndex = response.lastIndexOf(']');
    if (endIndex == -1 || endIndex < startIndex) {
      print("Malformed JSON data.");
      return [];
    }
    String jsonPart = response.substring(startIndex, endIndex + 1);

    // Attempt to parse the trimmed JSON part
    try {
      List<dynamic> jsonData = json.decode(jsonPart);
      List<DrawingElement> elements = jsonData.map((jsonItem) => DrawingElement.fromJson(jsonItem)).toList();
      return elements;
    } catch (e) {
      print('Error parsing JSON: $e');
      return [];
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sketch'),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.visibility),
            onPressed: () {
              setState(() {
                showHints = !showHints;
              });
            },
          ),
          IconButton(
            icon: isLoading ? CircularProgressIndicator(color: Colors.black) : Icon(Icons.save),  // Modify the icon based on isLoading
            onPressed: isLoading ? null : () => takeSnapshotAndAnalyze(context),  // Disable button when loading
          ),
        ],
      ),
      body: buildBody(),
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
              painter: SketchPainter(points, missingElements, showHints),
              child: Container(),
            ),
          ),
        ),
      ),
      buildDropdown(),
    ],
  );

  Widget buildDropdown() => Padding(
    padding: const EdgeInsets.all(8.0),
    child: DropdownButton<FeedbackMode>(
      value: selectedMode,
      onChanged: (FeedbackMode? newValue) {
        if (newValue != null) {
          setState(() => selectedMode = newValue);
        }
      },
      items: FeedbackMode.values.map((FeedbackMode mode) {
        return DropdownMenuItem<FeedbackMode>(
          value: mode,
          child: Text(mode.toString().split('.').last),
        );
      }).toList(),
    ),
  );

  Future<String> capturePng() async {
    RenderRepaintBoundary boundary = repaintBoundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    Uint8List pngBytes = byteData!.buffer.asUint8List();
    String base64String = base64Encode(pngBytes);
    return base64String;
  }

  bool isContentSafe(Map<String, dynamic> candidate) {
    List<dynamic> safetyRatings = candidate['safetyRatings'];
    return safetyRatings.every((rating) => rating['probability'] == 'NEGLIGIBLE');
  }

  void takeSnapshotAndAnalyze(BuildContext context) async {
    setState(() => isLoading = true);  // Set loading to true when starting the analysis
    try {
      String base64String = await capturePng();
      String promptText = getPrompt(selectedMode); //prompts[selectedMode]!;
      String jsonBody = jsonEncode({
        "contents": [
          { "parts": [
            {"text": promptText},
            { "inlineData": {
              "mimeType": "image/png",
              "data": base64String
            }}
          ]}
        ]
      });

      var response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro-latest:generateContent?key=${widget.apiKey}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonBody,
      );

      if (response.statusCode == 200) {
        Map<String, dynamic> decodedResponse = jsonDecode(response.body);
        Map<String, dynamic> candidate = decodedResponse['candidates'][0];
        if (isContentSafe(candidate)) {
          String responseText = candidate['content']['parts'][0]['text'];
          if (selectedMode == FeedbackMode.Analysis) {
            _speak(responseText);
            print("Response from model: $responseText");
          } else {
            // TODO Overlay the hints;
            List<DrawingElement> newHints = parseModelResponse(responseText);
            setState(() {
              missingElements = newHints;
              showHints = true; // Automatically show new hints
            });
            print(responseText);
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
      setState(() => isLoading = false);  // Reset loading state after operation completes
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
  final List<DrawingElement> missingElements;
  final bool showHints;

  SketchPainter(this.points, this.missingElements, this.showHints);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.white);
    Paint paint = Paint()
      ..color = Colors.black
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5.0;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }

    // Draw hints
    if (showHints) {
      Paint hintPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      for (var element in missingElements) {
        canvas.drawRect(
          Rect.fromPoints(
              Offset(element.topLeftPoint[0].toDouble(), element.topLeftPoint[1].toDouble()),
              Offset(element.bottomRightPoint[0].toDouble(), element.bottomRightPoint[1].toDouble())
          ),
          hintPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class DrawingElement {
  String element;
  List<int> topLeftPoint;
  List<int> bottomRightPoint;

  DrawingElement({
    required this.element,
    required this.topLeftPoint,
    required this.bottomRightPoint,
  });

  // Factory constructor to create a DrawingElement from a JSON map
  factory DrawingElement.fromJson(Map<String, dynamic> json) {
    return DrawingElement(
      element: json['element'],
      // Access the correct keys from the JSON
      topLeftPoint: List<int>.from(json['bounds'][0]),
      bottomRightPoint: List<int>.from(json['bounds'][1]),
    );
  }
}