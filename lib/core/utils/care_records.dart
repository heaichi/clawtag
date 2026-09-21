import 'package:flutter/foundation.dart';

import '../database/app_database.dart';

/// 一条提醒/护理记录（时间线的一行）。
///
/// 既用于「提醒历史」（单条提醒视角），也用于「宠物护理记录」（按项目合并视角），
/// 保证两处的时间线装配算法**只有一份**（见 docs/开发进度看板.md 第六十八轮）。
@immutable
class CareRecord {
  const CareRecord({
    required this.occurrenceNo,
    required this.date,
    required this.completed,
    this.completedAt,
    this.fromLastDone = false,
    this.instanceId,
  });

  /// 对应的实例 id（补位行没有实例，为 null）。
  ///
  /// 用途：把项目时间线的编号映射回每一条实例 —— 卡片序号与通知标题都靠它
  /// 取到与护理记录/提醒历史**完全一致**的『第几次』。
  final String? instanceId;

  /// 第几次（项目内/提醒内的序号）。
  final int occurrenceNo;

  /// 这一次的日期（已完成用到期日，未完成用待办到期日）。
  final DateTime date;

  /// 是否已完成。
  final bool completed;

  /// 实际完成时间（仅已完成有值）。
  final DateTime? completedAt;

  /// true = 这行不是真实实例，而是由提醒的「上次执行日期」补位的记录
  /// （典型场景：用户在做第一次之前就已经做过一次，只有日期没有实例）。
  final bool fromLastDone;

  /// **有效日期**：时间线排序与展示都以它为准。
  ///
  /// - 已完成 → 实际完成时间（可由用户在校对弹窗里指定）
  /// - 未完成 → 到期日
  ///
  /// 之前排序用到期日、显示用完成时间，两者不一致会造成"列表顺序看不懂"。
  DateTime get effectiveDate => completed ? (completedAt ?? date) : date;

  CareRecord copyWith({int? occurrenceNo}) => CareRecord(
    occurrenceNo: occurrenceNo ?? this.occurrenceNo,
    date: date,
    completed: completed,
    completedAt: completedAt,
    fromLastDone: fromLastDone,
    instanceId: instanceId,
  );
}

/// 每条提醒只保留**最先到期**的那条待办（一提醒多待办时的统一口径）。
///
/// 正常情况下一条提醒只有一个待办；但历史数据/异常路径可能出现多条，
/// 之前用 `{for (inst in list) inst.reminderId: inst}` 是**后写覆盖**，
/// 结果取到"最晚"那条 —— 先到期的那条永远不会被展示/排通知
/// （见 docs/代码审计待办.md P2-11）。
Map<String, ReminderInstance> earliestPendingByReminder(
  List<ReminderInstance> pending,
) {
  final map = <String, ReminderInstance>{};
  for (final inst in pending) {
    final existing = map[inst.reminderId];
    if (existing == null || inst.dueDate.isBefore(existing.dueDate)) {
      map[inst.reminderId] = inst;
    }
  }
  return map;
}

/// 项目时间线的**起始次数**：
///
/// 取该项目**最早一条真实实例**的 `occurrence_no`，再往前回推它在时间线上的位置
/// （前面可能还有「上次执行日期」补位行）。这样用户手填的"第几次"就等于
/// "我在用这个 App 之前已经做过 N−1 次"，且与派生编号不再冲突。
/// 没有任何实例（只有补位行）时从 1 开始。
int projectStartNumber(List<CareRecord> timelineAsc) {
  for (var i = 0; i < timelineAsc.length; i++) {
    final r = timelineAsc[i];
    if (!r.fromLastDone) return r.occurrenceNo - i;
  }
  return 1;
}

/// 按「起始次数 + 时间线位置」给项目时间线重新编号（**全站唯一口径**）。
///
/// 卡片序号、通知标题、提醒历史、宠物护理记录都调用它，保证任何入口看到的
/// "第几次"完全一致（见 docs/开发进度看板.md 第七十七轮）。
List<CareRecord> numberProjectTimeline(List<CareRecord> timelineAsc) {
  if (timelineAsc.isEmpty) return const [];
  final start = projectStartNumber(timelineAsc);
  return [
    for (var i = 0; i < timelineAsc.length; i++)
      timelineAsc[i].copyWith(occurrenceNo: start + i),
  ];
}

