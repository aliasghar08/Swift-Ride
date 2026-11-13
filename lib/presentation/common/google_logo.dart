import 'package:flutter/material.dart';

/// Official 4-color Google 'G' vector logo rendered using vector paths.
/// Complies with Google Sign-In Branding Guidelines (Red, Blue, Yellow, Green).
class GoogleLogo extends StatelessWidget {
  final double size;

  const GoogleLogo({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GoogleLogoPainter(),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Original SVG coordinate space is 48 x 48.
    final double s = size.width / 48.0;
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // 1. RED ARC (Top)
    paint.color = const Color(0xFFEA4335);
    var path = Path()
      ..moveTo(24.0 * s, 9.5 * s)
      ..cubicTo(27.54 * s, 9.5 * s, 30.71 * s, 10.72 * s, 33.21 * s, 13.1 * s)
      ..lineTo(40.06 * s, 6.25 * s)
      ..cubicTo(35.9 * s, 2.38 * s, 30.47 * s, 0.0 * s, 24.0 * s, 0.0 * s)
      ..cubicTo(14.66 * s, 0.0 * s, 6.51 * s, 5.38 * s, 2.56 * s, 13.22 * s)
      ..lineTo(10.54 * s, 19.41 * s)
      ..cubicTo(12.43 * s, 13.72 * s, 17.74 * s, 9.5 * s, 24.0 * s, 9.5 * s)
      ..close();
    canvas.drawPath(path, paint);

    // 2. BLUE ARC & CROSSBAR (Right / Middle)
    paint.color = const Color(0xFF4285F4);
    path = Path()
      ..moveTo(46.98 * s, 24.55 * s)
      ..cubicTo(46.98 * s, 22.98 * s, 46.83 * s, 21.46 * s, 46.6 * s, 20.0 * s)
      ..lineTo(24.0 * s, 20.0 * s)
      ..lineTo(24.0 * s, 29.02 * s)
      ..lineTo(36.94 * s, 29.02 * s)
      ..cubicTo(36.36 * s, 31.98 * s, 34.68 * s, 34.5 * s, 32.16 * s, 36.2 * s)
      ..lineTo(39.89 * s, 42.2 * s)
      ..cubicTo(44.4 * s, 38.02 * s, 46.98 * s, 31.84 * s, 46.98 * s, 24.55 * s)
      ..close();
    canvas.drawPath(path, paint);

    // 3. YELLOW ARC (Left)
    paint.color = const Color(0xFFFBBC05);
    path = Path()
      ..moveTo(10.53 * s, 28.59 * s)
      ..cubicTo(10.05 * s, 27.14 * s, 9.77 * s, 25.6 * s, 9.77 * s, 24.0 * s)
      ..cubicTo(9.77 * s, 22.4 * s, 10.04 * s, 20.86 * s, 10.53 * s, 19.41 * s)
      ..lineTo(2.55 * s, 13.22 * s)
      ..cubicTo(0.92 * s, 16.46 * s, 0.0 * s, 20.12 * s, 0.0 * s, 24.0 * s)
      ..cubicTo(0.0 * s, 27.88 * s, 0.92 * s, 31.54 * s, 2.56 * s, 34.78 * s)
      ..lineTo(10.53 * s, 28.59 * s)
      ..close();
    canvas.drawPath(path, paint);

    // 4. GREEN ARC (Bottom)
    paint.color = const Color(0xFF34A853);
    path = Path()
      ..moveTo(24.0 * s, 48.0 * s)
      ..cubicTo(30.48 * s, 48.0 * s, 35.93 * s, 45.87 * s, 39.89 * s, 42.19 * s)
      ..lineTo(32.16 * s, 36.19 * s)
      ..cubicTo(30.01 * s, 37.64 * s, 27.24 * s, 38.49 * s, 24.0 * s, 38.49 * s)
      ..cubicTo(17.74 * s, 38.49 * s, 12.43 * s, 34.27 * s, 10.53 * s, 28.58 * s)
      ..lineTo(2.55 * s, 34.77 * s)
      ..cubicTo(6.51 * s, 42.62 * s, 14.66 * s, 48.0 * s, 24.0 * s, 48.0 * s)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

