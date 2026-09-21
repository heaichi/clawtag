import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clawtag/core/database/app_database.dart';
import 'package:clawtag/core/theme/app_theme.dart';
import 'package:clawtag/core/utils/care_records.dart';
import 'package:clawtag/services/reminder_service.dart';
import 'package:clawtag/widgets/reminder_history_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 提醒历史 / 护理记录的装配（docs/开发进度看板.md 第六十八轮）。
void main() {
  ReminderInstance inst(
    String id, {
    required int no,
    required DateTime due,
    bool completed = false,
    DateTime? completedAt,
    bool deleted = false,
    String reminderId = 'r1',
  }) => ReminderInstance(
    id: id,
    reminderId: reminderId,
    dueDate: due,
    completed: completed,
    completedAt: completedAt,
    occurrenceNo: no,
    createdAt: DateTime(2026, 1, 1),
    isDeleted: deleted,
  );

  group('buildReminderHistory（纯函数）', () {
    test('按第几次倒序返回，并保留完成状态', () {
      final records = buildReminderHistory(
        instances: [
          inst('i3', no: 3, due: DateTime(2026, 10, 20)),
          inst(
            'i2',
            no: 2,
            due: DateTime(2026, 9, 20),
            completed: true,
            completedAt: DateTime(2026, 9, 20, 9, 12),
          ),
          inst(
            'i1',
            no: 1,
            due: DateTime(2026, 8, 21),
            completed: true,
            completedAt: DateTime(2026, 8, 21, 9, 0),
          ),
        ],
      );
      expect(records.map((r) => r.occurrenceNo).toList(), [3, 2, 1]);
      expect(records.first.completed, isFalse);
      expect(records[1].completedAt, DateTime(2026, 9, 20, 9, 12));
    });

    test('上次执行日期与某条实例同一天 → 不补位（避免重复）', () {
      final records = buildReminderHistory(
        instances: [inst('i2', no: 2, due: DateTime(2026, 9, 20))],
        lastDoneDate: DateTime(2026, 9, 20, 18),
      );
      expect(records, hasLength(1));
      expect(records.single.fromLastDone, isFalse);
    });

    test('历史从第 2 次开始且有更早的上次执行日期 → 补一条第 1 次记录', () {
      final records = buildReminderHistory(
        instances: [inst('i2', no: 2, due: DateTime(2026, 9, 20))],
        lastDoneDate: DateTime(2026, 7, 20),
      );
      expect(records, hasLength(2));
      expect(records.last.occurrenceNo, 1);
      expect(records.last.fromLastDone, isTrue);
      expect(records.last.date, DateTime(2026, 7, 20));
    });

    test('已是第 1 次则不补位（否则重号）', () {
      final records = buildReminderHistory(
        instances: [inst('i1', no: 1, due: DateTime(2026, 9, 20))],
        lastDoneDate: DateTime(2026, 7, 20),
      );
      expect(records, hasLength(1));
    });

    test('没有实例但有上次执行日期 → 一条第 1 次记录', () {
      final records = buildReminderHistory(
        instances: const [],
        lastDoneDate: DateTime(2026, 7, 20),
      );
      expect(records, hasLength(1));
      expect(records.single.occurrenceNo, 1);
      expect(records.single.fromLastDone, isTrue);
    });

    test('没有实例也没有上次执行日期 → 空', () {
      expect(buildReminderHistory(instances: const []), isEmpty);
    });
  });

  group('getInstancesForReminder（数据库）', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      AppDatabase.debugDatabasePathOverride = inMemoryDatabasePath;
    });
    setUp(() async => AppDatabase.debugResetForTest());

    test('返回待办 + 已完成、按第几次倒序、排除已软删', () async {
      await AppDatabase.insertPet(
        Pet(
          id: 'p1',
          name: '咪咪',
          species: 'cat',
          meetDate: DateTime(2024, 1, 1),
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        ),
      );
      await AppDatabase.insertReminder(
        Reminder(
          id: 'r1',
          petId: 'p1',
          title: '驱虫',
          type: 'deworm',
          firstDueDate: DateTime(2026, 10, 20),
          repeatInterval: 30,
          isRepeating: true,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
      await AppDatabase.insertReminderInstance(
        inst('i1', no: 1, due: DateTime(2026, 8, 21), completed: true),
      );
      await AppDatabase.insertReminderInstance(
        inst('i2', no: 2, due: DateTime(2026, 9, 20), completed: true),
      );
      await AppDatabase.insertReminderInstance(
        inst('i3', no: 3, due: DateTime(2026, 10, 20)),
      );
      await AppDatabase.insertReminderInstance(
        inst('i9', no: 9, due: DateTime(2026, 12, 1), deleted: true),
      );

      final list = await AppDatabase.getInstancesForReminder('r1');
      expect(list.map((e) => e.occurrenceNo).toList(), [3, 2, 1]);
      expect(list.any((e) => e.id == 'i9'), isFalse, reason: '软删不进历史');
    });
  });

  group('编号全站唯一（第 4 步）', () {
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      AppDatabase.debugDatabasePathOverride = inMemoryDatabasePath;
    });
    setUp(() async => AppDatabase.debugResetForTest());

    test('不同宠物的同名提醒**不合并**（各自从第 1 次开始）', () async {
      Future<void> pet(String id) => AppDatabase.insertPet(
        Pet(
          id: id,
          name: '宠物$id',
          species: 'cat',
          meetDate: DateTime(2024, 1, 1),
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        ),
      );
      await pet('p1');
      await pet('p2');
      for (final pid in ['p1', 'p2']) {
        await AppDatabase.insertReminder(
          Reminder(
            id: 'r-$pid',
            petId: pid,
            title: '狂犬疫苗',
            type: 'custom',
            firstDueDate: DateTime(2026, 9, 20),
            repeatInterval: 30,
            isRepeating: true,
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
      }

      // 只给 p2 的提醒加一条实例：它的项目编号必须是 1（不能因为 p1 也有同名项目而变 2）
      await AppDatabase.insertReminderInstance(
        ReminderInstance(
          id: 'x1',
          reminderId: 'r-p2',
          dueDate: DateTime(2026, 9, 20),
          occurrenceNo: 1,
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      final inst = (await AppDatabase.getPendingInstances()).single;
      final no = await projectNumberForInstance(
        (await AppDatabase.getAllReminders())
            .firstWhere((r) => r.id == 'r-p2'),
        inst,
      );
      expect(no, 1, reason: '项目按宠物隔离，不能被别只宠物的同名项目顶到第 2 次');
    });

    test('projectNumberForInstance：同名项目的第二条提醒也拿到项目编号', () async {
      await AppDatabase.insertPet(
        Pet(
          id: 'p1',
          name: '四筒',
          species: 'cat',
          meetDate: DateTime(2024, 1, 1),
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime(2024, 1, 1),
        ),
      );
      Reminder rem(String id) => Reminder(
        id: id,
        petId: 'p1',
        title: '驱虫',
        type: 'deworm',
        firstDueDate: DateTime(2026, 1, 15),
        repeatInterval: 30,
        isRepeating: true,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await AppDatabase.insertReminder(rem('r1'));
      await AppDatabase.insertReminder(rem('r2'));
      await AppDatabase.insertReminderInstance(
        inst(
          'a1',
          no: 1,
          due: DateTime(2026, 1, 15),
          completed: true,
          reminderId: 'r1',
        ),
      );
      await AppDatabase.insertReminderInstance(
        inst(
          'b1',
          no: 1,
          due: DateTime(2026, 7, 20),
          reminderId: 'r2',
        ),
      );

      // 第二条提醒自己的编号是 1，但在项目时间线上它是第 2 次
      final b1 = (await AppDatabase.getPendingInstances()).single;
      expect(b1.occurrenceNo, 1);
      final projectNo = await projectNumberForInstance(rem('r2'), b1);
      expect(projectNo, 2, reason: '通知/卡片必须用项目编号（与护理记录一致）');
    });
  });

  group('ReminderHistorySheet（渲染）', () {
    testWidgets('列出第 N 次 / 日期 / 状态', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: ReminderHistorySheet(
              title: '驱虫',
              typeLabel: '驱虫（通用）',
              isRepeating: true,
              intervalDays: 30,
              records: buildReminderHistory(
                instances: [
                  inst('i3', no: 3, due: DateTime(2026, 10, 20)),
                  inst('i2', no: 2, due: DateTime(2026, 9, 20), completed: true),
                ],
                lastDoneDate: DateTime(2026, 7, 20),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('第 3 次'), findsOneWidget);
      expect(find.text('第 2 次'), findsOneWidget);
      expect(find.text('第 1 次'), findsOneWidget);
      expect(find.text('待办'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
      expect(find.text('记录'), findsOneWidget, reason: '上次执行日期补位行');
      expect(find.textContaining('计划每 30 天'), findsOneWidget);
    });

    testWidgets('没有记录时显示空态', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: ReminderHistorySheet(title: '疫苗', records: []),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('还没有任何记录'), findsOneWidget);
    });
  });

  group('一提醒多待办时取最先到期的那条（P2-11）', () {
    test('多条待办 → 取 dueDate 最早的一条', () {
      final map = earliestPendingByReminder([
        inst('late', no: 2, due: DateTime(2026, 10, 20)),
        inst('early', no: 1, due: DateTime(2026, 9, 7)),
        inst('mid', no: 3, due: DateTime(2026, 9, 20)),
      ]);
      expect(map['r1']!.id, 'early', reason: '先到期的才是下一次');
    });

    test('不同提醒互不影响', () {
      final map = earliestPendingByReminder([
        inst('a', no: 1, due: DateTime(2026, 9, 20)),
        inst('b', no: 1, due: DateTime(2026, 9, 1), reminderId: 'r2'),
      ]);
      expect(map.keys.toSet(), {'r1', 'r2'});
      expect(map['r2']!.id, 'b');
    });
  });

  group('有效日期与项目编号（第 1 步）', () {
    test('有效日期：已完成用完成时间，未完成用到期日', () {
      final done = CareRecord(
        occurrenceNo: 1,
        date: DateTime(2026, 9, 1),
        completed: true,
        completedAt: DateTime(2026, 9, 5),
      );
      final pending = CareRecord(
        occurrenceNo: 2,
        date: DateTime(2026, 9, 20),
        completed: false,
      );
      expect(done.effectiveDate, DateTime(2026, 9, 5));
      expect(pending.effectiveDate, DateTime(2026, 9, 20));
    });

    test('起始次数：最早实例的 occurrenceNo 往前回推补位行', () {
      final timeline = [
        CareRecord(
          occurrenceNo: 0,
          date: DateTime(2026, 7, 20),
          completed: true,
          fromLastDone: true,
        ),
        CareRecord(
          occurrenceNo: 6,
          date: DateTime(2026, 9, 20),
          completed: false,
        ),
      ];
      // 最早实例是第 6 次，但它在时间线第 2 位 → 起始次数 = 6 − 1 = 5
      expect(projectStartNumber(timeline), 5);
      final numbered = numberProjectTimeline(timeline);
      expect(numbered.map((r) => r.occurrenceNo).toList(), [5, 6]);
    });

    test('全部是补位行（无实例）→ 从 1 开始', () {
      final timeline = [
        CareRecord(
          occurrenceNo: 1,
          date: DateTime(2026, 7, 20),
          completed: true,
          fromLastDone: true,
        ),
      ];
      expect(numberProjectTimeline(timeline).single.occurrenceNo, 1);
    });

    test('用户从第 6 次开始记录 → 时间线编号 6、7、8', () {
      final timeline = [
        for (var i = 0; i < 3; i++)
          CareRecord(
            occurrenceNo: 6 + i,
            date: DateTime(2026, 1 + i, 1),
            completed: i < 2,
            completedAt: i < 2 ? DateTime(2026, 1 + i, 1) : null,
          ),
      ];
      final numbered = numberProjectTimeline(timeline);
      expect(numbered.map((r) => r.occurrenceNo).toList(), [6, 7, 8]);
    });
  });

  group('groupCareRecords（按项目名合并）', () {
    Reminder rem(String id, String title, {String type = 'deworm', DateTime? lastDone}) =>
        Reminder(
          id: id,
          petId: 'p1',
          title: title,
          type: type,
          firstDueDate: DateTime(2026, 1, 15),
          repeatInterval: 30,
          isRepeating: true,
          lastDoneDate: lastDone,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        );

    test('多条同名提醒合并成一个项目，时间线按时间重新编号 1..N', () {
      final groups = groupCareRecords(
        reminders: [rem('r1', '驱虫'), rem('r2', '驱虫')],
        instances: [
          inst(
            'a1',
            no: 1,
            due: DateTime(2026, 1, 15),
            completed: true,
            reminderId: 'r1',
          ),
          inst(
            'a2',
            no: 2,
            due: DateTime(2026, 4, 18),
            completed: true,
            reminderId: 'r1',
          ),
          inst(
            'b1',
            no: 1,
            due: DateTime(2026, 7, 20),
            completed: true,
            reminderId: 'r2',
          ),
        ],
      );

      expect(groups, hasLength(1), reason: '同名必须合并');
      final g = groups.single;
      expect(g.name, '驱虫');
      expect(g.records.map((r) => r.occurrenceNo).toList(), [1, 2, 3]);
      expect(g.records.last.date, DateTime(2026, 7, 20));
      expect(g.doneCount, 3);
    });

    test('不同名不合并', () {
      final groups = groupCareRecords(
        reminders: [rem('r1', '驱虫'), rem('r2', '疫苗', type: 'vaccine')],
        instances: const [],
      );
      expect(groups, hasLength(2));
    });

    test('名称去空格 + 忽略大小写后合并', () {
      final groups = groupCareRecords(
        reminders: [rem('r1', 'Deworm'), rem('r2', ' deworm ')],
        instances: const [],
      );
      expect(groups, hasLength(1));
      expect(groups.single.reminders, hasLength(2));
    });

    test('下次取最早的未完成；上次取最近的已完成', () {
      final groups = groupCareRecords(
        reminders: [rem('r1', '驱虫')],
        instances: [
          inst('a1', no: 1, due: DateTime(2026, 1, 15), completed: true),
          inst('a2', no: 2, due: DateTime(2026, 12, 1)),
          inst('a3', no: 3, due: DateTime(2026, 10, 20)),
        ],
      );
      final g = groups.single;
      expect(g.nextDue, DateTime(2026, 10, 20));
      expect(g.lastDone, DateTime(2026, 1, 15));
      expect(g.doneCount, 1);
    });

    test('有待办的组排在前面（按待办日期升序）', () {
      final groups = groupCareRecords(
        reminders: [rem('r1', '疫苗', type: 'vaccine'), rem('r2', '驱虫')],
        instances: [
          inst('v1', no: 1, due: DateTime(2026, 12, 1), reminderId: 'r1'),
          inst('d1', no: 1, due: DateTime(2026, 10, 20), reminderId: 'r2'),
        ],
      );
      expect(groups.map((g) => g.name).toList(), ['驱虫', '疫苗']);
    });

    test('带上次执行日期的提醒会在组内补一条记录行', () {
      final groups = groupCareRecords(
        reminders: [rem('r1', '驱虫', lastDone: DateTime(2026, 7, 20))],
        instances: [inst('a2', no: 2, due: DateTime(2026, 9, 20))],
      );
      final g = groups.single;
      expect(g.records, hasLength(2));
      expect(g.records.first.occurrenceNo, 1);
      expect(g.records.first.fromLastDone, isTrue);
      expect(g.doneCount, 1);
    });

    test('同名项目的组头类型优先取非自定义（图标更有信息量）', () {
      final groups = groupCareRecords(
        reminders: [
          rem('r1', '疫苗', type: 'custom'),
          rem('r2', '疫苗', type: 'vaccine'),
        ],
        instances: const [],
      );
      expect(groups, hasLength(1));
      expect(groups.single.type, 'vaccine');
    });
  });
}
