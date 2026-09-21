import 'package:flutter_test/flutter_test.dart';

import 'package:pet_diary/core/database/app_database.dart';
import 'package:pet_diary/core/utils/pet_age.dart';

Pet _pet({
  required String species,
  DateTime? birthDate,
}) {
  return Pet(
    id: 'p1',
    name: '测试',
    species: species,
    birthDate: birthDate,
    meetDate: DateTime(2020, 1, 1),
    createdAt: DateTime(2020, 1, 1),
    updatedAt: DateTime(2020, 1, 1),
  );
}

void main() {
  group('PetAgeDisplay', () {
    test('无生日显示年龄未知', () {
      final result = buildPetAgeDisplay(
        _pet(species: 'cat'),
        now: DateTime(2024, 1, 1),
      );
      expect(result.hasAge, false);
      expect(result.ageText, '年龄未知');
      expect(result.fullLabel, '年龄未知');
    });

    test('未满1周显示未满1周', () {
      final birth = DateTime(2024, 1, 1);
      final result = buildPetAgeDisplay(
        _pet(species: 'cat', birthDate: birth),
        now: birth.add(const Duration(days: 3)),
      );
      expect(result.stageLabel, '幼猫');
      expect(result.ageText, '未满1周');
    });

    test('8周猫显示幼猫 · 8周（2月）', () {
      final birth = DateTime(2024, 1, 1);
      final result = buildPetAgeDisplay(
        _pet(species: 'cat', birthDate: birth),
        now: birth.add(const Duration(days: 56)),
      );
      expect(result.stageLabel, '幼猫');
      expect(result.ageText, '8周（1月）');
    });

    test('16周狗显示幼犬 · 16周（3月）', () {
      final birth = DateTime(2024, 1, 1);
      final result = buildPetAgeDisplay(
        _pet(species: 'dog', birthDate: birth),
        now: birth.add(const Duration(days: 112)),
      );
      expect(result.stageLabel, '幼犬');
      expect(result.ageText, '16周（3月）');
    });

    test('刚好1岁显示成猫 · 1岁0个月', () {
      final birth = DateTime(2023, 1, 1);
      final result = buildPetAgeDisplay(
        _pet(species: 'cat', birthDate: birth),
        now: birth.add(const Duration(days: 365)),
      );
      expect(result.stageLabel, '成猫');
      expect(result.ageText, '1岁0个月');
    });

    test('6岁11个月显示成犬', () {
      final birth = DateTime(2018, 1, 1);
      // 2520 天约为 6 年 10 个多月，仍在成年档。
      final result = buildPetAgeDisplay(
        _pet(species: 'dog', birthDate: birth),
        now: birth.add(const Duration(days: 2520)),
      );
      expect(result.stageLabel, '成犬');
      expect(result.ageText, contains('6岁'));
    });

    test('7岁显示老年猫 · 7岁0个月', () {
      final birth = DateTime(2017, 1, 1);
      final result = buildPetAgeDisplay(
        _pet(species: 'cat', birthDate: birth),
        now: birth.add(const Duration(days: 2557)),
      );
      expect(result.stageLabel, '老年猫');
      expect(result.ageText, '7岁0个月');
    });

    test('其他物种只显示数字年龄，不显示阶段', () {
      final birth = DateTime(2024, 1, 1);
      final result = buildPetAgeDisplay(
        _pet(species: 'other', birthDate: birth),
        now: birth.add(const Duration(days: 112)),
      );
      expect(result.stageLabel, isNull);
      expect(result.ageText, '16周（3月）');
    });

    test('其他物种1岁以上显示X岁X月', () {
      final birth = DateTime(2023, 1, 1);
      final result = buildPetAgeDisplay(
        _pet(species: 'other', birthDate: birth),
        now: birth.add(const Duration(days: 400)),
      );
      expect(result.stageLabel, isNull);
      expect(result.ageText, '1岁1个月');
    });
  });
}
