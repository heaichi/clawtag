import 'package:flutter_test/flutter_test.dart';
import 'package:pet_diary/core/database/app_database.dart';
import 'package:pet_diary/core/utils/medication_course.dart';

DateTime _d(int y, int m, int day, [int h = 9, int min = 0]) =>
    DateTime(y, m, day, h, min);

Reminder _med({
  int days = 15,
  List<int> times = const [540, 1260],
  DateTime? start,
}) => Reminder(
  id: 'm1',
  petId: 'p1',
  title: '阿莫西林',
  type: 'medicine',
  firstDueDate: start ?? _d(2026, 9, 18),
  courseDays: days,
  doseTimes: times,
  createdAt: _d(2026, 9, 18),
  updatedAt: _d(2026, 9, 18),
);

ReminderInstance _dose(
  String id,
  DateTime due, {
  bool done = false,
  int no = 1,
  String rid = 'm1',
}) => ReminderInstance(
  id: id,
  reminderId: rid,
  dueDate: due,
  completed: done,
  occurrenceNo: no,
  createdAt: due,
);

void main() {
  test('expandDoseTimes：15 天 × 2 次 = 30 个时刻，时分正确且升序', () {
    final list = expandDoseTimes(
      courseStart: _d(2026, 9, 18),
      courseDays: 15,
      doseTimes: const [540, 1260],
    );
    expect(list, hasLength(30));
    expect(list.first, _d(2026, 9, 18, 9));
    expect(list[1], _d(2026, 9, 18, 21));
    expect(list.last, _d(2026, 10, 2, 21));
  });

  test('expandDoseTimes：窗口与钳制（fromDay/toDay 越界不报错）', () {
    final list = expandDoseTimes(
      courseStart: _d(2026, 9, 18),
      courseDays: 3,
      doseTimes: const [480, 840, 1200],
      fromDay: 1,
      toDay: 99,
    );
    expect(list, hasLength(6), reason: '只剩第 2、3 天（各 3 次）');
    expect(list.first, _d(2026, 9, 19, 8));
  });

  test('doseSlotOf：第 4 天第 2 次 → dayIndex 3 / doseIndex 1 / overall 7', () {
    final slot = doseSlotOf(
      courseStart: _d(2026, 9, 18),
      doseTimes: const [540, 1260],
      dueDate: _d(2026, 9, 21, 21),
    );
    expect(slot!.dayIndex, 3);
    expect(slot.doseIndex, 1);
    expect(slot.overall, 7);
  });

  test('doseSlotOf：时间点对不上 / 落在疗程外 → null', () {
    expect(
      doseSlotOf(
        courseStart: _d(2026, 9, 18),
        doseTimes: const [540, 1260],
        dueDate: _d(2026, 9, 21, 10),
      ),
      isNull,
    );
    expect(
      doseSlotOf(
        courseStart: _d(2026, 9, 18),
        doseTimes: const [540],
        dueDate: _d(2026, 9, 17, 9),
      ),
      isNull,
    );
  });

  test('doseSlotOf：跨月正确', () {
    final slot = doseSlotOf(
      courseStart: _d(2026, 9, 30),
      doseTimes: const [540, 1260],
      dueDate: _d(2026, 10, 1, 9),
    );
    expect(slot!.dayIndex, 1);
  });

  test('courseSummary：第 4 天中间态（2/3 已完成、下次 20:00）', () {
    final r = _med(
      days: 15,
      times: const [480, 840, 1200],
      start: _d(2026, 9, 18),
    );
    final all = expandDoseTimes(
      courseStart: _d(2026, 9, 18),
      courseDays: 15,
      doseTimes: const [480, 840, 1200],
    );
    final instances = [
      for (var i = 0; i < all.length; i++)
        _dose('i$i', all[i], done: i < 11, no: i + 1),
    ];
    final s = courseSummary(
      reminder: r,
      instances: instances,
      now: _d(2026, 9, 21, 18),
    );
    expect(s.totalDoses, 45);
    expect(s.dayNumber, 4);
    expect(s.todayTotal, 3);
    expect(s.todayDone, 2);
    expect(s.remainingToday, 1);
    expect(s.nextDoseAt, _d(2026, 9, 21, 20));
  });

  test('courseSummary：前一天漏服会计数（只是计数，不拦人）', () {
    final r = _med(days: 3, times: const [540]);
    final instances = [
      _dose('a', _d(2026, 9, 18, 9), done: true, no: 1),
      _dose('b', _d(2026, 9, 19, 9), no: 2),
      _dose('c', _d(2026, 9, 20, 9), no: 3),
    ];
    final s = courseSummary(
      reminder: r,
      instances: instances,
      now: _d(2026, 9, 20, 8),
    );
    expect(s.todayMissed, 1);
    expect(s.remainingToday, 1);
  });

  test('missedDosesBefore：只数今天之前的漏服', () {
    final r = _med(days: 3, times: const [540]);
    final instances = [
      _dose('a', _d(2026, 9, 18, 9), no: 1),
      _dose('b', _d(2026, 9, 19, 9), no: 2),
    ];
    expect(
      missedDosesBefore(
        reminder: r,
        instances: instances,
        now: _d(2026, 9, 19, 8),
      ),
      1,
    );
  });

  test('isCourseFinished：最后一天当天算进行中，次日算结束', () {
    final r = _med(days: 3, times: const [540]);
    final instances = [
      _dose('a', _d(2026, 9, 18, 9), done: true, no: 1),
      _dose('b', _d(2026, 9, 19, 9), done: true, no: 2),
      _dose('c', _d(2026, 9, 20, 9), done: true, no: 3),
    ];
    expect(
      isCourseFinished(
        reminder: r,
        instances: instances,
        now: _d(2026, 9, 20, 23),
      ),
      isFalse,
    );
    expect(
      isCourseFinished(
        reminder: r,
        instances: instances,
        now: _d(2026, 9, 21, 0, 1),
      ),
      isTrue,
    );
  });

  test('courseCardSubtitle：进行中 / 今日已完成 / 疗程已结束', () {
    final r = _med(days: 2, times: const [540]);
    final a = _dose('a', _d(2026, 9, 18, 9), no: 1);
    final b = _dose('b', _d(2026, 9, 19, 9), no: 2);
    expect(
      courseCardSubtitle(
        reminder: r,
        instances: [a, b],
        now: _d(2026, 9, 18, 8),
      ),
      '第 1/2 天 · 今日 0/1 次 · 下次 09:00',
    );
    expect(
      courseCardSubtitle(
        reminder: r,
        instances: [_dose('a', _d(2026, 9, 18, 9), done: true, no: 1), b],
        now: _d(2026, 9, 18, 10),
      ),
      '第 1/2 天 · 今日已完成（1/1 次）',
    );
    expect(
      courseCardSubtitle(
        reminder: r,
        instances: [a, b],
        now: _d(2026, 9, 20, 8),
      ),
      '疗程已结束',
    );
  });

  test('courseCardSubtitle：今天之前的漏服会追加「漏 N 次」', () {
    final r = _med(days: 3, times: const [540]);
    final instances = [
      _dose('a', _d(2026, 9, 18, 9), no: 1), // 昨天漏了
      _dose('b', _d(2026, 9, 19, 9), no: 2),
    ];
    expect(
      courseCardSubtitle(
        reminder: r,
        instances: instances,
        now: _d(2026, 9, 19, 8),
      ),
      '第 2/3 天 · 今日 0/1 次 · 下次 09:00 · 漏 1 次',
    );
  });

  test('pendingDosesFor / doseWindow：只取该提醒、窗口内、未过期的待办', () {
    final r = _med(days: 3, times: const [540]);
    final instances = [
      _dose('a', _d(2026, 9, 18, 9), no: 1),
      _dose('b', _d(2026, 9, 19, 9), no: 2),
      _dose('c', _d(2026, 9, 20, 9), done: true, no: 3),
      _dose('x', _d(2026, 9, 19, 9), no: 9, rid: 'other'),
    ];
    final pend = pendingDosesFor(r, instances);
    expect(pend.map((e) => e.id), ['a', 'b']);
    final win = doseWindow(
      reminder: r,
      instances: instances,
      from: _d(2026, 9, 19),
      to: _d(2026, 9, 20),
      now: _d(2026, 9, 18, 8),
    );
    expect(win.map((e) => e.id), ['b']);
  });

  test('通知文案：第4天第2次 / 今日还剩次数', () {
    expect(
      buildDoseNotificationTitle(
        petName: '团团',
        medicineName: '阿莫西林',
        dayNumber: 4,
        doseOfDay: 2,
      ),
      '团团 · 阿莫西林（第4天 第2次）',
    );
    expect(
      buildDoseNotificationTitle(
        petName: '',
        medicineName: '阿莫西林',
        dayNumber: 1,
        doseOfDay: 1,
      ),
      '阿莫西林（第1天 第1次）',
    );
    expect(
      buildDoseNotificationBody(typeLabel: '喂药', remainingToday: 2),
      '喂药 · 今日还剩 2 次',
    );
    expect(buildDoseNotificationBody(typeLabel: '喂药'), '喂药');
  });

  test('开始日期在将来：不显示负数天，报「尚未开始」并给出首剂时间', () {
    final r = _med(days: 3, times: const [540], start: _d(2026, 9, 25));
    final a = _dose('a', _d(2026, 9, 25, 9), no: 1);
    final s = courseSummary(
      reminder: r,
      instances: [a],
      now: _d(2026, 9, 21, 8),
    );
    expect(s.dayNumber, 1, reason: '不能是 0 或负数');
    expect(s.todayTotal, 0);
    expect(s.nextDoseAt, _d(2026, 9, 25, 9), reason: '下一次要跨天找到首剂');
    expect(
      courseCardSubtitle(reminder: r, instances: [a], now: _d(2026, 9, 21, 8)),
      '第 1/3 天 · 尚未开始 · 首剂 9/25 09:00',
    );
  });

  test('validateMedicationCourse：天数与时间点的边界', () {
    expect(
      validateMedicationCourse(courseDays: 15, doseTimes: const [540, 1260]),
      isNull,
    );
    expect(
      validateMedicationCourse(courseDays: 0, doseTimes: const [540]),
      isNotNull,
    );
    expect(
      validateMedicationCourse(courseDays: 400, doseTimes: const [540]),
      isNotNull,
    );
    expect(
      validateMedicationCourse(courseDays: 15, doseTimes: const []),
      isNotNull,
    );
    expect(
      validateMedicationCourse(courseDays: 15, doseTimes: const [540, 540]),
      isNotNull,
      reason: '同一时刻重复没有意义',
    );
  });
}
