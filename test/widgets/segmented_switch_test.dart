import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clawtag/core/theme/app_theme.dart';
import 'package:clawtag/widgets/segmented_switch.dart';

void main() {
  testWidgets('两段切换：点击回调、选中态跟随', (tester) async {
    var index = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SegmentedSwitch(
              labels: const ['爪札 4 篇', '护理记录 3 项'],
              index: index,
              onChanged: (i) => setState(() => index = i),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('爪札 4 篇'), findsOneWidget);
    expect(find.text('护理记录 3 项'), findsOneWidget);

    await tester.tap(find.text('护理记录 3 项'));
    await tester.pumpAndSettle();
    expect(index, 1, reason: '点击第二段应回调 1');
  });
}
