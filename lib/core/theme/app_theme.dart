import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// ── 爪札 · Design Token System ────────────────────────────────
/// Inspired by premium stationery — a Moleskine for pet memories.
/// Palette: ink · leaf · plum · pine · slate · cloud

class AppColors {
  // ── Core palette ──────────────────────────────────────────────

  /// Warm black — primary text. Never pure #000.
  static const ink = Color(0xFF1F1D1B);

  /// Notebook-paper white — background. Subtle warmth, not cream.
  static const leaf = Color(0xFFF7F5F0);

  /// Muted mauve — primary accent. The signature risk.
  static const plum = Color(0xFF8B5E7A);

  /// Forest green — secondary accent, success, nature, growth.
  static const pine = Color(0xFF5C8A6E);

  /// Blue-gray — secondary text & icons, more character than #888.
  static const slate = Color(0xFF69727A);

  /// Warm gray — surfaces, cards, dividers.
  static const cloud = Color(0xFFE8E4DD);

  /// Error red — kept distinct from the core palette for clarity.
  static const error = Color(0xFFC94A4A);

  /// Pure white — used sparingly for card surfaces on light bg.
  static const white = Colors.white;

  // ── Legacy compatibility aliases (internal migration) ────────

  static const primary = plum;
  static const primaryLight = Color(0xFFEDE2E9); // plum @ 12%
  static const secondary = pine;
  static const accent = pine;
  static const warmBg = leaf;
  static const cardBg = white;
  static const textPrimary = ink;
  static const textSecondary = slate;
  static const success = pine;
  static const divider = cloud;

  // ── Dark mode ─────────────────────────────────────────────────

  static const darkBg = Color(0xFF1A1817);
  static const darkCard = Color(0xFF262322);
  static const darkSurface = Color(0xFF2E2B29);
  static const darkTextPrimary = Color(0xFFF0EDE8);
  static const darkTextSecondary = Color(0xFF9B948C);
  static const darkDivider = Color(0xFF383430);

  // ── Data display labels (Chinese) ─────────────────────────────

  static const speciesIcons = {'dog': '🐕', 'cat': '🐈', 'other': '🐾'};

  static const speciesLabels = {'dog': '狗狗', 'cat': '猫猫', 'other': '其他'};

  static const genderLabels = {
    'male': '♂️ 公',
    'female': '♀️ 母',
    'unknown': '未知',
  };

  static const meetTypeLabels = {'adopt': '领养', 'born': '出生', 'found': '捡到'};

  static const moodEmojis = {
    '': '😶',
    'happy': '😊',
    'calm': '😌',
    'sad': '😔',
    'sick': '🤒',
    'excited': '🎉',
  };

  static const moodLabels = {
    '': '无',
    'happy': '开心',
    'calm': '平静',
    'sad': '难过',
    'sick': '不适',
    'excited': '兴奋',
  };

  static const weatherIcons = {
    '': '',
    'sunny': '☀️',
    'cloudy': '☁️',
    'rainy': '🌧️',
    'snowy': '❄️',
    'windy': '💨',
  };

  static const weatherLabels = {
    '': '无',
    'sunny': '晴',
    'cloudy': '多云',
    'rainy': '雨',
    'snowy': '雪',
    'windy': '风',
  };

  static const reminderTypeLabels = {
    'vaccine': '疫苗',
    'deworm': '驱虫（通用）',
    'deworm_internal': '体内驱虫',
    'deworm_external': '体外驱虫',
    'heartworm': '心丝虫/跳蚤预防',
    'neuter': '绝育/去势',
    'bath': '洗澡',
    'grooming': '美容',
    'vet': '体检',
    'medicine': '喂药',
    'custom': '自定义',
  };

  static const reminderTypeIcons = {
    'vaccine': Icons.medication,
    'deworm': Icons.bug_report,
    'deworm_internal': Icons.medication_liquid,
    'deworm_external': Icons.pest_control,
    'heartworm': Icons.favorite,
    'neuter': Icons.medical_services,
    'bath': Icons.bathtub,
    'grooming': Icons.content_cut,
    'vet': Icons.local_hospital,
    'medicine': Icons.medication,
    'custom': Icons.notifications,
  };

  /// Reminder-type accent colours — each distinct but harmonised
  /// with the plum/pine/slate core palette.
  static const reminderTypeColors = {
    'vaccine': Color(0xFF7A8CC4), // muted periwinkle
    'deworm': Color(0xFFB08A7A), // warm terracotta
    'deworm_internal': Color(0xFF5C8A6E), // pine
    'deworm_external': Color(0xFFB08A7A), // terracotta
    'heartworm': Color(0xFF6B9DAF), // sky
    'neuter': Color(0xFF9B7AAA), // lavender
    'bath': Color(0xFF6B9DAF), // muted sky blue
    'grooming': Color(0xFFC4946A), // warm amber
    'vet': Color(0xFFC94A4A), // error red
    'medicine': Color(0xFF8B5E7A), // plum（与「喂药」语义一致）
    'custom': Color(0xFF69727A), // slate
  };

  static const repeatUnitLabels = {
    'once': '不重复',
    'daily': '每天',
    'weekly': '每周',
    'monthly': '每月',
    'yearly': '每年',
  };

  /// Default intervals (in days) for each reminder type.
  /// Returns interval based on pet species (cat/dog).
  static int defaultInterval(String type, {String species = 'dog'}) {
    switch (type) {
      case 'deworm':
      case 'deworm_internal':
        return 90;
      case 'deworm_external':
      case 'heartworm':
        return 30;
      case 'vaccine':
        return 365;
      case 'neuter':
        return 365;
      case 'bath':
        return species == 'cat' ? 60 : 30;
      case 'grooming':
        return species == 'cat' ? 60 : 45;
      case 'vet':
        return 365;
      default:
        return 30;
    }
  }

