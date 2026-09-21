import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

/// 内嵌展开下拉：点击后在字段正下方展开选项，不弹浮层、不遮挡标题。
class InlineDropdown<T> extends StatefulWidget {
  final String label;
  final T? value;
  final List<InlineOption<T>> options;
  final ValueChanged<T?>? onChanged;
  final String? placeholder;

  const InlineDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    this.onChanged,
    this.placeholder = '请选择',
  });

  @override
  State<InlineDropdown<T>> createState() => _InlineDropdownState<T>();
}

class _InlineDropdownState<T> extends State<InlineDropdown<T>> {
  bool _expanded = false;

  void _toggle() {
    FocusManager.instance.primaryFocus?.unfocus();
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
  }

  void _choose(InlineOption<T> option) {
    HapticFeedback.selectionClick();
    setState(() => _expanded = false);
    widget.onChanged?.call(option.value);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark
        ? const Color(0xFFF0EDE8)
        : const Color(0xFF1F1D1B);
    final mutedColor = isDark
        ? const Color(0xFF9B948C)
        : const Color(0xFF69727A);
    final surface = Theme.of(context).colorScheme.surface;

    InlineOption<T>? selected;
    for (final option in widget.options) {
      if (option.value == widget.value) {
        selected = option;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(14),
          child: InputDecorator(
            decoration: const InputDecoration(),
            child: Row(
              children: [
                if (widget.label.isNotEmpty) ...[
                  Text(
                    widget.label,
                    style: TextStyle(color: mutedColor, fontSize: 15),
                  ),
                  const SizedBox(width: 8),
                ],
                if (selected?.icon != null) ...[
                  Icon(
                    selected!.icon,
                    size: 20,
                    color: selected.color ?? AppColors.plum,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    selected?.label ?? widget.placeholder!,
                    style: TextStyle(
                      color: selected == null ? mutedColor : textColor,
                      fontSize: 15,
                    ),
                  ),
                ),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.expand_more, color: mutedColor, size: 20),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: _expanded
              ? Container(
                  margin: const EdgeInsets.only(top: 6),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF383430)
                          : const Color(0xFFE8E4DD),
                    ),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: SingleChildScrollView(
                      child: Column(
                        children: widget.options.map((option) {
                          final selectedOption = option.value == widget.value;
                          final accent = option.color ?? AppColors.plum;
                          return Material(
                            color: selectedOption
                                ? accent.withValues(alpha: 0.08)
                                : Colors.transparent,
                            child: InkWell(
                              onTap: () => _choose(option),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    if (option.icon != null) ...[
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: accent.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Icon(
                                          option.icon,
                                          size: 18,
                                          color: accent,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                    ],
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            option.label,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: selectedOption
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                              color: textColor,
                                            ),
                                          ),
                                          if (option.subtitle != null) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              option.subtitle!,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: mutedColor,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (selectedOption)
                                      Icon(
                                        Icons.check,
                                        size: 18,
                                        color: accent,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class InlineOption<T> {
  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final Color? color;

  const InlineOption({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.color,
  });
}
