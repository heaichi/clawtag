import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/database/app_database.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/theme_provider.dart';
import '../core/utils/error_utils.dart';
import '../core/utils/snack.dart';
import '../core/utils/version.dart';
import '../services/backup_service.dart';
import '../services/permission_service.dart';
import 'deleted_items_screen.dart';

class SettingsScreen extends StatefulWidget {
  final ValueListenable<int>? refreshSignal;

  const SettingsScreen({super.key, this.refreshSignal});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int? _petCount;
  int? _diaryCount;
  int? _reminderCount;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_handleExternalRefresh);
    _loadStats();
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_handleExternalRefresh);
    super.dispose();
  }

  void _handleExternalRefresh() {
    if (mounted) _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final results = await Future.wait([
        AppDatabase.getAllPets(),
        AppDatabase.getAllDiaries(),
        AppDatabase.countPendingReminderCards(),
      ]);
      if (mounted) {
        setState(() {
          _petCount = (results[0] as List<Pet>).length;
          _diaryCount = (results[1] as List<Diary>).length;
          _reminderCount = results[2] as int;
        });
      }
    } catch (e) {
      debugPrint('加载统计失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.ink;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.slate;

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 36),
        children: [
          const SizedBox(height: 20),
          // ── App header ──────────────────────────────────────────
          Center(
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.plum.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.pets,
                    size: 34,
                    color: AppColors.plum,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '爪札',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  AppVersion.display,
                  style: TextStyle(fontSize: 12, color: mutedColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── 外观 ────────────────────────────────────────────────
          const _SectionHeader(title: '外观'),
          Consumer<ThemeProvider>(
            builder: (_, themeProvider, _) {
              final mode = themeProvider.mode;
              final label = switch (mode) {
                ThemeMode.light => '浅色',
                ThemeMode.dark => '深色',
                _ => '跟随系统',
              };
              final icon = switch (mode) {
                ThemeMode.light => Icons.light_mode,
                ThemeMode.dark => Icons.dark_mode,
                _ => Icons.settings_brightness,
              };
              return _Tile(
                icon: icon,
                title: '主题模式',
                subtitle: label,
                onTap: () => _showThemePicker(context, themeProvider),
              );
            },
          ),
          const SizedBox(height: 12),

          // ── 提醒 ────────────────────────────────────────────────
          const _SectionHeader(title: '提醒'),
          _Tile(
            icon: Icons.notifications_active_outlined,
            title: '通知权限',
            subtitle: '检查并开启系统通知',
            onTap: () async {
              // 用户主动点击 → 允许弹系统权限框
              final ok = await PermissionService.requestNotification();
              if (context.mounted) {
                showAppSnackBar(
                  context,
                  ok ? '通知权限已开启' : '通知权限未开启',
                  isError: !ok,
                );
              }
            },
          ),
          const SizedBox(height: 12),

          // ── 数据 ────────────────────────────────────────────────
          const _SectionHeader(title: '数据'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                _StatCard(label: '宠物', value: _petCount),
                const SizedBox(width: 10),
                _StatCard(label: '爪札', value: _diaryCount),
                const SizedBox(width: 10),
                _StatCard(label: '提醒（待办）', value: _reminderCount),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _Tile(
            icon: Icons.backup_outlined,
            title: '导出数据',
            subtitle: '导出备份包（含照片视频，可用于换机导入）',
            onTap: () => _exportData(context),
          ),
          _Tile(
            icon: Icons.restore_page_outlined,
            title: '导入数据',
            subtitle: '从备份包恢复（不会覆盖现有数据）',
            onTap: () => _importData(context, onImported: _loadStats),
          ),
          _Tile(
            icon: Icons.restore_from_trash_outlined,
            title: '最近删除',
            subtitle: '查看并恢复已删除内容',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DeletedItemsScreen()),
              );
              _loadStats();
            },
          ),
          const SizedBox(height: 12),

          // ── 关于 ────────────────────────────────────────────────
          const _SectionHeader(title: '关于'),
          const _Tile(
            icon: Icons.privacy_tip_outlined,
            title: '隐私说明',
            subtitle: '数据仅保存在本地',
          ),
          _Tile(
            icon: Icons.info_outline,
            title: '关于应用',
            subtitle: '${AppVersion.full} · Flutter',
            onTap: () => _showAbout(context),
          ),
        ],
      ),
    );
  }

  void _showThemePicker(BuildContext context, ThemeProvider themeProvider) {
    final mode = themeProvider.mode;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            const Text(
              '选择主题',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.settings_brightness),
              title: const Text('跟随系统'),
              trailing: mode == ThemeMode.system
                  ? const Icon(Icons.check, color: AppColors.plum)
                  : null,
              onTap: () {
                themeProvider.setMode(ThemeMode.system);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.light_mode),
              title: const Text('浅色'),
              trailing: mode == ThemeMode.light
                  ? const Icon(Icons.check, color: AppColors.plum)
                  : null,
              onTap: () {
                themeProvider.setMode(ThemeMode.light);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode),
              title: const Text('深色'),
              trailing: mode == ThemeMode.dark
                  ? const Icon(Icons.check, color: AppColors.plum)
                  : null,
              onTap: () {
                themeProvider.setMode(ThemeMode.dark);
                Navigator.pop(ctx);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ── Private helpers ──────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: AppColors.plum, size: 22),
        title: Text(title, style: const TextStyle(fontSize: 15)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 13)),
        trailing: onTap != null
            ? Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 18,
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final int? value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.slate;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              value?.toString() ?? '—',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.plum,
              ),
            ),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(fontSize: 12, color: mutedColor)),
          ],
        ),
      ),
    );
  }
}

