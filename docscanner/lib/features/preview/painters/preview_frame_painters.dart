import 'package:flutter/material.dart';

class CornerLinePainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final double offset;
  final bool normalizedOffset;

  CornerLinePainter({
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.offset,
    required this.normalizedOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paintCorners = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    var order = [0, 2, 3, 1];
    List<Offset> orderedPoints = order.map((i) => points[i]).toList();

    for (int i = 0; i < orderedPoints.length; i++) {
      Offset p1 = orderedPoints[i];
      Offset p2 = orderedPoints[(i + 1) % orderedPoints.length];
      Offset p0 = orderedPoints[(i - 1) % orderedPoints.length];
      Offset delta0 = p2 - p1;
      Offset delta2 = p0 - p1;
      Offset deltaN0 = delta0 / delta0.distance;
      Offset deltaN2 = delta2 / delta2.distance;
      Offset offset0 = p1 + (normalizedOffset ? deltaN0 : delta0) * offset;
      Offset offset2 = p1 + (normalizedOffset ? deltaN2 : delta2) * offset;

      final path = Path();
      path.moveTo(offset0.dx, offset0.dy);
      path.lineTo(p1.dx, p1.dy);
      path.lineTo(offset2.dx, offset2.dy);
      canvas.drawPath(path, paintCorners);
    }
  }

  @override
  bool shouldRepaint(covariant CornerLinePainter oldDelegate) =>
      oldDelegate.points != points;
}

class MiddleLinePainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final double offset;
  final bool normalizedOffset;

  MiddleLinePainter({
    required this.points,
    this.color = Colors.black38,
    this.strokeWidth = 7.0,
    this.offset = 17.0,
    this.normalizedOffset = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final paintCorners = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;

    var order = [0, 2, 3, 1];
    List<Offset> orderedPoints = order.map((i) => points[i]).toList();

    for (int i = 0; i < orderedPoints.length; i++) {
      Offset p1 = orderedPoints[i];
      Offset p2 = orderedPoints[(i + 1) % orderedPoints.length];
      Offset delta = p2 - p1;
      Offset deltaN = delta / delta.distance;
      p1 -= deltaN * strokeWidth / 2;
      p2 += deltaN * strokeWidth / 2;
      Offset middleOffset1 = p1 + (normalizedOffset ? deltaN : delta) * offset;
      Offset middleOffset2 = p2 - (normalizedOffset ? deltaN : delta) * offset;
      canvas.drawLine(middleOffset1, middleOffset2, paintCorners);
    }
  }

  @override
  bool shouldRepaint(covariant MiddleLinePainter oldDelegate) =>
      oldDelegate.points != points;
}
