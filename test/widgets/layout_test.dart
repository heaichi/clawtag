import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clawtag/core/database/app_database.dart';
import 'package:clawtag/core/theme/app_theme.dart';
import 'package:clawtag/widgets/diary_card.dart';
import 'package:clawtag/widgets/empty_state.dart';
import 'package:clawtag/widgets/pet_card.dart';
import 'package:clawtag/widgets/reminder_card.dart';

/// 关键卡片的“尺寸 / 深色模式”适配回归：
/// 在多种机宽下渲染，任何 RenderFlex overflow 都会让用例失败，
/// 等价于自动检查 UI 是否撑破布局。

const _sizes = <String, Size>{
  '小屏 360': Size(360, 800),
  '常规 411': Size(411, 900),
  '大屏 480': Size(480, 1000),
};

Future<void> _pumpCard(
  WidgetTester tester,
  Widget card, {
  required Size size,
  required Brightness brightness,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      home: Scaffold(
        // 纵向可滚（不把“内容高”当溢出），横向锁死在机宽，专门查宽度适配。
        body: SingleChildScrollView(
          child: SizedBox(width: size.width, child: card),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _expectNoOverflow(WidgetTester tester, String label) {
  expect(tester.takeException(), isNull, reason: '$label 出现渲染异常/溢出');
}

Pet _pet() => Pet(
  id: 'p1',
  name: '咪咪是个很长很长的猫咪名字',
  species: 'cat',
  breed: '英国短毛猫（金渐层）',
  birthDate: DateTime(2020, 3, 1),
  meetDate: DateTime(2021, 5, 1),
  notes: '很长的备注'.padRight(80, '长'),
  currentWeightKg: 4.2,
  createdAt: DateTime(2024, 1, 1),
  updatedAt: DateTime(2024, 1, 1),
);

Diary _diary() => Diary(
  id: 'd1',
  petId: 'p1',
  title: '今天第一次带它去打疫苗',
  content: '内容'.padRight(120, '字'),
  mood: 'happy',
  weather: 'sunny',
  diaryDate: DateTime(2026, 1, 1),
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

Reminder _reminder({bool repeating = true}) => Reminder(
  id: 'r1',
  petId: 'p1',
  title: '体外驱虫（第 12 次）',
  type: 'deworm_external',
  firstDueDate: DateTime(2026, 2, 1),
  repeatUnit: repeating ? 'day' : 'once',
  repeatInterval: repeating ? 30 : 0,
  isRepeating: repeating,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  for (final entry in _sizes.entries) {
    final label = entry.key;
    final size = entry.value;

    for (final brightness in Brightness.values) {
      final mode = brightness == Brightness.dark ? '深色' : '浅色';

      testWidgets('宠物卡片 $label / $mode 不溢出', (tester) async {
        await _pumpCard(
          tester,
          PetCard(pet: _pet(), diaryCount: 12, onTap: () {}),
          size: size,
          brightness: brightness,
        );
        _expectNoOverflow(tester, 'PetCard $label $mode');
        expect(find.textContaining('咪咪'), findsOneWidget);
      });

      testWidgets('爪札卡片 $label / $mode 不溢出', (tester) async {
        await _pumpCard(
          tester,
          DiaryCard(
            diary: _diary(),
            petName: '咪咪是个很长很长的猫咪名字',
            tags: [
              Tag(id: 't1', name: '疫苗', createdAt: DateTime(2026)),
              Tag(id: 't2', name: '第一次', createdAt: DateTime(2026)),
            ],
            onTap: () {},
          ),
          size: size,
          brightness: brightness,
        );
        _expectNoOverflow(tester, 'DiaryCard $label $mode');
        expect(find.textContaining('疫苗'), findsWidgets);
      });

      testWidgets('用药卡片 $label / $mode 不溢出', (tester) async {
        final medication = Reminder(
          id: 'm1',
          petId: 'p1',
          title: '阿莫西林克拉维酸钾干混悬剂（儿童用）',
          type: 'medicine',
          firstDueDate: DateTime(2026, 9, 21, 9),
          courseDays: 15,
          doseTimes: const [480, 840, 1200],
          createdAt: DateTime(2026, 9, 21),
          updatedAt: DateTime(2026, 9, 21),
        );
        await _pumpCard(
          tester,
          ReminderCard(
            reminder: medication,
            petName: '咪咪是个很长很长的猫咪名字',
            subtitleOverride: '第 14/15 天 · 今日 2/3 次 · 下次 20:00 · 漏 3 次',
            pendingDoses: () => const [],
            onHistory: () {},
            onTap: () {},
          ),
          size: size,
          brightness: brightness,
        );
        _expectNoOverflow(tester, '用药卡片 $label $mode');
        expect(find.textContaining('阿莫西林'), findsOneWidget);
      });

      testWidgets('提醒卡片 $label / $mode 不溢出', (tester) async {
        await _pumpCard(
          tester,
          ReminderCard(
            reminder: _reminder(),
            petName: '咪咪',
            dueDate: DateTime(2026, 2, 1, 9),
            occurrenceNo: 12,
            onTap: () {},
            onToggle: () {},
          ),
          size: size,
          brightness: brightness,
        );
        _expectNoOverflow(tester, 'ReminderCard $label $mode');
        expect(find.textContaining('体外驱虫'), findsOneWidget);
      });

      testWidgets('已完成提醒卡片 $label / $mode 不溢出', (tester) async {
        await _pumpCard(
          tester,
          ReminderCard(
            reminder: _reminder(repeating: false),
            petName: '咪咪',
            completed: true,
            completedAt: DateTime(2026, 1, 2, 10),
            onTap: () {},
          ),
          size: size,
          brightness: brightness,
        );
        _expectNoOverflow(tester, 'ReminderCard(completed) $label $mode');
      });

      testWidgets('空状态 $label / $mode 不溢出', (tester) async {
        await _pumpCard(
          tester,
          Column(
            children: [
              SizedBox(
                height: size.height - 40,
                child: EmptyState(
                  icon: Icons.pets,
                  title: '还没有宠物档案',
                  subtitle: '添加第一只毛孩子，开始记录它的每一天',
                  actionLabel: '添加宠物',
                  onAction: () {},
                ),
              ),
            ],
          ),
          size: size,
          brightness: brightness,
        );
        _expectNoOverflow(tester, 'EmptyState $label $mode');
        expect(find.text('添加宠物'), findsOneWidget);
      });
    }
  }
}
