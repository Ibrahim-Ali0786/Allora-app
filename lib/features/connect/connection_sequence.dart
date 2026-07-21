import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

/// Enterprise-style connection sequence: platform artwork over a soft
/// gradient glow, an animated progress line, and staged status text —
///
///   Connecting securely… → Establishing encrypted session… →
///   Synchronizing workspace… → Preparing conversations… → Connected
///
/// No checkmark bursts, no confetti — just calm, premium transitions.
/// Runs ~2.6s, then calls [onDone] (e.g. auto-close the sheet; HomeGate
/// then drops the user straight into the inbox).
class ConnectionSequence extends StatefulWidget {
  final String? artworkAsset;
  final IconData fallbackIcon;
  final Color brandColor;
  final VoidCallback? onDone;
  final List<String> stages;

  const ConnectionSequence({
    super.key,
    required this.brandColor,
    this.artworkAsset,
    this.fallbackIcon = Icons.link_rounded,
    this.onDone,
    this.stages = const [
      'Connecting securely…',
      'Establishing encrypted session…',
      'Synchronizing workspace…',
      'Preparing conversations…',
      'Connected',
    ],
  });

  @override
  State<ConnectionSequence> createState() => _ConnectionSequenceState();
}

class _ConnectionSequenceState extends State<ConnectionSequence>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;
  Timer? _stageTimer;
  int _stage = 0;

  static const _stageInterval = Duration(milliseconds: 550);

  @override
  void initState() {
    super.initState();
    final total = _stageInterval * widget.stages.length;
    _progress = AnimationController(vsync: this, duration: total)..forward();
    _stageTimer = Timer.periodic(_stageInterval, (t) {
      if (!mounted) return;
      if (_stage >= widget.stages.length - 1) {
        t.cancel();
        // Brief hold on "Connected" before finishing.
        Timer(const Duration(milliseconds: 450), () {
          if (mounted) widget.onDone?.call();
        });
        return;
      }
      setState(() => _stage++);
    });
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    _progress.dispose();
    super.dispose();
  }

  bool get _finished => _stage >= widget.stages.length - 1;

  @override
  Widget build(BuildContext context) {
    final brand = widget.brandColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Platform artwork inside a soft blurred brand glow.
          SizedBox(
            width: 130,
            height: 130,
            child: Stack(
              alignment: Alignment.center,
              children: [
                ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          brand.withValues(alpha: 0.55),
                          brand.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.86, end: 1),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) => Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: Transform.scale(scale: t, child: child),
                  ),
                  child: widget.artworkAsset != null
                      ? Image.asset(widget.artworkAsset!,
                          width: 64,
                          height: 64,
                          errorBuilder: (_, __, ___) =>
                              Icon(widget.fallbackIcon,
                                  size: 52, color: brand))
                      : Icon(widget.fallbackIcon, size: 52, color: brand),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          // Animated connection line.
          SizedBox(
            width: 220,
            height: 3,
            child: AnimatedBuilder(
              animation: _progress,
              builder: (context, _) => ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: Curves.easeInOutCubic.transform(_progress.value),
                  minHeight: 3,
                  backgroundColor: brand.withValues(alpha: 0.14),
                  valueColor: AlwaysStoppedAnimation(brand),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          // Staged status text with gentle slide/fade swaps.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.35),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: Text(
              widget.stages[_stage],
              key: ValueKey(_stage),
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: _finished ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: -0.1,
                color: _finished ? brand : Colors.grey.shade600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
