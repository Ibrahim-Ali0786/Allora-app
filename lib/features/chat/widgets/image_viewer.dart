import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Full-screen media viewer: Hero in, pinch-to-zoom, drag-down to dismiss,
/// immersive black canvas.
class ImageViewerScreen extends StatefulWidget {
  final String url;
  final Map<String, String> headers;
  final String heroTag;
  final String? title;

  const ImageViewerScreen({
    super.key,
    required this.url,
    this.headers = const {},
    required this.heroTag,
    this.title,
  });

  static Route route({
    required String url,
    Map<String, String> headers = const {},
    required String heroTag,
    String? title,
  }) {
    return PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => ImageViewerScreen(
          url: url, headers: headers, heroTag: heroTag, title: title),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  final _transform = TransformationController();
  double _dragOffset = 0;
  bool _chromeVisible = true;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  bool get _zoomed => _transform.value.getMaxScaleOnAxis() > 1.05;

  @override
  Widget build(BuildContext context) {
    final dragProgress = (_dragOffset.abs() / 300).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 1 - dragProgress * 0.6),
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => setState(() => _chromeVisible = !_chromeVisible),
            onVerticalDragUpdate: _zoomed
                ? null
                : (d) => setState(() => _dragOffset += d.delta.dy),
            onVerticalDragEnd: _zoomed
                ? null
                : (d) {
                    if (_dragOffset.abs() > 120 ||
                        (d.primaryVelocity ?? 0).abs() > 700) {
                      Navigator.pop(context);
                    } else {
                      setState(() => _dragOffset = 0);
                    }
                  },
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: Transform.scale(
                scale: 1 - dragProgress * 0.12,
                child: Center(
                  child: Hero(
                    tag: widget.heroTag,
                    child: InteractiveViewer(
                      transformationController: _transform,
                      minScale: 1,
                      maxScale: 5,
                      child: Image.network(
                        widget.url,
                        headers: widget.headers,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: CircularProgressIndicator(
                                  color: Colors.white54, strokeWidth: 2.5),
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image_rounded,
                            color: Colors.white38,
                            size: 64),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: _chromeVisible && dragProgress == 0 ? 1 : 0,
            child: SafeArea(
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        widget.title ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Copy link',
                      icon: const Icon(Icons.link_rounded, color: Colors.white),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: widget.url));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied')));
                      },
                    ),
                    IconButton(
                      tooltip: 'Open externally',
                      icon: const Icon(Icons.open_in_new_rounded,
                          color: Colors.white),
                      onPressed: () => launchUrl(Uri.parse(widget.url),
                          mode: LaunchMode.externalApplication),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
