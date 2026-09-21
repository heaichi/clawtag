import 'package:flutter_test/flutter_test.dart';
import 'package:pet_diary/core/database/app_database.dart';
import 'package:pet_diary/services/reminder_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 恢复后重排通知的行为（docs/代码审计待办.md P2-10）。
///
/// 过期实例原先一律被跳过：单次提醒会由提醒页自动完成（保持不变），
/// 但**重复提醒**会因此永远不再提醒。
///
/// 现在的策略（C-i，用户确认）：**不再顺延日期**（顺延会掩盖『漏做』），
/// 而是把通知设为『每天同一时刻重复』直到用户完成。
/// 本文件里的插件调用全部走降级分支（无插件 → 返回 false / 抛异常被 catch），
/// 因此只能断言 DB 侧结果：逾期日期**保持不变**。
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

  Reminder reminder(String id, {required bool repeating}) => Reminder(
    id: id,
    petId: 'p1',
    title: '疫苗',
    type: 'vaccine',
    firstDueDate: DateTime.now().subtract(const Duration(days: 10)),
    repeatUnit: repeating ? 'day' : 'once',
    repeatInterval: repeating ? 30 : 0,
    isRepeating: repeating,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );

  Future<void> expiredInstance(String id, String reminderId) =>
      AppDatabase.insertReminderInstance(
        ReminderInstance(
          id: id,
          reminderId: reminderId,
          dueDate: DateTime.now().subtract(const Duration(days: 3)),
          occurrenceNo: 4,
          createdAt: DateTime.now(),
        ),
      );

  test('过期的重复提醒不再顺延日期（保留逾期事实，靠每天提醒兜底）', () async {
    await pet('p1');
    final r = reminder('r1', repeating: true);
    await AppDatabase.insertReminder(r);
    await expiredInstance('i1', 'r1');

    await rescheduleReminderNotifications([r]);

    final inst = (await AppDatabase.getPendingInstances()).single;
    expect(
      inst.dueDate.isBefore(DateTime.now()),
      isTrue,
      reason: 'C-i：保持逾期事实，不再偷偷顺延日期',
    );
    expect(inst.occurrenceNo, 4, reason: '序号不变');
  });

  test('过期的单次提醒保持不动（由提醒页自动完成）', () async {
    await pet('p1');
    final r = reminder('r1', repeating: false);
    await AppDatabase.insertReminder(r);
    await expiredInstance('i1', 'r1');

    await rescheduleReminderNotifications([r]);

    final inst = (await AppDatabase.getPendingInstances()).single;
    expect(inst.dueDate.isBefore(DateTime.now()), isTrue, reason: '单次提醒不应被顺延');
  });

  test('未来时间的重复提醒不会被改写（幂等）', () async {
    await pet('p1');
    final r = reminder('r1', repeating: true);
    await AppDatabase.insertReminder(r);
    final future = DateTime.now().add(const Duration(days: 5));
    await AppDatabase.insertReminderInstance(
      ReminderInstance(
        id: 'i1',
        reminderId: 'r1',
        dueDate: future,
        occurrenceNo: 1,
        createdAt: DateTime.now(),
      ),
    );

    await rescheduleReminderNotifications([r]);

    final inst = (await AppDatabase.getPendingInstances()).single;
    // 库里按毫秒存储，比较到毫秒即可（DateTime.now() 带微秒，直接比对象会假失败）
    expect(
      inst.dueDate.millisecondsSinceEpoch,
      future.millisecondsSinceEpoch,
      reason: '未过期的待办不应被改动',
    );
  });
}
