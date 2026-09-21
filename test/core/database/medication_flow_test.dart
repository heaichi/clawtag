import 'package:flutter_test/flutter_test.dart';
import 'package:pet_diary/core/database/app_database.dart';
import 'package:pet_diary/core/utils/medication_course.dart';
import 'package:pet_diary/core/utils/uuid.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 用药疗程**端到端**用例：把设计文档 §10.1 的验收标准固化成自动化断言。
///
/// 覆盖：建疗程 → 卡片口径 → 勾选一次 → 通知标题口径 → 窗口滚动 → 删除/恢复。
/// 真机只剩「看得见、点得着、到点响」这三件事需要人工确认（见 docs/开发接力.md 用药验收清单）。

DateTime _d(int y, int m, int day, [int h = 9, int min = 0]) =>
    DateTime(y, m, day, h, min);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.debugDatabasePathOverride = inMemoryDatabasePath;
  });
  setUp(() async => AppDatabase.debugResetForTest());

  test('验收 1-6：建疗程 → 今日 0/2 → 勾一次 → 通知标题 → 窗口滚动 → 删除恢复', () async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const times = [9 * 60, 21 * 60]; // 09:00 / 21:00

    await AppDatabase.insertPet(
      Pet(
        id: 'p1',
        name: '团团',
        species: 'cat',
        meetDate: _d(2024, 1, 1),
        createdAt: _d(2024, 1, 1),
        updatedAt: _d(2024, 1, 1),
      ),
    );

    // ── 1. 建「一天 2 次 × 15 天」的疗程（开始日期 = 今天，避免时间相关抖动）
    final reminder = Reminder(
      id: 'm1',
      petId: 'p1',
      title: '阿莫西林',
      type: 'medicine',
      firstDueDate: DateTime(today.year, today.month, today.day, 9),
      courseDays: 15,
      doseTimes: times,
      createdAt: now,
      updatedAt: now,
    );
    final plan = expandDoseTimes(
      courseStart: reminder.firstDueDate,
      courseDays: 15,
      doseTimes: times,
    );
    await AppDatabase.saveMedicationCourse(
      reminder: reminder,
      isNew: true,
      doses: [
        for (var i = 0; i < plan.length; i++)
          (id: generateUuidV7(), dueDate: plan[i], occurrenceNo: i + 1),
      ],
    );

    var instances = await AppDatabase.getInstanceHistoryForReminder('m1');
    expect(instances, hasLength(30), reason: '15 天 × 2 次 = 30 条服药计划');

    // ── 2. 卡片口径：第 1/15 天 · 今日 0/2 次
    var summary = courseSummary(
      reminder: reminder,
      instances: instances,
      now: today.add(const Duration(hours: 8)),
    );
    expect(summary.totalDoses, 30);
    expect(summary.dayNumber, 1);
    expect(summary.todayTotal, 2);
    expect(summary.todayDone, 0);
    expect(summary.remainingToday, 2);
    expect(summary.nextDoseAt, DateTime(today.year, today.month, today.day, 9));

    // ── 3. 勾掉第一次（弹层用的就是「该次计划时刻」，不是 now）
    final firstDose = instances.firstWhere((i) => i.occurrenceNo == 1);
    await AppDatabase.completeInstance(
      firstDose.id,
      completedAt: firstDose.dueDate,
    );

    instances = await AppDatabase.getInstanceHistoryForReminder('m1');
    summary = courseSummary(
      reminder: reminder,
      instances: instances,
      now: today.add(const Duration(hours: 10)),
    );
    expect(summary.todayDone, 1);
    expect(summary.remainingToday, 1);
    expect(
      summary.nextDoseAt,
      DateTime(today.year, today.month, today.day, 21),
      reason: '下一次应指向当天 21:00，而不是别的天',
    );
    final completed = instances.firstWhere((i) => i.occurrenceNo == 1);
    expect(completed.completed, isTrue);
    expect(
      completed.completedAt,
      firstDose.dueDate,
      reason: '完成时间 = 该次计划时刻（用户可事后用逾期弹窗改真实时间）',
    );

    // ── 4. 通知标题口径：第 1 天第 2 次
    final secondDose = instances.firstWhere((i) => i.occurrenceNo == 2);
    final slot = doseSlotOfInstance(reminder: reminder, instance: secondDose)!;
    expect(slot.dayIndex, 0);
    expect(slot.doseIndex, 1);
    expect(
      buildDoseNotificationTitle(
        petName: '团团',
        medicineName: reminder.title,
        dayNumber: slot.dayIndex + 1,
        doseOfDay: slot.doseIndex + 1,
      ),
      '团团 · 阿莫西林（第1天 第2次）',
    );

    // ── 5. 滚动窗口：只排未来 7 天，且不重复排已完成的
    var pendingNow = instances
        .where((i) => !i.completed && !i.isDeleted)
        .toList();
    final startOfToday = DateTime(today.year, today.month, today.day);
    var inWindow = doseWindow(
      reminder: reminder,
      instances: pendingNow,
      from: startOfToday,
      to: startOfToday.add(const Duration(days: medicationWindowDays)),
      now: today.add(const Duration(hours: 8)),
    );
    expect(inWindow, hasLength(13), reason: '7 天 × 2 次 = 14 次，减去已完成的那 1 次');
    expect(
      inWindow.first.dueDate,
      DateTime(today.year, today.month, today.day, 21),
      reason: '窗口内第一条应是今晚 21:00',
    );
    expect(
      inWindow.last.dueDate.isBefore(
        startOfToday.add(const Duration(days: medicationWindowDays)),
      ),
      isTrue,
    );
    // 第 8 天及以后必须在窗口外（靠完成/启动时滚动补排）
    final day8 = startOfToday.add(const Duration(days: 7));
    expect(
      inWindow.any((i) => !i.dueDate.isBefore(day8)),
      isFalse,
      reason: '第 8 天以后不预排，避免几十条通知撞厂商限制',
    );

    // 第 1 天全部喂完 → 窗口应当滚到第 2 天开始
    final second = instances.firstWhere((i) => i.occurrenceNo == 2);
    await AppDatabase.completeInstance(second.id, completedAt: second.dueDate);
    instances = await AppDatabase.getInstanceHistoryForReminder('m1');
    pendingNow = instances.where((i) => !i.completed && !i.isDeleted).toList();
    inWindow = doseWindow(
      reminder: reminder,
      instances: pendingNow,
      from: startOfToday.add(const Duration(days: 1)),
      to: startOfToday.add(const Duration(days: 1 + medicationWindowDays)),
      now: today.add(const Duration(hours: 22)),
    );
    expect(inWindow, isNotEmpty);
    expect(
      inWindow.first.dueDate,
      startOfToday.add(const Duration(days: 1, hours: 9)),
    );
    expect(
      courseSummary(
        reminder: reminder,
        instances: instances,
        now: today.add(const Duration(days: 1, hours: 8)),
      ).dayNumber,
      2,
    );

    // ── 6. 删除 → 最近删除 → 恢复：未完成次数回来、已完成记录不重复
    await AppDatabase.softDeleteReminder('m1');
    expect(await AppDatabase.getDeletedReminders(), hasLength(1));
    await AppDatabase.restoreReminder('m1');

    final after = await AppDatabase.getInstanceHistoryForReminder('m1');
    expect(
      after.where((i) => i.completed),
      hasLength(2),
      reason: '已喂过的两次不能被恢复动作抹掉，也不能翻倍',
    );
    expect(
      after.where((i) => !i.completed && !i.isDeleted),
      hasLength(28),
      reason: '30 次计划 - 已完成 2 次 = 28 条待办（一条不多一条不少）',
    );
    final pendingDoses = await AppDatabase.getPendingDoseInstances();
    expect(pendingDoses, hasLength(28));
    expect(pendingDoses.first.reminder.isMedicationCourse, isTrue);
  });
}
