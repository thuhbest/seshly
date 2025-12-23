import 'dart:math';
import 'package:flutter/material.dart';

class MyAppLogo extends StatelessWidget {
  final double size; // Width and height of the logo (square)

  const MyAppLogo({super.key, this.size = 100.0});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: SpiralLogoPainter(),
      ),
    );
  }
}

class SpiralLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill;

    // Teal background with rounded corners
    paint.color = const Color(0xFF00D0C0); // Approximate teal (adjust if needed for exact match)
    final backgroundRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final cornerRadius = size.width * 0.15; // About 15% for smooth rounding
    canvas.drawRRect(
      RRect.fromRectAndRadius(backgroundRect, Radius.circular(cornerRadius)),
      paint,
    );

    // White spiral path
    paint.color = Colors.white;
    paint.strokeWidth = size.width * 0.18; // Thick stroke for the spiral
    paint.strokeCap = StrokeCap.round;
    paint.style = PaintingStyle.stroke;

    final path = Path();
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width * 0.38;

    // Archimedean spiral parameters (tuned for ~2.5-3 turns to match the swirling "S" shape)
    double a = 0.0; // Starting "radius"
    double b = maxRadius / (2.8 * pi); // Growth rate for tight spiral

    path.moveTo(
      center.dx + (a + b * 0) * cos(0),
      center.dy + (a + b * 0) * sin(0),
    );

    const int steps = 800;
    const double thetaMax = 2.8 * pi; // Approximately 2.8 full rotations

    for (int i = 1; i <= steps; i++) {
      double t = i / steps.toDouble();
      double theta = t * thetaMax;
      double r = a + b * theta;
      path.lineTo(
        center.dx + r * cos(theta),
        center.dy + r * sin(theta),
      );
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Example usage in your app (e.g., in AppBar or splash screen):
void main() {
  runApp(
    const MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black, // Dark background like in the image
        body: Center(
          child: MyAppLogo(size: 200), // Adjust size as needed
        ),
      ),
    ),
  );
}