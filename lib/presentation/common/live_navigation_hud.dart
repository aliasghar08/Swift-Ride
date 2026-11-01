import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../services/map_service.dart';
import '../../services/native_map_service.dart';
import '../../services/native/native_audio_service.dart';
import '../../services/native/native_device_service.dart';

/// Live Turn-by-Turn Navigation HUD overlay.
///
/// Provides:
/// - Real-time green/navy turn maneuver banner with lane & street guidance.
/// - Next turn distance & directional arrow icons.
/// - Live Speedometer & Traffic Congestion indicator.
/// - Floating "Re-center" pill when user drags the map away.
/// - 3D Driver Perspective vs 2D Overhead map toggle.
/// - Google Maps Live Traffic layer toggle with active indicator.
/// - Automated turn-by-turn voice announcements.
class LiveNavigationHud extends StatefulWidget {
  final bool isDriver;
  final RouteOption? activeRoute;
  final LatLng currentVehicleLocation;
  final double currentSpeedKmh;
  final double heading;
  final String destinationAddress;
  final double remainingDistanceKm;
  final double remainingDurationMin;
  final bool isMapPanned;
  final bool is3DMode;
  final bool isTrafficLayerActive;
  final VoidCallback onRecenter;
  final ValueChanged<bool> onToggle3D;
  final ValueChanged<bool> onToggleTraffic;
  final VoidCallback? onExitNavigation;

  const LiveNavigationHud({
    super.key,
    required this.isDriver,
    required this.activeRoute,
    required this.currentVehicleLocation,
    required this.currentSpeedKmh,
    required this.heading,
    required this.destinationAddress,
    required this.remainingDistanceKm,
    required this.remainingDurationMin,
    required this.isMapPanned,
    required this.is3DMode,
    required this.isTrafficLayerActive,
    required this.onRecenter,
    required this.onToggle3D,
    required this.onToggleTraffic,
    this.onExitNavigation,
  });

  @override
  State<LiveNavigationHud> createState() => _LiveNavigationHudState();
}

class _LiveNavigationHudState extends State<LiveNavigationHud> {
  final NativeAudioService _audioService = NativeAudioService();
  final NativeDeviceService _deviceService = NativeDeviceService();

  bool _isVoiceMuted = false;
  int _lastAnnouncedStepIndex = -1;

