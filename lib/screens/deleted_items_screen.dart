import 'package:flutter/material.dart';

import '../core/database/app_database.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/confirm.dart';
import '../core/utils/error_utils.dart';
import '../core/utils/formatters.dart';
import '../core/utils/snack.dart';
import '../services/reminder_service.dart';

/// “最近删除”：查看并恢复已删除的宠物、爪札、提醒。
class DeletedItemsScreen extends StatefulWidget {
  const DeletedItemsScreen({super.key});

  @override
  State<DeletedItemsScreen> createState() => _DeletedItemsScreenState();
}

class _DeletedItemsScreenState extends State<DeletedItemsScreen> {
  List<Pet> _pets = [];
  List<Diary> _diaries = [];
  List<Reminder> _reminders = [];
  List<ReminderInstance> _completedRecords = [];
  List<ReminderInstance> _deletedPendingInstances = [];
  List<Reminder> _activeReminders = [];
  List<Pet> _activePets = [];
  bool _loading = true;
  bool _selectMode = false;
  final Set<String> _selectedKeys = {};

  String _petKey(String id) => 'pet:$id';
  String _diaryKey(String id) => 'diary:$id';
  String _reminderKey(String id) => 'reminder:$id';
  String _instanceKey(String id) => 'instance:$id';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        AppDatabase.getDeletedPets(),
        AppDatabase.getDeletedDiaries(),
        AppDatabase.getDeletedReminders(),
        AppDatabase.getDeletedCompletedInstances(),
        AppDatabase.getDeletedPendingInstances(),
        AppDatabase.getAllReminders(),
        AppDatabase.getAllPets(),
      ]);
      if (mounted) {
        setState(() {
          _pets = results[0] as List<Pet>;
          _diaries = results[1] as List<Diary>;
          _reminders = results[2] as List<Reminder>;
          _completedRecords = results[3] as List<ReminderInstance>;
          _deletedPendingInstances = results[4] as List<ReminderInstance>;
          _activeReminders = results[5] as List<Reminder>;
          _activePets = results[6] as List<Pet>;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('加载已删除内容失败: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      _selectedKeys.clear();
    });
  }

  void _toggleSelectAll() {
    final all = <String>[
      ..._pets.map((p) => _petKey(p.id)),
      ..._diaries.map((d) => _diaryKey(d.id)),
      ..._reminderEntitiesWithPending.map((r) => _reminderKey(r.id)),
      ..._completedRecords.map((i) => _instanceKey(i.id)),
    ];
    setState(() {
      if (_selectedKeys.length == all.length && all.isNotEmpty) {
        _selectedKeys.clear();
      } else {
        _selectedKeys
          ..clear()
          ..addAll(all);
      }
    });
  }

  void _toggleKey(String key) {
    setState(() {
      if (_selectedKeys.contains(key)) {
        _selectedKeys.remove(key);
      } else {
        _selectedKeys.add(key);
      }
    });
  }

  Future<void> _restorePet(Pet pet) async {
    try {
      await AppDatabase.restorePet(pet.id);
      await rescheduleRemindersForPet(pet.id);
      if (mounted) {
        showAppSnackBar(context, '已恢复「${pet.name}」及关联的爪札/提醒');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _restoreDiary(Diary diary) async {
    try {
      await AppDatabase.restoreDiary(diary.id);
      if (mounted) {
        showAppSnackBar(context, '已恢复爪札「${diary.title}」');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _restoreReminder(Reminder reminder) async {
    try {
      await AppDatabase.restoreReminder(reminder.id);
      await rescheduleReminder(reminder);
      if (mounted) {
        showAppSnackBar(context, '已恢复提醒「${reminder.title}」');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _restoreCompletedRecord(ReminderInstance inst) async {
    try {
      await AppDatabase.restoreCompletedInstance(inst.id);
      if (mounted) {
        showAppSnackBar(context, '已恢复已完成记录');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _permanentDeletePet(Pet pet) async {
    final ok = await showDestructiveConfirm(
      context,
      title: '彻底删除宠物',
      message: '确定彻底删除「${pet.name}」吗？该操作不可恢复。',
      confirmLabel: '彻底删除',
    );
    if (!ok) return;
    try {
      await AppDatabase.permanentlyDeletePet(pet.id);
      if (mounted) {
        showAppSnackBar(context, '已彻底删除「${pet.name}」');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _permanentDeleteDiary(Diary diary) async {
    final ok = await showDestructiveConfirm(
      context,
      title: '彻底删除爪札',
      message: '确定彻底删除「${diary.title}」吗？该操作不可恢复。',
      confirmLabel: '彻底删除',
    );
    if (!ok) return;
    try {
      await AppDatabase.permanentlyDeleteDiary(diary.id);
      if (mounted) {
        showAppSnackBar(context, '已彻底删除爪札');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _permanentDeleteReminder(Reminder reminder) async {
    final ok = await showDestructiveConfirm(
      context,
      title: '彻底删除提醒',
      message: '确定彻底删除「${reminder.title}」吗？该操作不可恢复。',
      confirmLabel: '彻底删除',
    );
    if (!ok) return;
    try {
      await AppDatabase.permanentlyDeleteReminder(reminder.id);
      if (mounted) {
        showAppSnackBar(context, '已彻底删除提醒');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _permanentDeleteCompletedRecord(ReminderInstance inst) async {
    final title = _reminderTitleOf(inst);
    final ok = await showDestructiveConfirm(
      context,
      title: '彻底删除已完成记录',
      message: '确定彻底删除「$title」这条已完成记录吗？该操作不可恢复。',
      confirmLabel: '彻底删除',
    );
    if (!ok) return;
    try {
      await AppDatabase.permanentlyDeleteCompletedInstance(inst.id);
      if (mounted) {
        showAppSnackBar(context, '已彻底删除已完成记录');
        _load();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  /// 已完成记录对应提醒的展示标题（醒目标题 + 第 N 次）。
  String _reminderTitleOf(ReminderInstance inst) {
    final reminder = _reminderById(inst.reminderId);
    final base = reminder?.title ?? '提醒';
    return reminder?.isRepeating == true
        ? '$base（第${inst.occurrenceNo}次）'
        : base;
  }

  /// 从未删/软删提醒中定位实体（用于已完成记录的标题/类型/宠物名）。
  Reminder? _reminderById(String id) =>
      _activeReminders.where((r) => r.id == id).firstOrNull ??
      _reminders.where((r) => r.id == id).firstOrNull;

  String? _petNameOf(String? petId) {
    if (petId == null) return null;
    return _activePets.where((p) => p.id == petId).firstOrNull?.name ??
        _pets.where((p) => p.id == petId).firstOrNull?.name;
  }

  /// 该提醒是否属于已删除宠物（级联删除）——恢复时需联动恢复整只宠物。
  bool _cascadeDeleted(String petId) =>
      _pets.any((p) => p.id == petId);

  /// 级联删除条目的恢复动作：恢复整只宠物（找回其全部关联）。
  VoidCallback _cascadeRestore(String petId) {
    final pet = _pets.where((p) => p.id == petId).firstOrNull;
    if (pet == null) return () {};
    return () => _restorePet(pet);
  }

  /// 「提醒」分组：软删提醒实体 + 软删已完成记录同组混排（按删除时间倒序）。
  List<Widget> _buildReminderTiles() {
    final items = <({DateTime sortTime, Widget tile})>[
      for (final r in _reminderEntitiesWithPending)
        (sortTime: r.updatedAt, tile: _buildReminderEntityTile(r)),
      for (final inst in _completedRecords)
        (
          sortTime: inst.deletedAt ?? inst.completedAt ?? inst.createdAt,
          tile: _buildCompletedRecordTile(inst),
        ),
    ]..sort((a, b) => b.sortTime.compareTo(a.sortTime));
    return items.map((e) => e.tile).toList();
  }

  /// 删除该提醒时软删待办实例的序号（“当前次数”）；无则返回 null。
  int? _pendingOccurrenceNo(String reminderId) {
    final inst = _deletedPendingInstances
        .where((i) => i.reminderId == reminderId)
        .firstOrNull;
    return inst?.occurrenceNo;
  }

  /// 最近删除只展示“删除时仍有待办”的提醒实体。
  ///
  /// 已完成单次提醒在删除宠物后虽然没有待办实例，但实体也会被级联软删；
  /// 若全部展示会把“3 待办 + 9 已完成”的预期变成多余 3 张实体卡。
  /// 这里只保留有软删待办实例的提醒实体，由已完成记录承担恢复入口。
  List<Reminder> get _reminderEntitiesWithPending {
    final pendingIds = _deletedPendingInstances
        .map((i) => i.reminderId)
        .toSet();
    return _reminders
        .where((r) => pendingIds.contains(r.id))
        .toList();
  }

  Widget _buildReminderEntityTile(Reminder r) {
    final occ = r.isRepeating ? _pendingOccurrenceNo(r.id) : null;
    final titleText = occ != null ? '${r.title}（第$occ次）' : r.title;
    final cascade = _cascadeDeleted(r.petId);
    return _buildTile(
      key: _reminderKey(r.id),
      icon: AppColors.reminderTypeIcons[r.type] ?? Icons.notifications,
      iconColor: AppColors.reminderTypeColors[r.type],
      title: titleText,
      subtitle: '',
      petName: _petNameOf(r.petId),
      onRestore: cascade ? _cascadeRestore(r.petId) : () => _restoreReminder(r),
      onDelete: () => _permanentDeleteReminder(r),
    );
  }

  Widget _buildCompletedRecordTile(ReminderInstance inst) {
    final reminder = _reminderById(inst.reminderId);
    final type = reminder?.type ?? '';
    final cascade = reminder != null && _cascadeDeleted(reminder.petId);
    return _buildTile(
      key: _instanceKey(inst.id),
      icon: AppColors.reminderTypeIcons[type] ?? Icons.check_circle_outline,
      iconColor: AppColors.reminderTypeColors[type],
      title: _reminderTitleOf(inst),
      subtitle: '',
      petName: _petNameOf(reminder?.petId),
      onRestore: cascade
          ? _cascadeRestore(reminder.petId)
          : () => _restoreCompletedRecord(inst),
      onDelete: () => _permanentDeleteCompletedRecord(inst),
    );
  }

  Future<void> _permanentDeleteSelected() async {
    if (_selectedKeys.isEmpty) return;
    final ok = await showDestructiveConfirm(
      context,
      title: '批量彻底删除',
      message: '确定彻底删除选中的 ${_selectedKeys.length} 项内容吗？该操作不可恢复。',
      confirmLabel: '彻底删除',
    );
    if (!ok) return;
    try {
      for (final key in _selectedKeys) {
        final parts = key.split(':');
        final type = parts[0];
        final id = parts.sublist(1).join(':');
        if (type == 'pet') {
          await AppDatabase.permanentlyDeletePet(id);
        } else if (type == 'diary') {
          await AppDatabase.permanentlyDeleteDiary(id);
        } else if (type == 'reminder') {
          await AppDatabase.permanentlyDeleteReminder(id);
        } else if (type == 'instance') {
          await AppDatabase.permanentlyDeleteCompletedInstance(id);
        }
      }
      if (mounted) {
        showAppSnackBar(context, '已彻底删除选中内容');
      }
      _selectedKeys.clear();
      _selectMode = false;
      _load();
    } catch (e) {
      debugPrint('批量彻底删除失败: $e');
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _pets.length +
        _diaries.length +
        _reminderEntitiesWithPending.length +
        _completedRecords.length;
    final allSelected = total > 0 && _selectedKeys.length == total;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectMode ? '已选 ${_selectedKeys.length} 项' : '最近删除（$total）',
        ),
        actions: [
          if (_selectMode) ...[
            TextButton(
              onPressed: _toggleSelectAll,
              child: Text(allSelected ? '取消全选' : '全选'),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '退出管理',
              onPressed: _toggleSelectMode,
            ),
          ] else
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: '批量管理',
              onPressed: _toggleSelectMode,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _pets.isEmpty &&
                  _diaries.isEmpty &&
                  _reminderEntitiesWithPending.isEmpty &&
                  _completedRecords.isEmpty
          ? const Center(
              child: Text('暂无已删除内容', style: TextStyle(color: AppColors.slate)),
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (_pets.isNotEmpty) ...[
                  const _SectionHeader('宠物'),
                  ..._pets.map(
                    (p) => _buildTile(
                      key: _petKey(p.id),
                      icon: Icons.pets,
                      title: p.name,
                      subtitle: dateFormatYMD.format(p.updatedAt),
                      onRestore: () => _restorePet(p),
                      onDelete: () => _permanentDeletePet(p),
                    ),
                  ),
                ],
                if (_diaries.isNotEmpty) ...[
                  const _SectionHeader('爪札'),
                  ..._diaries.map(
                    (d) => _buildTile(
                      key: _diaryKey(d.id),
                      icon: Icons.book_outlined,
                      title: d.title,
                      subtitle: dateFormatYMD.format(d.updatedAt),
                      onRestore: () => _restoreDiary(d),
                      onDelete: () => _permanentDeleteDiary(d),
                    ),
                  ),
                ],
                if (_reminderEntitiesWithPending.isNotEmpty ||
                    _completedRecords.isNotEmpty) ...[
                  const _SectionHeader('提醒'),
                  ..._buildReminderTiles(),
                ],
              ],
            ),
      bottomNavigationBar: _selectMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: OutlinedButton.icon(
                  onPressed: _selectedKeys.isEmpty
                      ? null
                      : _permanentDeleteSelected,
                  icon: const Icon(Icons.delete_forever_outlined, size: 18),
                  label: const Text('彻底删除选中'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildTile({
    required String key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onRestore,
    required VoidCallback onDelete,
    Color? iconColor,
    String? petName,
  }) {
    final selected = _selectedKeys.contains(key);
    return Card(
      child: ListTile(
        leading: _selectMode
            ? Checkbox(
                value: selected,
                onChanged: (_) => _toggleKey(key),
                activeColor: AppColors.plum,
              )
            : Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: (iconColor ?? AppColors.plum).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: iconColor ?? AppColors.plum,
                  size: 20,
                ),
              ),
        title: Text(
          (petName != null && petName.isNotEmpty) ? petName : title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          (petName != null && petName.isNotEmpty) ? title : subtitle,
          style: const TextStyle(fontSize: 13),
        ),
        onTap: _selectMode ? () => _toggleKey(key) : null,
        trailing: _selectMode
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(onPressed: onRestore, child: const Text('恢复')),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_forever_outlined,
                      color: AppColors.error,
                      size: 20,
                    ),
                    tooltip: '彻底删除',
                    onPressed: onDelete,
                  ),
                ],
              ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
