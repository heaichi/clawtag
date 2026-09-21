import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/care_records.dart';
import '../core/utils/formatters.dart';

/// 护理/提醒记录的一行：第 N 次 · 日期 · 状态。
///
/// 「提醒历史」弹层与「宠物护理记录」列表共用，保证两处观感与语义完全一致。
class CareRecordRow extends StatelessWidget {
  const CareRecordRow({
    super.key,
    required this.record,
    this.textColor,
    this.mutedColor,
  });

  final CareRecord record;
  final Color? textColor;
  final Color? mutedColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = textColor ?? (isDark ? AppColors.darkTextPrimary : AppColors.ink);
    final muted = mutedColor ?? (isDark ? AppColors.darkTextSecondary : AppColors.slate);
    final dateText = record.completed && record.completedAt != null
        ? dateFormatCompact.format(record.completedAt!)
        : dateFormatCompact.format(record.date);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(
              '第 ${record.occurrenceNo} 次',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: text,
              ),
            ),
          ),
          Expanded(
            child: Text(
              dateText,
              style: TextStyle(fontSize: 13, color: muted),
            ),
          ),
          CareStatusChip(record: record),
        ],
      ),
    );
  }
}

/// 记录状态标签：待办 / 已完成 / 记录（来自「上次执行日期」）。
class CareStatusChip extends StatelessWidget {
  const CareStatusChip({super.key, required this.record});

  final CareRecord record;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkTextSecondary : AppColors.slate;
    if (record.fromLastDone) return _chip('记录', muted);
    if (record.completed) return _chip('已完成', AppColors.pine);
    // 已过去但未完成：如实说逾期，不能还写『待办』（那是误导）
    final overdue = overdueDaysFor(record.date);
    if (overdue > 0) return _chip('已逾期 $overdue 天', AppColors.error);
    return _chip('待办', AppColors.plum);
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
