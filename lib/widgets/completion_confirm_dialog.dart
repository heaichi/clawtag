import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import 'apple_pickers.dart';

/// 完成确认弹窗（**仅在逾期时弹出**）：让用户核对完成日期，默认今天。
///
/// 为什么需要它：完成必须由用户手动确认 —— 逾期项若直接按『现在』记完成，
/// 记录的时间就不是真实做这件事的时间；让用户核对一次，历史才准确。
///
/// 返回用户确认的完成日期；**返回 null 表示取消，调用方绝不可写库**。
Future<DateTime?> showCompleteConfirmDialog(
  BuildContext context, {
  required String title,
  DateTime? dueDate,
  String? extraNote,
}) async {
  var pickedDate = DateTime.now();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('确认完成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 14)),
            if (dueDate != null) ...[
              const SizedBox(height: 4),
              Text(
                '原定 ${dateFormatCompact.format(dueDate)}'
                '（已逾期 ${overdueDaysFor(dueDate)} 天）',
                style: const TextStyle(fontSize: 12, color: AppColors.error),
              ),
            ],
            if (extraNote != null) ...[
              const SizedBox(height: 4),
              Text(
                extraNote,
                style: const TextStyle(fontSize: 12, color: AppColors.slate),
              ),
            ],
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '完成日期',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () async {
                final picked = await showAppleDatePicker(
                  ctx,
                  initialDate: pickedDate,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setLocal(() => pickedDate = picked);
              },
              child: InputDecorator(
                decoration: const InputDecoration(),
                child: Text(
                  dateFormatCompact.format(pickedDate),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '确认后本次计入已完成；重复提醒会顺延下一次。',
              style: TextStyle(fontSize: 12, color: AppColors.slate),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认完成'),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true) return null;
  // 完成时间 = 所选日期的当天 + 当前时刻（保留时分，历史排序自然）
  final now = DateTime.now();
  return DateTime(
    pickedDate.year,
    pickedDate.month,
    pickedDate.day,
    now.hour,
    now.minute,
  );
}
