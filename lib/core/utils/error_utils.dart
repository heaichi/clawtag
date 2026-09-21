import 'package:flutter/material.dart';

import 'snack.dart';

/// Strips the qualified exception-class prefix from a Dart exception
/// (e.g. `FormatException: bad input` → `bad input`).
String _userMessage(dynamic error) {
  final raw = error.toString();
  // Match any `FooException: ` or `FooError: ` prefix including qualified
  // class names like `FileSystemException: `.
  final cleaned =
      raw.replaceFirst(RegExp(r'^\S*(?:Exception|Error):\s*'), '');
  return cleaned.isNotEmpty ? cleaned : '操作失败，请重试';
}

/// Show error message as SnackBar（统一走 [showAppSnackBar]，先清空旧提示）。
void showError(BuildContext context, dynamic error) {
  final message = _userMessage(error);
  showAppSnackBar(
    context,
    message,
    isError: true,
    duration: const Duration(seconds: 3),
  );
}
