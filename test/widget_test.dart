import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:clawtag/app.dart';
import 'package:clawtag/core/theme/theme_provider.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: const PetDiaryApp(),
      ),
    );
    // The splash screen should render without errors
    // Advance past the splash screen's 1.5s delay timer
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(PetDiaryApp), findsOneWidget);
  });

  testWidgets('ThemeProvider initializes with system mode', (WidgetTester tester) async {
    final provider = ThemeProvider();
    // Default should be system mode
    expect(provider.mode, ThemeMode.system);
  });
}
