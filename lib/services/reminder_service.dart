import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

import '../core/database/app_database.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/care_records.dart';
import '../core/utils/medication_course.dart';
import '../core/utils/uuid.dart';

final _plugin = FlutterLocalNotificationsPlugin();

/// 生成通知标题：`宠物名 · 提醒标题（第X次）`。
///
/// 非重复或首次(第1次)时不附加“第X次”，与提醒列表展示保持一致。
String buildReminderNotificationTitle({
  required String petName,
  required String reminderTitle,
  int? occurrenceNo,
  bool isRepeating = false,
}) {
  final base = (isRepeating && occurrenceNo != null && occurrenceNo > 1)
      ? '$reminderTitle（第$occurrenceNo次）'
      : reminderTitle;
  return petName.isEmpty ? base : '$petName · $base';
}

/// 计算重复提醒的「下一次到期时间」：从今天起 + [intervalDays] 天，
/// 保留提醒的时分（与生成下一次实例的既有算法一致，抽出来便于单测）。
DateTime computeNextDueDate({
  required int hour,
  required int minute,
  required int intervalDays,
  DateTime? now,
}) {
  final base = now ?? DateTime.now();
  return DateTime(
    base.year,
    base.month,
    base.day,
    hour,
    minute,
  ).add(Duration(days: intervalDays));
}

/// 是否已经引导过用户去系统设置页开启"精确闹钟"（只引导一次）。
const _exactAlarmPromptedKey = 'exact_alarm_prompted';

/// 检查/引导「精确闹钟」权限，返回当前是否已授权。
///
/// - 已授权 → 直接返回 true（不打扰用户）；
/// - 未授权且从未引导 → 触发一次系统"闹钟与提醒"设置页，并记录标记；
/// - 未授权但已引导过 → 什么都不做。
///
/// 触发设置页时**不 await**：插件要等 Activity 返回才完成 Future，
/// await 会让"保存提醒"一直卡在保存中（见 docs/代码审计待办.md P1-6）。
/// 异常一律降级为 false（走 inexact 回退），不阻塞提醒保存。
Future<bool> ensureExactAlarmPermission() async {
  // 整个函数体都要兜住：插件未初始化时 resolvePlatformSpecificImplementation
  // 会抛 LateInitializationError，SharedPreferences 在异常环境也可能失败——
  // 这些都必须降级为 false（走 inexact），绝不能把异常抛给"保存/完成提醒"。
  try {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;

    final granted = (await android.canScheduleExactNotifications()) ?? false;
    if (granted) return true;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_exactAlarmPromptedKey) ?? false) return false;
    await prefs.setBool(_exactAlarmPromptedKey, true);

    unawaited(android.requestExactAlarmsPermission());
    return false;
  } catch (e) {
    debugPrint('ensureExactAlarmPermission failed（降级为 inexact）: $e');
    return false;
  }
}

Future<void> initNotifications() async {
  tz_data.initializeTimeZones();
  // 注意：此处不设置 tz.local（其默认值是 UTC）。原因：
  // - 本 App 的通知是一次性调度（迭代13 已移除平台级每日重复），
  //   TZDateTime.from 保留 scheduledDate 的瞬时值，触发时刻本就正确；
  // - 若未来要启用平台级 dayOfWeekAndTime 重复（依赖墙上时钟），
  //   需先引入 flutter_timezone 类依赖并 tz.setLocalLocation(...)。
  // 状态栏小图标用**单色** drawable：彩色自适应图标会显示成白块（P2-12）
  const androidSettings = AndroidInitializationSettings('ic_notification');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  const settings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  try {
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (_) {
        // 通知点击后不做导航——用户已在应用中
      },
    );
  } catch (e) {
    debugPrint('initNotifications failed: $e');
  }
}

