import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Dependency-free shimmer. One [AnimationController] per [SkeletonArea]
/// drives every child [SkeletonBox] via an [InheritedWidget]-style lookup,
/// so a full-screen skeleton costs a single ticker.
class SkeletonArea extends StatefulWidget {
  final Widget child;
  const SkeletonArea({super.key, required this.child});

  @override
  State<SkeletonArea> createState() => _SkeletonAreaState();
}

class _SkeletonAreaState extends State<SkeletonArea>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final t = _ctrl.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              c.surfaceAlt,
              Color.lerp(c.surfaceAlt, c.outline, 0.9)!,
              c.surfaceAlt,
            ],
            stops: [
              (t - 0.3).clamp(0.0, 1.0),
              t,
              (t + 0.3).clamp(0.0, 1.0),
            ],
          ).createShader(bounds),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final bool circle;

  const SkeletonBox({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.radius = 8,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    return Container(
      width: circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    );
  }
}

/// Chat-list style loading placeholder rows.
class ChatListSkeleton extends StatelessWidget {
  final int rows;
  const ChatListSkeleton({super.key, this.rows = 9});

  @override
  Widget build(BuildContext context) {
    return SkeletonArea(
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows,
        padding: const EdgeInsets.only(top: 4),
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const SkeletonBox(height: 52, circle: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(height: 14, width: 120.0 + (i % 3) * 40, radius: 7),
                    const SizedBox(height: 8),
                    SkeletonBox(height: 12, width: 190.0 + (i % 2) * 50, radius: 6),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const SkeletonBox(height: 10, width: 32, radius: 5),
            ],
          ),
        ),
      ),
    );
  }
}
