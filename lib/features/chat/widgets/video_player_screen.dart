import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/chat_time.dart';

/// In-app player for bridged audio & video.
///
/// Uses `video_player` with `httpHeaders`, so it can stream authenticated
/// Matrix media (the Bearer token an external browser/player can't send —
/// which is why "tap to open" opened a dead link before).
class VideoPlayerScreen extends StatefulWidget {
  final String url;
  final Map<String, String> headers;
  final String? title;
  final bool isAudio;

  const VideoPlayerScreen({
    super.key,
    required this.url,
    required this.headers,
    this.title,
    this.isAudio = false,
  });

  static Route route({
    required String url,
    required Map<String, String> headers,
    String? title,
    bool isAudio = false,
  }) {
    return PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => VideoPlayerScreen(
        url: url,
        headers: headers,
        title: title,
        isAudio: isAudio,
      ),
      transitionsBuilder: (_, anim, __, child) =>
          FadeTransition(opacity: anim, child: child),
    );
  }

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _initializing = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.url),
        httpHeaders: widget.headers,
      );
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      controller.addListener(_onTick);
      await controller.play();
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = 'Couldn\u2019t play this media.';
        });
      }
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final value = controller?.value;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.title ?? (widget.isAudio ? 'Audio' : 'Video'),
          style: const TextStyle(color: Colors.white, fontSize: 15),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: _initializing
            ? const CircularProgressIndicator(color: Colors.white54)
            : _error != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: Colors.white38, size: 48),
                      const SizedBox(height: 12),
                      Text(_error!,
                          style: const TextStyle(color: Colors.white70)),
                    ],
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.isAudio || (value?.size.height ?? 0) == 0)
                        _audioArt()
                      else
                        AspectRatio(
                          aspectRatio: value!.aspectRatio == 0
                              ? 16 / 9
                              : value.aspectRatio,
                          child: VideoPlayer(controller!),
                        ),
                      if (controller != null) _controls(controller),
                    ],
                  ),
      ),
    );
  }

  Widget _audioArt() {
    return Container(
      width: 160,
      height: 160,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A6FF8), Color(0xFF2F5CE0)],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Icon(
        (_controller?.value.isPlaying ?? false)
            ? Icons.graphic_eq_rounded
            : Icons.music_note_rounded,
        color: Colors.white,
        size: 64,
      ),
    );
  }

  Widget _controls(VideoPlayerController controller) {
    final v = controller.value;
    final pos = v.position;
    final dur = v.duration;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          Row(
            children: [
              Text(ChatTime.duration(pos),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: Color(0xFF3A6FF8),
                      bufferedColor: Colors.white24,
                      backgroundColor: Colors.white12,
                    ),
                  ),
                ),
              ),
              Text(ChatTime.duration(dur),
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                onPressed: () => controller.seekTo(
                    pos - const Duration(seconds: 10)),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 58,
                  height: 58,
                  decoration: const BoxDecoration(
                    color: Color(0xFF3A6FF8),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    v.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon:
                    const Icon(Icons.forward_10_rounded, color: Colors.white),
                onPressed: () => controller.seekTo(
                    pos + const Duration(seconds: 10)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
