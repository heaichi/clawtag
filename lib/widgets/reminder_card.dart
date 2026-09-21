import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/database/app_database.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';

/// 待办日期的相对文案（纯函数，便于单测）。
///
/// 过期必须如实显示：原先 `diff <= 0` 一律返回『今天提醒』，
/// 导致已逾期十几天的待办看起来像今天到期（逻辑不严谨，已被用户指出）。
String reminderRelativeLabel(DateTime target, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final overdue = overdueDaysFor(target, now: current);
  if (overdue > 0) return '已逾期 $overdue 天';
  final today = DateTime(current.year, current.month, current.day);
  final targetDay = DateTime(target.year, target.month, target.day);
  final diff = targetDay.difference(today).inDays;
  if (diff == 0) return '今天提醒';
  return '$diff天后提醒';
}

class ReminderCard extends StatelessWidget {
  final Reminder reminder;
  final String? titleOverride;
  final String? petName;
  final DateTime? dueDate;
  final bool completed;
  final DateTime? completedAt;
  final int? occurrenceNo;

  /// 「第 N 次」——作为**不参与省略**的固定尾部显示在标题右侧，
  /// 这样类型名很长被截断时，序号依然可见。
  final String? occurrenceLabel;

  /// 覆盖副标题（用药卡片显示「第 N/M 天 · 今日 X/Y 次 · 下次 HH:mm」）。
  final String? subtitleOverride;

  /// 返回这条提醒**当前全部待办实例**；非空 = 这是一条用药疗程卡片，
  /// 调用方会在 onTap 里打开服药勾选弹层（卡片自身不依赖弹层）。
  final List<ReminderInstance> Function()? pendingDoses;

  final VoidCallback? onTap;
  final VoidCallback? onToggle;

  /// 点「历史」图标时回调（查看这条提醒的第 1…N 次记录）。
  final VoidCallback? onHistory;

  const ReminderCard({
    super.key,
    required this.reminder,
    this.titleOverride,
    this.petName,
    this.dueDate,
    this.completed = false,
    this.completedAt,
    this.occurrenceNo,
    this.occurrenceLabel,
    this.subtitleOverride,
    this.pendingDoses,
    this.onTap,
    this.onToggle,
    this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.ink;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.slate;
    final type = reminder.type;
    final typeColor = AppColors.reminderTypeColors[type] ?? AppColors.slate;
    final typeIcon = AppColors.reminderTypeIcons[type] ?? Icons.notifications;
    final displayDate = dueDate ?? reminder.firstDueDate;
    final displayTitle = titleOverride ?? reminder.title;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Type icon — rounded square
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(typeIcon, color: typeColor, size: 20),
              ),
              const SizedBox(width: 12),
              // Title + pet tag
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayTitle,
                            // maxLines 必须显式给 1，否则 ellipsis 不生效会换行
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                              decoration: completed
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: mutedColor,
                            ),
                          ),
                        ),
                        // 序号固定在尾部，不参与省略（长名字也一定看得到第几次）
                        if (occurrenceLabel != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            occurrenceLabel!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: typeColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    if (subtitleOverride != null)
                      Text(
                        // 用药疗程：副标题由 courseCardSubtitle() 提供，
                        // 与弹层/通知同一口径（第 N 天 · 今日 X/Y 次 · 下次 HH:mm）
                        subtitleOverride!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: mutedColor),
                      )
                    else if (completedAt != null)
                      Text(
                        // 完成日期 + 状态；『第几次』在标题尾部。
                        // （原写作『已完成N次』会被读成完成次数，其实它是序号）
                        '${dateFormatCompact.format(completedAt!)} · 已完成',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: mutedColor),
                      )
                    else
                      Text(
                        '${dateFormatCompact.format(displayDate)} '
                        '${_timeStr(reminder)} · ${_relativeLabel(displayDate)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: mutedColor),
                      ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (!reminder.soundEnabled)
                          _badge(Icons.volume_off, '静音', mutedColor),
                        if (!reminder.vibrateEnabled)
                          _badge(Icons.vibration, '无震动', mutedColor),
                        if (reminder.repeatEndDate != null)
                          _badge(
                            Icons.event,
                            '截止 ${dateFormatMD.format(reminder.repeatEndDate!)}',
                            mutedColor,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              // 右侧：宠物名 / 历史 一列两行（行内容器默认垂直居中）
              if ((petName != null && petName!.isNotEmpty) ||
                  onHistory != null) ...[
                const SizedBox(width: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (petName != null && petName!.isNotEmpty)
                      _sideLabel(petName!),
                    if (petName != null &&
                        petName!.isNotEmpty &&
                        onHistory != null)
                      const SizedBox(height: 6),
                    if (onHistory != null) _historyLabel(onHistory!),
                  ],
                ),
              ],
              if (onToggle != null)
                Semantics(
                  label: completed ? '已完成' : '标记完成',
                  button: true,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onToggle?.call();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: completed ? AppColors.pine : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: completed ? AppColors.pine : mutedColor,
                          width: 1.5,
                        ),
                      ),
                      child: completed
                          ? const Icon(
                              Icons.check,
                              size: 18,
                              color: Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _relativeLabel(DateTime target) => reminderRelativeLabel(target);

  /// 右侧上方标签：宠物名（plum 加粗，与下方『历史记录』同尺寸同圆角）。
  ///
  /// 名字长度**必须限宽 + 单行省略**：否则长名字会把中间标题挤到换行，
  /// 极端情况（≥18 字或大字体）会直接 RenderFlex overflow。
  Widget _sideLabel(String text) {
    return Tooltip(
      message: text,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.plum.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ConstrainedBox(
          // 最小 76 / 最大 80：与下方『历史记录』等宽，超出省略（长按看全名）
          constraints: const BoxConstraints(minWidth: 76, maxWidth: 80),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.plum,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  /// 右侧下方标签：历史记录（与宠物名同尺寸，无图标，点击看第 1…N 次）
  Widget _historyLabel(VoidCallback onTap) {
    return Tooltip(
      message: '查看这条提醒的第 1…N 次记录',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.plum.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ConstrainedBox(
            // 与上方宠物名标签等宽
            constraints: const BoxConstraints(minWidth: 76, maxWidth: 80),
            child: const Text(
              '历史记录',
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.plum,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(IconData icon, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 2),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }

  String _timeStr(Reminder r) {
    if (r.notificationTime == null) return '';
    return r.notificationTime!;
  }
}
