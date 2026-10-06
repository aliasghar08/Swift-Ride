import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// A shimmering placeholder shown while real content loads.
///
/// Replaces bare spinners so the layout does not jump when data arrives, and so
/// the user can see the shape of what is coming. The shimmer honours the OS
/// reduce-motion setting by rendering a flat block instead of animating.
class SkeletonBox extends StatefulWidget {
  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius,
    this.baseColor,
  });

  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  /// Overrides the base tone — use on dark surfaces such as the map overlays,
  /// where the theme's light surface colour would glare.
  final Color? baseColor;

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final radius = widget.borderRadius ?? Radii.smAll;
    final base = widget.baseColor ?? c.surfaceRaised;
    final highlight = Color.lerp(base, c.surface, 0.55) ?? base;

    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      return Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(color: base, borderRadius: radius),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              transform: _SlidingGradient(_controller.value),
            ),
          ),
        );
      },
    );
  }
}

class _SlidingGradient extends GradientTransform {
  const _SlidingGradient(this.progress);

  /// 0 → 1 over one shimmer cycle.
  final double progress;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * (progress * 2 - 1), 0, 0);
  }
}

/// A single line of placeholder text.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.widthFactor = 1.0, this.height = 12});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: SkeletonBox(
        height: height,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );
  }
}

/// A placeholder card matching the app's list-row shape.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 2});

  final int lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Spacing.lg),
      decoration: BoxDecoration(
        color: AppColors.of(context).surface,
        borderRadius: Radii.lgAll,
        border: Border.all(color: AppColors.of(context).border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(
            width: 44,
            height: 44,
            borderRadius: BorderRadius.all(Radius.circular(22)),
          ),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < lines; i++) ...[
                  SkeletonLine(widthFactor: i.isEven ? 0.85 : 0.55),
                  if (i != lines - 1) const SizedBox(height: Spacing.sm),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A vertical stack of placeholder cards, for list loading states.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    this.count = 3,
    this.linesPerCard = 2,
    this.padding = const EdgeInsets.all(Spacing.lg),
  });

  final int count;
  final int linesPerCard;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        children: [
          for (var i = 0; i < count; i++) ...[
            SkeletonCard(lines: linesPerCard),
            if (i != count - 1) const SizedBox(height: Spacing.md),
          ],
        ],
      ),
    );
  }
}
