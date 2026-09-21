import 'package:flutter/material.dart';

import '../core/database/app_database.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/care_records.dart';
import '../core/utils/error_utils.dart';
import 'care_record_row.dart';

/// 打开「提醒历史」底部弹层：列出**该项目**的每一次（第 N 次 + 日期 + 状态）。
///
/// 口径与「宠物护理记录」**完全一致**：按项目名合并同名提醒、按时间线统一编号
/// （第八十轮用户要求：合并之后必须同一口径，不能有歧义）。
/// 数据来源：该宠物的提醒 + 全部实例（待办/已完成，过滤软删）在内存里分组；
/// 若提醒带有「上次执行日期」而时间线里没有对应的一天，会补一行『记录』。
Future<void> showReminderHistory(
  BuildContext context,
  Reminder reminder,
) async {
  List<CareGroup> groups;
  try {
    final reminders = await AppDatabase.getPetReminders(reminder.petId);
    final instances = await AppDatabase.getInstancesForPet(reminder.petId);
    groups = groupCareRecords(reminders: reminders, instances: instances);
  } catch (e) {
    if (context.mounted) showError(context, e);
    return;
  }
  final key = normalizeCareName(reminder.title);
  CareGroup? group;
  for (final g in groups) {
    if (normalizeCareName(g.name) == key) {
      group = g;
      break;
    }
  }
  // 时间线按时间升序装配，弹层从新到旧展示
  final records = (group?.records ?? const <CareRecord>[]).reversed.toList();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => ReminderHistorySheet(
      title: group?.name ?? reminder.title,
      typeLabel: AppColors.reminderTypeLabels[group?.type ?? reminder.type],
      intervalDays: reminder.repeatInterval,
      isRepeating: reminder.isRepeating,
      records: records,
    ),
  );
}

/// 提醒历史弹层的内容（可单独用于测试/复用）。
class ReminderHistorySheet extends StatelessWidget {
  const ReminderHistorySheet({
    super.key,
    required this.title,
    required this.records,
    this.typeLabel,
    this.intervalDays,
    this.isRepeating = false,
  });

  final String title;
  final List<CareRecord> records;
  final String? typeLabel;
  final int? intervalDays;
  final bool isRepeating;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.ink;
    final muted = isDark ? AppColors.darkTextSecondary : AppColors.slate;
    final doneCount = records.where((r) => r.completed).length;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Row(
                children: [
                  if (typeLabel != null) ...[
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.plum.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.history,
                        size: 18,
                        color: AppColors.plum,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _subtitle(doneCount),
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 14),
            Flexible(
              child: records.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Text(
                        '还没有任何记录',
                        style: TextStyle(fontSize: 14, color: muted),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                      itemCount: records.length,
                      itemBuilder: (_, i) => CareRecordRow(
                        record: records[i],
                        textColor: textColor,
                        mutedColor: muted,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(int doneCount) {
    final parts = <String>['共 $doneCount 次已完成'];
    if (isRepeating && intervalDays != null && intervalDays! > 0) {
      parts.add('计划每 $intervalDays 天');
    }
    return parts.join(' · ');
  }
}

