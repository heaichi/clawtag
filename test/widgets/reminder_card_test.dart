import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_diary/core/database/app_database.dart';
import 'package:pet_diary/core/theme/app_theme.dart';
import 'package:pet_diary/widgets/reminder_card.dart';

void main() {
  final reminder = Reminder(
    id: 'r1',
    petId: 'p1',
    title: '驱虫',
    type: 'deworm',
    firstDueDate: DateTime(2026, 9, 20, 9),
    repeatInterval: 30,
    isRepeating: true,
    notificationTime: '09:00',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  testWidgets('卡片内的「历史记录」可点并回调（不再用右侧悬浮图标）', (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: ReminderCard(
            reminder: reminder,
            petName: '团团',
            dueDate: DateTime(2026, 9, 20, 9),
            onHistory: () => tapped++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('历史记录'), findsOneWidget);
    expect(find.text('团团'), findsOneWidget);
    await tester.tap(find.text('历史记录'));
    expect(tapped, 1);
  });


  testWidgets('超长宠物名 + 超长类型名：不溢出，且「第N次」仍可见（②）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: ReminderCard(
              reminder: Reminder(
                id: 'r2',
                petId: 'p1',
                title: '每三个月一次的体内外驱虫与心脏彩超复查',
                type: 'deworm',
                firstDueDate: DateTime(2026, 9, 20, 9),
                repeatInterval: 30,
                isRepeating: true,
                notificationTime: '09:00',
                createdAt: DateTime(2026, 1, 1),
                updatedAt: DateTime(2026, 1, 1),
              ),
              petName: '我家的大橘猫叫小橘子',
              dueDate: DateTime(2026, 9, 7, 9),
              occurrenceLabel: '第2次',
              onHistory: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 不溢出（Debug 下溢出会抛异常）
    expect(tester.takeException(), isNull);
    // 序号固定尾部：即使类型名被省略也还在
    expect(find.text('第2次'), findsOneWidget);
    // 长宠物名被限宽省略（约 6 字），但 Tooltip 仍保留全名
    expect(find.text('我家的大橘猫叫小橘子'), findsOneWidget);
  });
}
