import 'package:flutter/material.dart';

import '../core/database/app_database.dart';
import '../core/utils/uuid.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/error_utils.dart';
import '../core/utils/formatters.dart';
import '../core/utils/medication_course.dart';
import '../core/utils/snack.dart';
import '../services/reminder_service.dart';
import '../services/permission_service.dart';
import '../widgets/apple_pickers.dart';
import '../widgets/inline_dropdown.dart';

class ReminderEditorScreen extends StatefulWidget {
  final Reminder? reminder;

  /// 以下为「从护理记录里新增提醒」时的预填项（默认 null = 现有行为不变）。
  final String? initialPetId;
  final String? initialTitle;
  final String? initialType;

  /// 预填「第几次」（= 该项目已有记录数 + 1）。
  final int? initialOccurrenceNo;

  /// 预填「上次执行日期」= 该项目最近一次**已完成**的日期；没有就留空（不捏造）。
  final DateTime? initialLastDoneDate;

  /// 从护理记录新增时，继承该项目原有的调度与通知设置（避免新建后节奏突变）。
  final int? initialIntervalDays;
  final bool? initialIsRepeating;
  final String? initialNotificationTime;
  final bool? initialSoundEnabled;
  final bool? initialVibrateEnabled;

  const ReminderEditorScreen({
    super.key,
    this.reminder,
    this.initialPetId,
    this.initialTitle,
    this.initialType,
    this.initialOccurrenceNo,
    this.initialLastDoneDate,
    this.initialIntervalDays,
    this.initialIsRepeating,
    this.initialNotificationTime,
    this.initialSoundEnabled,
    this.initialVibrateEnabled,
  });

  @override
  State<ReminderEditorScreen> createState() => _ReminderEditorScreenState();
}

