import 'dart:io';

import 'package:flutter/material.dart';

import '../core/database/app_database.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/confirm.dart';
import '../core/utils/error_utils.dart';
import '../core/utils/formatters.dart';
import '../core/utils/care_records.dart';
import '../core/utils/medication_course.dart';
import '../core/utils/pet_age.dart';
import '../core/utils/routes.dart';
import '../core/utils/snack.dart';
import '../core/utils/uuid.dart';
import '../services/reminder_service.dart';
import '../widgets/care_record_row.dart';
import '../widgets/diary_card.dart';
import '../widgets/segmented_switch.dart';
import '../widgets/shimmer.dart';
import '../screens/pet_editor_screen.dart';
import '../screens/diary_detail_screen.dart';
import '../screens/diary_editor_screen.dart';
import '../screens/reminder_editor_screen.dart';

class PetDetailScreen extends StatefulWidget {
  final Pet pet;
  final VoidCallback? onRestored;

  const PetDetailScreen({super.key, required this.pet, this.onRestored});

  @override
  State<PetDetailScreen> createState() => _PetDetailScreenState();
}

class _PetDetailScreenState extends State<PetDetailScreen> {
  late Pet _pet;
  List<Diary> _diaries = [];
  int _diaryCount = 0;
  bool _loading = true;
  Map<String, List<Tag>> _diaryTags = {};

  /// 0 = 爪札（默认），1 = 护理记录。
  int _tab = 0;

  /// 护理记录：该宠物的提醒 + 全部实例（在内存里按项目名合并分组）。
  List<Reminder> _reminders = [];
  List<ReminderInstance> _careInstances = [];

  /// 用药疗程提醒（单独成组，**不参与**项目时间线编号，见用药疗程设计 §6.4）。
  List<Reminder> get _medications =>
      _reminders.where((r) => r.isMedicationCourse).toList();

  /// 非用药的护理项目：按项目名合并的时间线（既有逻辑，一行未改）。
  List<CareGroup> get _careGroups => groupCareRecords(
    reminders: _reminders.where((r) => !r.isMedicationCourse).toList(),
    instances: _careInstances,
  );

  /// 某条用药提醒的全部实例（按计划时刻升序）。
  List<ReminderInstance> _instancesOf(String reminderId) {
    final list =
        _careInstances.where((i) => i.reminderId == reminderId).toList()
          ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return list;
  }

