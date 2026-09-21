import 'package:flutter/foundation.dart';

/// 全局数据版本号。
///
/// 每次业务数据发生变更（宠物/爪札/提醒/标签等新增、编辑、删除、恢复）
/// 后调用 [bump]，供各 Tab 判断是否需要刷新，避免每次切换 Tab 都重建列表。
class DataVersion {
  DataVersion._();

  static final ValueNotifier<int> notifier = ValueNotifier<int>(0);

  static int get value => notifier.value;

  static void bump() {
    notifier.value++;
  }
}
