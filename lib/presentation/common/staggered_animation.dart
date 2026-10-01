import 'dart:async';
import 'package:flutter/material.dart';

/// Reusable staggered entrance animation widget that gracefully cascades
/// UI elements into view with combined fade, subtle upward slide, and scale transitions.
class StaggeredEntryWidget extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration duration;
  final int staggerDelayMs;
  final double slideOffset;

  const StaggeredEntryWidget({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = const Duration(milliseconds: 400),
    this.staggerDelayMs = 60,
    this.slideOffset = 24.0,
  });

  @override
  State<StaggeredEntryWidget> createState() => _StaggeredEntryWidgetState();
}

class _StaggeredEntryWidgetState extends State<StaggeredEntryWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _scaleAnimation;
  Timer? _staggerTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _slideAnimation = Tween<Offset>(
      begin: Offset(0, widget.slideOffset / 100),
      end: Offset.zero,
    ).animate(curved);
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(curved);

    // Trigger immediately if index == 0, otherwise schedule with cancelable timer
    final delayMs = widget.index * widget.staggerDelayMs;
    if (delayMs <= 0) {
      _controller.forward();
    } else {
      _staggerTimer = Timer(Duration(milliseconds: delayMs), () {
        if (mounted) {
          _controller.forward();
        }
      });
    }
  }

  @override
  void dispose() {
    _staggerTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: widget.child,
        ),
      ),
    );
  }
}

/// An ambient pulsing glow widget for active elements (e.g. SOS beacons, live drivers, 0% commission badge).
class PulsingGlowWidget extends StatefulWidget {
  final Widget child;
  final Color glowColor;
  final double minSpread;
  final double maxSpread;
  final Duration duration;

  const PulsingGlowWidget({
    super.key,
    required this.child,
    required this.glowColor,
    this.minSpread = 2.0,
    this.maxSpread = 8.0,
    this.duration = const Duration(milliseconds: 1800),
  });

  @override
  State<PulsingGlowWidget> createState() => _PulsingGlowWidgetState();
}

class _PulsingGlowWidgetState extends State<PulsingGlowWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);

    _glowAnimation = Tween<double>(
      begin: widget.minSpread,
      end: widget.maxSpread,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withValues(alpha: 0.35),
                blurRadius: _glowAnimation.value * 2,
                spreadRadius: _glowAnimation.value,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
