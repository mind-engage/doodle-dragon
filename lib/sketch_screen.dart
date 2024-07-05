import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;

class SketchScreen extends StatefulWidget {
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
            //var appBarHeight = Scaffold.of(context).appBarMaxHeight ?? 0;
            const double appBarHeight = 56.0;
            Offset adjustedPosition = Offset(details.globalPosition.dx, details.globalPosition.dy - appBarHeight);
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

  void takeSnapshotAndUpload(BuildContext context) {
    // Implement snapshot capture and upload functionality
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