  /// Human-readable recommendation text for each reminder type.
  static String typeRecommendation(String type, {String species = 'dog'}) {
    final isCat = species == 'cat';
    switch (type) {
      case 'deworm':
        return isCat ? '成年猫每3个月一次 · 幼猫按兽医方案' : '成年犬每3个月一次 · 幼犬按兽医方案';
      case 'deworm_internal':
        return isCat ? '成年猫每3个月一次体内驱虫 · 幼猫按兽医方案' : '成年犬每3个月一次体内驱虫 · 幼犬按兽医方案';
      case 'deworm_external':
        return '体外驱虫建议每月一次 · 高风险地区可全年进行';
      case 'heartworm':
        return '心丝虫/跳蚤预防一般每月一次 · 请按当地风险与产品说明';
      case 'vaccine':
        return isCat ? '幼猫约8周首免，之后每年加强' : '幼犬约6周首免，之后每年加强';
      case 'neuter':
        return '一般6-12月龄进行 · 术后10-14天复查/拆线，期间避免洗澡';
      case 'bath':
        return isCat ? '猫咪一般不需频繁洗澡 · 建议每2个月或按需' : '短毛约每月一次 · 长毛可2-3周一次，视皮肤情况';
      case 'grooming':
        return isCat ? '长毛猫约2个月修剪一次' : '约1.5个月美容一次 · 长毛犬建议每月一次';
      case 'vet':
        return '成年宠物建议每年体检 · 7岁以上每半年一次';
      default:
        return '间隔天数可根据需要自定义';
    }
  }

  /// Tag chip palette — soft, desaturated so chips sit quietly
  /// alongside the plum primary accent.
  static const tagColors = [
    0xFF8B5E7A, // plum
    0xFF5C8A6E, // pine
    0xFF7A8CC4, // periwinkle
    0xFFB08A7A, // terracotta
    0xFF6B9DAF, // sky
    0xFFC4946A, // amber
    0xFF9B7AAA, // lavender
    0xFF5B8C8C, // teal
  ];

  // ── Deprecated (kept for compatibility) ───────────────────────

  static const moodColors = {
    'happy': Color(0xFFC4946A),
    'calm': Color(0xFF5C8A6E),
    'sad': Color(0xFF7A8CC4),
    'sick': Color(0xFFC97A7A),
    'excited': Color(0xFF8B5E7A),
  };
}

/// ── AppTheme — Material 3 shell with custom token overrides ─────
class AppTheme {
  // ── Light theme ────────────────────────────────────────────────

  static ThemeData get light => _base(ThemeData.light()).copyWith(
    scaffoldBackgroundColor: AppColors.leaf,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      backgroundColor: AppColors.leaf,
      foregroundColor: AppColors.ink,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.white,
      elevation: 1,
      surfaceTintColor: Colors.transparent,
      shadowColor: const Color(0x14000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide.none,
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.plum,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: CircleBorder(),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: AppColors.plum,
      unselectedItemColor: AppColors.slate,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      backgroundColor: AppColors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.cloud),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.cloud),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.plum, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.plum,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.plum,
        side: const BorderSide(color: AppColors.plum),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.plum),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.ink,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.cloud,
      thickness: 0.5,
      space: 1,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.cloud,
      labelStyle: const TextStyle(fontSize: 12, color: AppColors.ink),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide.none,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      behavior: SnackBarBehavior.floating,
    ),
  );

  // ── Dark theme ─────────────────────────────────────────────────

  static ThemeData get dark => _base(ThemeData.dark()).copyWith(
    scaffoldBackgroundColor: AppColors.darkBg,
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      backgroundColor: AppColors.darkBg,
      foregroundColor: AppColors.darkTextPrimary,
      titleTextStyle: TextStyle(
        color: AppColors.darkTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.darkCard,
      elevation: 1,
      surfaceTintColor: Colors.transparent,
      shadowColor: const Color(0x33000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide.none,
      ),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.plum,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: CircleBorder(),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      selectedItemColor: AppColors.plum,
      unselectedItemColor: AppColors.darkTextSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
      backgroundColor: AppColors.darkCard,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.darkSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.darkDivider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.darkDivider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.plum, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.error, width: 1.5),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.plum,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFC4A8B8),
        side: const BorderSide(color: Color(0xFFC4A8B8)),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: const Color(0xFFC4A8B8)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.darkCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: AppColors.darkTextPrimary,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.darkDivider,
      thickness: 0.5,
      space: 1,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.darkSurface,
      labelStyle: const TextStyle(
        fontSize: 12,
        color: AppColors.darkTextPrimary,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide.none,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.darkSurface,
      contentTextStyle: const TextStyle(
        color: AppColors.darkTextPrimary,
        fontSize: 14,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      behavior: SnackBarBehavior.floating,
    ),
  );

  // ── Base — shared colour-scheme & type-scale seed ──────────────

  static ThemeData _base(ThemeData base) {
    final isDark = base.brightness == Brightness.dark;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.ink;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.slate;

    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.plum,
      brightness: base.brightness,
    );
    return base.copyWith(
      colorScheme: colorScheme,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.fuchsia: CupertinoPageTransitionsBuilder(),
        },
      ),
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: textPrimary,
          letterSpacing: -0.3,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: textPrimary,
        ),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(
          fontSize: 15,
          height: 1.6,
          color: textPrimary,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          height: 1.5,
          color: textSecondary,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 13,
          letterSpacing: 0.2,
        ),
        labelSmall: base.textTheme.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.3,
          color: textSecondary,
        ),
      ),
    );
  }
}