  @override
  void initState() {
    super.initState();
    _pet = widget.pet;
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        AppDatabase.getPet(_pet.id),
        AppDatabase.getPetDiaries(_pet.id),
        AppDatabase.getDiaryCountForPet(_pet.id),
        AppDatabase.getPetReminders(_pet.id),
        AppDatabase.getInstancesForPet(_pet.id),
      ]);
      final pet = results[0] as Pet?;
      final diaries = results[1] as List<Diary>;
      final count = results[2] as int;
      final reminders = results[3] as List<Reminder>;
      final careInstances = results[4] as List<ReminderInstance>;
      final tags = diaries.isNotEmpty
          ? await AppDatabase.getDiaryTagsBatch(
              diaries.map((d) => d.id).toList(),
            )
          : <String, List<Tag>>{};
      if (mounted) {
        setState(() {
          if (pet != null) _pet = pet;
          _diaries = diaries;
          _diaryCount = count;
          _diaryTags = tags;
          _reminders = reminders;
          _careInstances = careInstances;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        showError(context, e);
      }
    }
  }

  Future<void> _deletePet() async {
    final confirmed = await showDestructiveConfirm(
      context,
      title: '删除宠物',
      message: '确定要删除「${_pet.name}」吗？\n所有相关的爪札和提醒也将被删除。',
    );
    if (confirmed == true && mounted) {
      // 先取消该宠物所有提醒的 OS 通知，否则删除后提醒仍会按时弹出。
      try {
        final reminders = await AppDatabase.getPetReminders(_pet.id);
        for (final r in reminders) {
          final baseId = notificationIdFromUuid(r.id);
          final maxSlots = r.repeatUnit == 'once' ? 1 : 12;
          for (var i = 0; i < maxSlots; i++) {
            await cancelReminderNotification(baseId + i);
          }
        }
      } catch (_) {
        // 通知取消失败不阻塞删除
      }
      // 只软删（爪札/提醒记录 + 宠物），保留物理文件以支持将来恢复。
      await AppDatabase.softDeletePet(_pet.id);
      if (mounted) {
        showAppSnackBar(
          context,
          '宠物已删除',
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: '撤销',
            textColor: AppColors.plum,
            onPressed: () async {
              try {
                await AppDatabase.restorePet(_pet.id);
                await rescheduleRemindersForPet(_pet.id);
                widget.onRestored?.call();
              } catch (e) {
                if (mounted) showError(context, e);
              }
            },
          ),
        );
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.slate;
    return Scaffold(
      appBar: AppBar(
        title: Text(_pet.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () async {
              await Navigator.push(
                context,
                AppRoutes.slideUp(builder: (_) => PetEditorScreen(pet: _pet)),
              );
              _load();
            },
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline,
              color: AppColors.error,
              size: 20,
            ),
            onPressed: _deletePet,
          ),
        ],
      ),
      body: _loading
          ? const _ShimmerDetail()
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                slivers: [
                  // ── Hero header (signature element) ──────────
                  SliverToBoxAdapter(child: _buildHeader()),
                  // ── Diaries section header ──────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                      child: Row(
                        children: [
                          // 爪札 / 护理记录：并排切换（默认爪札）
                          Expanded(
                            child: SegmentedSwitch(
                              labels: [
                                '爪札 $_diaryCount 篇',
                                '护理记录 ${_careGroups.length} 项',
                              ],
                              index: _tab,
                              onChanged: (i) => setState(() => _tab = i),
                            ),
                          ),
                          const SizedBox(width: 10),
                          TextButton.icon(
                            onPressed: _tab == 0
                                ? () => _addDiary()
                                : () => _addReminder(),
                            icon: const Icon(Icons.add, size: 16),
                            label: Text(_tab == 0 ? '写爪札' : '加提醒'),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.plum,
                              textStyle: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // ── 爪札列表（默认）/ 空态 ───────────────────
                  if (_tab == 0)
                    _diaries.isEmpty
                        ? SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 32),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.book_outlined,
                                    size: 40,
                                    color: AppColors.cloud,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '还没有爪札',
                                    style: TextStyle(
                                      color: mutedColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => DiaryCard(
                                diary: _diaries[i],
                                petName: _pet.name,
                                tags: _diaryTags[_diaries[i].id] ?? [],
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    AppRoutes.slideUp(
                                      builder: (_) => DiaryDetailScreen(
                                        diary: _diaries[i],
                                        onRestored: _load,
                                      ),
                                    ),
                                  );
                                  _load();
                                },
                              ),
                              childCount: _diaries.length,
                            ),
                          ),
                  // ── 护理记录（按项目名合并的时间线）───────────
                  if (_tab == 1) ..._buildCareSlivers(context),
                ],
              ),
            ),
    );
  }

  /// ── 新增/补充护理提醒（从护理记录进入时预填宠物、项目名、类型与第几次）──
  Future<void> _addReminder({CareGroup? group}) async {
    // 继承项目原有设置：类型/标题/第几次 + 间隔、重复开关、通知时间、响铃与震动，
    // 否则新建的提醒会退回类型默认值（例如狂犬疫苗原本 7 天，会变成 30 天）。
    final base = group?.reminders.first;
    await Navigator.push(
      context,
      AppRoutes.slideUp(
        builder: (_) => ReminderEditorScreen(
          initialPetId: _pet.id,
          initialTitle: group?.name,
          initialType: base?.type,
          initialOccurrenceNo: group == null ? null : group.records.length + 1,
          // 只有项目里真的完成过，才带出上次执行日期（否则保持未设置，不捏造）
          initialLastDoneDate: group?.lastDone,
          initialIntervalDays: base?.repeatInterval,
          initialIsRepeating: base?.isRepeating,
          initialNotificationTime: base?.notificationTime,
          initialSoundEnabled: base?.soundEnabled,
          initialVibrateEnabled: base?.vibrateEnabled,
        ),
      ),
    );
    _load();
  }

  /// ── 护理记录：分组卡片列表（无提醒时给空态）──────────────
  List<Widget> _buildCareSlivers(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.slate;
    final groups = _careGroups;
    final medications = _medications;
    if (groups.isEmpty && medications.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                const Icon(
                  Icons.medical_information_outlined,
                  size: 40,
                  color: AppColors.cloud,
                ),
                const SizedBox(height: 8),
                Text(
                  '还没有护理提醒',
                  style: TextStyle(color: mutedColor, fontSize: 14),
                ),
                TextButton(
                  onPressed: () => _addReminder(),
                  style: TextButton.styleFrom(foregroundColor: AppColors.plum),
                  child: const Text('添加第一条护理提醒'),
                ),
              ],
            ),
          ),
        ),
      ];
    }
    return [
      if (medications.isNotEmpty)
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => _buildMedicationCard(context, medications[i]),
            childCount: medications.length,
          ),
        ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) => _buildCareGroupCard(context, groups[i]),
          childCount: groups.length,
        ),
      ),
    ];
  }

  /// ── 护理记录里的用药疗程卡（按天聚合，不把几十次摊平）──────
  Widget _buildMedicationCard(BuildContext context, Reminder r) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.ink;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.slate;
    final instances = _instancesOf(r.id);
    final byDay = <DateTime, List<ReminderInstance>>{};
    for (final i in instances) {
      if (doseSlotOfInstance(reminder: r, instance: i) == null) continue;
      final day = DateTime(i.dueDate.year, i.dueDate.month, i.dueDate.day);
      byDay.putIfAbsent(day, () => []).add(i);
    }
    final days = byDay.keys.toList()..sort();
    final start = DateTime(
      r.firstDueDate.year,
      r.firstDueDate.month,
      r.firstDueDate.day,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.plum.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.medication,
                  size: 18,
                  color: AppColors.plum,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '用药 · ${r.title}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      courseCardSubtitle(reminder: r, instances: instances),
                      style: TextStyle(fontSize: 12, color: mutedColor),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final day in days)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 58,
                    child: Text(
                      '第 ${day.difference(start).inDays + 1} 天',
                      style: TextStyle(fontSize: 12, color: mutedColor),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${byDay[day]!.where((i) => i.completed).length}/${byDay[day]!.length} 次',
                      style: TextStyle(fontSize: 12, color: textColor),
                    ),
                  ),
                  if (byDay[day]!.any((i) => !i.completed && !i.isDeleted))
                    const Text(
                      '未完成',
                      style: TextStyle(fontSize: 12, color: AppColors.error),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCareGroupCard(BuildContext context, CareGroup group) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.ink;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.slate;
    final typeColor =
        AppColors.reminderTypeColors[group.type] ?? AppColors.slate;
    final typeIcon =
        AppColors.reminderTypeIcons[group.type] ?? Icons.notifications;
    final shown = group.records.reversed.take(5).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: typeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(typeIcon, size: 18, color: typeColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _careSummary(group),
                      style: TextStyle(fontSize: 12, color: mutedColor),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: '为这个项目加提醒',
                child: InkWell(
                  onTap: () => _addReminder(group: group),
                  borderRadius: BorderRadius.circular(8),
                  child: const SizedBox(
                    width: 34,
                    height: 34,
                    child: Icon(Icons.add, size: 19, color: AppColors.plum),
                  ),
                ),
              ),
            ],
          ),
          if (shown.isNotEmpty) ...[
            const Divider(height: 16),
            for (final record in shown)
              CareRecordRow(record: record, mutedColor: mutedColor),
            if (group.records.length > shown.length)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 4),
                child: Text(
                  '仅显示最近 ${shown.length} 次，共 ${group.records.length} 条记录',
                  style: TextStyle(fontSize: 11, color: mutedColor),
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 组头摘要：上次 · 下次 · 共 N 次。
  String _careSummary(CareGroup group) {
    final last = group.lastDone;
    final next = group.nextDue;
    // 口径写清楚：完成次数**不含待办**（否则『共 N 次』会被误读成含待办）
    String nextText;
    if (next == null) {
      nextText = '下次 —';
    } else {
      final overdueDays = overdueDaysFor(next);
      // 已过期的待办不能还写『下次 2026/9/7』（那是过去时间），要如实说逾期
      nextText = overdueDays > 0
          ? '逾期 $overdueDays 天（原定 ${dateFormatCompact.format(next)}）'
          : '下次 ${dateFormatCompact.format(next)}';
    }
    // 没有完成记录就不显示『上次 —』（省一行、避免摘要换行）
    final parts = <String>[
      if (last != null) '上次 ${dateFormatCompact.format(last)}',
      nextText,
      '完成 ${group.doneCount} 次',
    ];
    return parts.join(' · ');
  }

  /// ── Pet info card: avatar + name + core tags + info grid ──────
  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.ink;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.slate;
    final age = buildPetAgeDisplay(_pet);
    final speciesPrefix =
        '${AppColors.speciesIcons[_pet.species] ?? '🐾'} '
        '${AppColors.speciesLabels[_pet.species] ?? _pet.species}';
    final breedText = _pet.breed ?? '';
    final genderText = AppColors.genderLabels[_pet.gender] ?? '';
    final coreText = [
      speciesPrefix,
      if (breedText.isNotEmpty) breedText,
      if (genderText.isNotEmpty) genderText,
    ].where((s) => s.isNotEmpty).join(' · ');
    final weightText = _pet.currentWeightKg != null
        ? '${_pet.currentWeightKg!.toStringAsFixed(1)} kg'
        : null;
    final meetTypeText =
        AppColors.meetTypeLabels[_pet.meetType] ?? _pet.meetType;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.plum.withValues(alpha: 0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Hero(
                  tag: 'pet-avatar-${_pet.id}',
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: AppColors.plum.withValues(alpha: 0.08),
                    backgroundImage:
                        _pet.avatarPath != null && _pet.avatarPath!.isNotEmpty
                        ? FileImage(File(_pet.avatarPath!))
                        : null,
                    child: _pet.avatarPath == null || _pet.avatarPath!.isEmpty
                        ? Text(
                            _pet.name.characters.first,
                            style: const TextStyle(
                              fontSize: 28,
                              color: AppColors.plum,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pet.name,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          coreText,
                          style: TextStyle(fontSize: 13, color: mutedColor),
                        ),
                        if (age.stageLabel != null)
                          _StageChip(label: age.stageLabel!),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Row 1: age / weight / meet type
          Row(
            children: [
              Expanded(
                child: _InfoCell(
                  icon: Icons.cake_outlined,
                  label: '年龄',
                  value: age.ageText,
                ),
              ),
              if (weightText != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _InfoCell(
                    icon: Icons.monitor_weight,
                    label: '当前体重',
                    value: weightText,
                  ),
                ),
              ],
              const SizedBox(width: 8),
              Expanded(
                child: _InfoCell(
                  icon: Icons.favorite_outline,
                  label: '相遇方式',
                  value: meetTypeText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Row 2: meet date / birthday
          Row(
            children: [
              Expanded(
                child: _InfoCell(
                  icon: Icons.event_outlined,
                  label: '相识日期',
                  value: dateFormatYMD.format(_pet.meetDate),
                ),
              ),
              if (_pet.birthDate != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _InfoCell(
                    icon: Icons.cake,
                    label: '生日',
                    value: dateFormatYMD.format(_pet.birthDate!),
                  ),
                ),
              ],
            ],
          ),
          // Row 3: notes
          if (_pet.notes != null && _pet.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: _NoteCell(notes: _pet.notes!),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _addDiary() async {
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DiaryEditorScreen(petId: _pet.id, petName: _pet.name),
        ),
      );
      _load();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }
}

class _StageChip extends StatelessWidget {
  final String label;

  const _StageChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final color = label.startsWith('幼')
        ? AppColors.pine
        : label.startsWith('老')
        ? AppColors.error
        : AppColors.plum;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InfoCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoCell({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.ink;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.slate;
    const accent = AppColors.plum;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: accent),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: mutedColor)),
            ],
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteCell extends StatefulWidget {
  final String notes;

  const _NoteCell({required this.notes});

  @override
  State<_NoteCell> createState() => _NoteCellState();
}

class _NoteCellState extends State<_NoteCell> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.ink;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.slate;
    final showToggle = widget.notes.length > 60;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.plum.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notes, size: 13, color: AppColors.plum),
              const SizedBox(width: 4),
              Text('备注', style: TextStyle(fontSize: 11, color: mutedColor)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.notes,
            maxLines: _expanded ? null : 3,
            overflow: _expanded ? null : TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: textColor, height: 1.5),
          ),
          if (showToggle)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Text(_expanded ? '收起' : '展开'),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShimmerDetail extends StatelessWidget {
  const _ShimmerDetail();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Shimmer(
        child: Column(
          children: [
            ShimmerBox(width: double.infinity, height: 260, borderRadius: 12),
            SizedBox(height: 20),
            ShimmerBox(width: 80, height: 16),
            SizedBox(height: 12),
            ShimmerBox(width: 200, height: 14),
            SizedBox(height: 24),
            Row(
              children: [
                ShimmerBox(width: 60, height: 14),
                Spacer(),
                ShimmerBox(width: 80, height: 14),
              ],
            ),
            SizedBox(height: 12),
            ShimmerBox(height: 120, borderRadius: 8),
            SizedBox(height: 8),
            ShimmerBox(height: 120, borderRadius: 8),
          ],
        ),
      ),
    );
  }
}
