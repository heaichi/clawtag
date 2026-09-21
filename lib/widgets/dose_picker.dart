import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/database/app_database.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/medication_course.dart';
import '../services/reminder_service.dart';

/// 打开某条用药提醒的服药勾选弹层。
///
/// [onEdit]：弹层右上角「编辑」的动作。用药卡片的点击被「勾选服药」占用了，
/// 编辑入口必须显式给出来，否则用户根本进不去编辑器（真机上被指出过）。
Future<void> showDosePicker({
  required BuildContext context,
  required Reminder reminder,
  required String petName,
  required List<ReminderInstance> instances,
  DateTime? today,
  VoidCallback? onEdit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DosePickerSheet(
      reminder: reminder,
      petName: petName,
      instances: instances,
      today: today,
      onEdit: onEdit,
      onComplete: (instance, at) async {
        // 与列表页同一条完成路径：写库 → 取消该次通知 → 滚动补排窗口
        await AppDatabase.completeInstance(instance.id, completedAt: at);
        try {
          await cancelDoseNotification(instance.id);
        } catch (_) {
          // 取消失败不阻塞完成
        }
        await rescheduleMedicationWindow();
      },
    ),
  );
}

/// 「今天 / 整个疗程」的服药勾选弹层。
///
/// 本地维护一份实例快照：勾选时把该次的**计划时刻**作为完成时间（不取 now()，
/// 否则隔天补勾会把「第 2 次」记成第 3 次的时刻）；完成后立刻刷新计数与副标题。
class DosePickerSheet extends StatefulWidget {
  final Reminder reminder;
  final String petName;
  final List<ReminderInstance> instances;
  final DateTime? today;
  final Future<void> Function(ReminderInstance instance, DateTime at)
  onComplete;

  /// 点右上角「编辑」时回调（由列表页负责关弹层 + 进编辑器）。
  final VoidCallback? onEdit;

  const DosePickerSheet({
    super.key,
    required this.reminder,
    required this.petName,
    required this.instances,
    required this.onComplete,
    this.today,
    this.onEdit,
  });

  @override
  State<DosePickerSheet> createState() => _DosePickerSheetState();
}

class _DosePickerSheetState extends State<DosePickerSheet> {
  late List<ReminderInstance> _instances;
  bool _showAll = false;

  DateTime get _today {
    final now = widget.today ?? DateTime.now();
    return _dayOnly(now);
  }

  @override
  void initState() {
    super.initState();
    _instances = [...widget.instances];
  }

  /// 当前列表里已有的服药次数（不含软删）——用于和「计划次数」区分开。
  int get _listedCount {
    final ids = <String>{};
    for (final i in _instances) {
      if (i.isDeleted) continue;
      if (doseSlotOfInstance(reminder: widget.reminder, instance: i) == null) {
        continue;
      }
      ids.add(i.id);
    }
    return ids.length;
  }

  List<ReminderInstance> _dosesOn(DateTime day) {
    final list = _instances.where((i) {
      final slot = doseSlotOfInstance(reminder: widget.reminder, instance: i);
      if (slot == null) return false;
      return _dayOnly(i.dueDate) == day;
    }).toList()..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return list;
  }

