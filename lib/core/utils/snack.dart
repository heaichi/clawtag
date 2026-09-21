import 'package:flutter/material.dart';

/// 统一 SnackBar：先清空旧的再显示，避免底部提示排队/长时间堆积。
void showAppSnackBar(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 2),
  bool isError = false,
  SnackBarAction? action,
}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: duration,
      backgroundColor: isError ? const Color(0xFFC94A4A) : null,
      behavior: SnackBarBehavior.floating,
      action: action,
      persist: false,
    ),
  );
}
