import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/theme/theme_provider.dart';
import 'core/utils/error_widget.dart';
import 'services/reminder_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 全局错误处理器：捕获未处理的异步异常
  final originalOnError = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    debugPrint('未捕获的异常: $error\n$stack');
    return originalOnError?.call(error, stack) ?? false;
  };
  FlutterError.onError = (FlutterErrorDetails details) {
    debugPrint('Flutter 错误: ${details.exception}\n${details.stack}');
  };

  registerErrorWidget();
  // 通知初始化失败不能阻断启动（插件异常只体现在日志里）
  try {
    await initNotifications();
  } catch (e) {
    debugPrint('initNotifications failed: $e');
  }
  // 这里**不**申请通知权限：启动即弹系统权限框会阻塞首帧，也不符合
  // "权限申请需结合使用场景"的商店要求；改由"我的 → 通知权限"（用户主动）触发。
  // 见 docs/代码审计待办.md P1-9。
  // 用药疗程：补排未来 7 天的服药通知（滚动窗口）。
  // 必须在 runApp 之后异步触发，且失败只记日志，绝不阻塞启动。
  unawaited(rescheduleMedicationWindow());

  runApp(
    MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => ThemeProvider())],
      child: const PetDiaryApp(),
    ),
  );
}
