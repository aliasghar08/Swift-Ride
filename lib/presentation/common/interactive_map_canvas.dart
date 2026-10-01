import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'glass_container.dart';

class InteractiveMapCanvas extends StatefulWidget {
  final double driverLat;
  final double driverLng;
  final double driverHeading;
  final bool isPinPickingMode;
  final Function(double lat, double lng)? onPinChanged;
  final VoidCallback? onLocateMe;
  final bool showRoute;
  final bool isDarkMode;

  const InteractiveMapCanvas({
    super.key,
    required this.driverLat,
    required this.driverLng,
    this.driverHeading = 0.0,
    this.isPinPickingMode = false,
    this.onPinChanged,
    this.onLocateMe,
    this.showRoute = true,
    this.isDarkMode = false,
  });

  @override
  State<InteractiveMapCanvas> createState() => _InteractiveMapCanvasState();
}

class _InteractiveMapCanvasState extends State<InteractiveMapCanvas>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  Offset _panOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) {
        setState(() {
          _panOffset += details.delta;
        });
        if (widget.isPinPickingMode && widget.onPinChanged != null) {
          // Translate pan offset into micro coordinate shifts
          final newLat = widget.driverLat - (_panOffset.dy * 0.0001);
          final newLng = widget.driverLng + (_panOffset.dx * 0.0001);
          widget.onPinChanged!(newLat, newLng);
        }
      },
      child: Stack(
        children: [
          CustomPaint(
            size: Size.infinite,
            painter: _MapPainter(
              driverLat: widget.driverLat,
              driverLng: widget.driverLng,
              driverHeading: widget.driverHeading,
              panOffset: _panOffset,
              pulseVal: _animController.value,
              showRoute: widget.showRoute,
              isDarkMode: widget.isDarkMode,
            ),
          ),

          // Pinned location selector crosshair (Rider pin mode)
          if (widget.isPinPickingMode)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GlassContainer(
                    isDark: true,
                    borderRadius: 24,
                    blur: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shadows: AppTheme.glowShadow(AppTheme.accentCyan, opacity: 0.25, blur: 14),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app, color: AppTheme.accentCyan, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Drag map to set pin',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Icon(
                    Icons.location_on,
                    color: AppTheme.sunsetCoral,
                    size: 44,
                  ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Floating GPS "Locate Me" button with elevation and subtle glow
          Positioned(
            right: 16,
            bottom: 24,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: widget.isDarkMode ? AppTheme.darkElevation : AppTheme.premiumElevation,
              ),
              child: FloatingActionButton.small(
                heroTag: 'locate_me_fab',
                backgroundColor: widget.isDarkMode ? const Color(0xFF1E293B) : Colors.white,
                foregroundColor: AppTheme.primaryBlue,
                elevation: 0,
                onPressed: () {
                  setState(() {
                    _panOffset = Offset.zero;
                  });
                  widget.onLocateMe?.call();
                },
                child: const Icon(Icons.my_location),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final double driverLat;
  final double driverLng;
  final double driverHeading;
  final Offset panOffset;
  final double pulseVal;
  final bool showRoute;
  final bool isDarkMode;

  _MapPainter({
    required this.driverLat,
    required this.driverLng,
    required this.driverHeading,
    required this.panOffset,
    required this.pulseVal,
    required this.showRoute,
    required this.isDarkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()
      ..color = isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final roadPaint = Paint()
      ..color = isDarkMode ? const Color(0xFF1E293B) : Colors.white
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final minorRoadPaint = Paint()
      ..color = isDarkMode ? const Color(0xFF162036) : const Color(0xFFF1F5F9)
      ..strokeWidth = 6
      ..style = PaintingStyle.stroke;

    final parkPaint = Paint()
      ..color = isDarkMode ? const Color(0xFF064E3B).withValues(alpha: 0.4) : const Color(0xFFDCFCE7)
      ..style = PaintingStyle.fill;

    final waterPaint = Paint()
      ..color = isDarkMode ? const Color(0xFF1E3A8A).withValues(alpha: 0.4) : const Color(0xFFBAE6FD)
      ..style = PaintingStyle.fill;

    // Draw simulated decorative park and waterfront
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(40 + panOffset.dx, 60 + panOffset.dy, 120, 90),
        const Radius.circular(16),
      ),
      parkPaint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(size.width - 140 + panOffset.dx, size.height - 180 + panOffset.dy, 120, 110),
        const Radius.circular(20),
      ),
      waterPaint,
    );

    // Draw street grid
    final gridSpacing = 80.0;
    final startX = (panOffset.dx % gridSpacing) - gridSpacing;
    final startY = (panOffset.dy % gridSpacing) - gridSpacing;

    for (double x = startX; x < size.width + gridSpacing; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minorRoadPaint);
    }
    for (double y = startY; y < size.height + gridSpacing; y += gridSpacing) {
      canvas.drawLine(Offset(y, 0), Offset(y, size.height), minorRoadPaint);
    }

    // Main thoroughfares
    canvas.drawLine(
      Offset(0, size.height * 0.45 + panOffset.dy),
      Offset(size.width, size.height * 0.45 + panOffset.dy),
      roadPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.5 + panOffset.dx, 0),
      Offset(size.width * 0.5 + panOffset.dx, size.height),
      roadPaint,
    );

    // Draw route line if in active trip
    final center = Offset(size.width / 2 + panOffset.dx, size.height / 2 + panOffset.dy);
    final pickup = center + const Offset(-90, 80);
    final dropoff = center + const Offset(110, -90);

    if (showRoute) {
      final routePaint = Paint()
        ..color = AppTheme.primaryBlue
        ..strokeWidth = 6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final path = Path()
        ..moveTo(pickup.dx, pickup.dy)
        ..lineTo(center.dx - 40, pickup.dy)
        ..lineTo(center.dx, center.dy)
        ..lineTo(dropoff.dx, center.dy)
        ..lineTo(dropoff.dx, dropoff.dy);

      canvas.drawPath(path, routePaint);

      // Pickup pin
      final pinPaint = Paint()..color = AppTheme.emeraldGreen;
      canvas.drawCircle(pickup, 8, pinPaint);
      canvas.drawCircle(pickup, 4, Paint()..color = Colors.white);

      // Dropoff pin
      final dropPaint = Paint()..color = AppTheme.sunsetCoral;
      canvas.drawCircle(dropoff, 8, dropPaint);
      canvas.drawCircle(dropoff, 4, Paint()..color = Colors.white);
    }

    // Draw animated live driver vehicle marker
    final vehiclePos = center;

    // Pulse animation around vehicle
    final pulsePaint = Paint()
      ..color = AppTheme.accentCyan.withValues(alpha: max(0, 0.4 - (pulseVal * 0.35)))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(vehiclePos, 16 + (pulseVal * 16), pulsePaint);

    // Vehicle body with rotation based on heading
    canvas.save();
    canvas.translate(vehiclePos.dx, vehiclePos.dy);
    canvas.rotate((driverHeading * pi) / 180);

    final carPaint = Paint()..color = AppTheme.darkNavy;
    final carBorder = Paint()
      ..color = AppTheme.accentCyan
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final carRect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 20, height: 32),
      const Radius.circular(6),
    );
    canvas.drawRRect(carRect, carPaint);
    canvas.drawRRect(carRect, carBorder);

    // Car windshield highlight
    final glassPaint = Paint()..color = Colors.white.withValues(alpha: 0.8);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0, -6), width: 14, height: 7),
        const Radius.circular(2),
      ),
      glassPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => true;
}
