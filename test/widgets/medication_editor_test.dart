import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clawtag/core/database/app_database.dart';
import 'package:clawtag/core/theme/app_theme.dart';
import 'package:clawtag/core/utils/medication_course.dart';
import 'package:clawtag/screens/reminder_editor_screen.dart';

/// 编辑器「用药疗程」输入区：表单校验 + 互斥项隐藏。

void main() {
  test('疗程校验：天数与时间点的边界', () {
    expect(
      validateMedicationCourse(courseDays: 15, doseTimes: const [540, 1260]),
      isNull,
    );
    expect(
      validateMedicationCourse(courseDays: 0, doseTimes: const [540]),
      isNotNull,
    );
    expect(
      validateMedicationCourse(courseDays: 400, doseTimes: const [540]),
      isNotNull,
    );
    expect(
      validateMedicationCourse(courseDays: 15, doseTimes: const []),
      isNotNull,
    );
    expect(
      validateMedicationCourse(courseDays: 15, doseTimes: const [540, 540]),
      isNotNull,
      reason: '同一时刻重复没有意义',
    );
  });

  test('一天 1 次也是合法疗程（心脏药这类每天一次的药）', () {
    expect(
      validateMedicationCourse(courseDays: 30, doseTimes: const [8 * 60]),
      isNull,
      reason: '一天 1 次必须能保存',
    );
    expect(
      validateMedicationCourse(
        courseDays: 7,
        doseTimes: const [8 * 60, 12 * 60, 16 * 60, 20 * 60],
      ),
      isNull,
      reason: '一天 4 次（抗生素）也必须能保存',
    );
  });

  testWidgets('打开「用药疗程」后：隐藏重复/间隔，出现次数·时间·天数输入', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const ReminderEditorScreen(
          initialPetId: 'p1',
          initialTitle: '阿莫西林',
          initialType: 'medicine',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('重复提醒'), findsOneWidget);
    expect(find.text('用药疗程'), findsOneWidget);

    // 表单较长，开关可能在视口外：先滚动到它再点（与既有编辑器用例同一写法）
    await tester.ensureVisible(find.text('用药疗程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用药疗程'));
    await tester.pumpAndSettle();

    expect(find.text('重复提醒'), findsNothing, reason: '用药与重复提醒互斥');
    expect(find.text('药品名称'), findsOneWidget, reason: '用药模式必须能填药名（原来没有输入框）');
    expect(find.text('每天次数'), findsOneWidget);
    expect(find.text('第 1 次时间'), findsOneWidget);
    expect(find.text('第 3 次时间'), findsNothing, reason: '默认 2 次，只出现 2 个时间点');
    expect(find.text('疗程天数'), findsOneWidget);
    expect(find.text('开始日期'), findsOneWidget, reason: '执行日期改称开始日期');
    expect(
      find.widgetWithText(TextField, '阿莫西林'),
      findsOneWidget,
      reason: '编辑已有用药时应回填药名',
    );
  });

  testWidgets('编辑用药：开始日期取疗程开始日，且不显示「第几次提醒」', (tester) async {
    final med = Reminder(
      id: 'm1',
      petId: 'p1',
      title: '阿莫西林',
      type: 'medicine',
      firstDueDate: DateTime(2026, 9, 19, 9),
      courseDays: 14,
      doseTimes: const [540, 1260],
      createdAt: DateTime(2026, 9, 19),
      updatedAt: DateTime(2026, 9, 19),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ReminderEditorScreen(reminder: med),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('2026/9/19'),
      findsOneWidget,
      reason: '开始日期必须是疗程第一天，不能是「下一次服药」那天',
    );
    expect(
      find.text('第几次提醒'),
      findsNothing,
      reason: '用药用「第几天第几次」表达，不显示普通提醒的序号',
    );
    expect(find.text('上次执行日期'), findsNothing);
    expect(find.text('药品名称'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, '阿莫西林'),
      findsOneWidget,
      reason: '药名要回填',
    );
    expect(find.text('2026/9/14'), findsNothing);
  });

  testWidgets('用药但不填药名 → 保存被拦下并内联提示（原来无处可填）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const ReminderEditorScreen(
          initialPetId: 'p1',
          initialType: 'medicine',
          // 故意不给 initialTitle：模拟用户没填药名
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('用药疗程'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('用药疗程'));
    await tester.pumpAndSettle();

    // 药名输入框必须存在（这是本轮修的 bug：必填却没有输入框）
    expect(find.text('药品名称'), findsOneWidget);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(
      find.text('请填写药品名称'),
      findsOneWidget,
      reason: '药名为空时必须拦下保存，并给出可点击填写的内联提示',
    );
  });
}
