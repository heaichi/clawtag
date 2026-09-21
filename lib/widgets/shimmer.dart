import 'package:flutter/material.dart';

/// Shimmer loading effect
class Shimmer extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const Shimmer({
    super.key,
    required this.child,
    this.enabled = true,
  });

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? const Color(0xFF383430) : const Color(0xFFE8E4DD);
    final highlightColor = isDark ? const Color(0xFF4A4540) : const Color(0xFFF0EDE8);

    return _ShimmerAnimating(
      listenable: _controller,
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: widget.child,
    );
  }
}

class _ShimmerAnimating extends AnimatedWidget {
  final Color baseColor;
  final Color highlightColor;
  final Widget child;

  const _ShimmerAnimating({
    required super.listenable,
    required this.baseColor,
    required this.highlightColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) {
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            baseColor,
            baseColor,
            highlightColor,
            baseColor,
            baseColor,
          ],
          stops: [
            0.0,
            animation.value - 0.15,
            animation.value,
            animation.value + 0.15,
            1.0,
          ],
        ).createShader(bounds);
      },
      child: child,
    );
  }
}

/// Shimmer placeholder rectangle.
///
/// Adapts its fill to the current brightness so skeleton screens look
/// natural in both light and dark themes.
class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF383430) : const Color(0xFFF0EDE8),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton card for loading state
class ShimmerCard extends StatelessWidget {
  const ShimmerCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              ShimmerBox(width: 64, height: 64, borderRadius: 32),
              SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 120, height: 16),
                    SizedBox(height: 8),
                    ShimmerBox(width: 180, height: 12),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton diary card
class ShimmerDiaryCard extends StatelessWidget {
  const ShimmerDiaryCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ShimmerBox(width: 60, height: 20),
                  Spacer(),
                  ShimmerBox(width: 80, height: 16),
                ],
              ),
              SizedBox(height: 12),
              ShimmerBox(width: 200, height: 18),
              SizedBox(height: 8),
              ShimmerBox(height: 14),
              SizedBox(height: 4),
              ShimmerBox(width: 160, height: 14),
            ],
          ),
        ),
      ),
    );
  }
}