  @override
  Widget build(BuildContext context) {
    final route = widget.activeRoute;
    final nextStepInfo = _calculateNextStep(route, widget.currentVehicleLocation);
    final nextStep = nextStepInfo.step;
    final distToStepMeters = nextStepInfo.distanceMeters;

    // Trigger voice announcement when approaching next turn (<= 160m)
    _maybeAnnounceStep(nextStepInfo);

    final trafficStatus = _getTrafficStatus(route);

    return Stack(
      children: [
        // 1. Top Navigation Card (Turn Guidance Bar)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: _buildTurnGuidanceBanner(
                context,
                nextStep: nextStep,
                distanceMeters: distToStepMeters,
                trafficStatus: trafficStatus,
              ),
            ),
          ),
        ),

        // 2. Floating Action Controls (Re-center, 3D/2D, Traffic Layer)
        Positioned(
          right: 14,
          bottom: 260,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Re-Center Navigation Floating Pill
              if (widget.isMapPanned) ...[
                _buildRecenterPill(context),
                const SizedBox(height: 12),
              ],

              // 3D / 2D Perspective Toggle
              _buildControlFab(
                heroTag: 'nav_3d_toggle',
                tooltip: widget.is3DMode ? 'Switch to 2D Map' : 'Switch to 3D Navigation',
                icon: widget.is3DMode ? Icons.view_in_ar_rounded : Icons.map_rounded,
                isActive: widget.is3DMode,
                activeColor: AppTheme.accentCyan,
                onPressed: () {
                  _deviceService.triggerHaptic('selection');
                  widget.onToggle3D(!widget.is3DMode);
                },
              ),
              const SizedBox(height: 10),

              // Traffic Layer Toggle
              _buildControlFab(
                heroTag: 'nav_traffic_toggle',
                tooltip: widget.isTrafficLayerActive ? 'Hide Live Traffic' : 'Show Live Traffic',
                icon: Icons.traffic_rounded,
                isActive: widget.isTrafficLayerActive,
                activeColor: Colors.amber,
                onPressed: () {
                  _deviceService.triggerHaptic('selection');
                  widget.onToggleTraffic(!widget.isTrafficLayerActive);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Top Navigation Turn Banner
  Widget _buildTurnGuidanceBanner(
    BuildContext context, {
    required RouteStep? nextStep,
    required int distanceMeters,
    required _TrafficStatus trafficStatus,
  }) {
    final maneuver = nextStep?.maneuver ?? 'STRAIGHT';
    final primaryInstruction = nextStep?.primaryInstruction ?? 'Head towards destination';
    final roadName = nextStep?.roadName ?? widget.destinationAddress;

    final distanceStr = distanceMeters >= 1000
        ? '${(distanceMeters / 1000.0).toStringAsFixed(1)} km'
        : '$distanceMeters m';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A), // Deep Slate Navy
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.accentCyan.withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Maneuver Icon
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: AppTheme.emeraldGreen.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.emeraldGreen,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Icon(
                    _getManeuverIcon(maneuver),
                    color: AppTheme.emeraldGreen,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Distance & Next Street
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      distanceStr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      primaryInstruction,
                      style: const TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (roadName.isNotEmpty && roadName != primaryInstruction) ...[
                      Text(
                        roadName,
                        style: TextStyle(
                          color: AppTheme.accentCyan.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w500,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              // Speedometer Chip & Voice Mute Toggle
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Speedometer
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white24,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.speed_rounded,
                          size: 13,
                          color: AppTheme.accentCyan,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.currentSpeedKmh > 0
                              ? '${widget.currentSpeedKmh.round()} km/h'
                              : '42 km/h',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Mute / Unmute Button
                  InkWell(
                    onTap: () {
                      _deviceService.triggerHaptic('selection');
                      setState(() => _isVoiceMuted = !_isVoiceMuted);
                      if (_isVoiceMuted) _audioService.stop();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        _isVoiceMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                        color: _isVoiceMuted ? Colors.white38 : AppTheme.accentCyan,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: Colors.white12),
          const SizedBox(height: 8),

          // Bottom Bar: Remaining ETA, Remaining Distance & Live Traffic Status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Remaining Time & ETA
              Row(
                children: [
                  Text(
                    '${widget.remainingDurationMin.round()} min',
                    style: TextStyle(
                      color: trafficStatus.color,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${widget.remainingDistanceKm.toStringAsFixed(1)} km)',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              // Live Traffic Delay Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: trafficStatus.color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: trafficStatus.color.withValues(alpha: 0.6),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: trafficStatus.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      trafficStatus.label,
                      style: TextStyle(
                        color: trafficStatus.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Floating "Re-Center" button that pops up when user drags map
  Widget _buildRecenterPill(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          _deviceService.triggerHaptic('heavy');
          widget.onRecenter();
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppTheme.accentCyan,
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentCyan.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.navigation_rounded,
                color: AppTheme.accentCyan,
                size: 18,
              ),
              SizedBox(width: 6),
              Text(
                'Re-center',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Floating Map Controller Button (3D and Traffic toggles)
  Widget _buildControlFab({
    required String heroTag,
    required String tooltip,
    required IconData icon,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: FloatingActionButton.small(
        heroTag: heroTag,
        tooltip: tooltip,
        onPressed: onPressed,
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: isActive ? activeColor : Colors.white60,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 20),
            if (isActive)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: activeColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Calculates the next upcoming turn step based on proximity
  _NextStepInfo _calculateNextStep(RouteOption? route, LatLng vehicleLoc) {
    if (route == null || route.steps.isEmpty) {
      return const _NextStepInfo(step: null, distanceMeters: 450, stepIndex: 0);
    }

    double minDistance = double.infinity;
    int closestIndex = 0;

    for (int i = 0; i < route.steps.length; i++) {
      final step = route.steps[i];
      final target = step.startLocation ?? (step.stepPoints.isNotEmpty ? step.stepPoints.first : null);
      if (target != null) {
        final d = _distanceMeters(vehicleLoc, target);
        if (d < minDistance) {
          minDistance = d;
          closestIndex = i;
        }
      }
    }

    // If already at or past the closest step, navigate to the subsequent step
    final nextIndex = (closestIndex < route.steps.length - 1 && minDistance < 40)
        ? closestIndex + 1
        : closestIndex;

    final targetStep = route.steps[nextIndex];
    final stepTarget = targetStep.startLocation ??
        (targetStep.stepPoints.isNotEmpty ? targetStep.stepPoints.first : null);
    final finalDist = stepTarget != null
        ? _distanceMeters(vehicleLoc, stepTarget).round()
        : targetStep.distanceMeters;

    return _NextStepInfo(
      step: targetStep,
      distanceMeters: finalDist > 0 ? finalDist : 200,
      stepIndex: nextIndex,
    );
  }

  void _maybeAnnounceStep(_NextStepInfo info) {
    if (_isVoiceMuted || info.step == null) return;
    if (info.distanceMeters <= 180 && _lastAnnouncedStepIndex != info.stepIndex) {
      _lastAnnouncedStepIndex = info.stepIndex;
      final distStr = info.distanceMeters <= 50 ? 'Now' : 'In ${info.distanceMeters} meters';
      _audioService.speak('$distStr, ${info.step!.primaryInstruction}');
    }
  }

  _TrafficStatus _getTrafficStatus(RouteOption? route) {
    if (route == null) {
      return const _TrafficStatus(
        label: 'Fastest Route',
        color: AppTheme.emeraldGreen,
      );
    }

    final delay =
        (route.durationMin - route.staticDurationMin).clamp(0.0, 999.0);
    final isCongested = route.trafficLevel == 'HEAVY' ||
        route.trafficLevel == 'SLOW' ||
        delay >= 2.0;
    if (delay >= 5.0 || route.trafficLevel == 'HEAVY') {
      return _TrafficStatus(
        label: 'Heavy Traffic (+${delay.round()}m)',
        color: const Color(0xFFEF4444), // Red
      );
    } else if (isCongested) {
      return _TrafficStatus(
        label: 'Moderate (+${delay.round()}m)',
        color: const Color(0xFFF59E0B), // Amber
      );
    } else {
      return const _TrafficStatus(
        label: 'Normal Traffic',
        color: AppTheme.emeraldGreen,
      );
    }
  }

  IconData _getManeuverIcon(String maneuver) {
    final m = maneuver.toUpperCase();
    if (m.contains('LEFT')) {
      if (m.contains('SLIGHT')) return Icons.turn_slight_left_rounded;
      if (m.contains('SHARP')) return Icons.turn_sharp_left_rounded;
      if (m.contains('U_TURN') || m.contains('UTURN')) return Icons.u_turn_left_rounded;
      return Icons.turn_left_rounded;
    }
    if (m.contains('RIGHT')) {
      if (m.contains('SLIGHT')) return Icons.turn_slight_right_rounded;
      if (m.contains('SHARP')) return Icons.turn_sharp_right_rounded;
      if (m.contains('U_TURN') || m.contains('UTURN')) return Icons.u_turn_right_rounded;
      return Icons.turn_right_rounded;
    }
    if (m.contains('ROUNDABOUT')) return Icons.roundabout_left_rounded;
    if (m.contains('FORK') || m.contains('RAMP') || m.contains('MERGE')) {
      return Icons.call_split_rounded;
    }
    if (m.contains('ARRIVE')) return Icons.flag_rounded;
    return Icons.straight_rounded;
  }

  double _distanceMeters(LatLng p1, LatLng p2) {
    const r = 6371000.0;
    final dLat = (p2.latitude - p1.latitude) * math.pi / 180.0;
    final dLng = (p2.longitude - p1.longitude) * math.pi / 180.0;
    final lat1 = p1.latitude * math.pi / 180.0;
    final lat2 = p2.latitude * math.pi / 180.0;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLng / 2) * math.sin(dLng / 2) * math.cos(lat1) * math.cos(lat2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }
}

class _NextStepInfo {
  final RouteStep? step;
  final int distanceMeters;
  final int stepIndex;

  const _NextStepInfo({
    required this.step,
    required this.distanceMeters,
    required this.stepIndex,
  });
}

class _TrafficStatus {
  final String label;
  final Color color;

  const _TrafficStatus({
    required this.label,
    required this.color,
  });
}
