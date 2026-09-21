import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pet_diary/core/database/app_database.dart';
import 'package:pet_diary/core/utils/medication_course.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 用药疗程（Medication Course）的数据层与迁移回归。
///
/// 对应设计与计划：
/// - docs/superpowers/specs/2026-09-21-用药疗程-design.md
/// - docs/superpowers/plans/2026-09-21-用药疗程.md

DateTime _d(int y, int m, int day, [int h = 9]) => DateTime(y, m, day, h);

Pet _pet(String id) => Pet(
  id: id,
  name: '团团',
  species: 'cat',
  meetDate: _d(2024, 1, 1),
  createdAt: _d(2024, 1, 1),
  updatedAt: _d(2024, 1, 1),
);

Reminder _med(String id, String petId, {int days = 15}) => Reminder(
  id: id,
  petId: petId,
  title: '阿莫西林',
  type: 'medicine',
  firstDueDate: _d(2026, 9, 18),
  courseDays: days,
  doseTimes: const [540, 1260], // 09:00 / 21:00
  createdAt: _d(2026, 9, 18),
  updatedAt: _d(2026, 9, 18),
);

Reminder _plain(String id, String petId) => Reminder(
  id: id,
  petId: petId,
  title: '疫苗',
  type: 'vaccine',
  firstDueDate: _d(2026, 10, 1),
  createdAt: _d(2026, 10, 1),
  updatedAt: _d(2026, 10, 1),
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.debugDatabasePathOverride = inMemoryDatabasePath;
  });
  setUp(() async => AppDatabase.debugResetForTest());

  test('V18：用药两列能写入并读回（含排序与普通提醒空值）', () async {
    await AppDatabase.insertPet(_pet('p1'));
    await AppDatabase.insertReminder(_med('m1', 'p1'));
    await AppDatabase.insertReminder(_plain('r1', 'p1'));

    final all = await AppDatabase.getAllReminders();
    final med = all.firstWhere((r) => r.id == 'm1');
    expect(med.courseDays, 15);
    expect(med.doseTimes, [540, 1260]);
    expect(med.isMedicationCourse, isTrue);

    final plain = all.firstWhere((r) => r.id == 'r1');
    expect(plain.courseDays, isNull);
    expect(plain.doseTimes, isEmpty);
    expect(plain.isMedicationCourse, isFalse, reason: '老提醒 / 普通提醒不能被误判为用药');
  });

  test('dose_times 编解码：容错（乱序、重复、非法值、超范围）', () async {
    expect(AppDatabase.encodeDoseTimes(const [1260, 540]), '540,1260');
    expect(AppDatabase.encodeDoseTimes(const []), isNull);
    expect(AppDatabase.decodeDoseTimes(null), isEmpty);
    expect(AppDatabase.decodeDoseTimes(''), isEmpty);
    expect(AppDatabase.decodeDoseTimes('540, 1260'), [540, 1260]);
    expect(AppDatabase.decodeDoseTimes('1260,540,540'), [
      540,
      1260,
    ], reason: '去重 + 升序');
    expect(AppDatabase.decodeDoseTimes('abc,1440,-5,60'), [
      60,
    ], reason: '非法值丢弃，绝不抛异常');
  });

  test('V18 迁移：V17 老库升级后加列、旧提醒为 NULL、数据不变', () async {
    final dir = Directory.systemTemp.createTempSync('petdiary_med_v18');
    final path = p.join(dir.path, 'v17.db');
    addTearDown(() {
      AppDatabase.debugDatabasePathOverride = inMemoryDatabasePath;
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    AppDatabase.debugDatabasePathOverride = path;
    await AppDatabase.debugResetForTest();
    await AppDatabase.insertPet(_pet('p1'));
    await AppDatabase.insertReminder(_plain('r1', 'p1'));
    final db1 = await AppDatabase.instance;
    // 模拟 V17 老库：回退 user_version，让 V18 迁移重跑一遍（必须幂等）。
    // （SQLite 删列支持有限，不真的删列；迁移本身用 PRAGMA 判断列是否存在，幂等。）
    await db1.execute('PRAGMA user_version = 17');
    await AppDatabase.debugResetForTest();

    final db2 = await AppDatabase.instance;
    final cols = (await db2.rawQuery(
      'PRAGMA table_info(reminders)',
    )).map((r) => r['name'] as String).toSet();
    expect(cols.contains('course_days'), isTrue);
    expect(cols.contains('dose_times'), isTrue);
    expect(await db2.getVersion(), 18);
    final rows = await db2.query(
      'reminders',
      where: 'id = ?',
      whereArgs: ['r1'],
    );
    expect(rows.single['course_days'], isNull, reason: '老数据必须是 NULL（= 非用药）');
    expect(rows.single['dose_times'], isNull);
  });

  test('VERSION 基线 = 18', () async {
    expect(AppDatabase.VERSION, 18);
  });

  test('saveMedicationCourse 新建：30 条实例、occurrence_no 连续、时刻与纯函数一致', () async {
    await AppDatabase.insertPet(_pet('p1'));
    final reminder = _med('m1', 'p1');
    final plan = expandDoseTimes(
      courseStart: reminder.firstDueDate,
      courseDays: 15,
      doseTimes: const [540, 1260],
    );
    await AppDatabase.saveMedicationCourse(
      reminder: reminder,
      isNew: true,
      doses: [
        for (var i = 0; i < plan.length; i++)
          (id: 'd$i', dueDate: plan[i], occurrenceNo: i + 1),
      ],
    );

    final all = await AppDatabase.getInstanceHistoryForReminder('m1');
    final pending = all.where((i) => !i.completed && !i.isDeleted).toList()
      ..sort((a, b) => a.occurrenceNo.compareTo(b.occurrenceNo));
    expect(pending, hasLength(30));
    expect(
      pending.map((i) => i.occurrenceNo).toList(),
      List.generate(30, (i) => i + 1),
    );
    for (var i = 0; i < 30; i++) {
      expect(pending[i].dueDate, plan[i]);
    }
    expect(pending.first.dueDate, _d(2026, 9, 18, 9));
    expect(pending.last.dueDate, _d(2026, 10, 2, 21));
  });

  test('saveMedicationCourse 编辑：已完成保留、ID 复用、疗程外的待办被裁掉', () async {
    await AppDatabase.insertPet(_pet('p1'));
    final reminder = _med('m1', 'p1', days: 3);
    final plan = expandDoseTimes(
      courseStart: reminder.firstDueDate,
      courseDays: 3,
      doseTimes: const [540, 1260],
    );
    await AppDatabase.saveMedicationCourse(
      reminder: reminder,
      isNew: true,
      doses: [
        for (var i = 0; i < plan.length; i++)
          (id: 'd$i', dueDate: plan[i], occurrenceNo: i + 1),
      ],
    );
    await AppDatabase.completeInstance('d0'); // 第 1 天 09:00 已完成
    await AppDatabase.completeInstance('d2'); // 第 2 天 09:00 也已完成

    // 改成 2 天（时间点不变）。d0/d2 是**已完成**实例，编辑时不会被删，
    // 误把它们的 ID 传进来必须被安全丢弃（否则撞 UNIQUE / 张冠李戴改掉历史）。
    final newPlan = expandDoseTimes(
      courseStart: reminder.firstDueDate,
      courseDays: 2,
      doseTimes: const [540, 1260],
    );
    await AppDatabase.saveMedicationCourse(
      reminder: reminder.copyWith(
        courseDays: 2,
        doseTimes: const [540, 840, 1260],
      ),
      isNew: false,
      doses: [
        for (var i = 0; i < newPlan.length; i++)
          (id: 'n$i', dueDate: newPlan[i], occurrenceNo: i + 1),
      ],
      reuseInstanceIds: {newPlan[0]: 'd0', newPlan[2]: 'd2'},
    );

    final after = await AppDatabase.getInstanceHistoryForReminder('m1');
    expect(
      after.where((i) => i.completed).map((i) => i.id).toList()..sort(),
      ['d0', 'd2'],
      reason: '已完成的历史不能被编辑抹掉，且 ID 必须保持不变（通知 ID 依赖它）',
    );
    final pending = after.where((i) => !i.completed && !i.isDeleted).toList();
    expect(
      pending,
      hasLength(2),
      reason: '新计划 4 个时刻中有 2 个已有完成记录（不再补重复待办）→ 只剩 2 条待办',
    );
    expect(
      pending.any((i) => i.dueDate == _d(2026, 9, 20, 9)),
      isFalse,
      reason: '旧第 3 天已被裁掉',
    );
  });

  test('编辑疗程：已喂过的时刻不再补一条待办（今日 2/2 不能变成 2/4）', () async {
    await AppDatabase.insertPet(_pet('p1'));
    final reminder = _med('m1', 'p1', days: 3); // 09:00 / 21:00
    final plan = expandDoseTimes(
      courseStart: reminder.firstDueDate,
      courseDays: 3,
      doseTimes: const [540, 1260],
    );
    await AppDatabase.saveMedicationCourse(
      reminder: reminder,
      isNew: true,
      doses: [
        for (var i = 0; i < plan.length; i++)
          (id: 'd$i', dueDate: plan[i], occurrenceNo: i + 1),
      ],
    );
    // 第 1 天两次都喂了
    await AppDatabase.completeInstance('d0');
    await AppDatabase.completeInstance('d1');

    // 再保存一次（同名同时刻，典型的「进编辑器改个药名就存」）
    await AppDatabase.saveMedicationCourse(
      reminder: reminder.copyWith(title: '阿莫西林'),
      isNew: false,
      doses: [
        for (var i = 0; i < plan.length; i++)
          (id: 'n$i', dueDate: plan[i], occurrenceNo: i + 1),
      ],
    );

    final after = await AppDatabase.getInstanceHistoryForReminder('m1');
    final day1 = after.where(
      (i) =>
          i.dueDate.year == 2026 && i.dueDate.month == 9 && i.dueDate.day == 18,
    );
    expect(day1, hasLength(2), reason: '第 1 天仍应只有 2 条（2 条已完成），不能凭空多出 2 条待办');
    final summary = courseSummary(
      reminder: reminder.copyWith(title: '阿莫西林'),
      instances: after,
      now: _d(2026, 9, 18, 22),
    );
    expect(summary.todayDone, 2);
    expect(summary.todayTotal, 2, reason: '今日应是 2/2，不是 2/4');
  });

  test('saveMedicationCourse 编辑：未完成实例计划时刻没变时复用其 ID', () async {
    await AppDatabase.insertPet(_pet('p1'));
    final reminder = _med('m1', 'p1', days: 3);
    final plan = expandDoseTimes(
      courseStart: reminder.firstDueDate,
      courseDays: 3,
      doseTimes: const [540, 1260],
    );
    await AppDatabase.saveMedicationCourse(
      reminder: reminder,
      isNew: true,
      doses: [
        for (var i = 0; i < plan.length; i++)
          (id: 'd$i', dueDate: plan[i], occurrenceNo: i + 1),
      ],
    );
    // 未完成的 d1 计划时刻是第 1 天 21:00；新计划同样有这一刻 → 必须复用 d1
    final newPlan = expandDoseTimes(
      courseStart: reminder.firstDueDate,
      courseDays: 2,
      doseTimes: const [540, 1260],
    );
    await AppDatabase.saveMedicationCourse(
      reminder: reminder.copyWith(courseDays: 2),
      isNew: false,
      doses: [
        for (var i = 0; i < newPlan.length; i++)
          (id: 'n$i', dueDate: newPlan[i], occurrenceNo: i + 1),
      ],
      reuseInstanceIds: {newPlan[1]: 'd1'},
    );

    final after = await AppDatabase.getInstanceHistoryForReminder('m1');
    final reused = after.firstWhere((i) => i.dueDate == _d(2026, 9, 18, 21));
    expect(reused.id, 'd1', reason: '时刻没变就必须沿用实例 ID，否则已排的通知取消不掉');
    expect(after.where((i) => !i.completed && !i.isDeleted), hasLength(4));
  });

  test('getPendingDoseInstances：只返回用药、未删、未完成的实例（带提醒一起返回）', () async {
    await AppDatabase.insertPet(_pet('p1'));
    final reminder = _med('m1', 'p1', days: 2);
    final plan = expandDoseTimes(
      courseStart: reminder.firstDueDate,
      courseDays: 2,
      doseTimes: const [540],
    );
    await AppDatabase.saveMedicationCourse(
      reminder: reminder,
      isNew: true,
      doses: [
        for (var i = 0; i < plan.length; i++)
          (id: 'd$i', dueDate: plan[i], occurrenceNo: i + 1),
      ],
    );
    await AppDatabase.completeInstance('d0');
    await AppDatabase.insertReminder(_plain('r1', 'p1'));
    await AppDatabase.insertReminderInstance(
      ReminderInstance(
        id: 'x1',
        reminderId: 'r1',
        dueDate: _d(2026, 10, 1),
        createdAt: _d(2026, 10, 1),
      ),
    );

    final doses = await AppDatabase.getPendingDoseInstances();
    expect(doses.map((e) => e.instance.id), ['d1']);
    expect(doses.single.reminder.id, 'm1');
    expect(doses.single.reminder.isMedicationCourse, isTrue);
  });

  test('debugGroupPendingByReminder：按提醒分组', () {
    final grouped = AppDatabase.debugGroupPendingByReminder([
      ReminderInstance(
        id: 'a',
        reminderId: 'm1',
        dueDate: _d(2026, 9, 18, 9),
        createdAt: _d(2026, 9, 18),
      ),
      ReminderInstance(
        id: 'b',
        reminderId: 'm1',
        dueDate: _d(2026, 9, 18, 21),
        createdAt: _d(2026, 9, 18),
      ),
      ReminderInstance(
        id: 'c',
        reminderId: 'm2',
        dueDate: _d(2026, 9, 18, 9),
        createdAt: _d(2026, 9, 18),
      ),
    ]);
    expect(grouped['m1']!.map((i) => i.id), ['a', 'b']);
    expect(grouped['m2']!.map((i) => i.id), ['c']);
  });
}
