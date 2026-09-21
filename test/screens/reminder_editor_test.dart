import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clawtag/core/database/app_database.dart';
import 'package:clawtag/core/theme/app_theme.dart';
import 'package:clawtag/core/utils/formatters.dart';
import 'package:clawtag/screens/reminder_editor_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 提醒编辑器「第几次提醒 / 执行日期 / 上次执行日期」的显隐与联动（新功能）。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.debugDatabasePathOverride = inMemoryDatabasePath;
  });
  setUp(() async {
    await AppDatabase.debugResetForTest();
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
  });

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const ReminderEditorScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('第 1 次隐藏「上次执行日期」，切到第 3 次后出现', (tester) async {
    await pumpEditor(tester);

    expect(find.text('第几次提醒'), findsOneWidget);
    expect(find.text('第 1 次'), findsOneWidget);
    expect(find.text('执行日期'), findsOneWidget);
    expect(find.text('上次执行日期'), findsNothing, reason: '首次没有上一次');

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    expect(find.text('第 2 次'), findsOneWidget);
    expect(find.text('上次执行日期'), findsOneWidget, reason: '第 2 次起显示');

    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    expect(find.text('第 3 次'), findsOneWidget);

    // 再点「-」回到第 1 次 → 又隐藏
    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.remove_circle_outline));
    await tester.pump();
    expect(find.text('第 1 次'), findsOneWidget);
    expect(find.text('上次执行日期'), findsNothing);
  });

  testWidgets('关闭重复时隐藏「天后提醒」与「第 N+1 次提醒时间」', (tester) async {
    await pumpEditor(tester);

    expect(find.text('天后提醒'), findsNothing, reason: '单次提醒没有下一次');
    expect(find.textContaining('次提醒时间 ='), findsNothing);

    // 表单较长，先滚动到开关再点（否则 off-screen 无法命中）
    await tester.ensureVisible(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();

    expect(find.text('天后提醒'), findsOneWidget);
    expect(find.textContaining('次提醒时间 ='), findsOneWidget);
    expect(find.text('第 2 次提醒时间'), findsOneWidget);
  });

  testWidgets('重复提醒：改间隔不动执行日期（事实与计划分离）', (tester) async {
    await pumpEditor(tester);

    // 第 2 次 → 出现「上次执行日期」
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();

    // 默认执行日期 = 下一个还没过的通知时刻（今天或明天），随当前时间而定
    final defaultExec = defaultExecDateFor(hour: 9, minute: 0);
    final execText = dateFormatCompact.format(defaultExec);
    expect(find.text(execText), findsOneWidget, reason: '执行日期 = 下一个未过的 09:00');

    // 打开重复，才能改「天后提醒」
    await tester.ensureVisible(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();

    // 把间隔改成 10 天（间隔输入框是最后一个 TextFormField）
    final intervalField = find.byType(TextFormField).last;
    await tester.ensureVisible(intervalField);
    await tester.pumpAndSettle();
    await tester.enterText(intervalField, '10');
    await tester.pumpAndSettle();

    // 事实与计划分离：改「间隔天数」不影响执行日期，也不影响上次执行日期的记录
    expect(find.text(execText), findsOneWidget, reason: '改间隔不动执行日期');
    expect(
      find.text('未设置（点选）'),
      findsOneWidget,
      reason: '记录不受计划影响（没设过就一直是未设置）',
    );
  });

  testWidgets('单次提醒不提示「完成后自动第 N+1 次」（A）', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();

    expect(find.text('第 2 次'), findsOneWidget);
    expect(find.text('仅提醒一次'), findsOneWidget, reason: '单次没有下一次');
    expect(find.textContaining('完成后自动第'), findsNothing);
  });

  testWidgets('上次执行日期默认「未设置」（不捏造），给了真实日期才显示 N 天前', (tester) async {
    // 没有真实的上一次 → 留空（用户报的场景：第 1 次都还没做，哪来的上次执行日期）
    await pumpEditor(tester);
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    expect(find.text('上次执行日期'), findsOneWidget);
    expect(find.text('仅作记录，不影响执行日期'), findsOneWidget);
    expect(find.text('未设置（点选）'), findsOneWidget);
    expect(find.textContaining('天前'), findsNothing);

    // 打开重复：记录语义不变，只是次数提示变成『完成后自动第 3 次』
    await tester.ensureVisible(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    expect(find.text('仅作记录，不影响执行日期'), findsOneWidget);
    expect(find.text('完成后自动第 3 次'), findsOneWidget);
    expect(find.text('未设置（点选）'), findsOneWidget);
  });

  testWidgets('带真实上次执行日期（预填）时显示距执行日期多少天', (tester) async {
    // 与编辑器默认执行日期同基准，保证差值恰好 5 天
    final lastDone = defaultExecDateFor(
      hour: 9,
      minute: 0,
    ).subtract(const Duration(days: 5));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ReminderEditorScreen(
          initialPetId: 'p1',
          initialOccurrenceNo: 2,
          initialLastDoneDate: lastDone,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('5 天前'), findsOneWidget);
    expect(find.text('未设置（点选）'), findsNothing);
  });

  group('说明文字（纯函数，覆盖 A/B①/E 语义）', () {
    test('首次 → 首次提醒', () {
      expect(
        reminderOccurrenceHint(occurrenceNo: 1, repeating: false, historyNos: {}),
        '首次提醒',
      );
    });

    test('单次第 2 次 → 仅提醒一次（不能写自动第 3 次）', () {
      expect(
        reminderOccurrenceHint(occurrenceNo: 2, repeating: false, historyNos: {}),
        '仅提醒一次',
      );
    });

    test('重复第 2 次 → 完成后自动第 3 次', () {
      expect(
        reminderOccurrenceHint(occurrenceNo: 2, repeating: true, historyNos: {}),
        '完成后自动第 3 次',
      );
    });

    test('与已完成历史撞车 → 提示已有该次记录', () {
      expect(
        reminderOccurrenceHint(
          occurrenceNo: 2,
          repeating: true,
          historyNos: {1, 2},
        ),
        '已有第 2 次记录',
      );
    });
  });

  testWidgets('从护理记录新建：继承项目设置，上次执行日期没有就不捏造', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const ReminderEditorScreen(
          initialPetId: 'p1',
          initialTitle: '狂犬疫苗',
          initialType: 'custom',
          initialOccurrenceNo: 2,
          initialIntervalDays: 7,
          initialIsRepeating: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('狂犬疫苗'), findsWidgets, reason: '类型与标题都应是项目名');
    expect(find.text('第 2 次'), findsOneWidget, reason: '第几次 = 已有记录数 + 1');
    expect(
      find.text('未设置（点选）'),
      findsOneWidget,
      reason: '项目没有已完成的记录 → 上次执行日期留空，不按间隔捏造',
    );
  });

  group('类型显示文案（纯函数）', () {
    test('自定义 + 有标题 → 显示用户写的标题', () {
      expect(reminderTypeDisplayLabel('custom', '狂犬疫苗'), '狂犬疫苗');
    });

    test('自定义 + 空标题 → 回退「自定义」', () {
      expect(reminderTypeDisplayLabel('custom', '   '), '自定义');
    });

    test('内置类型 → 显示类型名（与标题无关）', () {
      expect(reminderTypeDisplayLabel('vaccine', '随便写的'), '疫苗');
    });
  });

  group('间隔与日期的独立关系（纯函数）', () {
    test('cadenceDaysBetween 按日期差、忽略时分', () {
      expect(
        cadenceDaysBetween(
          lastDoneDate: DateTime(2026, 8, 21, 18),
          execDate: DateTime(2026, 9, 20, 9),
        ),
        30,
      );
    });

    test('用户场景：上次 7/20、本次 9/20（隔 62 天），计划间隔 30 → 第 3 次 = 10/20', () {
      final exec = DateTime(2026, 9, 20, 9, 0);
      final last = DateTime(2026, 7, 20);
      // 实际间隔确实是 62 天（记录用）
      expect(
        cadenceDaysBetween(lastDoneDate: last, execDate: exec),
        62,
      );
      // 但计划间隔与它无关：第 3 次按执行日期 + 30 天
      expect(
        nextReminderPreview(
          execDate: exec,
          intervalDays: 30,
          hour: 9,
          minute: 0,
          now: DateTime(2026, 9, 20, 8),
        ),
        DateTime(2026, 10, 20, 9, 0),
        reason: '计划间隔 30 天，与 62 天的实际间隔无关',
      );
    });

    test('执行日期已过 → 按今天 + 间隔预览（与保存一致）', () {
      expect(
        nextReminderPreview(
          execDate: DateTime(2026, 6, 1),
          intervalDays: 30,
          hour: 9,
          minute: 0,
          now: DateTime(2026, 9, 20, 8),
        ),
        DateTime(2026, 10, 20, 9, 0),
      );
    });
  });

  group('距执行日期说明（纯函数）', () {
    test('过了 30 天 → 30 天前', () {
      expect(
        lastDoneGapHintText(
          lastDoneDate: DateTime(2026, 8, 21),
          execDate: DateTime(2026, 9, 20),
        ),
        '30 天前',
      );
    });

    test('同一天 → 同一天（按日期比较，忽略时分）', () {
      expect(
        lastDoneGapHintText(
          lastDoneDate: DateTime(2026, 9, 20, 18),
          execDate: DateTime(2026, 9, 20, 9),
        ),
        '同一天',
      );
    });

    test('上次晚于执行日期 → 明确提示而不是负数', () {
      expect(
        lastDoneGapHintText(
          lastDoneDate: DateTime(2026, 10, 1),
          execDate: DateTime(2026, 9, 20),
        ),
        '晚于执行日期 11 天',
      );
    });
  });

  testWidgets('单次提醒：上次执行日期可改，并显示距执行日期多少天', (tester) async {
    await pumpEditor(tester);
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();

    expect(find.text('上次执行日期'), findsOneWidget, reason: '单次也可手动改');
    expect(
      find.text('未设置（点选）'),
      findsOneWidget,
      reason: '没设过就留空，由用户点选真实日期',
    );
  });
}
