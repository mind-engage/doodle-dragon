import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class ColoredPoint {
  Offset? point;
  Color color;
  double strokeWidth; // New attribute for stroke width

  ColoredPoint(this.point, this.color, this.strokeWidth);
}

class SketchPainter extends CustomPainter {
  final List<ColoredPoint> points;
  final bool showSketch;
  final ui.Image? image;
  final double transparency;

  SketchPainter(this.points, this.showSketch, this.image, this.transparency);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = Colors.white);

    if (image != null) {
      paintImage(
        canvas: canvas,
        rect: Rect.fromLTWH(0, 0, size.width, size.height),
        image: image!,
        fit: BoxFit.contain,
        colorFilter: ColorFilter.mode(Colors.white.withOpacity(transparency), BlendMode.dstIn),
      );
    }

    if (showSketch) {
      Paint paint = Paint()
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      Path path = Path();
      bool pathStarted = false;

      for (var point in points) {
        if (point.point != null) {
          if (!pathStarted) {
            path.moveTo(point.point!.dx, point.point!.dy);
            // Draw the point immediately
            paint.color = point.color;
            paint.strokeWidth = point.strokeWidth;
            canvas.drawPoints(ui.PointMode.points, [point.point!], paint);
            pathStarted = true;
          } else {
            path.lineTo(point.point!.dx, point.point!.dy);
          }
          paint.color = point.color;
          paint.strokeWidth = point.strokeWidth;
        } else {
          if (pathStarted) {
            canvas.drawPath(path, paint);
            path = Path();  // Start a new path
            pathStarted = false;
          }
        }
      }

      if (pathStarted) {
        canvas.drawPath(path, paint);  // Draw the remaining path if any
      }
    }
  }

  @override
  bool shouldRepaint(covariant SketchPainter oldDelegate) => true;
}