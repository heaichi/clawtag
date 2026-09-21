import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clawtag/core/database/app_database.dart';
import 'package:clawtag/core/utils/medication_course.dart';
import 'package:clawtag/core/theme/app_theme.dart';
import 'package:clawtag/screens/reminder_list_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 提醒页的用药卡片与服药弹层（屏幕级用例）。
///
/// 覆盖「看得见 / 点得着」：卡片副标题口径、顶部待喂药提示、点卡片开弹层、勾选后列表刷新。

DateTime _d(int y, int m, int day, [int h = 9]) => DateTime(y, m, day, h);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.debugDatabasePathOverride = inMemoryDatabasePath;
  });
  setUp(() async => AppDatabase.debugResetForTest());

  Future<Reminder> seedCourse() async {
    // 说明：下面所有断言都用「同一批实例 + 纯函数」推出期望文案，
    // 而不是写死 08:00/20:00 —— 否则用例会随运行时刻（是否已过 08:00）而抖动。
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    await AppDatabase.insertPet(
      Pet(
        id: 'p1',
        name: '四筒',
        species: 'cat',
        meetDate: _d(2024, 1, 1),
        createdAt: _d(2024, 1, 1),
        updatedAt: _d(2024, 1, 1),
      ),
    );
    final reminder = Reminder(
      id: 'm1',
      petId: 'p1',
      title: '阿莫西林',
      type: 'medicine',
      firstDueDate: DateTime(today.year, today.month, today.day, 8),
      courseDays: 3,
      doseTimes: const [8 * 60, 20 * 60],
      createdAt: now,
      updatedAt: now,
    );
    final plan = expandDoseTimes(
      courseStart: reminder.firstDueDate,
      courseDays: 3,
      doseTimes: reminder.doseTimes,
    );
    await AppDatabase.saveMedicationCourse(
      reminder: reminder,
      isNew: true,
      doses: [
        for (var i = 0; i < plan.length; i++)
          (id: 'dose$i', dueDate: plan[i], occurrenceNo: i + 1),
      ],
    );
    return reminder;
  }

  Future<void> pumpList(WidgetTester tester) async {
    await tester.runAsync(() async {});
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const ReminderListScreen()),
    );
    // 真实数据库 I/O 必须放行真实异步（runAsync），fake-async 下永不返回
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
  }

  testWidgets('用药卡片：副标题与顶部待喂药提示都与纯函数同口径', (tester) async {
    await tester.runAsync(seedCourse);
    await pumpList(tester);

    final reminder = (await tester.runAsync(
      () => AppDatabase.getAllReminders(),
    ))!.single;
    final instances = (await tester.runAsync(
      () => AppDatabase.getInstanceHistoryForReminder('m1'),
    ))!;

    // 精确副标题用纯函数现算（避免「是否已过 08:00」让用例随运行时刻抖动）
    expect(
      find.text(courseCardSubtitle(reminder: reminder, instances: instances)),
      findsOneWidget,
      reason: '卡片必须显示与数据库同一口径的用药文案',
    );

    final summary = courseSummary(reminder: reminder, instances: instances);
    expect(
      find.textContaining('第 ${summary.dayNumber}/3 天'),
      findsOneWidget,
      reason: '第 N/3 天 必须与 courseSummary 一致',
    );
    // 顶部提示条：N = 今日剩余 + 今天之前漏掉的；**不能**写成「今天还需喂药 N 次」
    final total = summary.remainingToday + summary.todayMissed;
    expect(
      find.text('还有 $total 次没喂'),
      findsOneWidget,
      reason: '数字必须等于「今日剩余 + 之前漏服」，且文案不能自称全是今天的',
    );
    if (summary.todayMissed > 0) {
      expect(
        find.text('含 ${summary.todayMissed} 次逾期（点开可补记）'),
        findsOneWidget,
        reason: '有漏服时要把构成说清楚',
      );
    }
  });

  testWidgets('点卡片开弹层 → 勾一次 → 弹层与列表副标题同步变 1/2', (tester) async {
    await tester.runAsync(seedCourse);
    await pumpList(tester);

    final reminder = (await tester.runAsync(
      () => AppDatabase.getAllReminders(),
    ))!.single;
    var instances = (await tester.runAsync(
      () => AppDatabase.getInstanceHistoryForReminder('m1'),
    ))!;
    final today = DateTime.now();
    var summary = courseSummary(
      reminder: reminder,
      instances: instances,
      now: today,
    );

    // 点卡片 → 服药弹层
    await tester.tap(find.text('阿莫西林'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('今天 ${summary.todayDone}/${summary.todayTotal}'),
      findsOneWidget,
      reason: '弹层计数与 courseSummary 同口径',
    );
    expect(find.text('08:00'), findsOneWidget);

    // 勾掉 08:00 那一次（写库 + 取消通知 + 窗口重排都在 runAsync 里跑）
    await tester.runAsync(() async {
      await tester.tap(find.text('08:00'));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    instances = (await tester.runAsync(
      () => AppDatabase.getInstanceHistoryForReminder('m1'),
    ))!;
    summary = courseSummary(
      reminder: reminder,
      instances: instances,
      now: today,
    );
    expect(summary.todayDone, 1, reason: '勾选必须真的写进库');
    expect(
      find.text('今天 ${summary.todayDone}/${summary.todayTotal}'),
      findsOneWidget,
      reason: '勾选后弹层计数立刻更新',
    );

    // 关弹层 → 列表重载 → 卡片副标题同步
    await tester.runAsync(() async {
      Navigator.of(tester.element(find.textContaining('今天 '))).pop();
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text(courseCardSubtitle(reminder: reminder, instances: instances)),
      findsOneWidget,
    );
  });
}
