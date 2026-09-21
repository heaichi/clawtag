import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/database/app_database.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/confirm.dart';
import '../core/utils/care_records.dart';
import '../core/utils/error_utils.dart';
import '../core/utils/formatters.dart';
import '../core/utils/medication_course.dart';
import '../core/utils/routes.dart';
import '../core/utils/snack.dart';
import '../core/utils/uuid.dart';
import '../services/reminder_service.dart';
import '../widgets/completion_confirm_dialog.dart';
import '../widgets/dose_picker.dart';
import '../widgets/reminder_card.dart';
import '../widgets/reminder_history_sheet.dart';
import '../widgets/empty_state.dart';
import '../widgets/inline_dropdown.dart';
import '../widgets/shimmer.dart';
import 'reminder_editor_screen.dart';

class ReminderListScreen extends StatefulWidget {
  final ValueListenable<int>? refreshSignal;

  const ReminderListScreen({super.key, this.refreshSignal});

  @override
  State<ReminderListScreen> createState() => _ReminderListScreenState();
}

class _ReminderListScreenState extends State<ReminderListScreen> {
  List<Reminder> _reminders = [];
  List<Reminder> _deletedReminders = [];
  List<ReminderInstance> _instances = [];
  List<ReminderInstance> _completedInstances = [];
  List<Pet> _allPets = [];
  String? _filterPetId;
  bool _loading = true;
  bool _showCompleted = false;
  bool _selectMode = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_handleExternalRefresh);
    _load();
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_handleExternalRefresh);
    super.dispose();
  }

  void _handleExternalRefresh() {
    if (mounted) _load();
  }

  /// 当前逾期的待办（按日期算，已过到期日仍未完成）。
  /// 跟随「宠物筛选」，与列表里看到的范围保持一致。
  List<ReminderInstance> get _overdueItems {
    final byId = _reminderByIdMap;
    return _pendingMap.values.where((i) {
      if (overdueDaysFor(i.dueDate) == 0) return false;
      final r = byId[i.reminderId];
      return _filterPetId == null || r?.petId == _filterPetId;
    }).toList();
  }

  /// 点逾期汇总条：进入选择模式并**预选所有逾期项**，
  /// 复用既有的批量完成 / 批量删除（不新增一套交互）。
  void _selectOverdue() {
    setState(() {
      _selectMode = true;
      _selectedIds
        ..clear()
        ..addAll(_overdueItems.map((i) => i.reminderId));
    });
  }

  /// 逾期汇总条（有逾期项时才显示）。
  Widget _buildOverdueBanner(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: InkWell(
        onTap: _selectOverdue,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, size: 18, color: AppColors.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$count 个提醒已逾期',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.error,
                  ),
                ),
              ),
              const Text(
                '批量处理',
                style: TextStyle(fontSize: 12, color: AppColors.error),
              ),
              const Icon(Icons.chevron_right, size: 18, color: AppColors.error),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        AppDatabase.getAllReminders(),
        AppDatabase.getPendingInstances(),
        AppDatabase.getAllPets(),
        AppDatabase.getCompletedInstances(),
        AppDatabase.getDeletedReminders(),
      ]);
      final reminders = results[0] as List<Reminder>;
      final pending = results[1] as List<ReminderInstance>;
      final pets = results[2] as List<Pet>;
      final completed = results[3] as List<ReminderInstance>;
      final deletedReminders = results[4] as List<Reminder>;

      // 不再有任何"自动完成"：提醒只有在用户手动确认后才算完成，
      // 逾期项会保留在待办区并每天提醒（见 docs/开发进度看板.md 第七十七轮）。

      if (mounted) {
        setState(() {
          _reminders = reminders;
          _deletedReminders = deletedReminders;
          _instances = pending;
          _completedInstances = completed;
          _allPets = pets;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e);
      }
    }
  }

  /// 某条提醒的全部实例（待办 + 已完成，含软删），按计划时刻升序。
  /// 用药卡片副标题、服药弹层、顶部待喂药计数共用同一份数据。
  List<ReminderInstance> _instancesForReminder(String reminderId) {
    final list =
        [
          ..._instances,
          ..._completedInstances,
        ].where((i) => i.reminderId == reminderId).toList()..sort((a, b) {
          final byDate = a.dueDate.compareTo(b.dueDate);
          return byDate != 0
              ? byDate
              : a.occurrenceNo.compareTo(b.occurrenceNo);
        });
    return list;
  }

  /// 今天的用药提醒（跟着宠物筛选走）。
  ///
  /// 已过最后一天的疗程不算在内：它的漏服仍留在待办里可以补记，
  /// 但不该继续挂在顶部「今天还需喂药」条上（那些次数永远完不成，会一直挂着）。
  List<Reminder> get _activeCourses {
    final pending = _pendingMap;
    final now = DateTime.now();
    return _reminders
        .where(
          (r) =>
              r.isMedicationCourse &&
              pending.containsKey(r.id) &&
              (_filterPetId == null || r.petId == _filterPetId) &&
              !isCourseFinished(
                reminder: r,
                instances: _instancesForReminder(r.id),
                now: now,
              ),
        )
        .toList();
  }

  /// 今天还没喂 + 今天之前漏掉的总次数（顶部提示条用，点进去可以补记漏的那几次）。
  int get _dosesNeedingAttention {
    var left = 0;
    for (final r in _activeCourses) {
      final s = courseSummary(
        reminder: r,
        instances: _instancesForReminder(r.id),
      );
      left += s.remainingToday + s.todayMissed;
    }
    return left;
  }

  /// 今天之前漏掉的用药次数（顶部提示条的第二行用，说明 N 次的构成）。
  int get _missedDosesBeforeToday {
    var missed = 0;
    for (final r in _activeCourses) {
      missed += courseSummary(
        reminder: r,
        instances: _instancesForReminder(r.id),
      ).todayMissed;
    }
    return missed;
  }

  /// 点顶部用药提示条：打开第一条还没喂完的药的勾选弹层（可切「整个疗程」补记漏服）。
  Future<void> _openDoseSheetForFirstCourse() async {
    final courses = _activeCourses;
    if (courses.isEmpty) return;
    final target = courses.firstWhere(
      (r) =>
          courseSummary(
            reminder: r,
            instances: _instancesForReminder(r.id),
          ).remainingToday >
          0,
      orElse: () => courses.first,
    );
    await showDosePicker(
      context: context,
      reminder: target,
      petName: _petNameMap[target.petId] ?? '',
      instances: _instancesForReminder(target.id),
      onEdit: () => _openReminderEdit(target),
    );
    if (mounted) await _load();
  }

  /// 顶部用药提示条。
  ///
  /// 文案必须**如实**：N 含「今天还没喂的 + 昨天及以前漏掉的」，
  /// 所以不能写「今天还需喂药 N 次」（有漏服时那句话是错的，用户已经指出过）。
  Widget _buildDoseBanner(int count) {
    final missed = _missedDosesBeforeToday;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: InkWell(
        onTap: _openDoseSheetForFirstCourse,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.plum.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.plum.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.medication_outlined,
                size: 18,
                color: AppColors.plum,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '还有 $count 次没喂',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.plum,
                      ),
                    ),
                    if (missed > 0) const SizedBox(height: 2),
                    if (missed > 0)
                      Text(
                        '含 $missed 次逾期（点开可补记）',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.plum.withValues(alpha: 0.85),
                        ),
                      ),
                  ],
                ),
              ),
              const Text(
                '去喂药',
                style: TextStyle(fontSize: 12, color: AppColors.plum),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 每条提醒的待办（取**最先到期**的那条，见 P2-11）。
  Map<String, ReminderInstance> get _pendingMap =>
      earliestPendingByReminder(_instances);

  Map<String, String> get _petNameMap {
    return {for (final p in _allPets) p.id: p.name};
  }

  List<Reminder> get _activeReminders {
    final pending = _pendingMap;
    return _reminders
        .where(
          (r) =>
              pending.containsKey(r.id) &&
              (_filterPetId == null || r.petId == _filterPetId),
        )
        .toList();
  }

  List<ReminderInstance> get _completedRecords {
    final reminderById = _reminderByIdMap;
    return _completedInstances.where((i) {
      final r = reminderById[i.reminderId];
      return r != null && (_filterPetId == null || r.petId == _filterPetId);
    }).toList();
  }

  /// **实例 id → 项目编号**（全站唯一口径：卡片 / 通知 / 提醒历史 / 护理记录一致）。
  ///
  /// 同名项目合并后按时间线编号，起始次数取用户手填的『第几次』，
  /// 因此不再出现『卡片第 1 次、护理记录第 3 次』这种自相矛盾。
  Map<String, int> get _projectNumberByInstance {
    final map = <String, int>{};
    try {
      final allInstances = [..._instances, ..._completedInstances];
      // **按宠物隔离**：两只猫各自的『狂犬疫苗』是两个项目，不能合并编号
      final remindersByPet = <String, List<Reminder>>{};
      for (final r in _reminders) {
        remindersByPet.putIfAbsent(r.petId, () => []).add(r);
      }
      for (final entry in remindersByPet.entries) {
        final ids = entry.value.map((r) => r.id).toSet();
        final instances = allInstances
            .where((i) => ids.contains(i.reminderId))
            .toList();
        for (final g in groupCareRecords(
          reminders: entry.value,
          instances: instances,
        )) {
          for (final r in g.records) {
            final id = r.instanceId;
            if (id != null) map[id] = r.occurrenceNo;
          }
        }
      }
    } catch (e) {
      debugPrint('项目编号计算失败，回退提醒内编号: $e');
    }
    return map;
  }

  /// 取某实例的项目编号（算不出来时回退它自己的编号）。
  int _projectNoOf(Map<String, int> numbers, ReminderInstance inst) =>
      numbers[inst.id] ?? inst.occurrenceNo;

  /// 未删 + 个体软删提醒的合并映射（已完成历史可追溯到已删除的提醒）。
  Map<String, Reminder> get _reminderByIdMap {
    return {
      for (final r in _reminders) r.id: r,
      for (final r in _deletedReminders) r.id: r,
    };
  }

  void _toggleSelectMode() {
    setState(() {
      _selectMode = !_selectMode;
      if (!_selectMode) _selectedIds.clear();
    });
  }

  void _toggleSelectAll() {
    if (_showCompleted) {
      final visible = _completedRecords;
      if (visible.isEmpty) return;
      setState(() {
        if (_selectedIds.length == visible.length) {
          _selectedIds.clear();
        } else {
          _selectedIds
            ..clear()
            ..addAll(visible.map((i) => i.id));
        }
      });
      return;
    }
    final visible = _activeReminders;
    if (visible.isEmpty) return;
    setState(() {
      if (_selectedIds.length == visible.length) {
        _selectedIds.clear();
      } else {
        _selectedIds
          ..clear()
          ..addAll(visible.map((r) => r.id));
      }
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  Future<void> _batchComplete() async {
    final affected = _instances
        .where((i) => _selectedIds.contains(i.reminderId))
        .toList();
    // 含逾期项 → 弹一次确认（统一完成日期）；取消则整批不写库
    final overdueItems = affected
        .where((i) => overdueDaysFor(i.dueDate) > 0)
        .toList();
    DateTime? doneAt;
    if (overdueItems.isNotEmpty) {
      final earliest = overdueItems
          .map((i) => i.dueDate)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      doneAt = await showCompleteConfirmDialog(
        context,
        title: '批量完成 ${affected.length} 个提醒',
        dueDate: earliest,
        extraNote: '其中 ${overdueItems.length} 个已逾期，将按同一个完成日期记录。',
      );
      if (doneAt == null || !mounted) return;
    }
    var unscheduled = 0;
    for (final inst in affected) {
      await AppDatabase.completeInstance(inst.id, completedAt: doneAt);
      final reminder = _reminders
          .where((r) => r.id == inst.reminderId)
          .firstOrNull;
      if (reminder != null) {
        final ok = await _afterComplete(reminder);
        if (reminder.isRepeating && !ok) unscheduled++;
      }
    }
    _selectedIds.clear();
    _selectMode = false;
    _load();
    if (mounted) {
      showAppSnackBar(
        context,
        unscheduled == 0
            ? '已完成 ${affected.length} 个提醒'
            : '已完成 ${affected.length} 个提醒，其中 $unscheduled 个通知未排上',
        isError: unscheduled > 0,
      );
    }
  }

  Future<void> _batchDelete() async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定要删除选中的 $count 个提醒吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final id in _selectedIds) {
      final matches = _reminders.where((r) => r.id == id).toList();
      if (matches.isEmpty) continue;
      final r = matches.first;
      try {
        await cancelReminderNotification(notificationIdFromUuid(r.id));
      } catch (_) {
        // 通知取消失败不阻塞删除
      }
      await AppDatabase.softDeleteReminder(r.id);
    }
    _selectedIds.clear();
    _selectMode = false;
    _load();
    if (mounted) {
      showAppSnackBar(context, '已删除 $count 个提醒');
    }
  }

  /// 批量删除已完成记录（软删除，可到“最近删除”恢复）。
  Future<void> _batchDeleteCompleted() async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定要删除选中的 $count 条已完成记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final id in _selectedIds) {
      await AppDatabase.deleteCompletedInstance(id);
    }
    _selectedIds.clear();
    _selectMode = false;
    _load();
    if (mounted) {
      showAppSnackBar(context, '已删除 $count 条已完成记录');
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _activeReminders;
    final completed = _completedRecords;

    // 未添加宠物且没有任何提醒/完成记录时，隐藏“待办/已完成”分段栏，
    // 直接显示与宠物/爪札一致的空状态，保证按钮位置与大小统一。
    if (!_loading &&
        _allPets.isEmpty &&
        _reminders.isEmpty &&
        _instances.isEmpty &&
        _completedInstances.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('提醒')),
        body: EmptyState(
          icon: Icons.event_available,
          title: '暂无待办提醒',
          subtitle: '设定疫苗、驱虫等提醒',
          actionLabel: '添加提醒',
          onAction: _addReminder,
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'add_reminder',
          onPressed: _addReminder,
          child: const Icon(Icons.add),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectMode ? '已选 ${_selectedIds.length} 项' : '提醒'),
        actions: [
          if (_selectMode) ...[
            TextButton(
              onPressed: _toggleSelectAll,
              child: Text(
                _selectedIds.length ==
                        (_showCompleted
                            ? _completedRecords.length
                            : active.length)
                    ? '取消全选'
                    : '全选',
              ),
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
          ? const _ShimmerReminderList()
          : Column(
              children: [
                if (!_selectMode)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _SegmentTab(
                              label: '待办',
                              icon: Icons.event_available,
                              selected: !_showCompleted,
                              onTap: () {
                                setState(() {
                                  _showCompleted = false;
                                  if (_selectMode) {
                                    _selectMode = false;
                                    _selectedIds.clear();
                                  }
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _SegmentTab(
                              label: '已完成',
                              icon: Icons.check_circle_outline,
                              selected: _showCompleted,
                              onTap: () {
                                setState(() {
                                  _showCompleted = true;
                                  if (_selectMode) {
                                    _selectMode = false;
                                    _selectedIds.clear();
                                  }
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!_selectMode && _allPets.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: InlineDropdown<String?>(
                      label: '宠物',
                      value: _filterPetId,
                      options: [
                        const InlineOption<String?>(
                          value: null,
                          label: '全部宠物',
                          icon: Icons.pets,
                        ),
                        ..._allPets.map(
                          (p) => InlineOption<String?>(
                            value: p.id,
                            label: p.name,
                            icon: Icons.pets,
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _filterPetId = v),
                    ),
                  ),
                // 逾期汇总：一键进入选择模式并预选全部逾期项
                if (!_selectMode && !_showCompleted && _overdueItems.isNotEmpty)
                  _buildOverdueBanner(_overdueItems.length),
                // 用药：今天还没喂 + 之前漏掉的次数（点开可补记）
                if (!_selectMode &&
                    !_showCompleted &&
                    _dosesNeedingAttention > 0)
                  _buildDoseBanner(_dosesNeedingAttention),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: _showCompleted
                        ? _buildCompletedList(completed)
                        : _buildActiveList(active),
                  ),
                ),
              ],
            ),
      floatingActionButton: _selectMode
          ? null
          : FloatingActionButton(
              heroTag: 'add_reminder',
              onPressed: _addReminder,
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: _selectMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    if (!_showCompleted) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _selectedIds.isEmpty
                              ? null
                              : _batchComplete,
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 18,
                          ),
                          label: const Text('完成选中'),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _selectedIds.isEmpty
                            ? null
                            : (_showCompleted
                                  ? _batchDeleteCompleted
                                  : _batchDelete),
                        icon: const Icon(Icons.delete_outline, size: 18),
                        label: const Text('删除选中'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildActiveList(List<Reminder> active) {
    final projectNumbers = _projectNumberByInstance;
    if (active.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          EmptyState(
            icon: Icons.event_available,
            title: _showCompleted ? '还没有已完成的提醒' : '暂无待办提醒',
            subtitle: _showCompleted ? '完成提醒后会收纳到这里' : '设定疫苗、驱虫等提醒',
            actionLabel: _showCompleted ? null : '添加提醒',
            onAction: _showCompleted ? null : _addReminder,
          ),
        ],
      );
    }
    final instanceMap = _pendingMap;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: active.length,
      itemBuilder: (_, i) {
        final r = active[i];
        final instance = instanceMap[r.id];
        final selected = _selectedIds.contains(r.id);
        // 用药疗程：一条药一天有多次（1~4），右滑「完成一次」语义不清，
        // 因此禁用完成方向，只保留左滑删除；喂药走卡片 → 勾选弹层。
        final isCourse = r.isMedicationCourse;
        final allForReminder = isCourse ? _instancesForReminder(r.id) : null;
        return Dismissible(
          key: Key(r.id),
          direction: _selectMode
              ? DismissDirection.none
              : (isCourse
                    ? DismissDirection.endToStart
                    : DismissDirection.horizontal),
          // 写库一律放在 confirmDismiss 里：失败就返回 false 让条目弹回原位，
          // 绝不留下"已被 dismiss 但仍在树中"的状态（会触发断言 / release 下该行不可见）。
          // 见 docs/代码审计待办.md P1-11。
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              // 重复提醒完成后再排下一次，提醒本身仍留在待办列表，
              // 不能真的 dismiss，否则会触发 Dismissible 仍在树中的渲染错误。
              if (r.isRepeating) {
                try {
                  await _completeActive(r, instance);
                } catch (e) {
                  if (mounted) showError(context, e);
                }
                return false;
              }
              // 单次提醒：完成不需要二次确认
              try {
                await _completeActive(r, instance);
                return true;
              } catch (e) {
                if (mounted) showError(context, e);
                return false;
              }
            }
            final confirmed = await _confirmDeleteReminder(r);
            if (confirmed != true) return false;
            try {
              await _cancelAndDeleteReminder(r);
              return true;
            } catch (e) {
              if (mounted) showError(context, e);
              return false;
            }
          },
          onDismissed: (_) => _load(),
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 24),
            color: AppColors.pine,
            child: const Icon(
              Icons.check_circle_outline,
              color: Colors.white,
              size: 28,
            ),
          ),
          secondaryBackground: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: AppColors.error,
            child: const Icon(
              Icons.delete_outline,
              color: Colors.white,
              size: 28,
            ),
          ),
          child: InkWell(
            onTap: _selectMode
                ? () => _toggleSelection(r.id)
                : (isCourse
                      ? () async {
                          await showDosePicker(
                            context: context,
                            reminder: r,
                            petName: _petNameMap[r.petId] ?? '',
                            instances: allForReminder!,
                            // 用药卡片的点击给了「勾选服药」，编辑只能从弹层右上角进
                            onEdit: () => _openReminderEdit(r),
                          );
                          if (mounted) await _load();
                        }
                      : () => _openReminderEdit(r)),
            child: Row(
              children: [
                if (_selectMode)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => _toggleSelection(r.id),
                      activeColor: AppColors.plum,
                    ),
                  ),
                Expanded(
                  child: ReminderCard(
                    reminder: r,
                    titleOverride: r.title,
                    // 序号作为不参与省略的尾部；用**项目编号**（与护理记录/历史一致）。
                    // 用药不显示它：副标题已经是「第 3/14 天 · 今日 1/2 次」，
                    // 再挂一个「第6次」就是两套编号打架（用户已指出这类表达问题）。
                    occurrenceLabel: instance == null || isCourse
                        ? null
                        : '第${_projectNoOf(projectNumbers, instance)}次',
                    petName: _petNameMap[r.petId],
                    dueDate: instance?.dueDate,
                    completed: false,
                    // 用药：副标题换成「第 N/M 天 · 今日 X/Y 次 · 下次 HH:mm」
                    subtitleOverride: allForReminder == null
                        ? null
                        : courseCardSubtitle(
                            reminder: r,
                            instances: allForReminder,
                          ),
                    pendingDoses: allForReminder == null
                        ? null
                        : () => allForReminder,
                    onTap: null,
                    onToggle: null,
                    onHistory: () => showReminderHistory(context, r),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompletedList(List<ReminderInstance> completed) {
    final projectNumbers = _projectNumberByInstance;
    if (completed.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 120),
          EmptyState(
            icon: Icons.check_circle_outline,
            title: '暂无已完成的提醒',
            subtitle: '完成提醒后会收纳到这里',
          ),
        ],
      );
    }
    final reminderById = _reminderByIdMap;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: completed.length,
      itemBuilder: (_, i) {
        final inst = completed[i];
        final r = reminderById[inst.reminderId];
        if (r == null) return const SizedBox.shrink();
        final titleOverride = r.title;
        final occurrenceLabel = '第${_projectNoOf(projectNumbers, inst)}次';
        final selected = _selectedIds.contains(inst.id);
        return Dismissible(
          key: Key('done-${inst.id}'),
          direction: _selectMode
              ? DismissDirection.none
              : DismissDirection.endToStart,
          confirmDismiss: (_) async {
            final confirmed = await _confirmDeleteCompletedRecord();
            if (confirmed != true) return false;
            try {
              await AppDatabase.deleteCompletedInstance(inst.id);
              return true;
            } catch (e) {
              if (mounted) showError(context, e);
              return false;
            }
          },
          onDismissed: (_) async {
            _load();
            if (mounted) {
              showAppSnackBar(context, '已完成记录已删除');
            }
          },
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            color: AppColors.error,
            child: const Icon(
              Icons.delete_outline,
              color: Colors.white,
              size: 28,
            ),
          ),
          child: InkWell(
            onTap: _selectMode
                ? () => _toggleSelection(inst.id)
                : () => _openReminderEdit(r),
            child: Row(
              children: [
                if (_selectMode)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Checkbox(
                      value: selected,
                      onChanged: (_) => _toggleSelection(inst.id),
                      activeColor: AppColors.plum,
                    ),
                  ),
                Expanded(
                  child: ReminderCard(
                    reminder: r,
                    titleOverride: titleOverride,
                    occurrenceLabel: occurrenceLabel,
                    petName: _petNameMap[r.petId],
                    dueDate: inst.dueDate,
                    completed: true,
                    completedAt: inst.completedAt,
                    occurrenceNo: inst.occurrenceNo,
                    onTap: null,
                    onToggle: null,
                    onHistory: () => showReminderHistory(context, r),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 点击提醒卡片：待办/已完成均可编辑（含重复提醒）。
  /// 若实体已（个体）删除（从已完成历史点击），先整体恢复再进入编辑，
  /// 避免编辑一个软删状态的实体导致保存后状态不一致。
  Future<void> _openReminderEdit(Reminder r) async {
    if (r.isDeleted) {
      try {
        await AppDatabase.restoreReminder(r.id);
        await rescheduleReminder(r);
      } catch (e) {
        if (mounted) showError(context, e);
        return;
      }
      if (!mounted) return;
      showAppSnackBar(context, '已恢复提醒，可继续编辑');
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      AppRoutes.slideUp(builder: (_) => ReminderEditorScreen(reminder: r)),
    );
    _load();
  }

  Future<void> _completeActive(
    Reminder reminder,
    ReminderInstance? instance,
  ) async {
    HapticFeedback.mediumImpact();
    var scheduled = true;
    if (instance != null) {
      // 逾期项：先让用户核对完成日期（默认今天）；取消则什么都不做
      // —— 完成必须由用户手动确认，通知也会继续每天提醒。
      final overdue = overdueDaysFor(instance.dueDate) > 0;
      DateTime? doneAt;
      if (overdue) {
        doneAt = await showCompleteConfirmDialog(
          context,
          title: '${reminder.title} · 第 ${instance.occurrenceNo} 次',
          dueDate: instance.dueDate,
        );
        if (doneAt == null || !mounted) return;
      }
      await AppDatabase.completeInstance(instance.id, completedAt: doneAt);
      scheduled = await _afterComplete(reminder);
    }
    if (mounted) {
      // 调度失败时如实提示，别让用户以为下一次提醒已经排上了（P2-9）
      final String message;
      if (!reminder.isRepeating) {
        message = '${reminder.title} 已完成，进入已完成列表';
      } else if (scheduled) {
        message = '${reminder.title} 已完成，已安排下一次提醒';
      } else {
        message = '${reminder.title} 已完成，但通知未排上，请检查通知权限';
      }
      showAppSnackBar(
        context,
        message,
        isError: reminder.isRepeating && !scheduled,
      );
    }
    _load();
  }

  /// 完成提醒后的通知收尾：
  /// - 重复提醒 → 生成下一次实例并重排通知（返回是否排上）；
  /// - 单次提醒 → 取消已排的通知（否则到期前完成，到点仍会弹这条已完成的提醒），恒返回 true。
  Future<bool> _afterComplete(Reminder reminder) async {
    // 用药疗程：完成的是「这一次」——取消该次通知并滚动补排窗口；
    // **不生成新实例**（疗程的实例在建疗程时已全部展开），也绝不复用 _scheduleNext。
    if (reminder.isMedicationCourse) {
      try {
        await rescheduleMedicationWindow();
      } catch (e) {
        debugPrint('用药窗口重排失败（不影响本次完成）: $e');
      }
      return true;
    }
    if (reminder.isRepeating) {
      return _scheduleNext(reminder);
    }
    try {
      await cancelReminderNotification(notificationIdFromUuid(reminder.id));
    } catch (_) {
      // 取消失败不阻塞完成流程
    }
    return true;
  }

  /// 按间隔生成下一条实例并排通知：next = 现在 + interval 天（保留原提醒时间）。
  /// 只有显式勾选“重复提醒”的提醒才会重排。
  ///
  /// 返回是否**真的排上了通知**（调度失败时应如实告知用户，见 P2-9）。
  Future<bool> _scheduleNext(Reminder reminder) async {
    if (!reminder.isRepeating) return false;
    final now = DateTime.now();
    final nextDate = computeNextDueDate(
      hour: reminder.firstDueDate.hour,
      minute: reminder.firstDueDate.minute,
      intervalDays: reminder.repeatInterval,
    );

    final nextOccurrenceNo = await AppDatabase.getNextOccurrenceNo(reminder.id);
    final nextInstance = ReminderInstance(
      id: generateUuidV7(),
      reminderId: reminder.id,
      dueDate: nextDate,
      occurrenceNo: nextOccurrenceNo,
      createdAt: now,
    );
    await AppDatabase.insertReminderInstance(nextInstance);

    final baseId = notificationIdFromUuid(reminder.id);
    final notifTitle = buildReminderNotificationTitle(
      petName: _petNameMap[reminder.petId] ?? '',
      reminderTitle: reminder.title,
      // 与卡片 / 提醒历史 / 护理记录同一口径（项目时间线编号）
      occurrenceNo: await projectNumberForInstance(reminder, nextInstance),
      isRepeating: true,
    );
    return scheduleReminderNotification(
      id: baseId,
      title: notifTitle,
      body: AppColors.reminderTypeLabels[reminder.type] ?? '提醒',
      scheduledDate: nextDate,
      soundEnabled: reminder.soundEnabled,
      vibrateEnabled: reminder.vibrateEnabled,
      // 重复提醒始终按天提醒，直到下一次被完成
      repeatDaily: true,
    );
  }

  Future<bool?> _confirmDeleteReminder(Reminder r) {
    return showDestructiveConfirm(
      context,
      title: '删除提醒',
      message: '确定要删除「${r.title}」吗？',
    );
  }

  Future<bool?> _confirmDeleteCompletedRecord() {
    return showDestructiveConfirm(
      context,
      title: '删除已完成记录',
      message: '确定删除这条已完成记录吗？该操作不会恢复为待办。',
      confirmLabel: '删除',
    );
  }

  Future<void> _cancelAndDeleteReminder(Reminder r) async {
    try {
      await cancelReminderNotification(notificationIdFromUuid(r.id));
    } catch (_) {
      // 通知取消失败不阻塞删除
    }
    await AppDatabase.softDeleteReminder(r.id);
    if (mounted) {
      showAppSnackBar(
        context,
        '提醒已删除',
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () async {
            try {
              await AppDatabase.restoreReminder(r.id);
              await rescheduleReminder(r);
              if (mounted) _load();
            } catch (e) {
              if (mounted) showError(context, e);
            }
          },
        ),
      );
      _load();
    }
  }

  Future<void> _addReminder() async {
    await Navigator.push(
      context,
      AppRoutes.slideUp(builder: (_) => const ReminderEditorScreen()),
    );
    _load();
  }
}

class _SegmentTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SegmentTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: selected
          ? (isDark ? const Color(0xFF4A4540) : Colors.white)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? AppColors.plum : const Color(0xFF69727A),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? AppColors.plum
                      : (isDark
                            ? const Color(0xFF9B948C)
                            : const Color(0xFF69727A)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShimmerReminderList extends StatelessWidget {
  const _ShimmerReminderList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: List.generate(4, (_) => const ShimmerCard()),
    );
  }
}