/// 按"响铃 / 震动"组合派生通知渠道。
///
/// Android 8+ 的渠道在**创建后**声音与震动就由系统锁定，builder 级
/// `playSound`/`enableVibration` 对已存在渠道的通知不起作用；如果所有提醒共用
/// 一个渠道，那么"第一条被调度的提醒"会决定整条渠道的行为，单条提醒上的
/// 静音 / 无震动开关形同虚设（见 docs/代码审计待办.md P1-7）。
/// 因此这里按组合拆渠道，让每条提醒自己的设置真正生效。
({String id, String name}) reminderChannelFor({
  required bool soundEnabled,
  required bool vibrateEnabled,
}) {
  if (soundEnabled && vibrateEnabled) {
    return (id: 'pet_reminders_sound_vibrate', name: '宠物提醒（响铃 + 震动）');
  }
  if (soundEnabled) {
    return (id: 'pet_reminders_sound', name: '宠物提醒（仅响铃）');
  }
  if (vibrateEnabled) {
    return (id: 'pet_reminders_vibrate', name: '宠物提醒（仅震动）');
  }
  return (id: 'pet_reminders_silent', name: '宠物提醒（静音）');
}

/// 把本地时间转成调度用的 TZDateTime。
///
/// 时区数据可能因为 `initNotifications()` 失败而未初始化（P1-9 起该异常只记日志、
/// 不再阻断启动），此时 `tz.local` 会抛 LateInitializationError；这里兜底初始化一次。
/// 返回 null 表示无法调度，调用方应降级返回 false，而不是把异常抛给"保存/完成提醒"。
tz.TZDateTime? _resolveTzDate(DateTime date) {
  try {
    return tz.TZDateTime.from(date, tz.local);
  } catch (_) {
    try {
      tz_data.initializeTimeZones();
      return tz.TZDateTime.from(date, tz.local);
    } catch (e) {
      debugPrint('时区数据不可用，放弃本次调度: $e');
      return null;
    }
  }
}

/// 调度一条提醒通知。
///
/// [repeatDaily] = true 时按「每天同一时刻」重复（`DateTimeComponents.time`）：
/// **重复提醒**用它，这样到执行日期起每天提醒，直到用户完成为止 ——
/// 即使 App 从未被打开，逾期也不会静默（用户要求的 C-i）。
/// 单次提醒仍是一次性通知（逾期由提醒页自动完成）。
Future<bool> scheduleReminderNotification({
  required int id,
  required String title,
  required String body,
  required DateTime scheduledDate,
  bool soundEnabled = true,
  bool vibrateEnabled = true,
  bool repeatDaily = false,

  /// 是否按「每天同一时刻」重复。null = 用 [repeatDaily]（默认行为，普通提醒完全不变）；
  /// 显式 false = 强制一次性（用药的每一次服药都是独立事件，不能按天重复）。
  bool? repeatDailyOverride,
}) async {
  final tzDate = _resolveTzDate(scheduledDate);
  if (tzDate == null) return false;

  // 精确闹钟权限：已授权 → 用 exact 准点触发；未授权 → 最多引导一次系统设置页，
  // 其余情况直接走 inexact 回退，不再每次调度都把用户甩进设置页并阻塞保存。
  final canExact = await ensureExactAlarmPermission();

  // 渠道随"响铃/震动"组合派生（渠道的声音与震动由系统在创建时锁定）
  final channel = reminderChannelFor(
    soundEnabled: soundEnabled,
    vibrateEnabled: vibrateEnabled,
  );
  final androidDetails = AndroidNotificationDetails(
    channel.id,
    channel.name,
    channelDescription: '宠物日常提醒通知',
    importance: Importance.high,
    priority: Priority.high,
    // 状态栏小图标（单色），避免显示成白色方块（P2-12）
    icon: 'ic_notification',
    playSound: soundEnabled,
    enableVibration: vibrateEnabled,
  );

  Future<bool> schedule(AndroidScheduleMode mode) async {
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzDate,
      NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: soundEnabled,
        ),
      ),
      androidScheduleMode: mode,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      // 每天同一时刻重复（重复提醒专用）：到点提醒后若未完成，次日继续提醒
      matchDateTimeComponents: (repeatDailyOverride ?? repeatDaily)
          ? DateTimeComponents.time
          : null,
    );
    return true;
  }

  // 已授权精确闹钟 → 先试 exact，失败再回退 inexact；未授权 → 直接用 inexact。
  final modes = canExact
      ? const [
          AndroidScheduleMode.exactAllowWhileIdle,
          AndroidScheduleMode.inexactAllowWhileIdle,
        ]
      : const [AndroidScheduleMode.inexactAllowWhileIdle];
  for (final mode in modes) {
    try {
      await schedule(mode);
      return true;
    } catch (e) {
      debugPrint('schedule failed with $mode: $e');
    }
  }
  debugPrint('scheduleReminderNotification failed: 所有调度模式均失败');
  return false;
}

