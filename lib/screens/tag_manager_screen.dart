import 'package:flutter/material.dart';

import '../core/database/app_database.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/error_utils.dart';
import '../core/utils/snack.dart';
import '../core/utils/uuid.dart';

class TagManagerScreen extends StatefulWidget {
  const TagManagerScreen({super.key});

  @override
  State<TagManagerScreen> createState() => _TagManagerScreenState();
}

class _TagManagerScreenState extends State<TagManagerScreen> {
  List<Tag> _tags = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tags = await AppDatabase.getAllTags();
      if (mounted) setState(() { _tags = tags; _loading = false; });
    } catch (e) {
      debugPrint('加载标签失败: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addTag() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建标签'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '标签名'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null && name.isNotEmpty && mounted) {
      try {
        final existing = await AppDatabase.getTagByName(name);
        if (existing == null) {
          await AppDatabase.insertTag(Tag(
            id: generateUuidV7(),
            name: name,
            color: AppColors.tagColors[_tags.length % AppColors.tagColors.length],
            createdAt: DateTime.now(),
          ));
          _load();
        } else if (mounted) {
          showAppSnackBar(context, '该标签已存在', isError: true);
        }
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
  }

  Future<void> _renameTag(Tag tag) async {
    final ctrl = TextEditingController(text: tag.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名标签'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '标签名'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (name != null && name.isNotEmpty && name != tag.name && mounted) {
      try {
        final existing = await AppDatabase.getTagByName(name);
        if (existing == null) {
          await AppDatabase.updateTag(tag.copyWith(name: name));
          _load();
        } else if (mounted) {
          showAppSnackBar(context, '该标签已存在', isError: true);
        }
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
  }

  Future<void> _deleteTag(Tag tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除标签'),
        content: Text('确定要删除「${tag.name}」吗？\n已关联该标签的爪札不会受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await AppDatabase.deleteTag(tag.id);
        _load();
      } catch (e) {
        if (mounted) showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('标签管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建标签',
            onPressed: _addTag,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tags.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.label_outline, size: 48, color: AppColors.cloud),
                      const SizedBox(height: 12),
                      Text('还没有标签',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _addTag,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('创建第一个标签'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _tags.length,
                  itemBuilder: (_, i) => _TagTile(
                    tag: _tags[i],
                    onRename: () => _renameTag(_tags[i]),
                    onDelete: () => _deleteTag(_tags[i]),
                  ),
                ),
    );
  }
}

class _TagTile extends StatelessWidget {
  final Tag tag;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _TagTile({
    required this.tag,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = Color(tag.color ?? 0xFF8B5E7A);
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.label, color: color, size: 18),
      ),
      title: Text(tag.name, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: '重命名',
            onPressed: onRename,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            tooltip: '删除',
            color: AppColors.error,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
