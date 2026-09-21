import '../database/app_database.dart';

/// 宠物年龄展示结果。
class PetAgeDisplay {
  /// 阶段标签：猫/狗为 幼猫/成猫/老年猫/幼犬/成犬/老年犬；其他物种为 null。
  final String? stageLabel;

  /// 数字年龄文案：`16周（4月）` / `2岁3个月` / `年龄未知` / `未满1周`。
  final String ageText;

  /// 是否有生日可计算。
  final bool hasAge;

  const PetAgeDisplay({
    this.stageLabel,
    required this.ageText,
    this.hasAge = true,
  });

  /// 组合完整展示文案。
  String get fullLabel {
    if (!hasAge) return ageText;
    if (stageLabel == null || stageLabel!.isEmpty) return ageText;
    return '$stageLabel · $ageText';
  }
}

/// 根据宠物生日计算年龄展示信息。
///
/// - 猫/狗：<1岁=幼年，1~6岁11个月=成年，>=7岁=老年。
/// - 其他物种：只显示数字年龄，不显示阶段标签。
/// - 无生日：显示“年龄未知”。
PetAgeDisplay buildPetAgeDisplay(Pet pet, {DateTime? now}) {
  final birth = pet.birthDate;
  if (birth == null) {
    return const PetAgeDisplay(ageText: '年龄未知', hasAge: false);
  }

  final today = now ?? DateTime.now();
  if (today.isBefore(birth)) {
    return const PetAgeDisplay(ageText: '年龄未知', hasAge: false);
  }

  final days = today.difference(birth).inDays;
  final isCat = pet.species == 'cat';
  final isDog = pet.species == 'dog';
  final isCatDog = isCat || isDog;
  final speciesWord = isCat ? '猫' : '犬';

  if (days < 7) {
    return PetAgeDisplay(
      stageLabel: isCatDog ? '幼$speciesWord' : null,
      ageText: '未满1周',
    );
  }

  if (days < 365) {
    final weeks = days ~/ 7;
    final months = (days ~/ 30).clamp(0, 11);
    return PetAgeDisplay(
      stageLabel: isCatDog ? '幼$speciesWord' : null,
      ageText: '$weeks周（$months月）',
    );
  }

  final years = days ~/ 365;
  final months = (days % 365) ~/ 30;
  final ageText = '$years岁$months个月';
  if (!isCatDog) {
    return PetAgeDisplay(ageText: ageText);
  }

  final stage = years >= 7 ? '老年$speciesWord' : '成$speciesWord';
  return PetAgeDisplay(stageLabel: stage, ageText: ageText);
}
