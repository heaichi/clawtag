import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_diary/core/database/app_database.dart';
import 'package:pet_diary/core/theme/app_theme.dart';
import 'package:pet_diary/screens/reminder_list_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 逾期汇总条 + 批量处理入口（C-i 配套）。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.debugDatabasePathOverride = inMemoryDatabasePath;
  });
  setUp(() async => AppDatabase.debugResetForTest());

  testWidgets('有逾期提醒时显示汇总条，点击进入选择模式并预选', (tester) async {
    await tester.runAsync(() async {
      await AppDatabase.insertPet(
        Pet(
          id: 'p1',
          name: '团团',
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
    });

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

    expect(find.text('1 个提醒已逾期'), findsOneWidget);
    expect(find.text('批量处理'), findsOneWidget);

    await tester.tap(find.text('批量处理'));
    await tester.pumpAndSettle();
    // 进入选择模式：标题变为「已选 N 项」
    expect(find.text('已选 1 项'), findsOneWidget);
  });
}
