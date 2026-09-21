import 'package:intl/intl.dart';

/// Centralised [DateFormat] instances for the app.
///
/// Pre-allocating them avoids the cost of re-instantiating formatters on
/// every build, and keeping them in one place prevents accidental
/// duplication across files.

/// 逾期天数（**只按日期算**，忽略时分）：
/// - 今天或未来 → 0
/// - 已过去的第 N 天 → N
///
/// 用于把「已过去但未完成」的提醒如实标成『已逾期 N 天』，
/// 而不是含糊的『待办』（列表卡片与宠物护理记录共用同一口径）。
int overdueDaysFor(DateTime dueDate, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final today = DateTime(current.year, current.month, current.day);
  final dueDay = DateTime(dueDate.year, dueDate.month, dueDate.day);
  final diff = today.difference(dueDay).inDays;
  return diff > 0 ? diff : 0;
}

/// "2026年07月15日"
final dateFormatYMD = DateFormat('yyyy年MM月dd日');

/// "07月15日"
final dateFormatMD = DateFormat('MM月dd日');

/// "07月15日 14:30"
final dateFormatMDHM = DateFormat('MM月dd日 HH:mm');

/// "2026/8/25" — 紧凑日期，用于表单内避免文字过长。
final dateFormatCompact = DateFormat('yyyy/M/d');
