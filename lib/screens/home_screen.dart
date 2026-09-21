import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/data_version.dart';
import 'pet_list_screen.dart';
import 'diary_list_screen.dart';
import 'reminder_list_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final ValueNotifier<int> _petRefresh = ValueNotifier<int>(0);
  final ValueNotifier<int> _diaryRefresh = ValueNotifier<int>(0);
  final ValueNotifier<int> _reminderRefresh = ValueNotifier<int>(0);
  final ValueNotifier<int> _settingsRefresh = ValueNotifier<int>(0);
  late final List<int> _lastSeenVersions;

  @override
  void initState() {
    super.initState();
    _lastSeenVersions = List<int>.filled(4, DataVersion.value);
    DataVersion.notifier.addListener(_onDataVersionChanged);
  }

  @override
  void dispose() {
    DataVersion.notifier.removeListener(_onDataVersionChanged);
    super.dispose();
  }

  /// 当前 Tab 自身会负责刷新（如从详情/编辑页返回后 _load），
  /// 因此只把“当前 Tab 已经看过”的版本号推进，隐藏 Tab 保留旧版本，
  /// 等切过去时若数据版本已变化再触发定向刷新。
  void _onDataVersionChanged() {
    _lastSeenVersions[_currentIndex] = DataVersion.value;
  }

  /// 非游戏页面用 IndexedStack 保持状态，不通过 epoch key 销毁重建。
  /// 每个 Tab 接收一个刷新信号：只有跨 Tab 数据确实变化时才触发刷新，
  /// 普通切换不重建列表/视频。
  List<Widget> get _mainScreens => [
    PetListScreen(
      key: const ValueKey('pet-tab'),
      refreshSignal: _petRefresh,
    ),
    DiaryListScreen(
      key: const ValueKey('diary-tab'),
      refreshSignal: _diaryRefresh,
    ),
    ReminderListScreen(
      key: const ValueKey('reminder-tab'),
      refreshSignal: _reminderRefresh,
    ),
    SettingsScreen(
      key: const ValueKey('settings-tab'),
      refreshSignal: _settingsRefresh,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          // Minimize app to background instead of exiting
          try {
            const channel = MethodChannel('com.heaichi.pet_diary/app');
            channel.invokeMethod('moveToBackground').catchError((_) {});
          } catch (_) {}
        }
      },
      child: Scaffold(
        body: IndexedStack(index: _currentIndex, children: _mainScreens),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) {
            HapticFeedback.selectionClick();
            final needsRefresh = DataVersion.value != _lastSeenVersions[i];
            setState(() {
              _currentIndex = i;
              _lastSeenVersions[i] = DataVersion.value;
              if (needsRefresh) {
                switch (i) {
                  case 0:
                    _petRefresh.value++;
                  case 1:
                    _diaryRefresh.value++;
                  case 2:
                    _reminderRefresh.value++;
                  case 3:
                    _settingsRefresh.value++;
                }
              }
            });
          },
          indicatorColor: AppColors.plum.withValues(alpha: 0.1),
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          backgroundColor: isDark ? AppColors.darkCard : AppColors.white,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.pets_outlined),
              selectedIcon: Icon(Icons.pets, color: AppColors.plum),
              label: '宠物',
            ),
            NavigationDestination(
              icon: Icon(Icons.book_outlined),
              selectedIcon: Icon(Icons.book, color: AppColors.plum),
              label: '爪札',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_outlined),
              selectedIcon: Icon(Icons.notifications, color: AppColors.plum),
              label: '提醒',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: AppColors.plum),
              label: '我的',
            ),
          ],
        ),
      ),
    );
  }
}
