import 'dart:io';

import 'package:flutter/material.dart';

/// Optimized local image widget with loading placeholder and error state.
class AppImage extends StatefulWidget {
  final String? path;
  final double width;
  final double height;
  final double borderRadius;
  final BoxFit fit;
  final VoidCallback? onTap;

  const AppImage({
    super.key,
    this.path,
    this.width = 100,
    this.height = 100,
    this.borderRadius = 8,
    this.fit = BoxFit.cover,
    this.onTap,
  });

  @override
  State<AppImage> createState() => _AppImageState();
}

class _AppImageState extends State<AppImage> {
  bool _hasError = false;

  @override
  void didUpdateWidget(AppImage old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) {
      _hasError = false;
    }
  }

  bool get _shouldShowPlaceholder =>
      _hasError || widget.path == null || widget.path!.isEmpty;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: SizedBox(
          width: widget.width,
          height: widget.height,
          child: _shouldShowPlaceholder
              ? Container(
                  color: isDark ? const Color(0xFF2E2B29) : const Color(0xFFE8E4DD),
                  child: Icon(
                    Icons.image_outlined,
                    color: isDark ? const Color(0xFF6B6560) : const Color(0xFFB0A99E),
                    size: widget.width > 50 ? 32 : 16,
                  ),
                )
              : Image.file(
                  File(widget.path!),
                  fit: widget.fit,
                  width: widget.width,
                  height: widget.height,
                  cacheWidth: widget.width.isFinite
                      ? (widget.width * 2).round()
                      : null,
                  cacheHeight: widget.height.isFinite
                      ? (widget.height * 2).round()
                      : null,
                  errorBuilder: (_, _, _) {
                    // Use post-frame callback to avoid setState during build
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && !_hasError) {
                        setState(() => _hasError = true);
                      }
                    });
                    return const SizedBox.shrink();
                  },
                ),
        ),
      ),
    );
  }
}
