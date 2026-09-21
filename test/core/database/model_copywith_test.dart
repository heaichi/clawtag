import 'package:flutter_test/flutter_test.dart';
import 'package:clawtag/core/database/app_database.dart';

void main() {
  group('Diary.copyWith 清空语义（审计回归：体重/心情/天气可清空）', () {
    final base = Diary(
      id: 'd1',
      petId: 'p1',
      title: 't',
      content: 'c',
      mood: 'happy',
      weather: 'sunny',
      weight: 12.5,
      diaryDate: DateTime(2026, 1, 1),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    test('clearWeight 清空体重', () {
      expect(base.copyWith(clearWeight: true).weight, isNull);
    });

    test('clearMood / clearWeather 清空', () {
      final next = base.copyWith(clearMood: true, clearWeather: true);
      expect(next.mood, isNull);
      expect(next.weather, isNull);
    });

    test('不传 clear 时正常覆盖并保留未改字段', () {
      final next = base.copyWith(weight: 10);
      expect(next.weight, 10);
      expect(next.mood, 'happy');
      expect(next.title, 't');
    });
  });

  group('Pet.copyWith 清空语义（审计回归：头像/品种/备注/生日可清空）', () {
    final base = Pet(
      id: 'p1',
      name: 'n',
      species: 'dog',
      breed: '柯基',
      birthDate: DateTime(2020),
      meetDate: DateTime(2021),
      avatarPath: '/a.png',
      notes: 'note',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    test('clearAvatarPath 清空头像', () {
      expect(base.copyWith(clearAvatarPath: true).avatarPath, isNull);
    });

    test('clearBreed / clearNotes / clearBirthDate 清空', () {
      final next = base.copyWith(
        clearBreed: true,
        clearNotes: true,
        clearBirthDate: true,
      );
      expect(next.breed, isNull);
      expect(next.notes, isNull);
      expect(next.birthDate, isNull);
    });

    test('保留未清空字段', () {
      final next = base.copyWith(name: '新名');
      expect(next.name, '新名');
      expect(next.breed, '柯基');
    });
  });

  group('Reminder.copyWith petId（审计回归：编辑换宠物生效）', () {
    final base = Reminder(
      id: 'r1',
      petId: 'p1',
      title: 't',
      type: 'custom',
      firstDueDate: DateTime(2026, 2, 1),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

    test('petId 可变更，不传则保留', () {
      expect(base.copyWith(petId: 'p2').petId, 'p2');
      expect(base.copyWith().petId, 'p1');
    });

    test('lastDoneDate 保留（迭代19：编辑不丢上次完成时间）', () {
      final done = base.copyWith(lastDoneDate: DateTime(2026, 3, 1));
      expect(done.lastDoneDate, DateTime(2026, 3, 1));
      expect(done.copyWith(title: 'x').lastDoneDate, DateTime(2026, 3, 1));
    });

    test('clearLastDoneDate 清空上次完成时间（第 1 次提醒用）', () {
      final done = base.copyWith(lastDoneDate: DateTime(2026, 3, 1));
      expect(done.copyWith(clearLastDoneDate: true).lastDoneDate, isNull);
      // 不传 clear 时保留原值
      expect(done.copyWith(title: 'x').lastDoneDate, DateTime(2026, 3, 1));
    });

    test('clearDescription 清空备注（审计回归 P1-5：备注原本删不掉）', () {
      final withNote = base.copyWith(description: '旧备注');
      expect(withNote.description, '旧备注');
      // 只传 null 会被 ?? 回退（旧行为），所以清空必须显式声明
      expect(withNote.copyWith(description: null).description, '旧备注');
      expect(withNote.copyWith(clearDescription: true).description, isNull);
      // 不传 clear 时正常覆盖、并保留未改字段
      expect(withNote.copyWith(description: '新备注').description, '新备注');
      expect(withNote.copyWith(title: 'x').description, '旧备注');
    });
  });

  group('ReminderInstance 软删除字段（V15 审计回归：已完成记录进最近删除）', () {
    test('默认构造为未删除状态', () {
      final inst = ReminderInstance(
        id: 'i1',
        reminderId: 'r1',
        dueDate: DateTime(2026, 4, 1),
        createdAt: DateTime(2026),
      );
      expect(inst.isDeleted, isFalse);
      expect(inst.deletedAt, isNull);
    });

    test('显式软删除字段保留', () {
      final deletedAt = DateTime(2026, 4, 2);
      final inst = ReminderInstance(
        id: 'i1',
        reminderId: 'r1',
        dueDate: DateTime(2026, 4, 1),
        createdAt: DateTime(2026),
        isDeleted: true,
        deletedAt: deletedAt,
      );
      expect(inst.isDeleted, isTrue);
      expect(inst.deletedAt, deletedAt);
    });

    test('软删除不改变业务字段（occurrenceNo 保留原值）', () {
      final inst = ReminderInstance(
        id: 'i1',
        reminderId: 'r1',
        dueDate: DateTime(2026, 4, 1),
        completed: true,
        completedAt: DateTime(2026, 4, 1, 10),
        occurrenceNo: 3,
        createdAt: DateTime(2026),
        isDeleted: true,
      );
      expect(inst.completed, isTrue);
      expect(inst.occurrenceNo, 3);
    });
  });
}
