import 'dart:io';

import 'package:flutter/material.dart';

import 'app_image.dart';
import 'app_video_player.dart';
import '../core/utils/routes.dart';

class PhotoGrid extends StatelessWidget {
  final List<String> imagePaths;
  final VoidCallback onAdd;
  final void Function(int index) onRemove;

  const PhotoGrid({
    super.key,
    required this.imagePaths,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...imagePaths.asMap().entries.map((e) => _MediaTile(
              path: e.value,
              onRemove: () => onRemove(e.key),
            )),
        if (imagePaths.length < 9) _AddTile(onTap: onAdd),
      ],
    );
  }
}

class _MediaTile extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;

  const _MediaTile({required this.path, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    if (isVideoFile(path)) {
      return VideoThumbnail(
        path: path,
        width: 100,
        height: 100,
        showRemove: true,
        onRemove: onRemove,
        onTap: () => _playVideo(context),
      );
    }
    return _PhotoTile(path: path, onRemove: onRemove);
  }

  void _playVideo(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenVideoPlayer(path: path),
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final String path;
  final VoidCallback onRemove;

  const _PhotoTile({required this.path, required this.onRemove});

  void _viewFullScreen(BuildContext context) {
    Navigator.push(
      context,
      AppRoutes.slideUp(
        builder: (_) => _FullScreenPhoto(path: path),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _viewFullScreen(context),
      child: Stack(
        children: [
          AppImage(
            path: path,
            width: 100,
            height: 100,
            borderRadius: 8,
          ),
          Positioned(
            top: -2,
            right: -2,
            child: IconButton(
              icon: const Icon(Icons.cancel, color: Colors.white, size: 20),
              onPressed: onRemove,
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

class _FullScreenPhoto extends StatelessWidget {
  final String path;

  const _FullScreenPhoto({required this.path});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 5.0,
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, e, s) => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image, size: 64, color: Colors.white54),
                SizedBox(height: 16),
                Text('图片加载失败',
                    style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AddTile extends StatelessWidget {
  final VoidCallback onTap;

  const _AddTile({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        height: 100,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2E2B29) : const Color(0xFFF0EDE8),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? const Color(0xFF383430) : const Color(0xFFE8E4DD),
          ),
        ),
        child: Icon(
          Icons.add_a_photo,
          color: isDark ? const Color(0xFF9B948C) : const Color(0xFF69727A),
          size: 32,
        ),
      ),
    );
  }
}
