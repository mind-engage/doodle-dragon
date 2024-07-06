import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

enum FeedbackMode { ChildArt, AdultArt, DesignFeedback }

class SketchScreen extends StatefulWidget {
  final String apiKey;
  const SketchScreen({super.key, required this.apiKey});

  @override
  _SketchScreenState createState() => _SketchScreenState();
}

class _SketchScreenState extends State<SketchScreen> {
  List<Offset?> points = [];
  GlobalKey repaintBoundaryKey = GlobalKey();
  FeedbackMode selectedMode = FeedbackMode.ChildArt;
  FlutterTts flutterTts = FlutterTts();
  bool isLoading = false;  // Add a boolean state variable to track loading

  Map<FeedbackMode, String> prompts = {
    FeedbackMode.ChildArt: "The attached sketch is drawn by a child. Analyze and suggest improvements. The output is used to play to child using text to speech",
    FeedbackMode.AdultArt: "Review this artistic piece by an adult for professional improvement.",
    FeedbackMode.DesignFeedback: "Provide feedback on the design elements of the attached sketch."
  };

  @override
  void initState() {
    super.initState();
    flutterTts.setLanguage("en-US");
    flutterTts.setSpeechRate(0.5);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sketch'),
        actions: <Widget>[
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
              painter: SketchPainter(points),
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
      String promptText = prompts[selectedMode]!;
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
          _speak(responseText);
          print("Response from model: $responseText");
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
  SketchPainter(this.points);

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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
