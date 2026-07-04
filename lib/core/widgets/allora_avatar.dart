// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';

import '../utils/matrix_media.dart';

import '../theme/app_theme.dart';
import '../../screens/networks/network_meta.dart';

/// Deterministic pastel color for a name/id so placeholder avatars stay
/// stable between rebuilds and app launches.
Color colorForId(String id, {required bool dark}) {
  const palette = [
    Color(0xFF3A6FF8), Color(0xFF7C5CFC), Color(0xFF00A3AD),
    Color(0xFFE45794), Color(0xFFE8930C), Color(0xFF1FA45B),
    Color(0xFFDB5C5C), Color(0xFF5C7CDB),
  ];
  var hash = 0;
  for (final unit in id.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  final base = palette[hash % palette.length];
  return dark ? Color.lerp(base, Colors.white, 0.08)! : base;
}

/// Unified avatar for rooms and users.
///
/// * Uses the Matrix thumbnail endpoint with an explicit `cacheWidth`
///   so decoded bitmaps stay small — Flutter's [ImageCache] then keeps them
///   in memory, which is what makes fast scrolling smooth.
/// * Falls back to colored initials (never a broken-image glyph).
/// * Optionally overlays the source-network badge (WhatsApp, Telegram, …).
class AlloraAvatar extends StatelessWidget {
  final Uri? mxcUri;
  final Client? client;
  final String name;
  final double size;
  final NetworkMeta? network;
  final bool showNetworkBadge;

  const AlloraAvatar({
    super.key,
    required this.name,
    this.mxcUri,
    this.client,
    this.size = 52,
    this.network,
    this.showNetworkBadge = true,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final initial = _initials(name);
    final bg = colorForId(name.isEmpty ? '?' : name, dark: dark);

    Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg.withValues(alpha: 0.95), Color.lerp(bg, Colors.black, 0.18)!],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _thumbnail(initial),
    );

    if (network != null && showNetworkBadge) {
      final badgeSize = (size * 0.42).clamp(16.0, 22.0);
      avatar = Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: badgeSize,
              height: badgeSize,
              padding: EdgeInsets.all(badgeSize * 0.16),
              decoration: BoxDecoration(
                color: c.canvas,
                shape: BoxShape.circle,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: network!.brandColor,
                  shape: BoxShape.circle,
                ),
                padding: EdgeInsets.all(badgeSize * 0.18),
                child: network!.asset != null
                    ? Image.asset(network!.asset!, color: Colors.white,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink())
                    : Icon(network!.icon ?? Icons.link,
                        size: badgeSize * 0.5, color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }
    return avatar;
  }

  Widget _thumbnail(String initial) {
    final fallback = Center(
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.38,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
    );

    if (mxcUri == null || client == null) return fallback;

    final px = (size * 3).round(); // ~3x for crisp thumbs on high-dpi
    final source = MatrixMedia.thumbnail(client!, mxcUri.toString(),
        width: px, height: px);
    if (source == null) return fallback;

    return Image.network(
      source.url,
      headers: source.headers,
      fit: BoxFit.cover,
      width: size,
      height: size,
      cacheWidth: px,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => fallback,
      frameBuilder: (context, child, frame, wasSync) {
        if (wasSync || frame != null) return child;
        return fallback;
      },
    );
  }

  static String _initials(String name) {
    final cleaned = name.trim();
    if (cleaned.isEmpty) return '?';
    final parts = cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first).toUpperCase();
  }
}
