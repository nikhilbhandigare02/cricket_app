import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

/// Fades and slides its child up when it first appears. Give list items their
/// [index] so they arrive one after another (the stagger is capped, so long
/// lists never feel slow).
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;
  const FadeSlideIn({super.key, required this.child, this.index = 0});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final Animation<double> _fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
  late final Animation<Offset> _slide = Tween(begin: const Offset(0, 0.12), end: Offset.zero)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _delay = Timer(Duration(milliseconds: min(widget.index, 8) * 55), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _fade, child: SlideTransition(position: _slide, child: widget.child));
}

/// A softly pulsing dot, used for "LIVE".
class PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  const PulseDot({super.key, this.color = Colors.red, this.size = 10});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size + 4,
      height: widget.size + 4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Center(
          child: Container(
            width: widget.size * (0.75 + 0.35 * _c.value),
            height: widget.size * (0.75 + 0.35 * _c.value),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.55 + 0.45 * _c.value),
              boxShadow: [
                BoxShadow(color: widget.color.withValues(alpha: 0.5 * _c.value), blurRadius: 6, spreadRadius: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Text that slides and fades when its value changes (scores, counts).
class AnimatedValueText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const AnimatedValueText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      child: Text(text, key: ValueKey(text), style: style),
    );
  }
}

/// Full-screen loading: the logo gently breathing.
class AplLoader extends StatefulWidget {
  const AplLoader({super.key});

  @override
  State<AplLoader> createState() => _AplLoaderState();
}

class _AplLoaderState extends State<AplLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
          animation: _c,
          builder: (_, child) => Transform.scale(scale: 0.9 + 0.12 * _c.value, child: child),
          child: Image.asset('assets/logo.png', width: 110, height: 110),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: 90,
          child: LinearProgressIndicator(borderRadius: BorderRadius.circular(8), minHeight: 4),
        ),
      ]),
    );
  }
}
