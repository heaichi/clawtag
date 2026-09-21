import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clawtag/widgets/care_record_row.dart';
import 'package:clawtag/core/theme/app_theme.dart';
import 'package:clawtag/core/utils/care_records.dart';
import 'package:clawtag/core/utils/formatters.dart';
import 'package:clawtag/screens/reminder_editor_screen.dart';
import 'package:clawtag/widgets/reminder_card.dart';

/// 待办相对时间与默认执行日期（本轮逻辑修正的回归锁）。
void main() {
  group('reminderRelativeLabel', () {
    final now = DateTime(2026, 9, 20, 19, 30);

    test('过期 → 已逾期 N 天（不能显示今天提醒）', () {
      expect(
        reminderRelativeLabel(DateTime(2026, 9, 7), now: now),
        '已逾期 13 天',
      );
    });

    test('今天 → 今天提醒', () {
      expect(
        reminderRelativeLabel(DateTime(2026, 9, 20, 9), now: now),
        '今天提醒',
      );
    });

    test('未来 → N 天后提醒', () {
      expect(
        reminderRelativeLabel(DateTime(2026, 10, 1), now: now),
        '11天后提醒',
      );
    });
  });

  group('overdueDaysFor', () {
    final now = DateTime(2026, 9, 20, 19, 30);

    test('未来/今天 → 0（不算逾期）', () {
      expect(overdueDaysFor(DateTime(2026, 9, 20, 9), now: now), 0);
      expect(overdueDaysFor(DateTime(2026, 10, 1), now: now), 0);
    });

    test('过去的第 N 天 → N', () {
      expect(overdueDaysFor(DateTime(2026, 9, 7), now: now), 13);
    });
  });

  group('CareStatusChip（已过去但未完成 → 已逾期，不写待办）', () {
    Future<void> pumpChip(WidgetTester tester, CareRecord record) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(body: CareStatusChip(record: record)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('过去的未完成 → 已逾期 N 天', (tester) async {
      final due = DateTime.now().subtract(const Duration(days: 13));
      await pumpChip(
        tester,
        CareRecord(occurrenceNo: 1, date: due, completed: false),
      );
      expect(find.text('已逾期 13 天'), findsOneWidget);
      expect(find.text('待办'), findsNothing);
    });

    testWidgets('未来的未完成 → 待办', (tester) async {
      final due = DateTime.now().add(const Duration(days: 5));
      await pumpChip(
        tester,
        CareRecord(occurrenceNo: 1, date: due, completed: false),
      );
      expect(find.text('待办'), findsOneWidget);
    });

    testWidgets('已完成 → 已完成', (tester) async {
      await pumpChip(
        tester,
        CareRecord(
          occurrenceNo: 1,
          date: DateTime.now(),
          completed: true,
        ),
      );
      expect(find.text('已完成'), findsOneWidget);
    });
  });

  group('defaultExecDateFor', () {
    test('通知时刻还没过 → 今天', () {
      expect(
        defaultExecDateFor(
          hour: 9,
          minute: 0,
          now: DateTime(2026, 9, 20, 8, 30),
        ),
        DateTime(2026, 9, 20, 9, 0),
      );
    });

    test('通知时刻已过 → 明天（避免一进页面就报已过期）', () {
      expect(
        defaultExecDateFor(
          hour: 9,
          minute: 0,
          now: DateTime(2026, 9, 20, 19, 30),
        ),
        DateTime(2026, 9, 21, 9, 0),
      );
    });
  });
}
