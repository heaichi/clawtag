import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 苹果风日期选择器：底部 Cupertino 滚轮。
Future<DateTime?> showAppleDatePicker(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  DateTime selected = initialDate;
  return showCupertinoModalPopup<DateTime>(
    context: context,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return _ApplePickerSheet<DateTime>(
        isDark: isDark,
        onCancel: () => Navigator.pop(ctx),
        onDone: () => Navigator.pop(ctx, selected),
        child: SizedBox(
          height: 220,
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.date,
            initialDateTime: initialDate,
            minimumDate: firstDate,
            maximumDate: lastDate,
            onDateTimeChanged: (v) => selected = v,
          ),
        ),
      );
    },
  );
}

/// 苹果风时间选择器：底部 Cupertino 滚轮（24 小时制）。
Future<TimeOfDay?> showAppleTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
}) {
  var selected = initialTime;
  final initial = DateTime(2026, 1, 1, initialTime.hour, initialTime.minute);
  return showCupertinoModalPopup<TimeOfDay>(
    context: context,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return _ApplePickerSheet<TimeOfDay>(
        isDark: isDark,
        onCancel: () => Navigator.pop(ctx),
        onDone: () => Navigator.pop(ctx, selected),
        child: SizedBox(
          height: 220,
          child: CupertinoDatePicker(
            mode: CupertinoDatePickerMode.time,
            use24hFormat: true,
            initialDateTime: initial,
            onDateTimeChanged: (v) {
              selected = TimeOfDay(hour: v.hour, minute: v.minute);
            },
          ),
        ),
      );
    },
  );
}

/// 苹果风滚轮选择器：用于品种等文本选项。
Future<String?> showAppleWheelPicker(
  BuildContext context, {
  required String title,
  required List<String> items,
  String? initial,
}) {
  var index = 0;
  if (initial != null && items.contains(initial)) {
    index = items.indexOf(initial);
  }
  return showCupertinoModalPopup<String>(
    context: context,
    builder: (ctx) {
      final isDark = Theme.of(ctx).brightness == Brightness.dark;
      return _ApplePickerSheet<String>(
        isDark: isDark,
        onCancel: () => Navigator.pop(ctx),
        onDone: () => Navigator.pop(ctx, items[index]),
        child: SizedBox(
          height: 220,
          child: CupertinoPicker(
            itemExtent: 42,
            scrollController: FixedExtentScrollController(initialItem: index),
            onSelectedItemChanged: (i) => index = i,
            children: items
                .map(
                  (e) => Center(
                    child: Text(e, style: const TextStyle(fontSize: 17)),
                  ),
                )
                .toList(),
          ),
        ),
      );
    },
  );
}

class _ApplePickerSheet<T> extends StatelessWidget {
  final bool isDark;
  final VoidCallback onCancel;
  final VoidCallback onDone;
  final Widget child;

  const _ApplePickerSheet({
    required this.isDark,
    required this.onCancel,
    required this.onDone,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final background = isDark ? const Color(0xFF262322) : Colors.white;
    final handle = isDark ? Colors.grey[600] : Colors.grey[300];

    return CupertinoPopupSurface(
      child: Container(
        decoration: BoxDecoration(
          color: background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: handle,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: onCancel,
                      child: const Text('取消'),
                    ),
                    const Spacer(),
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: onDone,
                      child: const Text(
                        '完成',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
