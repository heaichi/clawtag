import 'package:flutter_test/flutter_test.dart';
import 'package:pet_diary/core/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// `saveReminderWithInstance`（事务化保存提醒 + 待办）回归测试。
///
/// 对应 docs/代码审计待办.md P1-8：编辑器原先 3 次独立写库，中途失败会把待办
/// 物理删掉且无法恢复；现在必须"要么全成、要么全不成"。
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

  Reminder reminder(String id, String petId, {bool repeating = true}) =>
      Reminder(
        id: id,
        petId: petId,
        title: '疫苗',
        type: 'vaccine',
        firstDueDate: DateTime(2026, 2, 1),
        repeatUnit: 'day',
        repeatInterval: 30,
        isRepeating: repeating,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  Future<void> addInstance(
    String id,
    String rid, {
    required int no,
    bool completed = false,
  }) => AppDatabase.insertReminderInstance(
    ReminderInstance(
      id: id,
      reminderId: rid,
      dueDate: DateTime(2026, 1, no.toDouble().toInt()),
      completed: completed,
      completedAt: completed ? DateTime(2026, 1, 2) : null,
      occurrenceNo: no,
      createdAt: DateTime(2026, 1, 1),
    ),
  );

  test('新建：实体与首条待办一起写入，序号为 1', () async {
    await pet('p1');
    final r = reminder('r1', 'p1', repeating: false);

    final saved = await AppDatabase.saveReminderWithInstance(
      reminder: r,
      isNew: true,
      instanceId: 'i1',
      instanceDueDate: DateTime(2026, 2, 1),
    );

    expect(saved.occurrenceNo, 1);
    expect(saved.nextOccurrenceNo, isNull);
    expect(await AppDatabase.getAllReminders(), hasLength(1));
    final pending = await AppDatabase.getPendingInstances();
    expect(pending, hasLength(1));
    expect(pending.single.id, 'i1');
    expect(pending.single.occurrenceNo, 1);
  });

  test('编辑：替换旧待办，序号沿用"删除后的 MAX+1"（与旧行为一致）', () async {
    await pet('p1');
    await AppDatabase.insertReminder(reminder('r1', 'p1'));
    await addInstance('h1', 'r1', no: 1, completed: true);
    await addInstance('h2', 'r1', no: 2, completed: true);
    await addInstance('old', 'r1', no: 3);

    final saved = await AppDatabase.saveReminderWithInstance(
      reminder: reminder('r1', 'p1'),
      isNew: false,
      instanceId: 'new',
      instanceDueDate: DateTime(2026, 3, 1),
    );

    expect(saved.occurrenceNo, 3, reason: '历史 1..2 保留，新待办接第 3 次');
    final pending = await AppDatabase.getPendingInstances();
    expect(pending, hasLength(1));
    expect(pending.single.id, 'new');
    // 历史不受影响
    expect(await AppDatabase.getCompletedInstances(), hasLength(2));
  });

  test('过期保存：实例直接进已完成，并补一条"下一次"', () async {
    await pet('p1');

    final saved = await AppDatabase.saveReminderWithInstance(
      reminder: reminder('r1', 'p1'),
      isNew: true,
      instanceId: 'past',
      instanceDueDate: DateTime(2026, 1, 1),
      completedAt: DateTime(2026, 1, 1),
      nextDueDate: DateTime(2026, 2, 1),
      nextInstanceId: 'next',
    );

    expect(saved.occurrenceNo, 1);
    expect(saved.nextOccurrenceNo, 2);
    expect(await AppDatabase.getCompletedInstances(), hasLength(1));
    final pending = await AppDatabase.getPendingInstances();
    expect(pending, hasLength(1));
    expect(pending.single.id, 'next');
    expect(pending.single.occurrenceNo, 2);
  });

  test('可显式指定「第几次」：实例按用户值编号，下一次自动 +1（新功能）', () async {
    await pet('p1');

    final saved = await AppDatabase.saveReminderWithInstance(
      reminder: reminder('r1', 'p1'),
      isNew: true,
      instanceId: 'i1',
      instanceDueDate: DateTime(2026, 9, 25),
      occurrenceNo: 3,
    );

    expect(saved.occurrenceNo, 3, reason: '用户选的「第几次」直接写库');
    final pending = await AppDatabase.getPendingInstances();
    expect(pending.single.id, 'i1');
    expect(pending.single.occurrenceNo, 3);
    expect(
      await AppDatabase.getNextOccurrenceNo('r1'),
      4,
      reason: '下一次自动 +1',
    );
  });

  test('编辑时改「第几次」：新待办按新值，历史编号不动', () async {
    await pet('p1');
    await AppDatabase.insertReminder(reminder('r1', 'p1'));
    await addInstance('h1', 'r1', no: 1, completed: true);
    await addInstance('h2', 'r1', no: 2, completed: true);
    await addInstance('old', 'r1', no: 3);

    final saved = await AppDatabase.saveReminderWithInstance(
      reminder: reminder('r1', 'p1'),
      isNew: false,
      instanceId: 'new',
      instanceDueDate: DateTime(2026, 9, 25),
      occurrenceNo: 5,
    );

    expect(saved.occurrenceNo, 5);
    final pending = await AppDatabase.getPendingInstances();
    expect(pending.single.occurrenceNo, 5);
    // 历史保持原编号
    final history = await AppDatabase.getCompletedInstances();
    expect(history.map((e) => e.occurrenceNo).toSet(), {1, 2});
  });

  test('原子性：写库中途失败（id 冲突）时整个事务回滚，旧待办仍在', () async {
    await pet('p1');
    await AppDatabase.insertReminder(reminder('r1', 'p1'));
    await addInstance('old', 'r1', no: 1);

    // nextInstanceId 与 instanceId 相同 → 第二条 insert 触发主键冲突
    await expectLater(
      AppDatabase.saveReminderWithInstance(
        reminder: reminder('r1', 'p1'),
        isNew: false,
        instanceId: 'dup',
        instanceDueDate: DateTime(2026, 3, 1),
        nextDueDate: DateTime(2026, 4, 1),
        nextInstanceId: 'dup',
      ),
      throwsA(isA<Exception>()),
    );

    final pending = await AppDatabase.getPendingInstances();
    expect(pending, hasLength(1), reason: 'P1-8：回滚后必须还是原来那条待办');
    expect(pending.single.id, 'old');
    expect(await AppDatabase.getAllReminders(), hasLength(1));
  });
}