class _ReminderEditorScreenState extends State<ReminderEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _intervalCtrl;
  final _titleFocus = FocusNode();

  String? _selectedPetId;
  String _selectedPetSpecies = 'dog';
  String _type = 'custom';

  /// 本次是第几次提醒（用户可选，默认首次）。
  int _occurrenceNo = 1;

  /// 新建提醒时的默认执行日期（纯函数见文件末尾）。
  static DateTime _initialExecDate(TimeOfDay t) =>
      defaultExecDateFor(hour: t.hour, minute: t.minute);

  /// 执行日期 = 本次（第 N 次）的执行日期，可任意天（含过去）。
  /// 默认取「下一个还没过的通知时刻」：上午建 09:00 的提醒用今天，下午建就用明天，
  /// 否则一进页面就命中『提醒时间已过』提示。
  DateTime _execDate = _initialExecDate(const TimeOfDay(hour: 9, minute: 0));

  /// 上次执行日期 = 第 N-1 次的执行日期；仅「第≥2次」展示与写入。
  ///
  /// **可以为空（未设置）**：没有真实的上一次时宁可留空，也不要用『执行日期 − 间隔』
  /// 凭空捏造一个（用户场景：第 1 次还是待办，哪来的上次执行日期）。
  DateTime? _lastDoneDate;

  /// 该提醒已完成历史里的编号集合（编辑时用于提示『编号已存在』）。
  Set<int> _historyNos = <int>{};

  TimeOfDay _dueTime = const TimeOfDay(hour: 9, minute: 0);
  int _intervalDays = 30;
  bool _repeating = false;

  /// 用药疗程：每天 2~3 个时间点 × 连续 N 天（与「间隔天数 / 重复提醒」互斥）。
  bool _isMedication = false;

  /// 每天服药次数（1~4；新建默认 2 次）。
  int _doseCount = 2;

  /// 时间点槽位：1~4 次/天（下拉给到 4，覆盖真实处方）。
  final List<TimeOfDay> _doseTimes = [
    const TimeOfDay(hour: 8, minute: 0),
    const TimeOfDay(hour: 20, minute: 0),
    const TimeOfDay(hour: 14, minute: 0),
    const TimeOfDay(hour: 12, minute: 0),
  ];
  late final TextEditingController _courseDaysCtrl;

  bool _soundEnabled = true;
  bool _vibrateEnabled = true;
  bool _saving = false;
  late final Future<List<Pet>> _petsFuture;

  bool get _isEditing => widget.reminder != null;

  /// 第 N+1 次提醒时间（只读汇总行用，纯函数见文件末尾）。
  DateTime get _nextReminderDate => nextReminderPreview(
    execDate: _execDate,
    intervalDays: _intervalDays,
    hour: _dueTime.hour,
    minute: _dueTime.minute,
  );

  /// 「第几次提醒」右侧的说明文字（纯函数见文件末尾，便于单测）。
  String get _occurrenceHint => reminderOccurrenceHint(
    occurrenceNo: _occurrenceNo,
    repeating: _repeating,
    historyNos: _historyNos,
  );

  /// 说明文字是否需要按『警告』配色。
  bool get _occurrenceHintIsWarning => _historyNos.contains(_occurrenceNo);

  /// 本次（第 N 次）提醒的实际触发时刻 = 执行日期 + 通知时间。
  DateTime get _combinedDue => DateTime(
    _execDate.year,
    _execDate.month,
    _execDate.day,
    _dueTime.hour,
    _dueTime.minute,
  );

  /// 统一更新间隔天数。
  ///
  /// **事实与计划分离**（docs/开发进度看板.md 第六十七轮）：
  /// 「上次执行日期」是事实（可自由改、不影响任何计算），
  /// 「间隔天数」是计划（下次与本次之间），两者互不改写。
  /// 典型场景：上次 7/20、隔了 62 天才做第二次（9/20），但下次仍想按 30 天 → 10/20。
  void _applyInterval(int days) {
    _intervalDays = days;
    _intervalCtrl.text = '$days';
  }

  /// 编辑已有提醒时，用**当前待办实例**回填「第几次」与「执行日期」
  /// （列表卡片显示的就是它，避免编辑器与列表不一致），
  /// 同时取回已完成历史的编号，用于提示『编号已存在』。
  Future<void> _loadEditContext(String reminderId) async {
    // 用药疗程**不**用待办实例回填：那里的 dueDate 是「下一次服药」而不是「疗程开始」，
    // 拿来当开始日期会把整条疗程挪到那天重排（真机上撞到过）。
    // 用药的开始日期始终取 firstDueDate，第几次由「第几天第几次」自己表达。
    if (widget.reminder?.isMedicationCourse ?? false) {
      final start = widget.reminder!.firstDueDate;
      if (mounted) {
        setState(() {
          _execDate = DateTime(start.year, start.month, start.day);
          _occurrenceNo = 1;
        });
      }
      return;
    }
    try {
      final pending = await AppDatabase.getPendingInstances();
      final inst = pending.where((i) => i.reminderId == reminderId).firstOrNull;
      final history = await AppDatabase.getCompletedInstances();
      if (!mounted) return;
      setState(() {
        _historyNos = history
            .where((i) => i.reminderId == reminderId)
            .map((i) => i.occurrenceNo)
            .toSet();
        if (inst != null) {
          _occurrenceNo = inst.occurrenceNo;
          _execDate = inst.dueDate;
        }
      });
    } catch (e) {
      debugPrint('回填待办实例失败: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    final r = widget.reminder;
    _titleCtrl = TextEditingController(text: r?.title ?? '');
    _descCtrl = TextEditingController(text: r?.description ?? '');
    _petsFuture = AppDatabase.getAllPets().then((pets) {
      if (_selectedPetId != null) {
        final pet = pets.where((p) => p.id == _selectedPetId).firstOrNull;
        if (pet != null) _selectedPetSpecies = pet.species;
      }
      return pets;
    });
    if (r != null) {
      _selectedPetId = r.petId;
      _type = r.type;
      // 初值：执行日期 = 提醒锚点日期；上次执行日期只用真实记录，没有就留空。
      // 稍后再用当前待办实例精确回填执行日期。
      _execDate = r.firstDueDate;
      _lastDoneDate = r.lastDoneDate;
      _intervalDays = r.repeatInterval;
      _repeating = r.isRepeating;
      _soundEnabled = r.soundEnabled;
      _vibrateEnabled = r.vibrateEnabled;
      if (r.notificationTime != null) {
        final parts = r.notificationTime!.split(':');
        if (parts.length == 2) {
          _dueTime = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 9,
            minute: int.tryParse(parts[1]) ?? 0,
          );
        }
      }
    } else {
      // 从护理记录新建：预填宠物 / 类型 / 标题 / 第几次
      _selectedPetId = widget.initialPetId;
      if (widget.initialType != null) _type = widget.initialType!;
      if (widget.initialTitle != null) _titleCtrl.text = widget.initialTitle!;
      // 先定间隔，再算「上次执行日期」的默认值——否则会用到旧的默认间隔
      // （例如项目本来是 7 天，上次日期却按 30 天反推）。
      _intervalDays =
          widget.initialIntervalDays ??
          AppColors.defaultInterval(_type, species: _selectedPetSpecies);
      if (widget.initialOccurrenceNo != null &&
          widget.initialOccurrenceNo! > 1) {
        _occurrenceNo = widget.initialOccurrenceNo!.clamp(1, 99);
      }
      // 只有项目里确实完成过，才带出上次执行日期
      _lastDoneDate = widget.initialLastDoneDate;
      _repeating = widget.initialIsRepeating ?? false;
      _soundEnabled = widget.initialSoundEnabled ?? true;
      _vibrateEnabled = widget.initialVibrateEnabled ?? true;
      final notif = widget.initialNotificationTime;
      if (notif != null) {
        final parts = notif.split(':');
        if (parts.length == 2) {
          _dueTime = TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 9,
            minute: int.tryParse(parts[1]) ?? 0,
          );
        }
      }
    }
    _intervalCtrl = TextEditingController(text: '$_intervalDays');
    // 用药疗程回填：天数与每天时间点
    _courseDaysCtrl = TextEditingController(text: '${r?.courseDays ?? 7}');
    if (r != null && r.isMedicationCourse) {
      _isMedication = true;
      _doseCount = r.doseTimes.length.clamp(1, _doseTimes.length);
      for (var i = 0; i < r.doseTimes.length && i < _doseTimes.length; i++) {
        final minutes = r.doseTimes[i];
        _doseTimes[i] = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
      }
    }
    if (r != null) {
      // 待办实例里的「第几次 / 到期日」才是列表上显示的值，异步回填
      _loadEditContext(r.id);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _intervalCtrl.dispose();
    _courseDaysCtrl.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  String get _notificationTimeStr =>
      '${_dueTime.hour.toString().padLeft(2, '0')}:${_dueTime.minute.toString().padLeft(2, '0')}';

  /// 与「选择宠物 / 开始日期」同一视觉语言的表单行：
  /// 圆角填充框内一行「灰色标签 + 内容」，不使用会压在边框上的浮动 label。
  Widget _inlineField({
    required String label,
    required Widget child,
    VoidCallback? onTap,
  }) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final content = InputDecorator(
      decoration: const InputDecoration(),
      child: Row(
        children: [
          Text(label, style: TextStyle(color: muted, fontSize: 15)),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: content,
    );
  }

  String _timeLabel(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 用药表单当前的服药时刻（当日分钟数，升序）。
  List<int> get _doseTimesMinutes {
    final times = [
      for (var i = 0; i < _doseCount; i++)
        _doseTimes[i].hour * 60 + _doseTimes[i].minute,
    ]..sort();
    return times;
  }

  /// 只读预览：共 N 次 · 开始 → 结束。
  String _coursePreviewText() {
    final days = int.tryParse(_courseDaysCtrl.text.trim()) ?? 0;
    final times = _doseTimesMinutes;
    if (days <= 0 || times.isEmpty) return '共 0 次';
    final dates = expandDoseTimes(
      courseStart: _execDate,
      courseDays: days,
      doseTimes: times,
    );
    if (dates.isEmpty) return '共 0 次';
    return '共 ${dates.length} 次 · '
        '${dateFormatCompact.format(_execDate)} → '
        '${dateFormatCompact.format(dates.last)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑提醒' : '添加提醒'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.all(20),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Pet selector ──────────────────────────
                FutureBuilder<List<Pet>>(
                  future: _petsFuture,
                  builder: (_, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const InputDecorator(
                        decoration: InputDecoration(labelText: '选择宠物 *'),
                        child: Text('加载中...'),
                      );
                    }
                    final pets = snap.data ?? [];
                    return InlineDropdown<String>(
                      label: '选择宠物',
                      value: _selectedPetId,
                      placeholder: '请选择宠物',
                      options: pets
                          .map(
                            (p) => InlineOption<String>(
                              value: p.id,
                              label: p.name,
                              subtitle:
                                  AppColors.speciesLabels[p.species] ??
                                  p.species,
                              icon: Icons.pets,
                              color: AppColors.plum,
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null || !mounted) return;
                        final pet = pets.where((p) => p.id == v).firstOrNull;
                        setState(() {
                          _selectedPetId = v;
                          if (pet != null) {
                            _selectedPetSpecies = pet.species;
                            _applyInterval(
                              AppColors.defaultInterval(
                                _type,
                                species: _selectedPetSpecies,
                              ),
                            );
                          }
                        });
                      },
                    );
                  },
                ),
                const SizedBox(height: 16),

                // ── Type ──────────────────────────────────
                InlineDropdown<String>(
                  label: '提醒类型',
                  value: _type,
                  options: AppColors.reminderTypeLabels.entries
                      .map(
                        (e) => InlineOption<String>(
                          value: e.key,
                          // 自定义显示用户写的标题（改标题时联动刷新）
                          label: reminderTypeDisplayLabel(
                            e.key,
                            _titleCtrl.text,
                          ),
                          subtitle:
                              '建议每 ${AppColors.defaultInterval(e.key, species: _selectedPetSpecies)} 天',
                          icon:
                              AppColors.reminderTypeIcons[e.key] ??
                              Icons.notifications,
                          color:
                              AppColors.reminderTypeColors[e.key] ??
                              AppColors.slate,
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null || !mounted) return;
                    setState(() {
                      _type = v;
                      _applyInterval(
                        AppColors.defaultInterval(
                          _type,
                          species: _selectedPetSpecies,
                        ),
                      );
                    });
                  },
                ),
                const SizedBox(height: 4),
                // Recommendation hint
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    AppColors.typeRecommendation(
                      _type,
                      species: _selectedPetSpecies,
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          (AppColors.reminderTypeColors[_type] ??
                          AppColors.slate),
                      height: 1.3,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 2),
                  child: Text(
                    '以上为常见养护参考，具体请遵兽医或药品说明',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Custom title (only for custom type) ───
                if (_type == 'custom') ...[
                  TextFormField(
                    controller: _titleCtrl,
                    focusNode: _titleFocus,
                    // 自定义类型时标题即类型名 → 输入时刷新类型下拉的显示
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: '标题 *'),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入标题' : null,
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Description ───────────────────────────
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(hintText: '备注'),
                  maxLines: 2,
                ),
                const SizedBox(height: 20),

                // ── 第几次提醒（与其他输入框同款外框，保持表单统一）──
                // 用药疗程不显示：它的「第几次」是「第 N 天第 M 次」，
                // 普通提醒的「第几次提醒」放进来只会打架（真机上被指出过）。
                if (!_isMedication) ...[
                  Text(
                    '第几次提醒',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InputDecorator(
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                    ),
                    child: Row(
                      children: [
                        _StepperButton(
                          icon: Icons.remove_circle_outline,
                          tooltip: '减少一次',
                          onPressed: _occurrenceNo > 1
                              ? () => setState(() {
                                  _occurrenceNo--;
                                })
                              : null,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '第 $_occurrenceNo 次',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.plum,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _StepperButton(
                          icon: Icons.add_circle_outline,
                          tooltip: '增加一次',
                          onPressed: _occurrenceNo < 99
                              ? () => setState(() {
                                  _occurrenceNo++;
                                })
                              : null,
                        ),
                        const Spacer(),
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            _occurrenceHint,
                            style: TextStyle(
                              fontSize: 12,
                              color: _occurrenceHintIsWarning
                                  ? AppColors.error
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // ── 执行日期（第 N 次）/ 开始日期 + 通知时间 ──────
                Text(
                  _isMedication ? '开始日期' : '执行日期',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          FocusManager.instance.primaryFocus?.unfocus();
                          final picked = await showAppleDatePicker(
                            context,
                            initialDate: _execDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null && mounted) {
                            // 只改执行日期；间隔（计划）不动
                            setState(() => _execDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(),
                          child: Text(
                            dateFormatCompact.format(_execDate),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                    if (!_isMedication) const SizedBox(width: 10),
                    if (!_isMedication)
                      Expanded(
                        child: InkWell(
                          onTap: () async {
                            FocusManager.instance.primaryFocus?.unfocus();
                            final picked = await showAppleTimePicker(
                              context,
                              initialTime: _dueTime,
                            );
                            if (picked != null && mounted) {
                              setState(() => _dueTime = picked);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(),
                            child: Text(
                              _notificationTimeStr,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // 上次执行日期：仅「第≥2次」显示（首次没有上一次）；用药也不显示
                if (!_isMedication && _occurrenceNo >= 2) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        '上次执行日期',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      // 无论单次还是重复，这个日期都只是记录，不参与调度计算
                      Text(
                        '仅作记录，不影响执行日期',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      FocusManager.instance.primaryFocus?.unfocus();
                      final picked = await showAppleDatePicker(
                        context,
                        // 未设置时从「执行日期 − 间隔」开始选（只是一个起点，不写库）
                        initialDate:
                            _lastDoneDate ??
                            _execDate.subtract(Duration(days: _intervalDays)),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null && mounted) {
                        // 只记录；间隔（计划）与执行日期都不动
                        setState(() => _lastDoneDate = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(),
                      child: Row(
                        children: [
                          Text(
                            _lastDoneDate == null
                                ? '未设置（点选）'
                                : dateFormatCompact.format(_lastDoneDate!),
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              color: _lastDoneDate == null
                                  ? Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant
                                  : null,
                            ),
                          ),
                          const Spacer(),
                          // 设过了才显示『距执行日期多少天』
                          if (_lastDoneDate != null)
                            Text(
                              lastDoneGapHintText(
                                lastDoneDate: _lastDoneDate!,
                                execDate: _execDate,
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                color: _lastDoneDate!.isAfter(_execDate)
                                    ? AppColors.error
                                    : AppColors.plum,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // ── Repeat switch（用药疗程与它互斥）─────────────
                if (!_isMedication)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('重复提醒'),
                    subtitle: Text(
                      _repeating ? '完成后自动安排下一次提醒' : '仅提醒一次，完成后进入已完成',
                    ),
                    value: _repeating,
                    activeTrackColor: AppColors.plum.withValues(alpha: 0.4),
                    activeThumbColor: AppColors.plum,
                    onChanged: (v) {
                      setState(() {
                        _repeating = v;
                        // 无论开启/关闭重复，都保留一个正的天数（关闭时只是不展示），
                        // 避免关闭重复后出现 0 导致无法保存。
                        _applyInterval(
                          AppColors.defaultInterval(
                            _type,
                            species: _selectedPetSpecies,
                          ),
                        );
                      });
                    },
                  ),
                // 间隔天数：仅重复提醒需要（单次提醒没有"下一次"；用药不用它）
                if (_repeating && !_isMedication) ...[
                  const SizedBox(height: 8),
                  // ── Interval (days) ───────────────────────
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Spacer(),
                            SizedBox(
                              width: 80,
                              child: TextFormField(
                                controller: _intervalCtrl,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.plum,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                ),
                                keyboardType: TextInputType.number,
                                onChanged: (v) {
                                  setState(() {
                                    // 改间隔：执行日期不动，上次执行日期跟着重算
                                    _applyInterval(int.tryParse(v) ?? 0);
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '天后提醒',
                              style: TextStyle(
                                fontSize: 15,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '计划：第 ${_occurrenceNo + 1} 次提醒时间 = 执行日期 + 这些天数'
                          '（与上次实际间隔无关）',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── 用药疗程（与间隔/重复互斥）────────────────
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('用药疗程'),
                  subtitle: Text(
                    _isMedication
                        ? '按「每天几次 × 连续几天」提醒，例如一天两次吃 15 天'
                        : '打开后可按疗程喂药（一天 1~4 次 × 连续 N 天）',
                  ),
                  value: _isMedication,
                  activeTrackColor: AppColors.plum.withValues(alpha: 0.4),
                  activeThumbColor: AppColors.plum,
                  onChanged: (v) => setState(() => _isMedication = v),
                ),
                if (_isMedication) ...[
                  const SizedBox(height: 8),
                  // 样式与「选择宠物 / 开始日期」统一：InputDecorator 内一行「标签 + 输入」，
                  // 不用 labelText（浮动 label 会压在边框上，用户明确要求不要压线）。
                  _inlineField(
                    label: '药品名称',
                    child: TextField(
                      controller: _titleCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: '例如：阿莫西林',
                      ),
                      style: const TextStyle(fontSize: 15),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(height: 10),
                  InlineDropdown<int>(
                    label: '每天次数',
                    value: _doseCount,
                    // 1~4 次；若历史数据里次数更多，把它也带上，避免一打开就丢配置
                    options: [
                      for (var n = 1; n <= 4; n++)
                        InlineOption<int>(
                          value: n,
                          label: '$n 次',
                          icon: Icons.medication,
                        ),
                      if (_doseCount > 4)
                        InlineOption<int>(
                          value: _doseCount,
                          label: '$_doseCount 次',
                          icon: Icons.medication,
                        ),
                    ],
                    onChanged: (v) => setState(() => _doseCount = v ?? 1),
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < _doseCount; i++) ...[
                    _inlineField(
                      label: '第 ${i + 1} 次时间',
                      onTap: () async {
                        FocusManager.instance.primaryFocus?.unfocus();
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _doseTimes[i],
                        );
                        if (picked != null && mounted) {
                          setState(() => _doseTimes[i] = picked);
                        }
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _timeLabel(_doseTimes[i]),
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          Icon(
                            Icons.schedule,
                            size: 18,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  _inlineField(
                    label: '疗程天数',
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _courseDaysCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            style: const TextStyle(fontSize: 15),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        Text(
                          '天',
                          style: TextStyle(
                            fontSize: 15,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _coursePreviewText(),
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 16),
                // ── 第 N+1 次提醒时间（自动计算，只读）───────
                // 单次提醒没有"下一次"，整行隐藏。
                if (_repeating)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.plum.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.event,
                          color: AppColors.plum,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '第 ${_occurrenceNo + 1} 次提醒时间',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${dateFormatYMD.format(_nextReminderDate)}  $_notificationTimeStr',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.plum,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                if (_combinedDue.isBefore(DateTime.now())) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC94A4A).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 18,
                          color: AppColors.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _repeating
                                ? '当前设置的提醒时间已过。建议重新选择执行日期或间隔天数；'
                                      '若仍希望保存，本次将进入已完成，并自动安排第 ${_occurrenceNo + 1} 次。'
                                : '当前设置的提醒时间已过。建议重新选择执行日期；'
                                      '若仍希望保存，保存后该提醒将进入已完成列表。',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.error,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // ── Notification settings ─────────────────
                Text(
                  '通知设置',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  // 外层 Container 有背景色，ListTile 的墨水效果会被盖住并触发
                  // Debug 断言（"ListTile ... DecoratedBox"）→ 用透明 Material 承接。
                  child: Material(
                    type: MaterialType.transparency,
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('声音'),
                          subtitle: const Text('通知时播放提示音'),
                          value: _soundEnabled,
                          activeTrackColor: AppColors.plum.withValues(
                            alpha: 0.4,
                          ),
                          activeThumbColor: AppColors.plum,
                          onChanged: (v) => setState(() => _soundEnabled = v),
                        ),
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        SwitchListTile(
                          title: const Text('震动'),
                          subtitle: const Text('通知时震动'),
                          value: _vibrateEnabled,
                          activeTrackColor: AppColors.plum.withValues(
                            alpha: 0.4,
                          ),
                          activeThumbColor: AppColors.plum,
                          onChanged: (v) => setState(() => _vibrateEnabled = v),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                // ── Save button ───────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('保存提醒', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_selectedPetId == null) {
      if (mounted) {
        showAppSnackBar(context, '请先选择宠物', isError: true);
      }
      return;
    }
    if (_type == 'custom' && _titleCtrl.text.trim().isEmpty) {
      _titleFocus.requestFocus();
      if (mounted) {
        showAppSnackBar(context, '请填写自定义提醒标题', isError: true);
      }
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_intervalDays < 1) {
      if (mounted) {
        showAppSnackBar(context, '天后提醒必须大于 0 天', isError: true);
      }
      return;
    }

    // ── 用药疗程：单独一条保存路径 ──────────────────────────
    if (_isMedication) {
      // 药名必填：留空会退化成「喂药」，卡片和通知都看不出是哪种药
      if (_titleCtrl.text.trim().isEmpty) {
        _titleFocus.requestFocus();
        if (mounted) showAppSnackBar(context, '请填写药品名称', isError: true);
        return;
      }
      final days = int.tryParse(_courseDaysCtrl.text.trim()) ?? 0;
      final times = _doseTimesMinutes;
      final error = validateMedicationCourse(
        courseDays: days,
        doseTimes: times,
      );
      if (error != null) {
        if (mounted) showAppSnackBar(context, error, isError: true);
        return;
      }
      setState(() => _saving = true);
      final now = DateTime.now();
      final medicineTitle = _titleCtrl.text.trim();
      final plan = expandDoseTimes(
        courseStart: _execDate,
        courseDays: days,
        doseTimes: times,
      );
      final first = plan.first;
      final saved = Reminder(
        id: _isEditing ? widget.reminder!.id : generateUuidV7(),
        petId: _selectedPetId!,
        title: medicineTitle,
        type: _type,
        description: _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        firstDueDate: first,
        courseDays: days,
        doseTimes: times,
        soundEnabled: _soundEnabled,
        vibrateEnabled: _vibrateEnabled,
        createdAt: _isEditing ? widget.reminder!.createdAt : now,
        updatedAt: now,
      );
      // 复用计划时刻未变的实例 ID：用药通知按实例 ID 排，换 ID 会漏提醒
      final reuse = <DateTime, String>{};
      if (_isEditing) {
        final old = await AppDatabase.getInstanceHistoryForReminder(
          widget.reminder!.id,
        );
        for (final i in old) {
          if (i.completed || i.isDeleted) continue;
          reuse[i.dueDate] = i.id;
        }
      }
      try {
        await AppDatabase.saveMedicationCourse(
          reminder: saved,
          isNew: !_isEditing,
          doses: [
            for (var i = 0; i < plan.length; i++)
              (id: generateUuidV7(), dueDate: plan[i], occurrenceNo: i + 1),
          ],
          reuseInstanceIds: reuse,
        );
        try {
          // 先取消这条提醒可能残留的旧通知（含已被改掉的时间点），再滚动重排
          for (final id in reuse.values) {
            await cancelDoseNotification(id);
          }
          await rescheduleMedicationWindow();
        } catch (e) {
          debugPrint('用药通知重排异常（提醒已保存）: $e');
        }
        if (mounted) {
          showAppSnackBar(context, _isEditing ? '用药疗程已更新' : '用药疗程已创建');
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _saving = false);
          showError(context, e);
        }
      }
      return;
    }

    final combinedNext = _combinedDue;
    final willBePastDue = combinedNext.isBefore(DateTime.now());
    if (willBePastDue) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('提醒时间已过'),
          content: Text(
            '当前设置的提醒时间（${dateFormatYMD.format(combinedNext)} $_notificationTimeStr）已经过去了。'
            '建议重新设置执行日期；如果你仍希望保存，它会作为**逾期待办**保留在待办区，'
            '并从今天起每天提醒，直到你确认完成为止。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('重新设置'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('仍然保存'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final repeatInterval = _intervalDays;
      final reminderTitle = _type == 'custom'
          ? _titleCtrl.text.trim()
          : (AppColors.reminderTypeLabels[_type] ?? '提醒');
      Reminder savedReminder;

      if (_isEditing) {
        savedReminder = widget.reminder!.copyWith(
          petId: _selectedPetId,
          title: reminderTitle,
          type: _type,
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          // 清空备注必须显式告知 copyWith，否则 null 会被 ?? 回退成旧值（备注删不掉）
          clearDescription: _descCtrl.text.trim().isEmpty,
          firstDueDate: combinedNext,
          repeatInterval: repeatInterval,
          isRepeating: _repeating,
          notificationTime: _notificationTimeStr,
          soundEnabled: _soundEnabled,
          vibrateEnabled: _vibrateEnabled,
          // 第≥2次才写「上次执行日期」；首次没有上一次，必须显式清空
          // （传 null 会被 copyWith 的 ?? 回退成旧值）。
          lastDoneDate: _occurrenceNo >= 2 ? _lastDoneDate : null,
          // 第 1 次、或用户没设上次日期 → 显式清空（传 null 会被 copyWith 回退）
          clearLastDoneDate: _occurrenceNo < 2 || _lastDoneDate == null,
        );
      } else {
        savedReminder = Reminder(
          id: generateUuidV7(),
          petId: _selectedPetId!,
          title: reminderTitle,
          type: _type,
          description: _descCtrl.text.trim().isEmpty
              ? null
              : _descCtrl.text.trim(),
          firstDueDate: combinedNext,
          repeatUnit: 'once',
          repeatInterval: repeatInterval,
          isRepeating: _repeating,
          notificationTime: _notificationTimeStr,
          soundEnabled: _soundEnabled,
          vibrateEnabled: _vibrateEnabled,
          lastDoneDate: _occurrenceNo >= 2 ? _lastDoneDate : null,
          createdAt: now,
          updatedAt: now,
        );
      }

      // 由「用药疗程」改回普通提醒：把疗程时期按实例 ID 排的那批通知全部取消，
      // 否则改完之后它们还会照常响（并且再也没人取消得掉）。
      if (_isEditing && widget.reminder!.isMedicationCourse) {
        try {
          final history = await AppDatabase.getInstanceHistoryForReminder(
            widget.reminder!.id,
          );
          for (final i in history) {
            try {
              await cancelDoseNotification(i.id);
            } catch (_) {
              // 取消失败不阻塞保存
            }
          }
        } catch (e) {
          debugPrint('取消用药通知失败（不阻塞保存）: $e');
        }
      }

      // 过期保存（用户选『仍然保存』）：只生成一条**逾期待办**。
      //
      // 不再直接写成已完成 —— 完成必须由用户手动确认（否则等于替用户
      // 承认『做过了』，而实际可能没做）；也不再额外补一条『下一次』，
      // 因为逾期待办会每天提醒直到完成（见 docs/开发进度看板.md 第七十七轮）。

      // 实体 + 旧待办删除 + 新待办插入放在同一个事务里，避免中途失败丢待办（P1-8）
      final instanceId = generateUuidV7();
      final saved = await AppDatabase.saveReminderWithInstance(
        reminder: savedReminder,
        isNew: !_isEditing,
        instanceId: instanceId,
        instanceDueDate: combinedNext,
        // 一律生成为待办（含逾期）：完成时间由用户在完成时确认
        completedAt: null,
        // 用户在「第几次提醒」里选的值（卡片/通知立即按它显示第 N 次）
        occurrenceNo: _occurrenceNo,
      );

      // 需要排通知的就是刚建的这条（逾期也排：从今天/明天的通知时刻起每天提醒）
      final scheduleTarget = ReminderInstance(
        id: instanceId,
        reminderId: savedReminder.id,
        dueDate: combinedNext,
        occurrenceNo: saved.occurrenceNo,
        createdAt: now,
      );

      // 通知权限提示只依据权限状态；调度异常不再误报“通知设置失败”。
      var notificationPermissionWarning = false;
      final toSchedule = scheduleTarget;
      {
        try {
          final granted = await PermissionService.isNotificationGranted();
          notificationPermissionWarning = !granted;
        } catch (e) {
          debugPrint('通知权限检查异常: $e');
        }
        try {
          final baseId = notificationIdFromUuid(savedReminder.id);
          try {
            await cancelReminderNotification(baseId);
          } catch (_) {
            // 取消旧通知失败不视为调度失败
          }
          final pets = await _petsFuture;
          final selectedPet = pets
              .where((p) => p.id == _selectedPetId)
              .firstOrNull;
          final notifTitle = buildReminderNotificationTitle(
            petName: selectedPet?.name ?? '',
            reminderTitle: reminderTitle,
            // 与卡片 / 提醒历史 / 护理记录同一口径（项目时间线编号）
            occurrenceNo: await projectNumberForInstance(
              savedReminder,
              toSchedule,
            ),
            isRepeating: _repeating,
          );
          await scheduleReminderNotification(
            id: baseId,
            title: notifTitle,
            body: AppColors.reminderTypeLabels[_type] ?? '提醒',
            scheduledDate: toSchedule.dueDate,
            // 每天提醒：到期前静默、到期起每天提醒直到手动完成
            repeatDaily: true,
            soundEnabled: _soundEnabled,
            vibrateEnabled: _vibrateEnabled,
          );
        } catch (e) {
          debugPrint('通知调度流程异常（提醒已保存）: $e');
        }
      }

      if (mounted) {
        showAppSnackBar(
          context,
          notificationPermissionWarning
              ? '提醒已保存，但系统通知权限未开启，请到“我的-通知权限”开启'
              : (_isEditing ? '提醒已更新' : '提醒已添加'),
          isError: notificationPermissionWarning,
        );
        Navigator.pop(context);
      }
    } catch (e, stack) {
      debugPrint('⚠️ 保存提醒失败: $e\n$stack');
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// 新建提醒的默认「执行日期」：
/// 今天的该时刻若还没过就用今天，否则用明天（保证默认不会一上来就是过去的时刻）。
DateTime defaultExecDateFor({
  required int hour,
  required int minute,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final today = DateTime(
    current.year,
    current.month,
    current.day,
    hour,
    minute,
  );
  return today.isAfter(current) ? today : today.add(const Duration(days: 1));
}

/// 提醒类型的**显示文案**。
///
/// 「用户写什么类型就是什么类型」：自定义类型直接显示用户写的标题，
/// 只有标题为空时才回退成『自定义』（避免出现『标题=狂犬疫苗、类型=自定义』的割裂感）。
String reminderTypeDisplayLabel(String type, String title) {
  if (type == 'custom') {
    final trimmed = title.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return AppColors.reminderTypeLabels[type] ?? '提醒';
}

/// 「第几次提醒」右侧的说明文字。
///
/// - 与已完成历史编号撞车 → 提示（避免出现两个『第 N 次』）；
/// - 首次 → 首次提醒；
/// - 重复提醒 → 完成后自动第 N+1 次；
/// - 单次提醒 → 仅提醒一次（**不能**写『完成后自动第 N+1 次』，单次没有下一次）。
String reminderOccurrenceHint({
  required int occurrenceNo,
  required bool repeating,
  required Set<int> historyNos,
}) {
  if (historyNos.contains(occurrenceNo)) {
    return '已有第 $occurrenceNo 次记录';
  }
  if (occurrenceNo == 1) return '首次提醒';
  return repeating ? '完成后自动第 ${occurrenceNo + 1} 次' : '仅提醒一次';
}

/// 「第 N+1 次提醒时间」预览（= 执行日期 + 计划间隔）。
///
/// 与保存逻辑同源：执行日期已过时按『今天 + 间隔』算，
/// 否则预览会显示一个已经过去的『下一次』，与实际保存结果不符。
DateTime nextReminderPreview({
  required DateTime execDate,
  required int intervalDays,
  required int hour,
  required int minute,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  final execMoment = DateTime(
    execDate.year,
    execDate.month,
    execDate.day,
    hour,
    minute,
  );
  if (execMoment.isBefore(current)) {
    return computeNextDueDate(
      hour: hour,
      minute: minute,
      intervalDays: intervalDays,
      now: current,
    );
  }
  return execDate.add(Duration(days: intervalDays));
}

/// 两个日期之间的天数（只按日期算，忽略时分）。
///
/// 只按**日期**（忽略时分）计算，避免同一天不同时刻算出 0/1 的抖动。
int cadenceDaysBetween({
  required DateTime lastDoneDate,
  required DateTime execDate,
}) {
  final last = DateTime(
    lastDoneDate.year,
    lastDoneDate.month,
    lastDoneDate.day,
  );
  final exec = DateTime(execDate.year, execDate.month, execDate.day);
  return exec.difference(last).inDays;
}

/// 「上次执行日期」相对「执行日期」的直观说明（仅单次提醒展示）。
///
/// 单次提醒没有「间隔天数」可看，用户最想知道的是『距这次执行过了多少天』，
/// 例如『30 天前』＝ 距上次执行已过 30 天。
/// - 同一天 → 同一天；
/// - 上次晚于执行日期（非法组合）→ 明确提示，而不是显示负数。
String lastDoneGapHintText({
  required DateTime lastDoneDate,
  required DateTime execDate,
}) {
  final days = cadenceDaysBetween(
    lastDoneDate: lastDoneDate,
    execDate: execDate,
  );
  if (days > 0) return '$days 天前';
  if (days == 0) return '同一天';
  return '晚于执行日期 ${-days} 天';
}

/// 「第几次提醒」的加减按钮。
///
/// 样式对齐 App 既有的「图标胶囊」：淡紫底 + 圆角 8 + plum 图标
/// （与提醒卡片的类型图标、我的页统计卡同款），
/// 并保持紧凑尺寸，避免把整行撑高破坏表单的视觉统一。
class _StepperButton extends StatelessWidget {
  const _StepperButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: enabled
            ? AppColors.plum.withValues(alpha: 0.10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(
              icon,
              size: 20,
              color: enabled
                  ? AppColors.plum
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
        ),
      ),
    );
  }
}
