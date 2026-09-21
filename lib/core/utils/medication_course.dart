import '../database/app_database.dart';

/// 用药疗程的纯函数集合（见 docs/superpowers/specs/2026-09-21-用药疗程-design.md）。
///
/// 约定：
/// - 疗程以「本地日期」为单位，`dayIndex` 从 0 开始，展示用的「第 N 天」= dayIndex + 1；
/// - `doseTimes` 是**当日分钟数**（09:00 = 540），升序；
/// - 所有函数都不写库、不看当前时间（需要时通过 `now` 传入），便于单测。

/// 滚动调度窗口：只排最近这么多天的服药通知。
///
/// 一个 15 天 × 3 次的疗程有 45 条通知，一次性全排会撞上系统/厂商后台限制。
const medicationWindowDays = 7;

/// 一次服药在疗程中的位置。
class DoseSlot {
  /// 0-based 第几天。
  final int dayIndex;

  /// 0-based 当天第几次。
  final int doseIndex;

  /// 0-based 整个疗程第几次（= dayIndex * doseTimes.length + doseIndex）。
  final int overall;

  const DoseSlot({
    required this.dayIndex,
    required this.doseIndex,
    required this.overall,
  });
}

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 从「时刻」推导它在疗程中的位置；落在疗程外或不是服药时刻时返回 null。
DoseSlot? doseSlotOf({
  required DateTime courseStart,
  required List<int> doseTimes,
  required DateTime dueDate,
}) {
  if (doseTimes.isEmpty) return null;
  final times = [...doseTimes]..sort();
  final dayIndex = _dayOnly(dueDate).difference(_dayOnly(courseStart)).inDays;
  if (dayIndex < 0) return null;
  final doseIndex = times.indexOf(dueDate.hour * 60 + dueDate.minute);
  if (doseIndex < 0) return null;
  return DoseSlot(
    dayIndex: dayIndex,
    doseIndex: doseIndex,
    overall: dayIndex * times.length + doseIndex,
  );
}

/// 模型版：从提醒 + 实例推导位置。
DoseSlot? doseSlotOfInstance({
  required Reminder reminder,
  required ReminderInstance instance,
}) {
  if (!reminder.isMedicationCourse) return null;
  return doseSlotOf(
    courseStart: reminder.firstDueDate,
    doseTimes: reminder.doseTimes,
    dueDate: instance.dueDate,
  );
}

/// 展开疗程第 [fromDay, toDay) 天的服药时刻（`toDay` 排他，默认 = courseDays）。
///
/// 越界一律钳制，不抛异常（`fromDay < 0` 视作 0，`toDay > courseDays` 视作 courseDays）。
List<DateTime> expandDoseTimes({
  required DateTime courseStart,
  required int courseDays,
  required List<int> doseTimes,
  int fromDay = 0,
  int? toDay,
}) {
  if (courseDays <= 0 || doseTimes.isEmpty) return const [];
  final times = [...doseTimes]..sort();
  final start = _dayOnly(courseStart);
  final from = fromDay < 0 ? 0 : fromDay;
  final to = (toDay ?? courseDays).clamp(0, courseDays);
  final out = <DateTime>[];
  for (var d = from; d < to; d++) {
    final day = DateTime(start.year, start.month, start.day + d);
    for (final t in times) {
      out.add(DateTime(day.year, day.month, day.day, t ~/ 60, t % 60));
    }
  }
  return out;
}

/// 整条疗程的全部服药时刻（非用药提醒返回空表）。
List<DateTime> courseDoseDates({required Reminder reminder}) {
  if (!reminder.isMedicationCourse) return const [];
  return expandDoseTimes(
    courseStart: reminder.firstDueDate,
    courseDays: reminder.courseDays!,
    doseTimes: reminder.doseTimes,
  );
}

