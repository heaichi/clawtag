import 'package:flutter_test/flutter_test.dart';
import 'package:clawtag/services/reminder_service.dart';

/// 重复提醒「下一次到期时间」的纯函数测试。
///
/// 这段日期算法原先在列表页与编辑页各写了一份、且完全没有测试
/// （见 docs/代码审计待办.md 测试缺口 #2），这里抽出 [computeNextDueDate] 后补上。
void main() {
  group('computeNextDueDate（重复提醒下一次到期时间）', () {
    test('保留提醒的时分，从今天起 + interval 天', () {
      final next = computeNextDueDate(
        hour: 9,
        minute: 30,
        intervalDays: 30,
        now: DateTime(2026, 3, 15, 20, 5),
      );
      expect(next, DateTime(2026, 4, 14, 9, 30));
    });

    test('跨月与跨年都正确', () {
      expect(
        computeNextDueDate(
          hour: 8,
          minute: 0,
          intervalDays: 20,
          now: DateTime(2026, 12, 20, 23, 59),
        ),
        DateTime(2027, 1, 9, 8, 0),
      );
    });

    test('interval=1 得到"明天同一时刻"，且一定晚于现在', () {
      final now = DateTime(2026, 6, 1, 23, 30);
      final next = computeNextDueDate(
        hour: 7,
        minute: 0,
        intervalDays: 1,
        now: now,
      );
      expect(next, DateTime(2026, 6, 2, 7, 0));
      expect(next.isAfter(now), isTrue);
    });

    test('通知渠道按"响铃/震动"组合拆分，四种组合互不相同', () {
      final both = reminderChannelFor(soundEnabled: true, vibrateEnabled: true);
      final soundOnly = reminderChannelFor(
        soundEnabled: true,
        vibrateEnabled: false,
      );
      final vibrateOnly = reminderChannelFor(
        soundEnabled: false,
        vibrateEnabled: true,
      );
      final silent = reminderChannelFor(
        soundEnabled: false,
        vibrateEnabled: false,
      );

      expect({
        both.id,
        soundOnly.id,
        vibrateOnly.id,
        silent.id,
      }, hasLength(4), reason: 'P1-7：渠道 id 必须互不相同，否则单条提醒的静音/无震动失效');
      expect(both.id, 'pet_reminders_sound_vibrate');
      expect(silent.id, 'pet_reminders_silent');
      // 渠道名给用户看，必须非空且能区分
      expect({both.name, soundOnly.name, vibrateOnly.name, silent.name}, hasLength(4));
    });

    test('精确闹钟权限查询在无插件环境下降级返回 false（不抛异常）', () async {
      // 测试进程没有 Android 插件/SharedPreferences：该函数必须 catch 降级，
      // 不能把异常抛给调用方，否则"保存提醒"会整条失败（集成点异常降级规则）。
      expect(await ensureExactAlarmPermission(), isFalse);
    });

    test('闰年 2/29 边界不出错，且保持时分', () {
      expect(
        computeNextDueDate(
          hour: 6,
          minute: 15,
          intervalDays: 1,
          now: DateTime(2028, 2, 28, 12, 0),
        ),
        DateTime(2028, 2, 29, 6, 15),
      );
      expect(
        computeNextDueDate(
          hour: 6,
          minute: 15,
          intervalDays: 1,
          now: DateTime(2028, 2, 29, 12, 0),
        ),
        DateTime(2028, 3, 1, 6, 15),
      );
    });
  });
}