/// 通知标题里的「第N次」必须与卡片 / 提醒历史 / 护理记录**完全一致**：
/// 用项目时间线编号（同名项目合并后按时间顺序）。
///
/// 计算失败（或实例尚未落库）时回退到实例自身编号，**绝不阻塞调度**。
Future<int> projectNumberForInstance(
  Reminder reminder,
  ReminderInstance instance,
) async {
  try {
    final reminders = await AppDatabase.getPetReminders(reminder.petId);
    final instances = await AppDatabase.getInstancesForPet(reminder.petId);
    final key = normalizeCareName(reminder.title);
    for (final g in groupCareRecords(
      reminders: reminders,
      instances: instances,
    )) {
      if (normalizeCareName(g.name) != key) continue;
      for (final r in g.records) {
        if (r.instanceId == instance.id) return r.occurrenceNo;
      }
    }
  } catch (e) {
    debugPrint('项目编号计算失败，回退提醒内编号: $e');
  }
  return instance.occurrenceNo;
}

/// 恢复宠物/提醒后，为这些提醒当前存在的“未来待办实例”重新调度本地通知。
///
/// 删除时通知已被取消；如果恢复后不重排，提醒会只在待办区可见但到点不提醒。
/// 已过期实例不补排（单次过期会由提醒页按现有逻辑处理），避免历史通知轰炸。
Future<void> rescheduleReminderNotifications(List<Reminder> reminders) async {
  if (reminders.isEmpty) return;
  List<ReminderInstance> allPending;
  try {
    allPending = await AppDatabase.getPendingInstances();
  } catch (e) {
    debugPrint('rescheduleReminderNotifications load pending failed: $e');
    return;
  }
  // 每条提醒取**最先到期**的待办（原来后写覆盖会取到最晚那条，P2-11）
  final pendingByReminder = earliestPendingByReminder(allPending);
  for (final reminder in reminders) {
    final instance = pendingByReminder[reminder.id];
    if (instance == null) continue;
    var dueDate = instance.dueDate;
    if (!dueDate.isAfter(DateTime.now())) {
      // 已过期：**不**顺延日期（顺延会掩盖『漏做』），改为从今天/明天的通知
      // 时刻起每天提醒，直到用户手动确认完成 —— 单次与重复一视同仁。
      dueDate = computeNextDueDate(
        hour: reminder.firstDueDate.hour,
        minute: reminder.firstDueDate.minute,
        intervalDays: 1,
      );
    }
    final baseId = notificationIdFromUuid(reminder.id);
    try {
      await cancelReminderNotification(baseId);
    } catch (_) {
      // 取消旧通知失败不阻塞重排
    }
    Pet? pet;
    try {
      pet = await AppDatabase.getPet(reminder.petId);
    } catch (_) {
      // 取不到宠物名不阻塞通知重排
    }
    final notifTitle = buildReminderNotificationTitle(
      petName: pet?.name ?? '',
      reminderTitle: reminder.title,
      // 与卡片 / 提醒历史 / 护理记录同一口径（项目时间线编号）
      occurrenceNo: await projectNumberForInstance(reminder, instance),
      isRepeating: reminder.isRepeating,
    );
    await scheduleReminderNotification(
      id: baseId,
      title: notifTitle,
      body: AppColors.reminderTypeLabels[reminder.type] ?? '提醒',
      scheduledDate: dueDate,
      soundEnabled: reminder.soundEnabled,
      vibrateEnabled: reminder.vibrateEnabled,
      // 所有提醒都每天提醒：到期前静默，到期后每天提醒直到手动完成
      repeatDaily: true,
    );
  }
}

Future<void> rescheduleReminder(Reminder reminder) {
  return rescheduleReminderNotifications([reminder]);
}

