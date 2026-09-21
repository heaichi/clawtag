import 'package:flutter_test/flutter_test.dart';
import 'package:pet_diary/core/database/app_database.dart';
import 'package:pet_diary/core/utils/medication_course.dart';
import 'package:pet_diary/core/utils/uuid.dart';
import 'package:pet_diary/services/reminder_service.dart';

/// 用药通知调度：一实例一通知 ID + 7 天滚动窗口。
///
/// 这里覆盖的是**纯函数与降级路径**；真实的到点触发需要真机验收。

DateTime _d(int y, int m, int day, [int h = 9]) => DateTime(y, m, day, h);

Reminder _med({int days = 15, List<int> times = const [540, 1260]}) => Reminder(
  id: 'm1',
  petId: 'p1',
  title: '阿莫西林',
  type: 'medicine',
  firstDueDate: _d(2026, 9, 18),
  courseDays: days,
  doseTimes: times,
  createdAt: _d(2026, 9, 18),
  updatedAt: _d(2026, 9, 18),
);

ReminderInstance _dose(
  String id,
  DateTime due, {
  bool done = false,
  String rid = 'm1',
}) => ReminderInstance(
  id: id,
  reminderId: rid,
  dueDate: due,
  completed: done,
  createdAt: due,
);

void main() {
  test('滚动窗口 = 7 天', () {
    expect(medicationWindowDays, 7);
  });

  test('doseWindow：排除已完成、已过期、窗口外与别的提醒', () {
    final r = _med(days: 3, times: const [540]);
    final all = [
      _dose('a', _d(2026, 9, 18, 9), done: true),
      _dose('b', _d(2026, 9, 19, 9)),
      _dose('c', _d(2026, 9, 25, 9)),
      _dose('x', _d(2026, 9, 19, 9), rid: 'other'),
    ];
    final win = doseWindow(
      reminder: r,
      instances: all,
      from: _d(2026, 9, 18),
      to: _d(2026, 9, 25),
      now: _d(2026, 9, 18, 12),
    );
    expect(win.map((i) => i.id), ['b']);
  });

  test('通知 ID 由实例 ID 派生：两个实例不会撞同一个 ID', () {
    final a = notificationIdFromUuid('d1');
    final b = notificationIdFromUuid('d2');
    expect(a, isNot(b));
    expect(a, greaterThanOrEqualTo(0));
  });

  test('scheduleDoseNotification：无插件环境下降级返回 false，不抛异常', () async {
    final ok = await scheduleDoseNotification(
      reminder: _med(days: 2, times: const [540]),
      instance: _dose('d1', _d(2026, 9, 18, 9)),
      petName: '团团',
      dayNumber: 1,
      doseOfDay: 1,
      remainingToday: 1,
    );
    expect(ok, isFalse);
  });

  test('rescheduleMedicationWindow：空库/无用药时安全返回，不抛异常', () async {
    await rescheduleMedicationWindow(now: _d(2026, 9, 18, 8));
  });

  test('完成分支判定：用药走窗口重排，普通重复提醒仍走 _scheduleNext', () {
    final med = _med(days: 15);
    final plain = Reminder(
      id: 'r1',
      petId: 'p1',
      title: '疫苗',
      type: 'vaccine',
      firstDueDate: _d(2026, 10, 1),
      isRepeating: true,
      createdAt: _d(2026, 10, 1),
      updatedAt: _d(2026, 10, 1),
    );
    expect(med.isMedicationCourse, isTrue);
    expect(
      plain.isMedicationCourse,
      isFalse,
      reason: '普通重复提醒必须继续走 _scheduleNext',
    );
  });
}
