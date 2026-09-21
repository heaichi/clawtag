import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pet_diary/core/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 审计回归用例（2026-09-20 四个审计 agent 报告 + 主代理交叉验证）。
///
/// 这些用例**断言的是"修好之后应有的行为"**，当前全部标记 `skip`。
/// 修完 docs/代码审计待办.md 里对应条目后，去掉该条的 skip，让用例转绿。
///
/// 交叉验证方式：真实 SQLite 内存库执行与源码逐字相同的 SQL/调用链。

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.debugDatabasePathOverride = inMemoryDatabasePath;
  });
  setUp(() async => AppDatabase.debugResetForTest());

  Future<void> pet(String id) => AppDatabase.insertPet(
    Pet(
      id: id,
      name: '咪咪',
      species: 'cat',
      meetDate: DateTime(2024, 1, 1),
      createdAt: DateTime(2024, 1, 1),
      updatedAt: DateTime(2024, 1, 1),
    ),
  );

  Future<void> reminder(String id, String petId) => AppDatabase.insertReminder(
    Reminder(
      id: id,
      petId: petId,
      title: '疫苗',
      type: 'vaccine',
      firstDueDate: DateTime(2026, 1, 1),
      repeatUnit: 'day',
      repeatInterval: 30,
      isRepeating: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
  );

  Future<void> pending(
    String id,
    String rid, {
    int no = 1,
    DateTime? dueDate,
  }) => AppDatabase.insertReminderInstance(
    ReminderInstance(
      id: id,
      reminderId: rid,
      dueDate: dueDate ?? DateTime(2026, 2, 1),
      occurrenceNo: no,
      createdAt: DateTime(2026, 2, 1),
    ),
  );

  Future<void> done(String id, String rid, {int no = 1}) =>
      AppDatabase.insertReminderInstance(
        ReminderInstance(
          id: id,
          reminderId: rid,
          dueDate: DateTime(2026, 1, 1),
          completed: true,
          completedAt: DateTime(2026, 1, 2),
          occurrenceNo: no,
          createdAt: DateTime(2026, 1, 1),
        ),
      );

  test('P0 用陈旧对象（isDeleted=true）保存，不应把提醒重新写回已删除', () async {
    await pet('p1');
    await reminder('r1', 'p1');
    await done('i1', 'r1');
    await AppDatabase.deleteCompletedInstance('i1'); // 无活跃实例 → 实体联动软删
    final stale = (await AppDatabase.getDeletedReminders()).single;
    expect(stale.isDeleted, isTrue, reason: '前置条件：实体已被联动软删');

    await AppDatabase.restoreReminder('r1'); // 编辑器路径：先恢复
    await AppDatabase.updateReminder(stale.copyWith(title: '改标题')); // 但仍用旧对象保存

    final rows = await (await AppDatabase.instance).query(
      'reminders',
      where: 'id = ?',
      whereArgs: ['r1'],
    );
    expect(rows.single['is_deleted'], 0, reason: '保存后实体不应重新变成已删除（幽灵提醒）');
    expect(await AppDatabase.getAllReminders(), hasLength(1));
  }); // P0-1 已修复：updateReminder 不再写回 is_deleted

  test('P1 恢复宠物不应复活"用户个体删除"的完成记录', () async {
    await pet('p1');
    await reminder('r1', 'p1');
    await pending('i1', 'r1'); // 保持实体活跃
    await done('i2', 'r1', no: 1);
    await AppDatabase.deleteCompletedInstance('i2'); // 个体删除该条完成记录
    expect(await AppDatabase.getDeletedCompletedInstances(), hasLength(1));

    await AppDatabase.softDeletePet('p1');
    await AppDatabase.restorePet('p1');

    expect(
      await AppDatabase.getDeletedCompletedInstances(),
      hasLength(1),
      reason: 'P1：个体删除的记录应仍在最近删除，而不是被"恢复宠物"静默复活',
    );
  }); // P1-2 已修复：实例带 deleted_with_pet 标记，恢复宠物只还原级联删除的实例

  test('P1 随宠物删除的爪札被单独恢复后，应至少在一个列表可见', () async {
    await pet('p1');
    await AppDatabase.insertDiary(
      Diary(
        id: 'd1',
        petId: 'p1',
        title: 't',
        content: 'c',
        diaryDate: DateTime(2026, 1, 1),
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      ),
    );
    await AppDatabase.softDeletePet('p1');

    await AppDatabase.restoreDiary('d1'); // 最近删除里点"恢复"

    final inList = (await AppDatabase.getAllDiaries()).any((d) => d.id == 'd1');
    final inDeleted = (await AppDatabase.getDeletedDiaries()).any(
      (d) => d.id == 'd1',
    );
    expect(inList || inDeleted, isTrue, reason: 'P1：恢复后不应从所有列表消失（父级仍软删的分裂态）');
  }); // P1-3 已修复：restoreDiary 在父宠物仍软删时联动恢复宠物，并确保该爪札可见

  test('P2 V14 序号 off-by-one 会在升级时被就地修正（历史 1..n、待办 n+1）', () async {
    final dir = Directory.systemTemp.createTempSync('petdiary_p21');
    final path = p.join(dir.path, 'v14.db');
    addTearDown(() {
      AppDatabase.debugDatabasePathOverride = inMemoryDatabasePath;
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    // 1) 造出"V14 回填后"的错误编号（历史 2..n+1、待办 1），并标记为 V15 老库
    AppDatabase.debugDatabasePathOverride = path;
    await AppDatabase.debugResetForTest();
    await pet('p1');
    await reminder('r1', 'p1');
    await done('c1', 'r1', no: 1);
    await done('c2', 'r1', no: 2);
    await done('c3', 'r1', no: 3);
    await pending('w1', 'r1', no: 1);
    final db1 = await AppDatabase.instance;
    await db1.execute(
      "UPDATE reminder_instances SET completed_at = 100 WHERE id = 'c1'",
    );
    await db1.execute(
      "UPDATE reminder_instances SET completed_at = 200 WHERE id = 'c2'",
    );
    await db1.execute(
      "UPDATE reminder_instances SET completed_at = 300 WHERE id = 'c3'",
    );
    await db1.execute('''
      UPDATE reminder_instances SET occurrence_no = (
        SELECT COUNT(*) FROM reminder_instances AS ri2
        WHERE ri2.reminder_id = reminder_instances.reminder_id
          AND ri2.completed = 1 AND ri2.completed_at IS NOT NULL
          AND ri2.completed_at <= reminder_instances.completed_at
      ) + 1 WHERE completed = 1
    ''');
    final before = await db1.query(
      'reminder_instances',
      where: 'completed = 1',
      orderBy: 'completed_at ASC',
    );
    expect(
      before.map((r) => r['occurrence_no']).toList(),
      [2, 3, 4],
      reason: '前置：重现 V14 的 off-by-one',
    );
    await db1.execute('PRAGMA user_version = 15');
    await AppDatabase.debugResetForTest();

    // 2) 以 V16 重新打开 → 迁移应就地修正序号
    final db2 = await AppDatabase.instance;
    final completed = await db2.query(
      'reminder_instances',
      where: 'completed = 1',
      orderBy: 'completed_at ASC',
    );
    expect(
      completed.map((r) => r['occurrence_no']).toList(),
      [1, 2, 3],
      reason: 'P2：最早的完成记录应是第 1 次',
    );
    final pend = await db2.query('reminder_instances', where: 'completed = 0');
    expect(pend.single['occurrence_no'], 4, reason: 'P2：待办实例序号应为已完成条数 + 1');
  });

  test('P2 恢复提醒不应复活"用户在最近删除里单独删除"的完成记录', () async {
    await pet('p1');
    await reminder('r1', 'p1');
    await pending('i1', 'r1'); // 待办：会随提醒一起被删
    await done('c1', 'r1', no: 1);
    await done('c2', 'r1', no: 2);
    await AppDatabase.deleteCompletedInstance('c1'); // 个体删除该条完成记录
    await AppDatabase.softDeleteReminder('r1'); // 再删提醒（待办实例随之软删）
    expect(await AppDatabase.getDeletedCompletedInstances(), hasLength(1));

    await AppDatabase.restoreReminder('r1'); // 最近删除里恢复提醒

    final instances = await AppDatabase.getInstancesForReminder('r1');
    expect(
      instances.map((i) => i.id).toList(),
      unorderedEquals(['i1', 'c2']),
      reason: 'P2-2：随提醒删除的待办与历史完成记录应恢复，个体删除的完成记录不应被复活',
    );
    expect(
      await AppDatabase.getDeletedCompletedInstances(),
      hasLength(1),
      reason: 'P2-2：个体删除的完成记录必须仍留在最近删除，不能被恢复提醒静默吞掉',
    );
    final db = await AppDatabase.instance;
    final flags = await db.query(
      'reminder_instances',
      columns: ['is_deleted', 'deleted_with_reminder'],
      where: 'id = ?',
      whereArgs: ['c1'],
    );
    expect(flags.single['is_deleted'], 1);
    expect(flags.single['deleted_with_reminder'], 0);
  }); // P2-2 已修复：实例带 deleted_with_reminder 标记，恢复提醒只还原随提醒删除的实例

  test('P2 V16 老库升级到 V17：加列并回填"随提醒删除"标记（升级前后行为一致）', () async {
    final dir = Directory.systemTemp.createTempSync('petdiary_p22');
    final path = p.join(dir.path, 'v16.db');
    addTearDown(() {
      AppDatabase.debugDatabasePathOverride = inMemoryDatabasePath;
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    // 1) 造出"V16 库"：提醒下有 1 条待办（随提醒删除）、1 条随提醒删除的完成记录、
    //    1 条被用户个体删除的完成记录。
    AppDatabase.debugDatabasePathOverride = path;
    await AppDatabase.debugResetForTest();
    await pet('p1');
    await reminder('r1', 'p1');
    await pending('w1', 'r1', dueDate: DateTime(2026, 1, 20));
    await done('c1', 'r1', no: 1);
    await done('c2', 'r1', no: 2);
    final db1 = await AppDatabase.instance;
    // 实体没有 deleted_at 列："实体删除时刻"在生产代码里记在 updated_at
    await db1.update(
      'reminders',
      {'is_deleted': 1, 'deleted_with_pet': 0, 'updated_at': 5000},
      where: 'id = ?',
      whereArgs: ['r1'],
    );
    // 待办随提醒删除（V16 的 softDeleteReminder 行为：同一 nowMs() 删实体与实例）
    await db1.update(
      'reminder_instances',
      {
        'is_deleted': 1,
        'deleted_at': 5000,
        'deleted_with_pet': 0,
        'completed': 0,
      },
      where: 'id = ?',
      whereArgs: ['w1'],
    );
    // 随提醒删除的完成记录（同一时刻删除）
    await db1.update(
      'reminder_instances',
      {
        'is_deleted': 1,
        'deleted_at': 5000,
        'deleted_with_pet': 0,
        'completed': 1,
      },
      where: 'id = ?',
      whereArgs: ['c1'],
    );
    // 个体删除的完成记录：删除时刻**晚于**实体删除（这是它唯一可能的顺序）
    await db1.update(
      'reminder_instances',
      {
        'is_deleted': 1,
        'deleted_at': 9000,
        'deleted_with_pet': 0,
        'completed': 1,
      },
      where: 'id = ?',
      whereArgs: ['c2'],
    );
    await db1.execute('PRAGMA user_version = 16');
    await AppDatabase.debugResetForTest();

    // 2) 以 V17 重新打开 → 应加列并回填
    final db2 = await AppDatabase.instance;
    final cols = (await db2.rawQuery(
      'PRAGMA table_info(reminder_instances)',
    )).map((r) => r['name'] as String).toSet();
    expect(cols, contains('deleted_with_reminder'), reason: 'V17 应新增随提醒删除标记列');
    final rows = await db2.query(
      'reminder_instances',
      columns: ['id', 'deleted_with_reminder'],
    );
    expect(
      {for (final r in rows) r['id']: r['deleted_with_reminder']},
      {'w1': 1, 'c1': 1, 'c2': 0},
      reason: '回填：随提醒删除的实例（待办 / 同刻完成记录）标记 1，个体删除的完成记录保持 0',
    );

    // 3) 升级后恢复提醒：只有随提醒删除的实例回来，个体删除的那条留在最近删除
    await AppDatabase.restoreReminder('r1');
    final instances = await AppDatabase.getInstancesForReminder('r1');
    expect(instances.map((i) => i.id).toList(), unorderedEquals(['w1', 'c1']));
    expect(await AppDatabase.getDeletedCompletedInstances(), hasLength(1));
  }); // P2-2 迁移：V16 → V17（只增列 + 回填，升级前后恢复行为一致）
}
