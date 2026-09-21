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

const _catBreeds = [
  '英短',
  '美短',
  '布偶',
  '暹罗',
  '橘猫',
  '狸花猫',
  '蓝猫',
  '加菲',
  '缅因',
  '无毛猫',
  '中华田园猫',
];

const _dogBreeds = [
  '金毛',
  '拉布拉多',
  '柯基',
  '柴犬',
  '泰迪/贵宾',
  '边牧',
  '哈士奇',
  '萨摩耶',
  '比熊',
  '博美',
  '中华田园犬',
];

const _customSpeciesValue = '__custom__';

class PetEditorScreen extends StatefulWidget {
  final Pet? pet;

  const PetEditorScreen({super.key, this.pet});

  @override
  State<PetEditorScreen> createState() => _PetEditorScreenState();
}

class _PetEditorScreenState extends State<PetEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _breedCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _weightCtrl;
  final _nameFocus = FocusNode();
  final _weightFocus = FocusNode();

  String _species = 'dog';
  String _gender = 'unknown';
  String _meetType = 'adopt';
  DateTime? _birthDate;
  DateTime _meetDate = DateTime.now();
  String? _avatarPath;
  String? _originalAvatarPath;
  final Set<String> _newAvatarPaths = {};
  bool _saved = false;
  bool _saving = false;

  bool get _isEditing => widget.pet != null;

  @override
  void initState() {
    super.initState();
    final p = widget.pet;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _breedCtrl = TextEditingController(text: p?.breed ?? '');
    _notesCtrl = TextEditingController(text: p?.notes ?? '');
    _weightCtrl = TextEditingController(
      text: p?.currentWeightKg?.toString() ?? '',
    );
    if (p != null) {
      _species = p.species;
      _gender = p.gender;
      _meetType = p.meetType;
      _birthDate = p.birthDate;
      _meetDate = p.meetDate;
      _avatarPath = p.avatarPath;
      _originalAvatarPath = p.avatarPath;
    }
  }

  @override
  void dispose() {
    // 未保存退出时清理本次新选择但未入库的头像文件。
    if (!_saved) {
      for (final path in _newAvatarPaths) {
        _deleteFileSafe(path);
      }
    }
    _nameCtrl.dispose();
    _breedCtrl.dispose();
    _notesCtrl.dispose();
    _weightCtrl.dispose();
    _nameFocus.dispose();
    _weightFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑宠物' : '添加宠物'),
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
              children: [
                // Avatar
                GestureDetector(
                  onTap: _pickAvatar,
                  child: CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.primaryLight,
                    backgroundImage:
                        _avatarPath != null && _avatarPath!.isNotEmpty
                        ? FileImage(File(_avatarPath!))
                        : null,
                    child: _avatarPath == null || _avatarPath!.isEmpty
                        ? const Icon(
                            Icons.add_a_photo,
                            size: 32,
                            color: AppColors.primary,
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 20),

                // Name
                TextFormField(
                  controller: _nameCtrl,
                  focusNode: _nameFocus,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: '名字 *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入名字' : null,
                  onFieldSubmitted: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                ),
                const SizedBox(height: 16),

                // Species
                InlineDropdown<String>(
                  label: '种类',
                  value: _species,
                  options: [
                    ...AppColors.speciesLabels.entries.map(
                      (e) => InlineOption<String>(
                        value: e.key,
                        label:
                            '${AppColors.speciesIcons[e.key] ?? '🐾'} ${e.value}',
                        icon: Icons.pets,
                      ),
                    ),
                    if (_species.isNotEmpty &&
                        !AppColors.speciesLabels.containsKey(_species))
                      InlineOption<String>(
                        value: _species,
                        label: _species,
                        icon: Icons.pets,
                      ),
                    const InlineOption<String>(
                      value: _customSpeciesValue,
                      label: '自定义种类',
                      icon: Icons.edit,
                    ),
                  ],
                  onChanged: (v) async {
                    if (!mounted) return;
                    if (v == _customSpeciesValue) {
                      final custom = await _showCustomInput(title: '自定义种类');
                      if (custom != null && custom.isNotEmpty && mounted) {
                        _breedCtrl.clear();
                        setState(() => _species = custom.trim());
                      }
                    } else if (v != null) {
                      _breedCtrl.clear();
                      setState(() => _species = v);
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Breed
                InkWell(
                  onTap: _pickBreed,
                  borderRadius: BorderRadius.circular(14),
                  child: InputDecorator(
                    decoration: const InputDecoration(),
                    child: Row(
                      children: [
                        const Text(
                          '品种',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFF69727A),
                          ),
                        ),
                        const Spacer(),
                        Expanded(
                          child: Text(
                            _breedCtrl.text.isEmpty ? '请选择品种' : _breedCtrl.text,
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        const Icon(
                          Icons.expand_more,
                          size: 20,
                          color: Color(0xFF69727A),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Gender
                InlineDropdown<String>(
                  label: '性别',
                  value: _gender,
                  options: AppColors.genderLabels.entries
                      .map(
                        (e) => InlineOption<String>(
                          value: e.key,
                          label: e.value,
                          icon: e.key == 'male'
                              ? Icons.male
                              : e.key == 'female'
                              ? Icons.female
                              : Icons.transgender,
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null && mounted) setState(() => _gender = v);
                  },
                ),
                const SizedBox(height: 16),

                // Meet type
                InlineDropdown<String>(
                  label: '相遇方式',
                  value: _meetType,
                  options: AppColors.meetTypeLabels.entries
                      .map(
                        (e) =>
                            InlineOption<String>(value: e.key, label: e.value),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null && mounted) setState(() => _meetType = v);
                  },
                ),
                const SizedBox(height: 16),

                // Dates — first row labels, second row pickers
                const Row(
                  children: [
                    Expanded(
                      child: Text('出生日期', style: TextStyle(fontSize: 15)),
                    ),
                    Expanded(
                      child: Text('相遇日期 *', style: TextStyle(fontSize: 15)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _DateField(
                        date: _birthDate,
                        onPicked: (d) => setState(() => _birthDate = d),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DateField(
                        date: _meetDate,
                        onPicked: (d) => setState(() => _meetDate = d),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Notes
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(hintText: '备注'),
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  minLines: 3,
                  maxLines: 6,
                ),
                const SizedBox(height: 16),

                // Current weight — used by reminder/health suggestions
                TextFormField(
                  controller: _weightCtrl,
                  focusNode: _weightFocus,
                  decoration: const InputDecoration(
                    hintText: '当前体重（kg）',
                    suffixText: 'kg',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) =>
                      FocusManager.instance.primaryFocus?.unfocus(),
                  validator: (v) {
                    final text = v?.trim() ?? '';
                    if (text.isEmpty) return null;
                    final value = double.tryParse(text);
                    if (value == null || value <= 0 || value > 200) {
                      return '请输入有效体重（0.1-200 kg）';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickAvatar() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '选择头像来源',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
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
                title: const Text('从相册选择'),
                onTap: () => Navigator.pop(ctx, 'gallery'),
              ),
              if (_avatarPath != null)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: AppColors.error,
                  ),
                  title: const Text('移除头像'),
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;

    // "remove" is explicit — clear the avatar.
    if (source == 'remove') {
      if (mounted) setState(() => _avatarPath = null);
      return;
    }

    // Camera / gallery: only update state when a real file was picked,
    // otherwise keep the previous avatar so a cancelled picker never
    // silently erases an existing photo.
    String? path;
    if (!mounted) return;
    switch (source) {
      case 'camera':
        final granted = await PermissionService.checkCamera(context);
        if (granted) {
          path = await pickImageFromCamera();
        }
      case 'gallery':
        final paths = await pickImagesFromGallery(maxCount: 1);
        path = paths.isNotEmpty ? paths.first : null;
    }
    if (path != null && mounted) {
      _newAvatarPaths.add(path);
      setState(() => _avatarPath = path);
    }
  }

  Future<void> _pickBreed() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final breeds = _species == 'cat'
        ? _catBreeds
        : _species == 'dog'
        ? _dogBreeds
        : <String>[];
    final items = [...breeds, '自定义品种'];
    final picked = await showAppleWheelPicker(
      context,
      title: '选择品种',
      items: items,
      initial: _breedCtrl.text.isEmpty ? null : _breedCtrl.text,
    );
    if (picked == null || !mounted) return;
    if (picked == '自定义品种') {
      final custom = await _showCustomInput(
        title: '自定义品种',
        initial: _breedCtrl.text,
      );
      if (custom != null && custom.isNotEmpty && mounted) {
        setState(() => _breedCtrl.text = custom);
      }
    } else {
      setState(() => _breedCtrl.text = picked);
    }
  }

  /// 全宽底部输入面板，用于自定义种类/品种。
  Future<String?> _showCustomInput({
    required String title,
    String initial = '',
  }) async {
    final ctrl = TextEditingController(text: initial);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(hintText: '请输入'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                    child: const Text('确定'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _nameFocus.requestFocus();
      if (mounted) {
        showAppSnackBar(context, '请填写宠物名字', isError: true);
      }
      return;
    }
    final weightText = _weightCtrl.text.trim();
    if (weightText.isNotEmpty) {
      final parsed = double.tryParse(weightText);
      if (parsed == null || parsed <= 0 || parsed > 200) {
        _weightFocus.requestFocus();
        if (mounted) {
          showAppSnackBar(context, '请检查体重数值（0.1-200 kg）', isError: true);
        }
        return;
      }
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final weight = weightText.isEmpty ? null : double.tryParse(weightText);
      final weightUpdatedAt = weight != null ? now : null;
      if (_isEditing) {
        final updated = widget.pet!.copyWith(
          name: _nameCtrl.text.trim(),
          species: _species,
          breed: _breedCtrl.text.trim().isEmpty ? null : _breedCtrl.text.trim(),
          clearBreed: _breedCtrl.text.trim().isEmpty,
          gender: _gender,
          birthDate: _birthDate,
          clearBirthDate: _birthDate == null,
          meetDate: _meetDate,
          meetType: _meetType,
          avatarPath: _avatarPath,
          clearAvatarPath: _avatarPath == null,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          clearNotes: _notesCtrl.text.trim().isEmpty,
          currentWeightKg: weight,
          clearCurrentWeight: weight == null,
          weightUpdatedAt: weightUpdatedAt,
        );
        await AppDatabase.updatePet(updated);
      } else {
        final petId = generateUuidV7();
        final petName = _nameCtrl.text.trim();
        await AppDatabase.insertPet(
          Pet(
            id: petId,
            name: petName,
            species: _species,
            breed: _breedCtrl.text.trim().isEmpty
                ? null
                : _breedCtrl.text.trim(),
            gender: _gender,
            birthDate: _birthDate,
            meetDate: _meetDate,
            meetType: _meetType,
            avatarPath: _avatarPath,
            notes: _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
            currentWeightKg: weight,
            weightUpdatedAt: weightUpdatedAt,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      _saved = true;
      _cleanupAvatarFiles();
      if (mounted) {
        showAppSnackBar(context, _isEditing ? '宠物已更新' : '宠物已添加');
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('保存宠物失败: $e');
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 保存成功后清理不再被引用的头像文件：
  /// - 编辑时旧头像已被替换/移除，删除旧文件；
  /// - 本次多次选择后未被最终使用的头像文件，删除。
  void _cleanupAvatarFiles() {
    final finalPath = _avatarPath;
    if (_originalAvatarPath != null && _originalAvatarPath != finalPath) {
      _deleteFileSafe(_originalAvatarPath!);
    }
    for (final path in _newAvatarPaths) {
      if (path != finalPath) {
        _deleteFileSafe(path);
      }
    }
    _newAvatarPaths.clear();
  }

  void _deleteFileSafe(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}

class _DateField extends StatelessWidget {
  final DateTime? date;
  final void Function(DateTime) onPicked;

  const _DateField({required this.date, required this.onPicked});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        FocusManager.instance.primaryFocus?.unfocus();
        final picked = await showAppleDatePicker(
          context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime(1990),
          lastDate: DateTime.now(),
        );
        if (picked != null) onPicked(picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(),
        child: Text(date != null ? dateFormatYMD.format(date!) : '未选择'),
      ),
    );
  }
}