/// 组装**单条提醒**的历史：真实实例 +（可选的）「上次执行日期」补位行。
///
/// 规则：
/// - 返回按「第几次」从大到小（最新在最上面）；
/// - [lastDoneDate] 与某条实例**同一天**时视为同一次，不补位（避免重复）；
/// - 补位行编号 = 最早实例编号 − 1；若最早实例已是第 1 次则不补位（否则会重号）；
/// - 没有任何实例但存在 [lastDoneDate] 时，补一条第 1 次的记录行。
List<CareRecord> buildReminderHistory({
  required List<ReminderInstance> instances,
  DateTime? lastDoneDate,
}) {
  final records = instances
      .map(
        (i) => CareRecord(
          occurrenceNo: i.occurrenceNo,
          date: i.dueDate,
          completed: i.completed,
          completedAt: i.completedAt,
          instanceId: i.id,
        ),
      )
      .toList()
    // 按**有效日期**倒序（最新在最上面）：排序与展示用同一个日期，避免"顺序看不懂"
    ..sort((a, b) => b.effectiveDate.compareTo(a.effectiveDate));

  if (lastDoneDate == null) return records;

  final sameDay = records.any((r) => _isSameDay(r.date, lastDoneDate));
  if (sameDay) return records;

  final int recordNo;
  if (records.isEmpty) {
    recordNo = 1;
  } else {
    final earliest = records.last.occurrenceNo;
    if (earliest <= 1) return records; // 会重号，宁可不补
    recordNo = earliest - 1;
  }

  records.add(
    CareRecord(
      occurrenceNo: recordNo,
      date: lastDoneDate,
      completed: true,
      fromLastDone: true,
    ),
  );
  return records;
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// 一个**护理项目**：按项目名合并后的一组记录（③ 宠物护理记录页用）。
///
/// 合并规则：`reminder.title` 去掉首尾空格、忽略英文大小写后相同即视为同一项目；
/// 因此用户即使建了多条「驱虫」提醒（或自写的「心丝虫预防」），也只会看到一个项目，
/// 组内是该项目的**完整时间线**（按时间重新编号 1..N，不会重号）。
class CareGroup {
  const CareGroup({
    required this.name,
    required this.type,
    required this.records,
    required this.reminders,
  });

  /// 项目名（用户写的标题 / 内置类型名）。
  final String name;

  /// 展示用类型（取组内第一条提醒的 type，决定图标与配色）。
  final String type;

  /// 组内时间线：按时间升序、编号已重排为 1..N。
  final List<CareRecord> records;

  /// 组成该项目的提醒（新增提醒时用于预填宠物/类型/第几次）。
  final List<Reminder> reminders;

  /// 已完成（含「记录」补位行）的次数。
  int get doneCount =>
      records.where((r) => r.completed || r.fromLastDone).length;

  /// 最近一次已完成/记录的日期。
  DateTime? get lastDone {
    final done = records.where((r) => r.completed || r.fromLastDone);
    if (done.isEmpty) return null;
    return done
        .map((r) => r.completedAt ?? r.date)
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }

  /// 下一次待办日期（最早的未完成实例）。
  DateTime? get nextDue {
    final pending = records.where((r) => !r.completed && !r.fromLastDone);
    if (pending.isEmpty) return null;
    return pending.map((r) => r.date).reduce((a, b) => a.isBefore(b) ? a : b);
  }
}

/// 项目名归一化：去首尾空格 + 忽略英文大小写（用于合并判断）。
String normalizeCareName(String name) => name.trim().toLowerCase();

/// 把某只宠物的提醒与实例装配成**按项目名合并**的护理记录分组。
///
/// - 只统计未删除的提醒（已删除的记录不进护理记录，恢复走『最近删除』）；
/// - 组内时间线按时间升序并**重新编号 1..N**（多条同名提醒合并后也不会重号）；
/// - 提醒的「上次执行日期」若在组内没有对应的一天，补一行『记录』；
/// - 排序：有待办的组按待办日期升序在前，其余按最近完成时间倒序，最后是无记录的组。
List<CareGroup> groupCareRecords({
  required List<Reminder> reminders,
  required List<ReminderInstance> instances,
}) {
  final instancesByReminder = <String, List<ReminderInstance>>{};
  for (final i in instances) {
    instancesByReminder.putIfAbsent(i.reminderId, () => []).add(i);
  }

  final grouped = <String, List<Reminder>>{};
  for (final r in reminders) {
    grouped.putIfAbsent(normalizeCareName(r.title), () => []).add(r);
  }

  final groups = <CareGroup>[];
  grouped.forEach((_, groupReminders) {
    final raw = <CareRecord>[];
    for (final r in groupReminders) {
      final own = instancesByReminder[r.id] ?? const <ReminderInstance>[];
      final history = buildReminderHistory(
        instances: own,
        lastDoneDate: r.lastDoneDate,
      );
      raw.addAll(
        history,

      );
    }

    // 按有效日期升序，再按「起始次数 + 位置」统一编号（合并同名也不重号）
    raw.sort((a, b) => a.effectiveDate.compareTo(b.effectiveDate));
    final records = numberProjectTimeline(raw);

    // 组头图标/配色：优先取**非自定义**类型（信息量更大，
    // 例如同名项目里既有内置的『疫苗』又有自写的『疫苗』时，显示疫苗图标而不是灰色铃铛）。
    final displayType = groupReminders
        .firstWhere((r) => r.type != 'custom', orElse: () => groupReminders.first)
        .type;
    groups.add(
      CareGroup(
        name: groupReminders.first.title,
        type: displayType,
        records: records,
        reminders: groupReminders,
      ),
    );
  });

  groups.sort((a, b) {
    final an = a.nextDue;
    final bn = b.nextDue;
    if (an != null && bn != null) return an.compareTo(bn);
    if (an != null) return -1;
    if (bn != null) return 1;
    final al = a.lastDone;
    final bl = b.lastDone;
    if (al != null && bl != null) return bl.compareTo(al);
    if (al != null) return -1;
    if (bl != null) return 1;
    return a.name.compareTo(b.name);
  });
  return groups;
}

