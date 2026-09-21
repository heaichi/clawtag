import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clawtag/core/database/app_database.dart';
import 'package:clawtag/core/theme/app_theme.dart';
import 'package:clawtag/screens/reminder_list_screen.dart';
import 'package:clawtag/widgets/reminder_card.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 逾期项完成必须手动核对完成日期（第七十七轮）。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.debugDatabasePathOverride = inMemoryDatabasePath;
  });
  setUp(() async => AppDatabase.debugResetForTest());

  Future<void> seedOverdue() async {
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
    await AppDatabase.insertReminder(
      Reminder(
        id: 'r1',
        petId: 'p1',
        title: '狂犬疫苗',
        type: 'custom',
        firstDueDate: DateTime.now().subtract(const Duration(days: 13)),
        repeatInterval: 7,
        isRepeating: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    await AppDatabase.insertReminderInstance(
      ReminderInstance(
        id: 'i1',
        reminderId: 'r1',
        dueDate: DateTime.now().subtract(const Duration(days: 13)),
        occurrenceNo: 1,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const ReminderListScreen(),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('取消确认 → 不写库（仍是待办）', (tester) async {
    await tester.runAsync(seedOverdue);
    await pumpList(tester);

    await tester.drag(find.byType(ReminderCard).first, const Offset(400, 0));
    await tester.pumpAndSettle();
    // 弹窗标题与确认按钮同名，这里断言弹窗本身存在
    expect(find.byType(AlertDialog), findsOneWidget, reason: '逾期项完成必须弹确认');
    expect(find.text('取消'), findsOneWidget);
    expect(find.textContaining('已逾期'), findsWidgets);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final pending = await tester.runAsync(
      () => AppDatabase.getPendingInstances(),
    );
    expect(pending, hasLength(1), reason: '取消后不得写入完成');
  });

  test('completeInstance 可写入用户选定的完成时间（数据库层）', () async {
    await seedOverdue();
    final chosen = DateTime(2026, 9, 18, 10, 30);
    await AppDatabase.completeInstance('i1', completedAt: chosen);

    final completed = await AppDatabase.getCompletedInstances();
    expect(completed, hasLength(1));
    expect(completed.single.completedAt, chosen, reason: '完成时间用用户核对的日期');
    // 提醒的「上次执行日期」与实例完成时间保持一致
    final reminders = await AppDatabase.getAllReminders();
    expect(reminders.single.lastDoneDate, chosen);
  });
}
