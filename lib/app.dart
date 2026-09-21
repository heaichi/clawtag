import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'screens/splash_screen.dart';

class PetDiaryApp extends StatelessWidget {
  const PetDiaryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (_, provider, _) => MaterialApp(
        title: '爪札',
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: provider.mode,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [
          Locale('zh'),
        ],
        locale: const Locale('zh'),
        home: const SplashScreen(),
      ),
    );
  }
}
