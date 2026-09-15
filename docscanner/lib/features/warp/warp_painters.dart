import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class CircularCropPainter extends CustomPainter {
  final ui.Image image;
  final Rect cropRect;

  CircularCropPainter({required this.image, required this.cropRect});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final clipPath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.clipPath(clipPath);

    canvas.drawImageRect(
      image,
      cropRect,
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint(),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is CircularCropPainter) {
      return image != oldDelegate.image || cropRect != oldDelegate.cropRect;
    }
    return true;
  }
}

class ZoomCornerPainter extends CustomPainter {
  final List<Offset> cornerPoints;
  final Color color;
  final double strokeWidth;
  final Color colorBg;
  final double strokeWidthBg;
  final int currentCorner;
  final double zoomSize;

  ZoomCornerPainter({
    required this.cornerPoints,
    required this.color,
    required this.strokeWidth,
    required this.colorBg,
    required this.strokeWidthBg,
    required this.currentCorner,
    required this.zoomSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cornerPoints.length < 4) return;
    final double radius = zoomSize / 2;

    final paintBg = Paint()
      ..color = colorBg
      ..strokeWidth = strokeWidthBg
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    var order = [0, 2, 3, 1];
    List<Offset> orderedPoints = order.map((i) => cornerPoints[i]).toList();

    int currentIndex = order.indexOf(currentCorner);
    int nextIndex = (currentIndex + 1) % orderedPoints.length;
    int prevIndex = (currentIndex - 1) % orderedPoints.length;

    Offset currentPoint = orderedPoints[currentIndex];
    Offset nextPoint = orderedPoints[nextIndex];
    Offset prevPoint = orderedPoints[prevIndex];

    Offset center = Offset(radius, radius);
    Offset vectorToNext = nextPoint - currentPoint;
    Offset vectorToPrev = prevPoint - currentPoint;
    Offset directionToNext = vectorToNext / vectorToNext.distance;
    Offset directionToPrev = vectorToPrev / vectorToPrev.distance;

    final pathBg = Path();
    pathBg.moveTo(
      (center + directionToPrev * radius).dx,
      (center + directionToPrev * radius).dy,
    );
    pathBg.lineTo(center.dx, center.dy);
    pathBg.lineTo(
      (center + directionToNext * radius).dx,
      (center + directionToNext * radius).dy,
    );

    canvas.drawPath(pathBg, paintBg);
    canvas.drawLine(center, center + directionToNext * radius, paint);
    canvas.drawLine(center, center + directionToPrev * radius, paint);
  }

  @override
  bool shouldRepaint(covariant ZoomCornerPainter oldDelegate) =>
      oldDelegate.cornerPoints != cornerPoints ||
      oldDelegate.currentCorner != currentCorner;
}

class ZoomEdgePainter extends CustomPainter {
  final List<Offset> cornerPoints;
  final Color color;
  final double strokeWidth;
  final Color colorBg;
  final double strokeWidthBg;
  final (int, int) currentEdge;
  final double zoomSize;

  ZoomEdgePainter({
    required this.cornerPoints,
    required this.color,
    required this.strokeWidth,
    required this.colorBg,
    required this.strokeWidthBg,
    required this.currentEdge,
    required this.zoomSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (cornerPoints.length < 4) return;
    final double radius = zoomSize / 2;

    final paintBg = Paint()
      ..color = colorBg
      ..strokeWidth = strokeWidthBg
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    Offset vector = cornerPoints[currentEdge.$1] - cornerPoints[currentEdge.$2];
    Offset normVector = vector / vector.distance;
    Offset center = Offset(radius, radius);

    final path = Path();
    path.moveTo(
      (center + normVector * radius).dx,
      (center + normVector * radius).dy,
    );
    path.lineTo(
      (center - normVector * radius).dx,
      (center - normVector * radius).dy,
    );

    canvas.drawPath(path, paintBg);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ZoomEdgePainter oldDelegate) =>
      oldDelegate.cornerPoints != cornerPoints ||
      oldDelegate.currentEdge != currentEdge;
}
