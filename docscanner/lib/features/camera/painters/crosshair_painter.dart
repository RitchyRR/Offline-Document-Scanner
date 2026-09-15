import 'package:flutter/material.dart';

class CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double crossSize = 17.0;
    final double crossThickness = 1.5;
    final double bgThickness = 0.5;
    final double bgThickness2 = 2;
    final double bgThickness3 = 4;
    final double bgThickness4 = 8;

    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = crossThickness;
    final paintBg = Paint()
      ..color = Colors.black.withAlpha(70)
      ..strokeWidth = crossThickness + 2 * bgThickness;
    final paintBg2 = Paint()
      ..color = Colors.black.withAlpha(14)
      ..strokeWidth = crossThickness + 2 * bgThickness2;
    final paintBg3 = Paint()
      ..color = Colors.black.withAlpha(5)
      ..strokeWidth = crossThickness + 2 * bgThickness3;
    final paintBg4 = Paint()
      ..color = Colors.black.withAlpha(2)
      ..strokeWidth = crossThickness + 2 * bgThickness4;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Draw Cross BG
    canvas.drawLine(
      Offset(centerX - crossSize - bgThickness4 * 0.75, centerY),
      Offset(centerX + crossSize + bgThickness4 * 0.75, centerY),
      paintBg4,
    );
    canvas.drawLine(
      Offset(centerX, centerY - crossSize - bgThickness4 * 0.75),
      Offset(centerX, centerY + crossSize + bgThickness4 * 0.75),
      paintBg4,
    );
    // Draw Cross BG
    canvas.drawLine(
      Offset(centerX - crossSize - bgThickness3 * 0.75, centerY),
      Offset(centerX + crossSize + bgThickness3 * 0.75, centerY),
      paintBg3,
    );
    canvas.drawLine(
      Offset(centerX, centerY - crossSize - bgThickness3 * 0.75),
      Offset(centerX, centerY + crossSize + bgThickness3 * 0.75),
      paintBg3,
    );
    // Draw Cross BG
    canvas.drawLine(
      Offset(centerX - crossSize - bgThickness2 * 0.75, centerY),
      Offset(centerX + crossSize + bgThickness2 * 0.75, centerY),
      paintBg2,
    );
    canvas.drawLine(
      Offset(centerX, centerY - crossSize - bgThickness2 * 0.75),
      Offset(centerX, centerY + crossSize + bgThickness2 * 0.75),
      paintBg2,
    );
    // Draw Cross BG
    canvas.drawLine(
      Offset(centerX - crossSize - bgThickness * 0.75, centerY),
      Offset(centerX + crossSize + bgThickness * 0.75, centerY),
      paintBg,
    );
    canvas.drawLine(
      Offset(centerX, centerY - crossSize - bgThickness * 0.75),
      Offset(centerX, centerY + crossSize + bgThickness * 0.75),
      paintBg,
    );
    // Draw Cross
    canvas.drawLine(
      Offset(centerX - crossSize, centerY),
      Offset(centerX + crossSize, centerY),
      paint,
    );
    canvas.drawLine(
      Offset(centerX, centerY - crossSize),
      Offset(centerX, centerY + crossSize),
      paint,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
