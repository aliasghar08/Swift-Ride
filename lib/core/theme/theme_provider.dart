import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/native/native_storage_service.dart';
import 'app_theme.dart';
import 'design_tokens.dart';

/// Available visual theme presets across Swift Ride.
enum SwiftThemePreset {
  obsidianGlass, // DEFAULT: Midnight slate, frosted glass, electric cyan & emerald
  daylightPearl, // Crisp alabaster surfaces, deep cobalt actions, subtle elevation
  amoledPitch, // Pure #000000 OLED black, 1px crisp borders, neon telemetry
  emeraldGold, // Deep forest slate, champagne gold & emerald luxury accents
}

/// Available interface layout density and accessibility styles.
enum SwiftUiLayoutMode {
  modernFloating, // DEFAULT: Full-bleed map, floating glass sheets r=24, balanced blur
  compactCockpit, // High-density cards, tighter padding, persistent quick-action telemetry
  easyRead, // Larger touch targets (minHeight: 56), +15% scaled typography, opaque cards with blur disabled
}

/// Global controller managing active UI visual theme and layout density.
class ThemeProvider extends ChangeNotifier {
  static const String keyThemePreset = 'swift_theme_preset';
  static const String keyUiLayoutMode = 'swift_ui_layout_mode';

  final NativeStorageService _storage;

  SwiftThemePreset _preset = SwiftThemePreset.obsidianGlass;
  SwiftUiLayoutMode _layoutMode = SwiftUiLayoutMode.modernFloating;
  bool _hasUserOverride = false;

  ThemeProvider({NativeStorageService? storage})
      : _storage = storage ?? NativeStorageService() {
    _loadPreferences();
  }

  SwiftThemePreset get preset => _preset;
  SwiftUiLayoutMode get layoutMode => _layoutMode;

  bool get isDarkMode => _preset != SwiftThemePreset.daylightPearl;

  ThemeData get themeData => AppTheme.buildFromPreset(_preset, _layoutMode);

  AppColors get appColors => AppColors.forPreset(_preset, _layoutMode);

  /// Loads saved theme preferences asynchronously on startup.
  Future<void> _loadPreferences() async {
    try {
      final savedPreset = await _storage.getString(keyThemePreset);
      final savedLayout = await _storage.getString(keyUiLayoutMode);

      if (_hasUserOverride) return;

      bool changed = false;
      if (savedPreset != null) {
        final match = SwiftThemePreset.values.firstWhere(
          (p) => p.name == savedPreset,
          orElse: () => SwiftThemePreset.obsidianGlass,
        );
        if (match != _preset) {
          _preset = match;
          changed = true;
        }
      }

      if (savedLayout != null) {
        final match = SwiftUiLayoutMode.values.firstWhere(
          (m) => m.name == savedLayout,
          orElse: () => SwiftUiLayoutMode.modernFloating,
        );
        if (match != _layoutMode) {
          _layoutMode = match;
          changed = true;
        }
      }

      if (changed) {
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Sets the visual color theme preset and persists to storage.
  Future<void> setPreset(SwiftThemePreset newPreset) async {
    _hasUserOverride = true;
    if (_preset == newPreset) return;
    HapticFeedback.selectionClick();
    _preset = newPreset;
    notifyListeners();
    await _storage.setString(keyThemePreset, newPreset.name);
  }

  /// Sets the UI layout density mode and persists to storage.
  Future<void> setLayoutMode(SwiftUiLayoutMode newMode) async {
    _hasUserOverride = true;
    if (_layoutMode == newMode) return;
    HapticFeedback.selectionClick();
    _layoutMode = newMode;
    notifyListeners();
    await _storage.setString(keyUiLayoutMode, newMode.name);
  }

  /// Resets both theme and interface style to defaults (Obsidian Glass + Modern Floating).
  Future<void> resetToDefault() async {
    _hasUserOverride = true;
    HapticFeedback.selectionClick();
    _preset = SwiftThemePreset.obsidianGlass;
    _layoutMode = SwiftUiLayoutMode.modernFloating;
    notifyListeners();
    await _storage.remove(keyThemePreset);
    await _storage.remove(keyUiLayoutMode);
  }

  /// Generates the matching Google Maps JSON styling for the active theme preset.
  String get mapStyleJson {
    switch (_preset) {
      case SwiftThemePreset.daylightPearl:
        return _silverDaylightMapStyle;
      case SwiftThemePreset.amoledPitch:
        return _amoledPitchMapStyle;
      case SwiftThemePreset.emeraldGold:
        return _emeraldGoldMapStyle;
      case SwiftThemePreset.obsidianGlass:
        return _obsidianGlassMapStyle;
    }
  }

  // --------------------------------------------------------------------------
  // Curated Google Maps JSON Styling Strings
  // --------------------------------------------------------------------------

  static const String _obsidianGlassMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#0b1120"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#94a3b8"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#0b1120"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#cbd5e1"}]},
  {"featureType": "poi", "elementType": "labels.text.fill", "stylers": [{"color": "#64748b"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#0c2328"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#1e293b"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#0f172a"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#2563eb"}]},
  {"featureType": "transit", "elementType": "geometry", "stylers": [{"color": "#1e293b"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#070c18"}]}
]
''';

  static const String _silverDaylightMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#f8fafc"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#334155"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#f8fafc"}]},
  {"featureType": "poi", "elementType": "geometry", "stylers": [{"color": "#f1f5f9"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#cbd5e1"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#bfdbfe"}]}
]
''';

  static const String _amoledPitchMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#000000"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#71717a"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#000000"}]},
  {"featureType": "poi", "stylers": [{"visibility": "off"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#18181b"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#27272a"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#050505"}]}
]
''';

  static const String _emeraldGoldMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#071a15"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#6ee7b7"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#071a15"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#0d3127"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#143b30"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#f59e0b"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#04100d"}]}
]
''';
}
