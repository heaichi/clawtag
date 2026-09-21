import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pet_diary/core/database/app_database.dart';
import 'package:pet_diary/widgets/dose_picker.dart';

/// 服药勾选弹层：今天/整个疗程视图、计数口径、勾选回调。

DateTime _d(int y, int m, int day, [int h = 9]) => DateTime(y, m, day, h);

Reminder _med({List<int> times = const [480, 840]}) => Reminder(
  id: 'm1',
  petId: 'p1',
  title: '阿莫西林',
  type: 'medicine',
  firstDueDate: _d(2026, 9, 21),
  courseDays: 15,
  doseTimes: times,
  createdAt: _d(2026, 9, 21),
  updatedAt: _d(2026, 9, 21),
);

ReminderInstance _dose(
  String id,
  DateTime due, {
  bool done = false,
  int no = 1,
}) => ReminderInstance(
  id: id,
  reminderId: 'm1',
  dueDate: due,
  completed: done,
  completedAt: done ? due : null,
  occurrenceNo: no,
  createdAt: due,
);

void main() {
  testWidgets('弹层渲染今天的服药时刻、计数与副标题', (tester) async {
    final instances = [
      _dose('a', _d(2026, 9, 21, 8), done: true, no: 1),
      _dose('b', _d(2026, 9, 21, 14), no: 2),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DosePickerSheet(
            reminder: _med(),
            petName: '团团',
            instances: instances,
            today: _d(2026, 9, 21),
            onComplete: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('08:00'), findsOneWidget);
    expect(find.text('14:00'), findsOneWidget);
    expect(find.text('今天 1/2'), findsOneWidget);
    expect(find.text('第 1/15 天 · 今日 1/2 次 · 下次 14:00'), findsOneWidget);
  });

  testWidgets('点未完成的一次 → 回调收到该实例与计划时刻，视图立刻变已完成', (tester) async {
    final instances = [_dose('b', _d(2026, 9, 21, 14))];
    final completed = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DosePickerSheet(
            reminder: _med(),
            petName: '团团',
            instances: instances,
            today: _d(2026, 9, 21),
            onComplete: (instance, at) async {
              completed.add(instance.id);
              expect(at, _d(2026, 9, 21, 14), reason: '完成时间用该次的计划时刻，而不是 now()');
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('14:00'));
    await tester.pumpAndSettle();
    expect(completed, ['b']);
    expect(find.text('今天 1/1'), findsOneWidget);
  });

  testWidgets('弹层右上角有「编辑」入口（用药卡片没有别的入口进编辑）', (tester) async {
    var edited = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DosePickerSheet(
            reminder: _med(),
            petName: '团团',
            instances: [_dose('a', _d(2026, 9, 21, 8), no: 1)],
            today: _d(2026, 9, 21),
            onComplete: (_, _) async {},
            onEdit: () => edited++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsOneWidget);
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(edited, 1);
  });

  testWidgets('切到「整个疗程」按天分组显示', (tester) async {
    final instances = [
      _dose('a', _d(2026, 9, 21, 8), done: true, no: 1),
      _dose('b', _d(2026, 9, 22, 8), no: 2),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DosePickerSheet(
            reminder: _med(),
            petName: '团团',
            instances: instances,
            today: _d(2026, 9, 21),
            onComplete: (_, _) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('整个疗程'));
    await tester.pumpAndSettle();
    expect(find.text('第 1 天'), findsOneWidget);
    expect(find.text('第 2 天'), findsOneWidget);
    expect(
      find.text('计划 30 次 · 已列出 2 次'),
      findsOneWidget,
      reason: '「计划」是疗程总次数，「已列出」是当前已有的实例数，两者不能混为一谈',
    );
  });
}
