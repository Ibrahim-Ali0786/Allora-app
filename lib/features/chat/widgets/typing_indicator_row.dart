// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/allora_avatar.dart';

/// Beeper-style typing bubble: avatar + three softly bouncing dots inside
/// a "theirs" bubble. Animates in/out with a slide+fade.
class TypingIndicatorRow extends StatelessWidget {
  final Room room;
  const TypingIndicatorRow({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final typing = room.typingUsers
        .where((u) => u.id != room.client.userID)
        .toList();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SizeTransition(sizeFactor: anim, axisAlignment: -1, child: child),
      ),
      child: typing.isEmpty
          ? const SizedBox.shrink()
          : Padding(
              key: const ValueKey('typing'),
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
              child: Row(
                children: [
                  AlloraAvatar(
                    name: typing.first.calcDisplayname(),
                    mxcUri: typing.first.avatarUrl,
                    client: room.client,
                    size: 26,
                    showNetworkBadge: false,
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                        bottomRight: Radius.circular(18),
                        bottomLeft: Radius.circular(6),
                      ),
                      border: Border.all(color: c.outline),
                    ),
                    child: const _Dots(),
                  ),
                ],
              ),
            ),
    );
  }
}

class _Dots extends StatefulWidget {
  const _Dots();

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

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
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final phase = ((_ctrl.value + i * 0.18) % 1.0);
          final lift = phase < 0.4 ? (phase / 0.4) : (1 - (phase - 0.4) / 0.6);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Transform.translate(
              offset: Offset(0, -3 * lift),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: Color.lerp(
                      c.textTertiary, c.textSecondary, lift.clamp(0.0, 1.0)),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
