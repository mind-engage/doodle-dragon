import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;

class SketchScreen extends StatefulWidget {
  final String apiKey;
  const SketchScreen({super.key, required this.apiKey});

  @override
  _SketchScreenState createState() => _SketchScreenState();
}

class _SketchScreenState extends State<SketchScreen> {
  List<Offset?> points = [];
  GlobalKey repaintBoundaryKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Sketch'),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.save),
            onPressed: () {
              takeSnapshotAndUpload(context);
            },
          ),
        ],
      ),
      body: GestureDetector(
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
        onPanEnd: (details) {
          points.add(null);
        },
        child: RepaintBoundary(
          key: repaintBoundaryKey,
          child: CustomPaint(
            painter: SketchPainter(points),
            child: Container(),
          ),
        ),
      ),
    );
  }

  Future<String> capturePng() async {
    RenderRepaintBoundary boundary = repaintBoundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    Uint8List pngBytes = byteData!.buffer.asUint8List();
    String base64String = base64Encode(pngBytes);
    return base64String;
  }

  void takeSnapshotAndUpload(BuildContext context) async {
    String base64String = await capturePng();
    String jsonBody = jsonEncode({
      "contents": [
        { "parts": [
          {"text": "The attached sketch is drawn by a child. Analyze and suggest him how to improve further"},
          { "inlineData": {
            "mimeType": "image/png",
            "data": base64String
          }
          }
        ]
        }
      ]
    });

    var response = await http.post(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro-latest:generateContent?key=${widget.apiKey}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonBody,
    );

    if (response.statusCode == 200) {
      // Handle successful response
      print("Response from model: ${response.body}");
    } else {
      // Handle error response
      print("Failed to get response: ${response.body}");
    }
  }
}

class SketchPainter extends CustomPainter {
  final List<Offset?> points;
  SketchPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.white); // Set canvas background color to white
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
