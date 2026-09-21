import 'dart:io';

import 'package:flutter/material.dart';
import '../core/database/app_database.dart';
import '../core/utils/uuid.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/error_utils.dart';
import '../core/utils/formatters.dart';
import '../core/utils/snack.dart';
import '../services/image_service.dart';
import '../services/permission_service.dart';
import '../widgets/apple_pickers.dart';
import '../widgets/inline_dropdown.dart';
import '../widgets/photo_grid.dart';
import 'tag_manager_screen.dart';

/// Available moods (empty string = none). Synced with [AppColors.moodEmojis]
/// and [AppColors.moodLabels].
const _moods = ['', 'happy', 'calm', 'sad', 'sick', 'excited'];

/// Available weather keys (empty string = none). Synced with
/// [AppColors.weatherIcons] and [AppColors.weatherLabels].
const _weathers = ['', 'sunny', 'cloudy', 'rainy', 'snowy', 'windy'];

class DiaryEditorScreen extends StatefulWidget {
  final String? petId;
  final String? petName;
  final Diary? diary;

  const DiaryEditorScreen({super.key, this.petId, this.petName, this.diary});

  @override
  State<DiaryEditorScreen> createState() => _DiaryEditorScreenState();
}

class _DiaryEditorScreenState extends State<DiaryEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  final _titleFocus = FocusNode();
  final _contentFocus = FocusNode();

  String? _selectedPetId;
  String _mood = '';
  String _weather = '';
  DateTime _diaryDate = DateTime.now();
  List<String> _photoPaths = [];

  /// 本次编辑期间被移除的照片/视频路径。保存成功后才物理删除，
  /// 取消编辑时保留文件以维持 DB 引用一致。
  final Set<String> _removedPhotoPaths = {};

  /// 本次新增的 pick 文件。未保存退出时清理，避免孤儿残留。
  final Set<String> _newlyPickedPaths = {};
  bool _saved = false;
  List<Tag> _availableTags = [];
  List<Tag> _selectedTags = [];
  List<Pet> _allPets = [];
  bool _saving = false;

  /// 编辑时关联数据（标签/照片）加载失败标记：阻止破坏性保存。
  bool _loadFailed = false;

  /// 首次/刷新加载是否已完成。未完成前禁止保存，避免用空列表覆盖旧数据。
  bool _dataReady = false;

  bool get _isEditing => widget.diary != null;

  @override
  void initState() {
    super.initState();
    final d = widget.diary;
    _titleCtrl = TextEditingController(text: d?.title ?? '');
    _contentCtrl = TextEditingController(text: d?.content ?? '');
    _selectedPetId = d?.petId ?? widget.petId;
    if (d != null) {
      _mood = d.mood ?? '';
      _weather = d.weather ?? '';
      _diaryDate = d.diaryDate;
    }
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      // Fetch pets and tags independently — simpler and more robust
      // than Future.wait with conditional elements.
      final pets = await AppDatabase.getAllPets();
      final tags = await AppDatabase.getAllTags();
      List<Tag> selectedTags = [];
      List<String> photoPaths = [];

      if (_isEditing) {
        selectedTags = await AppDatabase.getDiaryTags(widget.diary!.id);
        final images = await AppDatabase.getDiaryImages(widget.diary!.id);
        photoPaths = images.map<String>((i) => i.localPath).toList();
      }

      if (!mounted) return;
      setState(() {
        _allPets = pets;
        _availableTags = tags;
        _selectedTags = selectedTags;
        _photoPaths = photoPaths;
        _loadFailed = false;
        _dataReady = true;
      });
    } catch (e) {
      debugPrint('DiaryEditorScreen._loadData error: $e');
      // 加载失败：标记防破坏性保存（否则保存会用空列表清空标签/照片并删文件）
      _loadFailed = true;
      _dataReady = false;
      if (mounted) {
        showAppSnackBar(context, '关联数据加载失败，保存可能覆盖已有内容', isError: true);
      }
    }
  }

  /// 从标签管理页返回时不重载媒体，避免覆盖用户本次尚未保存的照片/视频；
  /// 同时把已选标签同步为最新名称，并移除已被管理的失效标签。
  Future<void> _refreshTagsAfterManager() async {
    try {
      final tags = await AppDatabase.getAllTags();
      final selectedIds = _selectedTags.map((t) => t.id).toSet();
      if (!mounted) return;
      setState(() {
        _availableTags = tags;
        _selectedTags = tags.where((t) => selectedIds.contains(t.id)).toList();
      });
    } catch (e) {
      debugPrint('DiaryEditorScreen._refreshTagsAfterManager error: $e');
      if (mounted) {
        showAppSnackBar(context, '标签刷新失败，请重试', isError: true);
      }
    }
  }

  @override
  void dispose() {
    // 未保存退出：清理本次 pick 复制但未入库的文件，避免孤儿残留。
    if (!_saved) {
      for (final p in _newlyPickedPaths) {
        _deleteFileSafe(p);
      }
    }
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _titleFocus.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑爪札' : '写爪札'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Pet selector (only when adding new from home)
                if (widget.petId == null) ...[
                  InlineDropdown<String>(
                    label: '选择宠物 *',
                    value: _selectedPetId,
                    placeholder: '请选择宠物',
                    options: _allPets
                        .map(
                          (p) => InlineOption<String>(
                            value: p.id,
                            label: p.name,
                            subtitle:
                                AppColors.speciesLabels[p.species] ?? p.species,
                            icon: Icons.pets,
                            color: AppColors.plum,
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null && mounted) {
                        setState(() => _selectedPetId = v);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Title
                TextFormField(
                  controller: _titleCtrl,
                  focusNode: _titleFocus,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: '标题'),
                ),
                const SizedBox(height: 16),

                // Date & Mood & Weather
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: SizedBox(height: 52, child: _buildDatePicker()),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: SizedBox(height: 52, child: _buildMoodSelector()),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 52,
                        child: _buildWeatherSelector(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Content
                TextFormField(
                  controller: _contentCtrl,
                  focusNode: _contentFocus,
                  decoration: const InputDecoration(hintText: '内容'),
                  maxLines: 8,
                ),
                const SizedBox(height: 16),

                // Photos
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '照片 / 视频',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_photoPaths.length}/9',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '点击 + 添加照片或视频',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                PhotoGrid(
                  imagePaths: _photoPaths,
                  onAdd: _addPhoto,
                  onRemove: (i) {
                    final path = _photoPaths[i];
                    // 不立即物理删除：编辑可能被取消，DB 仍会引用该文件。
                    // 保存成功后统一清理（见 _save）。
                    _removedPhotoPaths.add(path);
                    setState(() => _photoPaths.removeAt(i));
                  },
                ),
                const SizedBox(height: 16),

                // Tags
                Row(
                  children: [
                    Text(
                      '标签',
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TagManagerScreen(),
                          ),
                        );
                        await _refreshTagsAfterManager();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.settings,
                            size: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '管理',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ..._availableTags.map((t) {
                      final selected = _selectedTags.any((s) => s.id == t.id);
                      return FilterChip(
                        label: Text(t.name),
                        selected: selected,
                        onSelected: (v) {
                          setState(() {
                            if (v) {
                              _selectedTags.add(t);
                            } else {
                              _selectedTags.removeWhere((s) => s.id == t.id);
                            }
                          });
                        },
                        selectedColor: Color(
                          t.color ?? 0xFF8B5E7A,
                        ).withValues(alpha: 0.1),
                        checkmarkColor: Color(t.color ?? 0xFF8B5E7A),
                        labelStyle: TextStyle(
                          color: selected
                              ? Color(t.color ?? 0xFF8B5E7A)
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      );
                    }),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: const Text('创建标签'),
                      onPressed: _addTag,
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // ── Bottom save button (in addition to AppBar) ──────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('保存爪札', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Date picker ----

  Widget _buildDatePicker() {
    return InkWell(
      onTap: () async {
        FocusManager.instance.primaryFocus?.unfocus();
        final picked = await showAppleDatePicker(
          context,
          initialDate: _diaryDate,
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null && mounted) setState(() => _diaryDate = picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        child: Align(
          alignment: Alignment.center,
          child: Text(
            dateFormatCompact.format(_diaryDate),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ),
    );
  }

  // ---- Mood selector ----

  Widget _buildMoodSelector() {
    final moodIndex = _moods.indexOf(_mood);
    final safeIndex = moodIndex >= 0 ? moodIndex : 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 140.0;
        return PopupMenuButton<String>(
          position: PopupMenuPosition.under,
          constraints: BoxConstraints(minWidth: width, maxWidth: width),
          offset: const Offset(0, 4),
          onSelected: (v) => setState(() => _mood = v),
          itemBuilder: (_) => _moods.map((m) {
            final emoji = AppColors.moodEmojis[m] ?? '';
            final label = AppColors.moodLabels[m] ?? m;
            return PopupMenuItem(
              value: m,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '$emoji $label',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          child: InputDecorator(
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            child: Align(
              alignment: Alignment.center,
              child: Row(
                children: [
                  const Text('心情', style: TextStyle(fontSize: 14)),
                  const Spacer(),
                  Text(
                    AppColors.moodEmojis[_moods[safeIndex]] ?? '😶',
                    style: const TextStyle(fontSize: 18),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---- Weather selector ----

  Widget _buildWeatherSelector() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : 140.0;
        return PopupMenuButton<String>(
          position: PopupMenuPosition.under,
          constraints: BoxConstraints(minWidth: width, maxWidth: width),
          offset: const Offset(0, 4),
          onSelected: (v) => setState(() => _weather = v),
          itemBuilder: (_) => _weathers.map((w) {
            final icon = AppColors.weatherIcons[w] ?? '';
            final label = AppColors.weatherLabels[w] ?? w;
            return PopupMenuItem(
              value: w,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                '$icon $label',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          child: InputDecorator(
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            child: Align(
              alignment: Alignment.center,
              child: Row(
                children: [
                  const Text('天气', style: TextStyle(fontSize: 14)),
                  const Spacer(),
                  Text(
                    AppColors.weatherIcons[_weather] ?? '',
                    style: const TextStyle(fontSize: 18),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---- Weight validation ----

  // ---- Photo management ----

  Future<void> _addPhoto() async {
    final remaining = 9 - _photoPaths.length;
    final source = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Text('添加媒体', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: AppColors.primary,
              ),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: AppColors.primary,
              ),
              title: const Text('从相册选择照片'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            ListTile(
              leading: const Icon(
                Icons.videocam_outlined,
                color: AppColors.secondary,
              ),
              title: const Text('录制视频'),
              onTap: () => Navigator.pop(ctx, 'video_camera'),
            ),
            ListTile(
              leading: const Icon(
                Icons.video_library_outlined,
                color: AppColors.secondary,
              ),
              title: const Text('从相册选择视频'),
              onTap: () => Navigator.pop(ctx, 'video_gallery'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    List<String>? paths;
    String? errorHint;
    switch (source) {
      case 'camera':
        final granted = await PermissionService.checkCamera(context);
        if (!granted) {
          if (mounted) errorHint = '需要相机权限才能拍照';
          break;
        }
        final path = await pickImageFromCamera();
        if (path == null) errorHint = '拍照取消或失败';
        paths = path != null ? [path] : null;
        break;
      case 'gallery':
        // 已满时也允许进入相册；选择后由下方逻辑提示上限并丢弃。
        paths = await pickImagesFromGallery(
          maxCount: remaining > 0 ? remaining : 1,
        );
        if (paths.isEmpty) errorHint = '未选择照片';
        break;
      case 'video_camera':
        final granted = await PermissionService.checkCamera(context);
        if (!granted) {
          if (mounted) errorHint = '需要相机权限才能录制视频';
          break;
        }
        final path = await pickVideoFromCamera();
        if (path == null) errorHint = '录制取消或失败';
        paths = path != null ? [path] : null;
        break;
      case 'video_gallery':
        final path = await pickVideoFromGallery();
        if (path == null) errorHint = '未选择视频';
        paths = path != null ? [path] : null;
        break;
    }
    if (paths case final validPaths? when mounted) {
      // 强制不超过剩余名额；若系统返回超过上限，只保留前 N 个并提示。
      final accepted = validPaths.take(remaining).toList();
      if (accepted.isNotEmpty) {
        _newlyPickedPaths.addAll(accepted);
        setState(() => _photoPaths.addAll(accepted));
      }
      if (accepted.length < validPaths.length) {
        showAppSnackBar(context, '已达上限，不能再选照片/视频', isError: true);
      }
    } else if (errorHint != null && mounted) {
      showAppSnackBar(context, errorHint, isError: true);
    }
  }

  // ---- Tag creation ----

  Future<void> _addTag() async {
    final ctrl = TextEditingController();
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('新建标签'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: '标签名'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('创建'),
            ),
          ],
        ),
      );
      if (name != null && name.isNotEmpty) {
        final existing = await AppDatabase.getTagByName(name);
        if (existing == null) {
          final tag = Tag(
            id: generateUuidV7(),
            name: name,
            color: AppColors
                .tagColors[_availableTags.length % AppColors.tagColors.length],
            createdAt: DateTime.now(),
          );
          await AppDatabase.insertTag(tag);
          // Defer setState to next frame so the dialog's element tree
          // is fully torn down before we touch the widget tree again.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _availableTags.add(tag);
                _selectedTags.add(tag);
              });
            }
          });
        }
      }
    } finally {
      ctrl.dispose();
    }
  }

  // ---- Save ----

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    final hasMedia = _photoPaths.isNotEmpty;
    if (_selectedPetId == null) {
      if (mounted) {
        showAppSnackBar(context, '请先选择宠物', isError: true);
      }
      return;
    }
    // 有照片/视频时允许纯媒体爪札（标题/内容可空）；
    // 没有媒体时仍要求标题和内容都填写。
    if (!hasMedia) {
      if (title.isEmpty) {
        _titleFocus.requestFocus();
        if (mounted) {
          showAppSnackBar(context, '请填写爪札标题', isError: true);
        }
        return;
      }
      if (content.isEmpty) {
        _contentFocus.requestFocus();
        if (mounted) {
          showAppSnackBar(context, '请填写爪札内容', isError: true);
        }
        return;
      }
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    // 防止保存竞态：关联数据尚未加载完成时先用空列表覆盖。
    if (!_dataReady) {
      if (mounted) {
        showAppSnackBar(context, '正在加载数据，请稍候再保存');
      }
      return;
    }
    // 编辑时关联数据加载失败：阻止保存（空标签/照片会覆盖并删除原关联）
    if (_isEditing && _loadFailed) {
      if (mounted) {
        showAppSnackBar(context, '关联数据加载失败，请返回重试，避免覆盖已有内容', isError: true);
      }
      return;
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final tagIds = _selectedTags.map((t) => t.id).toList();
      final petId = _selectedPetId!;

      if (_isEditing) {
        final diaryId = widget.diary!.id;

        // 先记录旧图；DB 事务成功后再统一清理（DB 失败不丢文件）。
        final oldImages = await AppDatabase.getDiaryImages(diaryId);

        final updated = widget.diary!.copyWith(
          title: _titleCtrl.text.trim(),
          content: _contentCtrl.text.trim(),
          mood: _mood.isEmpty ? null : _mood,
          clearMood: _mood.isEmpty,
          weather: _weather.isEmpty ? null : _weather,
          clearWeather: _weather.isEmpty,
          diaryDate: _diaryDate,
        );
        await AppDatabase.updateDiaryWithRelations(
          diary: updated,
          imagePaths: _photoPaths,
          tagIds: tagIds,
        );
        _cleanupRemovedMedia(oldImages);
      } else {
        final diaryId = generateUuidV7();
        await AppDatabase.insertDiaryWithRelations(
          diary: Diary(
            id: diaryId,
            petId: petId,
            title: _titleCtrl.text.trim(),
            content: _contentCtrl.text.trim(),
            mood: _mood.isEmpty ? null : _mood,
            weather: _weather.isEmpty ? null : _weather,
            diaryDate: _diaryDate,
            createdAt: now,
            updatedAt: now,
          ),
          imagePaths: _photoPaths,
          tagIds: tagIds,
        );
        // 新建成功：清理「pick 后又移除」的媒体（从未入库）。
        _cleanupRemovedMedia(null);
      }

      _saved = true;
      if (mounted) {
        showAppSnackBar(context, _isEditing ? '爪札已更新' : '爪札已保存');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Safely delete a file — best-effort, never throws.
  void _deleteFileSafe(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  /// 在 DB 事务成功之后清理被移除的媒体文件：
  /// - [_removedPhotoPaths]：本次编辑期间移除的（含新建时添加又移除的）
  /// - [oldImages]：编辑场景下旧图不在新列表的（非空时对比）
  void _cleanupRemovedMedia(List<DiaryImage>? oldImages) {
    for (final p in _removedPhotoPaths) {
      _deleteFileSafe(p);
    }
    if (oldImages != null) {
      for (final old in oldImages) {
        if (!_photoPaths.contains(old.localPath)) {
          _deleteFileSafe(old.localPath);
        }
      }
    }
    _removedPhotoPaths.clear();
  }
}