/// 某条提醒当前未完成的服药实例（按计划时刻升序）。
List<ReminderInstance> pendingDosesFor(
  Reminder reminder,
  Iterable<ReminderInstance> all,
) {
  final list =
      all
          .where(
            (i) => i.reminderId == reminder.id && !i.completed && !i.isDeleted,
          )
          .toList()
        ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return list;
}

/// 滚动调度窗口内、且**尚未过期**的待办服药（[from, to) 左闭右开）。
List<ReminderInstance> doseWindow({
  required Reminder reminder,
  required Iterable<ReminderInstance> instances,
  required DateTime from,
  required DateTime to,
  required DateTime now,
}) {
  return pendingDosesFor(reminder, instances).where((i) {
    if (i.dueDate.isBefore(now)) return false;
    return !i.dueDate.isBefore(from) && i.dueDate.isBefore(to);
  }).toList();
}

/// 今天**之前**漏掉、且还挂着的服药次数（今天的漏服另算，不算在内）。
int missedDosesBefore({
  required Reminder reminder,
  required List<ReminderInstance> instances,
  required DateTime now,
}) {
  final today = _dayOnly(now);
  var count = 0;
  for (final i in instances) {
    if (i.reminderId != reminder.id || i.completed || i.isDeleted) continue;
    final slot = doseSlotOfInstance(reminder: reminder, instance: i);
    if (slot == null) continue;
    if (_dayOnly(i.dueDate).isBefore(today)) count++;
  }
  return count;
}

