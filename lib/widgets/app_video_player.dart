import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// Checks whether [path] looks like a video file by its extension.
bool isVideoFile(String path) {
  final ext = path.split('.').last.toLowerCase();
  return ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp', 'm4v'].contains(ext);
}

/// A video thumbnail tile that initializes [VideoPlayerController] to
/// capture the real first frame, then shows it as a static preview with
/// a play-icon badge — just like the phone's gallery app does.
class VideoThumbnail extends StatefulWidget {
  final String path;
  final double width;
  final double height;
  final double borderRadius;
  final VoidCallback? onTap;
  final bool showRemove;
  final VoidCallback? onRemove;

  const VideoThumbnail({
    super.key,
    required this.path,
    this.width = 100,
    this.height = 100,
    this.borderRadius = 6,
    this.onTap,
    this.showRemove = false,
    this.onRemove,
  });

  @override
  State<VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<VideoThumbnail> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.path.isEmpty) return; // 空路径不初始化解码器
    final ctrl = VideoPlayerController.file(File(widget.path));
    try {
      await ctrl.initialize();
      // Show first frame by staying paused (default state after initialize)
      // Don't play — just show the first frame like a still image
    } catch (e) {
      debugPrint('VideoThumbnail init error: $e');
      ctrl.dispose();
      return;
    }
    if (mounted) {
      setState(() {
        _controller = ctrl;
        _ready = true;
      });
    } else {
      ctrl.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Real first frame from video (or loading placeholder)
          ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: _ready && _controller != null
                  ? FittedBox(
                      fit: BoxFit.cover,
                      clipBehavior: Clip.hardEdge,
                      child: SizedBox(
                        width: _controller!.value.size.width,
                        height: _controller!.value.size.height,
                        child: VideoPlayer(_controller!),
                      ),
                    )
                  : Container(color: Colors.black26),
            ),
          ),
          // Play icon badge
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.play_arrow,
                color: Colors.white, size: 22),
          ),
          // Remove button
          if (widget.showRemove && widget.onRemove != null)
            Positioned(
              top: -2,
              right: -2,
              child: IconButton(
                icon: const Icon(Icons.cancel,
                    color: Colors.white, size: 20),
                onPressed: widget.onRemove,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(24, 24),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Full-screen video player with play/pause controls.
/// Creates and owns its own [VideoPlayerController].
class FullScreenVideoPlayer extends StatefulWidget {
  final String path;

  const FullScreenVideoPlayer({
    super.key,
    required this.path,
  });

  @override
  State<FullScreenVideoPlayer> createState() => _FullScreenVideoPlayerState();
}

class _FullScreenVideoPlayerState extends State<FullScreenVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ctrl = VideoPlayerController.file(File(widget.path));
    try {
      await ctrl.initialize();
      ctrl.setLooping(true);
      ctrl.play();
      ctrl.addListener(_onControllerEvent);
    } catch (e) {
      debugPrint('FullScreenVideoPlayer init error: $e');
      ctrl.dispose();
      return;
    }
    if (mounted) {
      setState(() {
        _controller = ctrl;
        _initialized = true;
      });
    } else {
      ctrl.dispose();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerEvent);
    _controller?.dispose();
    super.dispose();
  }

  void _onControllerEvent() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _controller != null
              ? _formatDuration(_controller!.value.position)
              : '加载中...',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
      ),
      body: GestureDetector(
        onTap: () => setState(() => _showControls = !_showControls),
        child: Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              _initialized && _controller != null
                  ? AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: VideoPlayer(_controller!),
                    )
                  : const Center(child: CircularProgressIndicator()),
              if (_showControls && _initialized)
                GestureDetector(
                  onTap: () {
                    if (_controller!.value.isPlaying) {
                      _controller!.pause();
                    } else {
                      _controller!.play();
                    }
                  },
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Colors.white24,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _controller!.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              if (_showControls && _initialized)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: VideoProgressIndicator(
                      _controller!,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Colors.white,
                        backgroundColor: Colors.white24,
                        bufferedColor: Colors.white38,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final min = d.inMinutes;
    final sec = d.inSeconds % 60;
    return '${min.toString().padLeft(2, "0")}:${sec.toString().padLeft(2, "0")}';
  }
}