void _showAbout(BuildContext context) {
  showAboutDialog(
    context: context,
    applicationName: '爪札',
    applicationVersion: AppVersion.display,
    applicationIcon: Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: AppColors.plum.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.pets, size: 30, color: AppColors.plum),
    ),
    applicationLegalese: '© 2026 Heaichi 保留所有权利\n本地优先 · 隐私安全',
    children: [
      const SizedBox(height: 16),
      Text(
        '技术栈: Flutter 3 + SQLite\n设计理念: 本地优先 (Local-First)',
        style: TextStyle(
          fontSize: 13,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ],
  );
}

Future<void> _exportData(BuildContext context) async {
  // barrierDismissible 只挡"点遮罩关闭"，系统返回键仍会关掉弹窗；一旦弹窗被
  // 提前关掉，下面用页面 context 的 Navigator.pop 就会把唯一根路由弹掉（黑屏）。
  // 用 PopScope 明确禁止返回键关闭这个进度弹窗（本来它就是不可取消的）。
  // 见 docs/代码审计待办.md P1-10。
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  try {
    final zip = await buildBackupZip();
    if (context.mounted) {
      Navigator.pop(context);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(zip.path)],
          subject: '爪札数据备份',
          text: '爪札备份包（含照片与视频）。在新设备上用「我的 → 导入数据」恢复。',
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context);
      showError(context, '导出失败: $e');
    }
  }
}

/// 导入备份：选文件 → 二次确认 → 进度弹窗 → 如实回执。
///
/// 支持新格式 `.zip`（`data.json` + `media/`，照片视频一起恢复）
/// 与旧版本导出的纯 `.json`（文字数据可恢复，媒体缺失会如实计数）。
Future<void> _importData(
  BuildContext context, {
  VoidCallback? onImported,
}) async {
  // file_picker 13 起是静态 API，返回 List<PlatformFile>（取消选择时为空列表）
  List<PlatformFile> picked;
  try {
    picked = await FilePicker.pickFiles(type: FileType.any);
  } catch (e) {
    if (context.mounted) showError(context, '打开文件选择器失败: $e');
    return;
  }
  final path = picked.isEmpty ? null : picked.first.path;
  if (path == null || !context.mounted) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('导入备份'),
      content: const Text(
        '备份里的宠物、爪札、提醒会被**追加**到现有数据中，不会覆盖或删除任何东西。\n\n'
        '标签会按名称合并；照片视频会一起复制到本机。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('开始导入'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  try {
    final summary = await importBackupFile(path);
    if (!context.mounted) return;
    Navigator.pop(context);
    onImported?.call();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入完成'),
        content: Text(formatImportSummary(summary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好'),
          ),
        ],
      ),
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context);
      showError(context, '导入失败: $e');
    }
  }
}
