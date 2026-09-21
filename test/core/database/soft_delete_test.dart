import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:clawtag/core/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 软删除 / 恢复 / 最近删除 / 统计口径 的回归测试。
///
/// 这些用例对应历史上真实出现过的 bug（见 docs/bugs.md）：
/// - 删除提醒时已完成历史被连带删除（第五轮）
/// - 恢复宠物时级联删除的实例漏恢复（第十三轮）
/// - 恢复宠物把“个体已删”的实例一起复活（第十轮 A1）
/// - 最近删除条数对不上（第八/九轮）
/// - 彻底删除单条完成记录连带清空其他最近删除记录（第十一轮）
/// - 删掉最后一条完成记录产生“幽灵提醒”（第三轮）
///
/// 用 sqflite_common_ffi 在测试进程里跑真实 SQLite（内存库）。

DateTime _d(int y, int m, int day) => DateTime(y, m, day);

Pet _pet(String id, {String name = '咪咪'}) => Pet(
  id: id,
  name: name,
  species: 'cat',
  meetDate: _d(2024, 1, 1),
  createdAt: _d(2024, 1, 1),
  updatedAt: _d(2024, 1, 1),
);

Reminder _reminder(
  String id,
  String petId, {
  bool repeating = true,
  String title = '疫苗',
}) => Reminder(
  id: id,
  petId: petId,
  title: title,
  type: 'vaccine',
  firstDueDate: _d(2026, 1, 1),
  repeatUnit: repeating ? 'day' : 'once',
  repeatInterval: repeating ? 30 : 0,
  isRepeating: repeating,
  createdAt: _d(2026, 1, 1),
  updatedAt: _d(2026, 1, 1),
);

ReminderInstance _pending(String id, String reminderId, {int no = 1}) =>
    ReminderInstance(
      id: id,
      reminderId: reminderId,
      dueDate: _d(2026, 2, 1),
      occurrenceNo: no,
      createdAt: _d(2026, 2, 1),
    );

ReminderInstance _done(String id, String reminderId, {int no = 1}) =>
    ReminderInstance(
      id: id,
      reminderId: reminderId,
      dueDate: _d(2026, 1, 1),
      completed: true,
      completedAt: _d(2026, 1, 2),
      occurrenceNo: no,
      createdAt: _d(2026, 1, 1),
    );

Diary _diary(String id, String petId) => Diary(
  id: id,
  petId: petId,
  title: '标题',
  content: '内容',
  diaryDate: _d(2026, 1, 1),
  createdAt: _d(2026, 1, 1),
  updatedAt: _d(2026, 1, 1),
);