  Future<void> _complete(ReminderInstance instance) async {
    HapticFeedback.lightImpact();
    try {
      await widget.onComplete(instance, instance.dueDate);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('标记失败：$e')));
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      final index = _instances.indexWhere((i) => i.id == instance.id);
      final updated = ReminderInstance(
        id: instance.id,
        reminderId: instance.reminderId,
        dueDate: instance.dueDate,
        completed: true,
        completedAt: instance.dueDate,
        occurrenceNo: instance.occurrenceNo,
        createdAt: instance.createdAt,
        isDeleted: instance.isDeleted,
        deletedAt: instance.deletedAt,
      );
      if (index >= 0) {
        _instances[index] = updated;
      } else {
        _instances.add(updated);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.ink;
    final muted = isDark ? AppColors.darkTextSecondary : AppColors.slate;
    final summary = courseSummary(
      reminder: widget.reminder,
      instances: _instances,
      now: widget.today,
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.reminder.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
                // 用药卡片的点击被「勾选服药」占用，编辑入口只能放这里
                if (widget.onEdit != null)
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onEdit!();
                    },
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('编辑'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.plum,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              courseCardSubtitle(
                reminder: widget.reminder,
                instances: _instances,
                now: widget.today,
              ),
              maxLines: 2,
              style: TextStyle(fontSize: 13, color: muted),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _tab('今天', !_showAll, () => setState(() => _showAll = false)),
                const SizedBox(width: 8),
                _tab('整个疗程', _showAll, () => setState(() => _showAll = true)),
                const Spacer(),
                Text(
                  // 口径写清楚：totalDoses 是整个疗程的**计划**次数，
                  // 而已排定的实例可能少于它（疗程还没走完就只展开到当天附近），
                  // 所以不能只写「共 45 次」——那会让人以为列表里有 45 条（与护理记录里的既有约定一致）。
                  _showAll
                      ? '计划 ${summary.totalDoses} 次 · 已列出 $_listedCount 次'
                      : '今天 ${summary.todayDone}/${summary.todayTotal}',
                  style: TextStyle(fontSize: 13, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: _showAll
                    ? _buildWholeCourse(textColor, muted)
                    : _buildToday(textColor, muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tab(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.plum.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.plum : null,
          ),
        ),
      ),
    );
  }

  Widget _buildToday(Color textColor, Color muted) {
    final doses = _dosesOn(_today);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final dose in doses) _doseRow(dose, textColor, muted),
        if (doses.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              // 三种情况要分开说，不能一律写「今天不在疗程内」：
              // 疗程还没开始 / 已经结束 / 今天就是没有安排（理论上不会出现）
              isCourseFinished(reminder: widget.reminder, instances: _instances)
                  ? '疗程已结束'
                  : '今天不在疗程内（可切「整个疗程」看全部）',
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ),
      ],
    );
  }

  Widget _buildWholeCourse(Color textColor, Color muted) {
    final groups = <DateTime, List<ReminderInstance>>{};
    for (final i in _instances) {
      if (doseSlotOfInstance(reminder: widget.reminder, instance: i) == null) {
        continue;
      }
      groups.putIfAbsent(_dayOnly(i.dueDate), () => []).add(i);
    }
    final days = groups.keys.toList()..sort();
    final start = _dayOnly(widget.reminder.firstDueDate);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final day in days) ...[
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text(
              '第 ${day.difference(start).inDays + 1} 天',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
          ),
          for (final dose
              in (groups[day]!..sort((a, b) => a.dueDate.compareTo(b.dueDate))))
            _doseRow(dose, textColor, muted),
        ],
      ],
    );
  }

  Widget _doseRow(ReminderInstance dose, Color textColor, Color muted) {
    final time = _hhmm(dose.dueDate);
    final missed = !dose.completed && dose.dueDate.isBefore(DateTime.now());
    return Opacity(
      opacity: dose.isDeleted ? 0.4 : 1,
      child: InkWell(
        onTap: dose.completed ? null : () => _complete(dose),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(
                dose.completed
                    ? Icons.check_circle
                    : Icons.radio_button_unchecked,
                size: 20,
                color: dose.completed
                    ? AppColors.pine
                    : (missed ? AppColors.error : muted),
              ),
              const SizedBox(width: 10),
              Text(time, style: TextStyle(fontSize: 14, color: textColor)),
              const SizedBox(width: 10),
              if (dose.completed)
                Expanded(
                  child: Text(
                    '已完成（${_hhmm(dose.completedAt ?? dose.dueDate)}）',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                )
              else if (missed)
                const Text(
                  '未完成',
                  style: TextStyle(fontSize: 12, color: AppColors.error),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}
