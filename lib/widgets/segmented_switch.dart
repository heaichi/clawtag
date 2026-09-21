import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// 两段式胶囊切换（宠物详情页「爪札 ｜ 护理记录」用）。
///
/// 视觉与全站一致：淡紫底 + 圆角胶囊 + plum 选中态。
class SegmentedSwitch extends StatelessWidget {
  const SegmentedSwitch({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
  });

  /// 每段的文案（如 ['爪札 4 篇', '护理记录 3 项']）。
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? AppColors.darkTextSecondary : AppColors.slate;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : AppColors.cloud.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: i == index ? AppColors.plum : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: i == index ? Colors.white : muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
