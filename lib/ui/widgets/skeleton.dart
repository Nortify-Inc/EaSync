/*!
 * @file skeleton.dart
 * @brief Reusable skeleton loading widgets and shimmer-like animation.
 * @param No external parameters.
 * @return Visual loading placeholders.
 * @author Erick Radmann
 */

import 'package:flutter/material.dart';

class EaSkeleton extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const EaSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
  });

  @override
  State<EaSkeleton> createState() => _EaSkeletonState();
}

class _EaSkeletonState extends State<EaSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final base = dark ? const Color(0xFF2C3342) : const Color(0xFFE3E8F4);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final opacity = 0.45 + (_controller.value * 0.35);
        return Opacity(
          opacity: opacity,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: base,
              borderRadius: widget.borderRadius,
            ),
          ),
        );
      },
    );
  }
}

class EaFadeSlideIn extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Offset begin;

  const EaFadeSlideIn({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 260),
    this.begin = const Offset(0, 0.02),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (context, t, _) {
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(begin.dx * (1 - t) * 30, begin.dy * (1 - t) * 30),
            child: child,
          ),
        );
      },
    );
  }
}
