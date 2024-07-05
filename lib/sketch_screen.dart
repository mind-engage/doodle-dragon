import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SketchScreen extends StatefulWidget {
  final String apiKey;
  const SketchScreen({super.key, required this.apiKey});

  @override
  _SketchScreenState createState() => _SketchScreenState();
}

class _SketchScreenState extends State<SketchScreen> {
  List<Offset?> points = [];

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

            // Adjust for app bar height before converting to local coordinates
            Offset adjustedPosition = details.globalPosition - Offset(0, appBarHeight + topPadding);
            Offset localPosition = renderBox.globalToLocal(adjustedPosition);

            points.add(localPosition);
          });
        },
        onPanEnd: (details) {
          points.add(null);
        },
        child: CustomPaint(
          painter: SketchPainter(points),
          child: Container(),
        ),
      ),
    );
  }

  void takeSnapshotAndUpload(BuildContext context) async {
    List<Map<String, dynamic>> jsonPoints = points.where((p) => p != null).map(
            (p) => {'x': p!.dx, 'y': p!.dy}
    ).toList();

    String jsonBody = jsonEncode({
      'contents': [{
        'parts': [{
          'text': 'Predict and complete this sketch based on the following points: $jsonPoints'
        }]
      }]
    });

    var response = await http.post(
      Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-pro-latest:generateContent?key=${widget.apiKey}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonBody,
    );

    if (response.statusCode == 200) {
      // Parse the response and update your sketch or UI here
      print("Response from model: ${response.body}");
    } else {
      print("Failed to get response: ${response.body}");
    }
  }
}

class SketchPainter extends CustomPainter {
  final List<Offset?> points;
  SketchPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
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
