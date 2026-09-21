import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../core/database/app_database.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/confirm.dart';
import '../core/utils/error_utils.dart';
import '../core/utils/formatters.dart';
import '../core/utils/snack.dart';
import '../widgets/app_image.dart';
import '../widgets/app_video_player.dart';
import 'diary_editor_screen.dart';

class DiaryDetailScreen extends StatefulWidget {
  final Diary diary;
  final VoidCallback? onRestored;

  const DiaryDetailScreen({super.key, required this.diary, this.onRestored});

  @override
  State<DiaryDetailScreen> createState() => _DiaryDetailScreenState();
}

class _DiaryDetailScreenState extends State<DiaryDetailScreen> {
  late Diary _diary;
  Pet? _pet;
  List<Tag> _tags = [];
  List<DiaryImage> _images = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _diary = widget.diary;
    _load();
  }

  Future<void> _load() async {
    try {
      final diary = await AppDatabase.getDiary(_diary.id);
      final pet = await AppDatabase.getPet(_diary.petId);
      final tags = await AppDatabase.getDiaryTags(_diary.id);
      final images = await AppDatabase.getDiaryImages(_diary.id);
      if (mounted) {
        setState(() {
          if (diary != null) _diary = diary;
          _pet = pet;
          _tags = tags;
          _images = images;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('diary detail load 失败: $e');
      // 不让页面卡在 loading 转圈
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteDiary() async {
    final confirmed = await showDestructiveConfirm(
      context,
      title: '删除爪札',
      message: '确定要删除「${_diary.title}」吗？',
    );
    if (confirmed == true && mounted) {
      // 只软删除，不删物理文件：撤销恢复时记录与照片都能完整还原。
      // 物理清理延到「永久删除」路径（app_database.permanentlyDeleteDiary）。
      await AppDatabase.softDeleteDiary(_diary.id);
      if (mounted) {
        showAppSnackBar(
          context,
          '爪札已删除',
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: '撤销',
            textColor: AppColors.plum,
            onPressed: () async {
              try {
                await AppDatabase.restoreDiary(_diary.id);
                widget.onRestored?.call();
              } catch (e) {
                if (mounted) showError(context, e);
              }
            },
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.ink;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.slate;

    return Scaffold(
      appBar: AppBar(
        title: const Text('爪札详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: '编辑',
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DiaryEditorScreen(
                    petId: _diary.petId,
                    petName: _pet?.name,
                    diary: _diary,
                  ),
                ),
              );
              _load();
            },
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              color: AppColors.error,
              size: 20,
            ),
            tooltip: '删除',
            onPressed: _deleteDiary,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_pet != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.primaryLight,
                            backgroundImage:
                                _pet!.avatarPath != null &&
                                    _pet!.avatarPath!.isNotEmpty
                                ? FileImage(File(_pet!.avatarPath!))
                                : null,
                            child:
                                _pet!.avatarPath == null ||
                                    _pet!.avatarPath!.isEmpty
                                ? Text(
                                    _pet!.name.characters.first,
                                    style: const TextStyle(
                                      color: AppColors.plum,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _pet!.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.end,
                                  children: [
                                    Text(
                                      dateFormatYMD.format(_diary.diaryDate),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: mutedColor,
                                      ),
                                    ),
                                    if (_diary.mood != null &&
                                        _diary.mood!.isNotEmpty)
                                      _emojiBadge(
                                        AppColors.moodEmojis[_diary.mood!] ??
                                            '',
                                      ),
                                    if (_diary.weather != null &&
                                        _diary.weather!.isNotEmpty)
                                      _emojiBadge(
                                        AppColors.weatherIcons[_diary
                                                .weather!] ??
                                            '',
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_diary.title.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _diary.title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                          height: 1.3,
                        ),
                      ),
                    ),
                  if (_diary.content.isNotEmpty)
                    SelectableText(
                      _diary.content,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.7,
                        color: textColor,
                      ),
                    ),
                  if (_images.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _MomentsPhotoGrid(images: _images),
                  ],
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Divider(height: 1),
                  ),
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _bottomChip(
                        Icons.access_time,
                        dateFormatMDHM.format(_diary.createdAt),
                        mutedColor,
                      ),
                    ],
                  ),
                  if (_tags.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: _tags.map((t) {
                        final color = Color(t.color ?? 0xFF8B5E7A);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            t.name,
                            style: TextStyle(
                              fontSize: 12,
                              color: color,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _emojiBadge(String emoji) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(emoji, style: const TextStyle(fontSize: 14)),
    );
  }

  Widget _bottomChip(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

class _MomentsPhotoGrid extends StatelessWidget {
  final List<DiaryImage> images;

  const _MomentsPhotoGrid({required this.images});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width - 32;
    const spacing = 6.0;
    final columns = images.length == 1 ? 1 : 3;
    final tileWidth = columns == 1
        ? screenWidth
        : (screenWidth - spacing * (columns - 1)) / columns;
    final tileHeight = images.length == 1 ? tileWidth * 0.75 : tileWidth;

    return Wrap(
      spacing: spacing,
      runSpacing: spacing,
      children: images.asMap().entries.map((e) {
        return _mediaTile(context, e.key, e.value, tileWidth, tileHeight);
      }).toList(),
    );
  }

  Widget _mediaTile(
    BuildContext context,
    int index,
    DiaryImage img,
    double w,
    double h,
  ) {
    if (isVideoFile(img.localPath)) {
      return SizedBox(
        width: w,
        height: h,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: VideoThumbnail(
            path: img.localPath,
            width: w,
            height: h,
            onTap: () => _openGallery(context, index),
          ),
        ),
      );
    }
    return SizedBox(
      width: w,
      height: h,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: GestureDetector(
          onTap: () => _openGallery(context, index),
          child: AppImage(
            path: img.localPath,
            width: w,
            height: h,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  void _openGallery(BuildContext context, int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _MediaGalleryScreen(images: images, initialIndex: index),
      ),
    );
  }
}

/// 全屏媒体查看器：支持左右滑动浏览照片/视频。
class _MediaGalleryScreen extends StatefulWidget {
  final List<DiaryImage> images;
  final int initialIndex;

  const _MediaGalleryScreen({required this.images, required this.initialIndex});

  @override
  State<_MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<_MediaGalleryScreen> {
  late final PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text('${_currentIndex + 1}/${widget.images.length}'),
      ),
      body: PageView.builder(
        controller: _controller,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemCount: widget.images.length,
        itemBuilder: (_, i) {
          final img = widget.images[i];
          if (isVideoFile(img.localPath)) {
            return _GalleryVideoPage(path: img.localPath);
          }
          return InteractiveViewer(
            maxScale: 5.0,
            child: Center(
              child: Image.file(
                File(img.localPath),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.broken_image, size: 64, color: Colors.white54),
                    SizedBox(height: 16),
                    Text('图片加载失败', style: TextStyle(color: Colors.white54)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 全屏媒体查看器里的单页视频播放。
class _GalleryVideoPage extends StatefulWidget {
  final String path;

  const _GalleryVideoPage({required this.path});

  @override
  State<_GalleryVideoPage> createState() => _GalleryVideoPageState();
}

class _GalleryVideoPageState extends State<_GalleryVideoPage> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _showControls = true;
  bool _isFullscreen = false;
  bool _isLandscape = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ctrl = VideoPlayerController.file(File(widget.path));
    try {
      await ctrl.initialize();
      await ctrl.setLooping(true);
      // 默认自动播放
      await ctrl.play();
    } catch (e) {
      debugPrint('GalleryVideoPage init error: $e');
      ctrl.dispose();
      return;
    }
    if (!mounted) {
      ctrl.dispose();
      return;
    }
    setState(() {
      _controller = ctrl;
      _ready = true;
    });
    // 确保 VideoPlayer widget 挂载后仍保持自动播放
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller == ctrl && !ctrl.value.isPlaying) {
        ctrl.play();
      }
    });
    _restartAutoHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _restoreSystemUi();
    _controller?.dispose();
    super.dispose();
  }

  void _restartAutoHide() {
    _hideTimer?.cancel();
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isPlaying) return;
    _hideTimer = Timer(const Duration(milliseconds: 3000), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _togglePlayPause() {
    final ctrl = _controller;
    if (ctrl == null || !_ready) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
    } else {
      ctrl.play();
    }
    setState(() => _showControls = true);
    _restartAutoHide();
  }

  /// 点击视频非按钮区域：显示/隐藏控制层，不暂停视频。
  void _handleVideoTap() {
    if (_showControls) {
      _hideTimer?.cancel();
      setState(() => _showControls = false);
    } else {
      setState(() => _showControls = true);
      _restartAutoHide();
    }
  }

  void _enterLandscapeFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    setState(() {
      _isFullscreen = true;
      _isLandscape = true;
    });
  }

  void _enterPortraitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    setState(() {
      _isFullscreen = true;
      _isLandscape = false;
    });
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    setState(() {
      _isFullscreen = false;
      _isLandscape = false;
    });
  }

  void _toggleLandscapeFullscreen() {
    if (_isFullscreen && _isLandscape) {
      _exitFullscreen();
    } else {
      _enterLandscapeFullscreen();
    }
  }

  void _togglePortraitFullscreen() {
    if (_isFullscreen && !_isLandscape) {
      _exitFullscreen();
    } else {
      _enterPortraitFullscreen();
    }
  }

  void _restoreSystemUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _isFullscreen = false;
    _isLandscape = false;
  }

  String _formatDuration(Duration d) {
    final total = d.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$mm:$ss';
    }
    return '$mm:$ss';
  }

  double _videoDisplayHeight(double width, double height) {
    final aspect = _controller!.value.aspectRatio;
    if (aspect <= 0) return height;
    if (width / height > aspect) {
      return height;
    }
    return width / aspect;
  }

  Widget _buildBottomControls() {
    final value = _controller!.value;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _togglePlayPause,
            icon: Icon(
              value.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 22,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          ),
          Expanded(
            child: _GallerySeekBar(
              controller: _controller!,
              onInteract: _restartAutoHide,
            ),
          ),
          Text(
            _formatDuration(value.position),
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
          Text(
            ' / ',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 10,
            ),
          ),
          Text(
            _formatDuration(value.duration),
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
          IconButton(
            onPressed: _toggleLandscapeFullscreen,
            icon: Icon(
              Icons.crop_landscape,
              color: (_isFullscreen && _isLandscape)
                  ? Colors.orangeAccent
                  : Colors.white,
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            tooltip: '横屏全屏',
          ),
          IconButton(
            onPressed: _togglePortraitFullscreen,
            icon: Icon(
              Icons.crop_portrait,
              color: (_isFullscreen && !_isLandscape)
                  ? Colors.orangeAccent
                  : Colors.white,
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 34, height: 34),
            tooltip: '竖屏全屏',
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready || _controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackH = constraints.maxHeight;
        final stackW = constraints.maxWidth;
        final videoH = _videoDisplayHeight(stackW, stackH);
        // 以视频实际底部为基准放置控制条，让进度条底部与视频底部齐平。
        final controlsBottom = (stackH - videoH) / 2 + 20;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleVideoTap,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.translate(
                offset: const Offset(0, -20),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  ),
                ),
              ),
              // 常驻细进度条：视频底部始终可见，方便隐藏控制条时知道播放位置
              Positioned(
                left: 0,
                right: 0,
                bottom: controlsBottom,
                child: _GalleryThinProgressBar(controller: _controller!),
              ),
              // 底部控制条：播放按钮 + 进度条 + 时间 + 横屏/竖屏全屏，B站风格
              Positioned(
                left: 0,
                right: 0,
                bottom: controlsBottom,
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: AnimatedSlide(
                    offset: _showControls ? Offset.zero : const Offset(0, 0.35),
                    duration: const Duration(milliseconds: 200),
                    child: AnimatedOpacity(
                      opacity: _showControls ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: _buildBottomControls(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 自定义大号视频进度条：更粗、触摸区域更大、带拖动动画。
class _GallerySeekBar extends StatefulWidget {
  final VideoPlayerController controller;
  final VoidCallback? onInteract;

  const _GallerySeekBar({required this.controller, this.onInteract});

  @override
  State<_GallerySeekBar> createState() => _GallerySeekBarState();
}

class _GallerySeekBarState extends State<_GallerySeekBar> {
  bool _dragging = false;
  double? _dragFraction;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  double _fraction(double maxWidth, double dx) {
    if (maxWidth <= 0) return 0;
    return (dx / maxWidth).clamp(0.0, 1.0);
  }

  void _seekAt(double maxWidth, double dx) {
    final value = widget.controller.value;
    final durationMs = value.duration.inMilliseconds;
    if (durationMs <= 0) return;
    final fraction = _fraction(maxWidth, dx);
    widget.onInteract?.call();
    widget.controller.seekTo(
      Duration(milliseconds: (durationMs * fraction).round()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final value = widget.controller.value;
        final durationMs = value.duration.inMilliseconds;
        final positionMs = _dragging && _dragFraction != null
            ? _dragFraction! * durationMs
            : value.position.inMilliseconds.toDouble();
        final fraction = durationMs <= 0
            ? 0.0
            : (positionMs / durationMs).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _seekAt(width, d.localPosition.dx),
          onHorizontalDragStart: (d) {
            setState(() {
              _dragging = true;
              _dragFraction = _fraction(width, d.localPosition.dx);
            });
            _seekAt(width, d.localPosition.dx);
          },
          onHorizontalDragUpdate: (d) {
            setState(
              () => _dragFraction = _fraction(width, d.localPosition.dx),
            );
            _seekAt(width, d.localPosition.dx);
          },
          onHorizontalDragEnd: (_) {
            setState(() {
              _dragging = false;
              _dragFraction = null;
            });
          },
          onHorizontalDragCancel: () {
            setState(() {
              _dragging = false;
              _dragFraction = null;
            });
          },
          child: SizedBox(
            height: 36,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: (36 - 6) / 2,
                  width: width,
                  height: 6,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: (36 - 6) / 2,
                  width: width * fraction,
                  height: 6,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
                Positioned(
                  left: (width * fraction - 7).clamp(0.0, width - 14),
                  top: (36 - 14) / 2,
                  child: AnimatedScale(
                    scale: _dragging ? 1.35 : 1.0,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 常驻细进度条：视频底部始终显示，不用操作，只显示播放位置。
class _GalleryThinProgressBar extends StatefulWidget {
  final VideoPlayerController controller;

  const _GalleryThinProgressBar({required this.controller});

  @override
  State<_GalleryThinProgressBar> createState() =>
      _GalleryThinProgressBarState();
}

class _GalleryThinProgressBarState extends State<_GalleryThinProgressBar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller.value;
    final durationMs = value.duration.inMilliseconds;
    final fraction = durationMs <= 0
        ? 0.0
        : (value.position.inMilliseconds / durationMs).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: fraction,
          minHeight: 2,
          backgroundColor: Colors.white24,
          color: Colors.white,
        ),
      ),
    );
  }
}