Future<void> rescheduleRemindersForPet(String petId) async {
  try {
    final reminders = await AppDatabase.getPetReminders(petId);
    await rescheduleReminderNotifications(reminders);
  } catch (e) {
    debugPrint('rescheduleRemindersForPet failed: $e');
  }
}

/// 排**一次**服药的通知。
///
/// 通知 ID **必须**由实例 ID 派生：一条用药提醒一天有多次（1~4），
/// 若沿用「一条提醒一个通知 ID」，后一次会把前一次覆盖掉，只剩最后一次能响。
Future<bool> scheduleDoseNotification({
  required Reminder reminder,
  required ReminderInstance instance,
  required String petName,
  required int dayNumber,
  required int doseOfDay,
  int? remainingToday,
}) {
  final typeLabel = AppColors.reminderTypeLabels[reminder.type] ?? '提醒';
  return scheduleReminderNotification(
    id: notificationIdFromUuid(instance.id),
    title: buildDoseNotificationTitle(
      petName: petName,
      medicineName: reminder.title,
      dayNumber: dayNumber,
      doseOfDay: doseOfDay,
    ),
    body: buildDoseNotificationBody(
      typeLabel: typeLabel,
      remainingToday: remainingToday,
    ),
    scheduledDate: instance.dueDate,
    soundEnabled: reminder.soundEnabled,
    vibrateEnabled: reminder.vibrateEnabled,
    repeatDailyOverride: false,
  );
}

/// 取消**某一次**服药的通知。
Future<void> cancelDoseNotification(String instanceId) {
  return cancelReminderNotification(notificationIdFromUuid(instanceId));
}

/// 用药的滚动窗口重排：只排「未来 [medicationWindowDays] 天内」的服药。
///
/// 15 天 × 3 次 = 45 条通知一次性全排会撞系统/厂商后台限制（小米/华为尤其），
/// 因此只排最近 7 天，靠「启动 / 恢复提醒 / 编辑疗程 / 完成一次」反复调用滚动补排。
/// 调用时先把窗口内的旧通知全部取消，所以本函数**幂等**。
Future<void> rescheduleMedicationWindow({DateTime? now}) async {
  final current = now ?? DateTime.now();
  List<MedicationDose> all;
  try {
    all = await AppDatabase.getPendingDoseInstances();
  } catch (e) {
    debugPrint('rescheduleMedicationWindow load failed: $e');
    return;
  }
  if (all.isEmpty) return;

  final byReminder = <String, List<ReminderInstance>>{};
  final reminders = <String, Reminder>{};
  for (final dose in all) {
    byReminder.putIfAbsent(dose.reminder.id, () => []).add(dose.instance);
    reminders[dose.reminder.id] = dose.reminder;
  }

  final startOfToday = DateTime(current.year, current.month, current.day);
  final windowEnd = startOfToday.add(
    const Duration(days: medicationWindowDays),
  );

  for (final entry in byReminder.entries) {
    final reminder = reminders[entry.key]!;
    final inWindow = doseWindow(
      reminder: reminder,
      instances: entry.value,
      from: startOfToday,
      to: windowEnd,
      now: current,
    );
    if (inWindow.isEmpty) continue;

    // 幂等：先把这条提醒可能已排的通知统统取消（含已滚出窗口的那些）
    for (final instance in entry.value) {
      try {
        await cancelDoseNotification(instance.id);
      } catch (_) {
        // 取消失败不阻塞重排
      }
    }

    Pet? pet;
    try {
      pet = await AppDatabase.getPet(reminder.petId);
    } catch (_) {
      // 取不到宠物名不阻塞调度
    }
    final summary = courseSummary(
      reminder: reminder,
      instances: entry.value,
      now: current,
    );

    for (final instance in inWindow) {
      final slot = doseSlotOfInstance(reminder: reminder, instance: instance);
      if (slot == null) continue;
      await scheduleDoseNotification(
        reminder: reminder,
        instance: instance,
        petName: pet?.name ?? '',
        dayNumber: slot.dayIndex + 1,
        doseOfDay: slot.doseIndex + 1,
        remainingToday: summary.remainingToday,
      );
    }
  }
}

Future<void> cancelReminderNotification(int id) async {
  await _plugin.cancel(id);
}

Future<void> cancelAllNotifications() async {
  await _plugin.cancelAll();
}
