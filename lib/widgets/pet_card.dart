import 'dart:io';

import 'package:flutter/material.dart';

import '../core/database/app_database.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/pet_age.dart';
import 'pressable.dart';

class PetCard extends StatelessWidget {
  final Pet pet;
  final int diaryCount;
  final VoidCallback onTap;

  const PetCard({
    super.key,
    required this.pet,
    required this.diaryCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.ink;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.slate;
    final ageDisplay = buildPetAgeDisplay(pet);
    return PressableScale(
      onTap: onTap,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar — subtle plum glow
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.plum.withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Hero(
                  tag: 'pet-avatar-${pet.id}',
                  child: CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.plum.withValues(alpha: 0.08),
                    backgroundImage:
                        pet.avatarPath != null && pet.avatarPath!.isNotEmpty
                        ? FileImage(File(pet.avatarPath!))
                        : null,
                    child: pet.avatarPath == null || pet.avatarPath!.isEmpty
                        ? Text(
                            pet.name.characters.first,
                            style: const TextStyle(
                              fontSize: 22,
                              color: AppColors.plum,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Name + info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pet.name,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    if (pet.breed != null && pet.breed!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        pet.breed!,
                        style: TextStyle(fontSize: 13, color: mutedColor),
                      ),
                    ],
                    if (ageDisplay.hasAge) ...[
                      const SizedBox(height: 2),
                      Text(
                        ageDisplay.fullLabel,
                        style: TextStyle(fontSize: 12, color: mutedColor),
                      ),
                    ],
                  ],
                ),
              ),
              // Diary count
              Column(
                children: [
                  Text(
                    '$diaryCount',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.plum,
                    ),
                  ),
                  const Text(
                    '篇爪札',
                    style: TextStyle(fontSize: 11, color: AppColors.slate),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: AppColors.slate, size: 20),
            ],
          ),
        ),
      ),
    );
  }

}
