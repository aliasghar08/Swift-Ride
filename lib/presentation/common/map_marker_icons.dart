import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Renders Uber-style map glyphs to PNG bytes at runtime and caches the
/// resulting [BitmapDescriptor]s.
///
/// These are drawn with `dart:ui` rather than shipped as assets so they stay
/// crisp at any device pixel ratio and carry no build-time asset dependency.
/// Call [ensureLoaded] once before building a map; the accessors fall back to
/// the stock Google teardrop until then.
/// Colours used by the map glyphs themselves.
///
/// These are a self-contained "sprite sheet" palette rather than UI chrome —
/// the car body and windscreen shades deliberately do not follow the app theme,
/// because the vehicle must read the same over both light and dark tiles.
abstract final class _Glyph {
  static const Color shadowSoft = Color(0x33000000);
  static const Color shadowCar = Color(0x40000000);
  static const Color carBody = Color(0xFF1D2330);
  static const Color windscreen = Color(0xFF7FA8D9);
  static const Color rearWindow = Color(0xFF38506E);
  static const Color puckConeFade = Color(0x002563EB);
}

class MapMarkerIcons {
  MapMarkerIcons._();

  /// Logical sizes multiplied by this to render at a crisp density.
  static const double _scale = 3.0;

  static BitmapDescriptor? pickup;
  static BitmapDescriptor? dropoff;
  static BitmapDescriptor? car;
  static BitmapDescriptor? puck;

  static bool _loading = false;
  static bool _loaded = false;

  static bool get isLoaded => _loaded;

  /// Renders every glyph once. Safe to call repeatedly and from multiple maps.
  static Future<void> ensureLoaded() async {
    if (_loaded || _loading) return;
    _loading = true;
    try {
      pickup = await _render(30, 30, _drawPickup);
      dropoff = await _render(30, 30, _drawDropoff);
      car = await _render(34, 34, _drawCar);
      puck = await _render(46, 46, _drawPuck);
      _loaded = true;
    } catch (e) {
      debugPrint('[MapMarkerIcons] glyph render failed, using stock markers: $e');
    } finally {
      _loading = false;
    }
  }

  static Future<BitmapDescriptor> _render(
    double logicalWidth,
    double logicalHeight,
    void Function(Canvas canvas, Size size) draw,
  ) async {
    final width = (logicalWidth * _scale).round();
    final height = (logicalHeight * _scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(_scale);
    draw(canvas, Size(logicalWidth, logicalHeight));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();

    if (data == null) {
      throw StateError('Failed to encode marker glyph');
    }
    return BitmapDescriptor.bytes(
      Uint8List.view(data.buffer),
    );
  }

  // ---------------------------------------------------------------- glyphs

  /// Pickup: solid green disc with a white ring, like Uber's boarding point.
  static void _drawPickup(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(c, 10.5, Paint()..color = _Glyph.shadowSoft);
    canvas.drawCircle(c, 9.5, Paint()..color = Colors.white);
    canvas.drawCircle(c, 6.8, Paint()..color = AppTheme.emeraldGreen);
  }

  /// Dropoff: dark rounded square with a white ring — visually distinct from
  /// pickup so the two are never confused at a glance.
  static void _drawDropoff(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 19,
      height: 19,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4.5)),
      Paint()..color = Colors.white,
    );
    final inner = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 15,
      height: 15,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(inner, const Radius.circular(3.5)),
      Paint()..color = AppTheme.primaryNavy,
    );
  }

  /// Vehicle: top-down car pointing north (12 o'clock). Marker `rotation` then
  /// maps directly onto the driver's heading.
  static void _drawCar(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;

    // Soft drop shadow.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy + 1), width: 17, height: 27),
        const Radius.circular(7),
      ),
      Paint()
        ..color = _Glyph.shadowCar
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    // Body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 16.5, height: 27),
        const Radius.circular(7),
      ),
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy), width: 13, height: 23.5),
        const Radius.circular(5.5),
      ),
      Paint()..color = _Glyph.carBody,
    );

    // Windscreen + rear window, so orientation is readable when rotated.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy - 5.5), width: 10.5, height: 5.5),
        const Radius.circular(2),
      ),
      Paint()..color = _Glyph.windscreen,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cy + 6.5), width: 9, height: 4.5),
        const Radius.circular(1.8),
      ),
      Paint()..color = _Glyph.rearWindow,
    );
  }

  /// Rider location puck: blue disc with a heading cone, replacing the stock
  /// blue dot so bearing is visible.
  static void _drawPuck(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);

    // Heading cone (points north before marker rotation).
    final cone = Path()
      ..moveTo(c.dx, c.dy - 20)
      ..lineTo(c.dx - 9, c.dy - 2)
      ..lineTo(c.dx + 9, c.dy - 2)
      ..close();
    canvas.drawPath(
      cone,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(c.dx, c.dy - 20),
          Offset(c.dx, c.dy),
          [AppTheme.primaryBlue, _Glyph.puckConeFade],
        ),
    );

    canvas.drawCircle(c, 9.5, Paint()..color = _Glyph.shadowSoft);
    canvas.drawCircle(c, 8.5, Paint()..color = Colors.white);
    canvas.drawCircle(c, 6.5, Paint()..color = AppTheme.primaryBlue);
  }
}