/// 卡片用汇总。`dayNumber` 从 1 开始；`todayDone` 含超量记录（可能 > todayTotal）。
({
  int totalDoses,
  int dayNumber,
  int todayTotal,
  int todayDone,
  int todayMissed,
  int remainingToday,
  DateTime? nextDoseAt,
})
courseSummary({
  required Reminder reminder,
  required List<ReminderInstance> instances,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final times = reminder.doseTimes;
  final total = (reminder.courseDays ?? 0) * times.length;
  final today = _dayOnly(current);
  final start = _dayOnly(reminder.firstDueDate);
  // 开始日期还没到（用户新建疗程时选了未来的开始日期）时，dayNumber 会是 0 或负数；
  // 钳到 1，否则卡片会显示「第 -1/15 天」这种荒唐文案。
  final rawDay = today.difference(start).inDays + 1;
  final dayNumber = rawDay < 1 ? 1 : rawDay;

  var todayTotal = 0;
  var todayDone = 0;
  DateTime? next;
  for (final i in instances) {
    final slot = doseSlotOfInstance(reminder: reminder, instance: i);
    if (slot == null || slot.dayIndex != dayNumber - 1) continue;
    todayTotal++;
    if (i.completed) todayDone++;
    if (!i.completed &&
        !i.isDeleted &&
        next == null &&
        i.dueDate.isAfter(current)) {
      next = i.dueDate;
    }
  }
  // 疗程还没开始（今天不在疗程内）时，今天的次数按 0 计，
  // 「下一次」要跨天去找第一剂（例如明天 09:00），否则卡片只会显示「今日 0/0 次」。
  if (rawDay < 1) {
    todayTotal = 0;
    todayDone = 0;
    next = null;
    for (final i in instances) {
      if (i.reminderId != reminder.id || i.completed || i.isDeleted) continue;
      if (doseSlotOfInstance(reminder: reminder, instance: i) == null) continue;
      if (!i.dueDate.isAfter(current)) continue;
      if (next == null || i.dueDate.isBefore(next)) next = i.dueDate;
    }
  }
  final missed = missedDosesBefore(
    reminder: reminder,
    instances: instances,
    now: current,
  );
  return (
    totalDoses: total,
    dayNumber: dayNumber,
    todayTotal: todayTotal,
    todayDone: todayDone,
    todayMissed: missed,
    remainingToday: (todayTotal - todayDone) < 0 ? 0 : todayTotal - todayDone,
    nextDoseAt: next,
  );
}

/// 疗程是否已经结束（今天已过最后一天）。
///
/// 注意：最后一天全部完成时**仍算进行中**（卡片用 remainingToday == 0 显示「今日已完成」），
/// 否则第 15 天刚喂完就显示「疗程已结束」，与「今天还在疗程里」的事实不符。
bool isCourseFinished({
  required Reminder reminder,
  required List<ReminderInstance> instances,
  DateTime? now,
}) {
  if (!reminder.isMedicationCourse) return false;
  final current = now ?? DateTime.now();
  final total = reminder.courseDays!;
  final base = reminder.firstDueDate;
  final lastDay = _dayOnly(
    DateTime(base.year, base.month, base.day + total - 1),
  );
  return _dayOnly(current).isAfter(lastDay);
}

/// 卡片副标题：'第 4/15 天 · 今日 2/3 次 · 下次 20:00' / '第 4/15 天 · 今日已完成' / '疗程已结束'。
///
/// 已有**今天之前**的漏服时追加 ' · 漏 N 次'（今天的漏服不显示，免得一天没过完就在催人）。
String courseCardSubtitle({
  required Reminder reminder,
  required List<ReminderInstance> instances,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  if (isCourseFinished(
    reminder: reminder,
    instances: instances,
    now: current,
  )) {
    return '疗程已结束';
  }
  final s = courseSummary(
    reminder: reminder,
    instances: instances,
    now: current,
  );
  // 今天还没到开始日期：只报「尚未开始」，不显示 0/0 次
  if (s.todayTotal == 0 && s.nextDoseAt != null) {
    final d = s.nextDoseAt!;
    return '第 1/${reminder.courseDays} 天 · 尚未开始 · 首剂 '
        '${d.month}/${d.day} ${_hhmm(d)}';
  }
  final buf = StringBuffer('第 ${s.dayNumber}/${reminder.courseDays} 天');
  if (s.remainingToday == 0) {
    buf.write(' · 今日已完成（${s.todayDone}/${s.todayTotal} 次）');
  } else {
    buf.write(' · 今日 ${s.todayDone}/${s.todayTotal} 次');
  }
  if (s.remainingToday > 0 && s.nextDoseAt != null) {
    buf.write(' · 下次 ${_hhmm(s.nextDoseAt!)}');
  }
  if (s.todayMissed > 0) buf.write(' · 漏 ${s.todayMissed} 次');
  return buf.toString();
}

/// 服药通知标题：'团团 · 阿莫西林（第4天 第2次）'。
String buildDoseNotificationTitle({
  required String petName,
  required String medicineName,
  required int dayNumber,
  required int doseOfDay,
}) {
  final base = '$medicineName（第$dayNumber天 第$doseOfDay次）';
  return petName.isEmpty ? base : '$petName · $base';
}

/// 服药通知正文：'喂药 · 今日还剩 2 次'；没有剩余时只显示类型标签。
String buildDoseNotificationBody({
  required String typeLabel,
  int? remainingToday,
}) {
  if (remainingToday == null || remainingToday <= 0) return typeLabel;
  return '$typeLabel · 今日还剩 $remainingToday 次';
}

/// 用药疗程表单校验；返回中文错误文案，null = 通过。
String? validateMedicationCourse({
  required int courseDays,
  required List<int> doseTimes,
}) {
  if (doseTimes.isEmpty) return '请至少设置一个服药时间';
  final sorted = [...doseTimes]..sort();
  for (var i = 1; i < sorted.length; i++) {
    if (sorted[i] == sorted[i - 1]) return '服药时间不能重复';
  }
  // 一天 1 次～4 次都是真实处方（心脏药 1 次、抗生素 4 次）；
  // 上限放宽到 12：编辑器下拉给 1~4，但已有数据里更大的值不该被判非法（避免一编辑就报错）。
  if (doseTimes.length > 12) return '每天最多 12 次';
  if (courseDays < 1) return '疗程天数至少 1 天';
  if (courseDays > 365) return '疗程天数最多 365 天';
  return null;
}
