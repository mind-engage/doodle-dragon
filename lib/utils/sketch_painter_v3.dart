import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'dart:typed_data';

class SketchPath {
  final Color color;
  final double strokeWidth;
  List<Offset> points = [];

  // Constructor with optional points argument
  SketchPath(this.color, this.strokeWidth, {List<Offset>? points})
      : this.points = points ?? [];


  // Clone method to create a deep copy of the instance
  SketchPath.clone(SketchPath path)
      : color = path.color,
        strokeWidth = path.strokeWidth,
        points = List<Offset>.from(path.points); // Make a deep copy of the points
}

class SketchPainter extends CustomPainter {
  final List<SketchPath> paths;
  final bool showSketch;
  final ui.Image? image;
  final double transparency;

  SketchPainter(this.paths, this.showSketch, this.image, this.transparency);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = Colors.white);

    if (image != null) {
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
      for (var pathData in paths) {
        Paint paint = Paint()
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke
          ..color = pathData.color
          ..strokeWidth = pathData.strokeWidth;

        Path path = Path();
        for (int i = 0; i < pathData.points.length; i++) {
          if (i == 0) {
            path.moveTo(pathData.points[i].dx, pathData.points[i].dy);
          } else {
            path.lineTo(pathData.points[i].dx, pathData.points[i].dy);
          }
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // You might need to make this more efficient
  }
}


Future<ui.Image> drawPointsToImage(List<SketchPath> paths, Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  // Draw the white background
  canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white);

  for (var pathData in paths) {
    Paint paint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..color = pathData.color
      ..strokeWidth = pathData.strokeWidth;
    Path path = Path();
    for (int i = 0; i < pathData.points.length; i++) {
      if (i == 0) {
        path.moveTo(pathData.points[i].dx, pathData.points[i].dy);
      } else {
        path.lineTo(pathData.points[i].dx, pathData.points[i].dy);
      }
    }
    canvas.drawPath(path, paint);
  }
  final picture = recorder.endRecording();
  return picture.toImage(size.width.toInt(), size.height.toInt());
}

Future<Uint8List> generateFrame(List<SketchPath> recordPaths, Size imgSize, Size encSize) async {
  ui.Image originalImage = await drawPointsToImage(recordPaths, imgSize);
  // Prepare to draw the original image onto a scaled canvas
  ui.PictureRecorder recorder = ui.PictureRecorder();
  ui.Canvas canvas = ui.Canvas(recorder);

  // Define the destination size (1920x1080)
  final int destWidth = encSize.width.toInt();
  final int destHeight = encSize.height.toInt();

  // Calculate the scaling factors
  double scaleX = destWidth / originalImage.width;
  double scaleY = destHeight / originalImage.height;
  double scale = scaleX < scaleY ? scaleX : scaleY; // Choose the smaller scaling factor to maintain aspect ratio without cropping

  // Calculate the centering offset to maintain aspect ratio
  double offsetX = (destWidth - originalImage.width * scale) / 2;
  double offsetY = (destHeight - originalImage.height * scale) / 2;

  // Apply scale and offset transformations
  canvas.scale(scale, scale);
  canvas.drawImage(originalImage, ui.Offset(offsetX / scale, offsetY / scale), ui.Paint());

  // Finish drawing and produce the scaled image
  ui.Image scaledImage = await recorder.endRecording().toImage(destWidth, destHeight);

  // Convert the scaled image to byte data in RGBA format
  ByteData? byteData = await scaledImage.toByteData(format: ui.ImageByteFormat.rawRgba);
  Uint8List frameData = byteData!.buffer.asUint8List();

  return frameData;
}