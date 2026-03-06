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

class EaFadeSlideIn extends StatefulWidget {
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
  State<EaFadeSlideIn> createState() => _EaFadeSlideInState();
}

class _EaFadeSlideInState extends State<EaFadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _bindAnimations();
    if (widget.duration == Duration.zero) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  void _bindAnimations() {
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: Offset(widget.begin.dx * 0.6, widget.begin.dy * 0.6),
      end: Offset.zero,
    ).animate(_fade);
  }

  @override
  void didUpdateWidget(covariant EaFadeSlideIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration ||
        oldWidget.begin != widget.begin) {
      _controller.duration = widget.duration;
      _bindAnimations();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
