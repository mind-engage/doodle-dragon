import 'dart:ui' as ui;

import 'package:flutter/material.dart';

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