void main() {
  setUpAll(() {
    // 在宿主进程里跑真实 SQLite（内存库），不依赖 Android。
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.debugDatabasePathOverride = inMemoryDatabasePath;
  });

  setUp(() async {
    // 每个用例重新开一个空的内存库，互不干扰。
    await AppDatabase.debugResetForTest();
  });

  tearDownAll(() async {
    await AppDatabase.debugResetForTest();
    AppDatabase.debugDatabasePathOverride = null;
  });

  group('提醒：软删 / 恢复闭环', () {
    test('软删提醒只软删实体与当前待办，已完成历史保留', () async {
      await AppDatabase.insertPet(_pet('p1'));
      await AppDatabase.insertReminder(_reminder('r1', 'p1'));
      await AppDatabase.insertReminderInstance(_pending('i1', 'r1', no: 3));
      await AppDatabase.insertReminderInstance(_done('i2', 'r1', no: 1));
      await AppDatabase.insertReminderInstance(_done('i3', 'r1', no: 2));

      await AppDatabase.softDeleteReminder('r1');

      expect(await AppDatabase.getPendingInstances(), isEmpty);
      // 历史仍留在“已完成”分区（曾经被连带删掉过）
      expect(await AppDatabase.getCompletedInstances(), hasLength(2));
      // 当前待办进最近删除
      final deletedPending = await AppDatabase.getDeletedPendingInstances();
      expect(deletedPending, hasLength(1));
      expect(deletedPending.single.occurrenceNo, 3);
      expect(await AppDatabase.getAllReminders(), isEmpty);
    });

    test('恢复提醒整体找回实体与软删待办', () async {
      await AppDatabase.insertPet(_pet('p1'));
      await AppDatabase.insertReminder(_reminder('r1', 'p1'));
      await AppDatabase.insertReminderInstance(_pending('i1', 'r1', no: 2));
      await AppDatabase.insertReminderInstance(_done('i2', 'r1', no: 1));
      await AppDatabase.softDeleteReminder('r1');

      await AppDatabase.restoreReminder('r1');

      expect(await AppDatabase.getAllReminders(), hasLength(1));
      final pending = await AppDatabase.getPendingInstances();
      expect(pending, hasLength(1));
      expect(pending.single.occurrenceNo, 2);
      expect(await AppDatabase.getCompletedInstances(), hasLength(1));
      expect(await AppDatabase.getDeletedPendingInstances(), isEmpty);
    });

    test('删掉最后一条完成记录会联动软删提醒实体，恢复该条即恢复实体', () async {
      await AppDatabase.insertPet(_pet('p1'));
      await AppDatabase.insertReminder(_reminder('r1', 'p1'));
      await AppDatabase.insertReminderInstance(_done('i1', 'r1'));

      await AppDatabase.deleteCompletedInstance('i1');

      // 防“幽灵提醒”：两个分区都看不到，实体也不该留着可见
      expect(await AppDatabase.getAllReminders(), isEmpty);
      expect(await AppDatabase.getCompletedInstances(), isEmpty);
      expect(await AppDatabase.getDeletedCompletedInstances(), hasLength(1));

      await AppDatabase.restoreCompletedInstance('i1');

      expect(await AppDatabase.getAllReminders(), hasLength(1));
      expect(await AppDatabase.getCompletedInstances(), hasLength(1));
    });

    test('恢复提醒会清掉级联标记（P2-4）', () async {
      await AppDatabase.insertPet(_pet('p1'));
      await AppDatabase.insertReminder(_reminder('r1', 'p1'));
      await AppDatabase.insertReminderInstance(_pending('i1', 'r1'));
      await AppDatabase.softDeletePet('p1'); // 级联：实体与实例都带 deleted_with_pet=1

      await AppDatabase.restoreReminder('r1');

      final rows = await (await AppDatabase.instance).query(
        'reminders',
        where: 'id = ?',
        whereArgs: ['r1'],
      );
      expect(rows.single['is_deleted'], 0);
      expect(rows.single['deleted_with_pet'], 0, reason: 'P2-4 恢复后级联标记必须清掉');
      // 实例也一并恢复；注意此时宠物仍软删，getAllReminders 仍为空（它要求宠物未删）
      final inst = await (await AppDatabase.instance).query(
        'reminder_instances',
        where: 'id = ?',
        whereArgs: ['i1'],
      );
      expect(inst.single['is_deleted'], 0);
    });

    test('个体软删提醒的历史仍显示；宠物级联删除后整体隐藏', () async {
      await AppDatabase.insertPet(_pet('p1'));
      await AppDatabase.insertReminder(_reminder('r1', 'p1'));
      await AppDatabase.insertReminderInstance(_done('i1', 'r1'));

      await AppDatabase.softDeleteReminder('r1');
      expect(await AppDatabase.getCompletedInstances(), hasLength(1));

      await AppDatabase.softDeletePet('p1');
      expect(await AppDatabase.getCompletedInstances(), isEmpty);
    });
  });

  group('彻底删除的连带边界', () {
    test('彻底删除单条完成记录不连带其他最近删除记录', () async {
      await AppDatabase.insertPet(_pet('p1'));
      await AppDatabase.insertReminder(_reminder('r1', 'p1'));
      await AppDatabase.insertReminderInstance(_done('i1', 'r1', no: 1));
      await AppDatabase.insertReminderInstance(_done('i2', 'r1', no: 2));
      await AppDatabase.insertReminderInstance(_done('i3', 'r1', no: 3));
      await AppDatabase.deleteCompletedInstance('i1');
      await AppDatabase.deleteCompletedInstance('i2');
      await AppDatabase.deleteCompletedInstance('i3');
      expect(await AppDatabase.getDeletedCompletedInstances(), hasLength(3));

      await AppDatabase.permanentlyDeleteCompletedInstance('i1');

      final rest = await AppDatabase.getDeletedCompletedInstances();
      expect(rest, hasLength(2));
      expect(rest.map((e) => e.id).toSet(), {'i2', 'i3'});
    });

    test('还有别的软删记录时，彻底删除单条不会动提醒实体', () async {
      await AppDatabase.insertPet(_pet('p1'));
      await AppDatabase.insertReminder(_reminder('r1', 'p1'));
      await AppDatabase.insertReminderInstance(_done('i1', 'r1', no: 1));
      await AppDatabase.insertReminderInstance(_done('i2', 'r1', no: 2));
      await AppDatabase.deleteCompletedInstance('i1');
      await AppDatabase.deleteCompletedInstance('i2');

      await AppDatabase.permanentlyDeleteCompletedInstance('i1');

      // 实体仍在（软删状态），可由最近删除里的 i2 恢复
      final raw = await (await AppDatabase.instance).query('reminders');
      expect(raw, hasLength(1));
    });

    test('彻底删除最后一条记录后，个体软删的提醒实体被一并清理（P2-3 幽灵实体）', () async {
      await AppDatabase.insertPet(_pet('p1'));
      await AppDatabase.insertReminder(_reminder('r1', 'p1'));
      await AppDatabase.insertReminderInstance(_done('i1', 'r1'));
      await AppDatabase.deleteCompletedInstance('i1'); // 无活跃实例 → 实体联动软删

      await AppDatabase.permanentlyDeleteCompletedInstance('i1');

      expect(await AppDatabase.getDeletedCompletedInstances(), isEmpty);
      // 已无任何实例 → 实体既看不到也恢复不了，必须清掉，避免脏数据累积
      final raw = await (await AppDatabase.instance).query('reminders');
      expect(raw, isEmpty, reason: 'P2-3：幽灵提醒实体应被清理');
    });

    test('级联删除（随宠物）的实体不会被该清理误删', () async {
      await AppDatabase.insertPet(_pet('p1'));
      await AppDatabase.insertReminder(_reminder('r1', 'p1'));
      await AppDatabase.insertReminderInstance(_done('i1', 'r1'));
      await AppDatabase.softDeletePet('p1'); // 级联：实体 deleted_with_pet=1

      await AppDatabase.permanentlyDeleteCompletedInstance('i1');

      // 级联实体归"恢复宠物"管，不能被单条记录清理误删
      final raw = await (await AppDatabase.instance).query('reminders');
      expect(raw, hasLength(1));
    });
  });

  group('宠物：级联软删 / 恢复', () {
    test('软删宠物级联软删爪札、提醒与实例', () async {
      await AppDatabase.insertPet(_pet('p1'));
      await AppDatabase.insertDiary(_diary('d1', 'p1'));
      await AppDatabase.insertReminder(_reminder('r1', 'p1'));
      await AppDatabase.insertReminderInstance(_pending('i1', 'r1'));
      await AppDatabase.insertReminderInstance(_done('i2', 'r1'));

      await AppDatabase.softDeletePet('p1');

      expect(await AppDatabase.getAllPets(), isEmpty);
      expect(await AppDatabase.getAllDiaries(), isEmpty);
      expect(await AppDatabase.getAllReminders(), isEmpty);
      expect(await AppDatabase.getPendingInstances(), isEmpty);
      expect(await AppDatabase.getCompletedInstances(), isEmpty);
      // 级联条目全部进最近删除（条数一一对应）
      expect(await AppDatabase.getDeletedPets(), hasLength(1));
      expect(await AppDatabase.getDeletedDiaries(), hasLength(1));
      expect(await AppDatabase.getDeletedPendingInstances(), hasLength(1));
      expect(await AppDatabase.getDeletedCompletedInstances(), hasLength(1));
    });

    test('恢复宠物完整恢复级联删除的提醒实例（事务顺序回归）', () async {
      await AppDatabase.insertPet(_pet('p1'));
      await AppDatabase.insertReminder(_reminder('r1', 'p1'));
      await AppDatabase.insertReminderInstance(_pending('i1', 'r1', no: 4));
      await AppDatabase.insertReminderInstance(_done('i2', 'r1', no: 3));
      await AppDatabase.softDeletePet('p1');

      await AppDatabase.restorePet('p1');

      expect(await AppDatabase.getAllPets(), hasLength(1));
      expect(await AppDatabase.getAllReminders(), hasLength(1));
      final pending = await AppDatabase.getPendingInstances();
      expect(pending, hasLength(1), reason: '级联删除的待办实例必须恢复');
      expect(pending.single.occurrenceNo, 4);
      expect(await AppDatabase.getCompletedInstances(), hasLength(1));
      expect(await AppDatabase.getDeletedPendingInstances(), isEmpty);
    });

    test('恢复宠物不复活“个体已删”的提醒与其实例', () async {
      await AppDatabase.insertPet(_pet('p1'));
      // r1：随宠物删除；r2：先被个体删除
      await AppDatabase.insertReminder(_reminder('r1', 'p1', title: '驱虫'));
      await AppDatabase.insertReminderInstance(_pending('i1', 'r1'));
      await AppDatabase.insertReminder(_reminder('r2', 'p1', title: '洗澡'));
      await AppDatabase.insertReminderInstance(_pending('i2', 'r2'));

      await AppDatabase.softDeleteReminder('r2');
      await AppDatabase.softDeletePet('p1');
      await AppDatabase.restorePet('p1');

      final reminders = await AppDatabase.getAllReminders();
      expect(reminders.map((r) => r.id).toSet(), {'r1'});
      final pending = await AppDatabase.getPendingInstances();
      expect(pending.map((e) => e.id).toSet(), {'i1'});
      // r2 仍留在最近删除里
      expect(
        (await AppDatabase.getDeletedPendingInstances())
            .map((e) => e.id)
            .toSet(),
        {'i2'},
      );
    });
  });

  group('统计与序号口径', () {
    test('待办卡片数按 DISTINCT 提醒统计，排除软删', () async {
      await AppDatabase.insertPet(_pet('p1'));
      await AppDatabase.insertReminder(_reminder('r1', 'p1'));
      await AppDatabase.insertReminderInstance(_pending('i1', 'r1', no: 1));
      await AppDatabase.insertReminderInstance(_pending('i2', 'r1', no: 2));
      await AppDatabase.insertReminder(_reminder('r2', 'p1', title: '洗澡'));
      await AppDatabase.insertReminderInstance(_pending('i3', 'r2'));

      // 同一提醒的两条待办只算 1 张卡
      expect(await AppDatabase.countPendingReminderCards(), 2);

      await AppDatabase.softDeleteReminder('r2');
      expect(await AppDatabase.countPendingReminderCards(), 1);

      await AppDatabase.softDeletePet('p1');
      expect(await AppDatabase.countPendingReminderCards(), 0);
    });

    test('序号计数包含软删记录，恢复后不会重号', () async {
      await AppDatabase.insertPet(_pet('p1'));
      await AppDatabase.insertReminder(_reminder('r1', 'p1'));
      await AppDatabase.insertReminderInstance(_done('i1', 'r1', no: 1));
      await AppDatabase.insertReminderInstance(_done('i2', 'r1', no: 2));
      expect(await AppDatabase.getNextOccurrenceNo('r1'), 3);

      await AppDatabase.deleteCompletedInstance('i2');

      expect(await AppDatabase.getNextOccurrenceNo('r1'), 3);
    });

    test('完成实例后待办卡片数随动（单次提醒完成后不再计入）', () async {
      await AppDatabase.insertPet(_pet('p1'));
      await AppDatabase.insertReminder(_reminder('r1', 'p1', repeating: false));
      await AppDatabase.insertReminderInstance(_pending('i1', 'r1'));
      expect(await AppDatabase.countPendingReminderCards(), 1);

      await AppDatabase.completeInstance('i1');

      expect(await AppDatabase.countPendingReminderCards(), 0);
      expect(await AppDatabase.getCompletedInstances(), hasLength(1));
    });
  });

  group('schema 基线', () {
    test('升级路径：V15 库以 V18 打开可幂等升级（补列 + 回填不报错）', () async {
      final dir = Directory.systemTemp.createTempSync('petdiary_mig');
      final path = p.join(dir.path, 'upgrade.db');
      addTearDown(() {
        AppDatabase.debugDatabasePathOverride = inMemoryDatabasePath;
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      });

      // 1) 先用当前代码建库，然后把 user_version 改回 15（模拟老库）
      AppDatabase.debugDatabasePathOverride = path;
      await AppDatabase.debugResetForTest();
      final db1 = await AppDatabase.instance;
      await db1.execute('PRAGMA user_version = 15');
      await AppDatabase.debugResetForTest();

      // 2) 再次打开 → 触发 onUpgrade(15 → 18)：迁移必须幂等（列已存在时跳过 ALTER）
      final db2 = await AppDatabase.instance;
      final cols = (await db2.rawQuery(
        'PRAGMA table_info(reminder_instances)',
      )).map((r) => r['name'] as String).toSet();
      expect(cols.contains('deleted_with_pet'), isTrue);
      expect(cols.contains('deleted_with_reminder'), isTrue);
      expect(await db2.getVersion(), 18);
    });

    test('VERSION=18 且实例表含 V15/V16/V17 三列、提醒表含 V18 用药两列', () async {
      expect(AppDatabase.VERSION, 18);
      final db = await AppDatabase.instance;
      final cols = (await db.rawQuery(
        'PRAGMA table_info(reminder_instances)',
      )).map((r) => r['name'] as String).toSet();
      expect(
        cols.containsAll({
          'occurrence_no',
          'is_deleted',
          'deleted_at',
          'deleted_with_pet',
          'deleted_with_reminder',
        }),
        isTrue,
      );
      final reminderCols = (await db.rawQuery(
        'PRAGMA table_info(reminders)',
      )).map((r) => r['name'] as String).toSet();
      expect(
        reminderCols.containsAll({'course_days', 'dose_times'}),
        isTrue,
        reason: 'V18 用药疗程两列',
      );
      final userVersion = await db.getVersion();
      expect(userVersion, 18);
    });
  });
}
