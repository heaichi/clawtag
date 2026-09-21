import 'package:flutter/material.dart';

import '../core/database/app_database.dart';
import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../widgets/app_image.dart';
import '../widgets/app_video_player.dart';

class DiaryCard extends StatelessWidget {
  final Diary diary;
  final String petName;
  final List<Tag> tags;
  final List<String> mediaPaths;
  final VoidCallback onTap;

  const DiaryCard({
    super.key,
    required this.diary,
    required this.petName,
    required this.tags,
    this.mediaPaths = const [],
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.ink;
    final mutedColor = isDark ? AppColors.darkTextSecondary : AppColors.slate;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: pet chip + date + mood
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.plum.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      petName,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.plum,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    dateFormatMD.format(diary.diaryDate),
                    style: TextStyle(fontSize: 12, color: mutedColor),
                  ),
                  if (diary.mood != null && diary.mood!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      AppColors.moodEmojis[diary.mood!] ?? '',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ],
                  if (diary.weather != null && diary.weather!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      AppColors.weatherIcons[diary.weather!] ?? '',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ],
                ],
              ),
              // 纯媒体爪札参考朋友圈：标题/内容为空时不显示，也不留空行。
              if (diary.title.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  diary.title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                    height: 1.3,
                  ),
                ),
              ],
              if (diary.content.isNotEmpty) ...[
                const SizedBox(height: 6),
                // Body preview — uses characters to avoid breaking emoji
                Text(
                  diary.content.characters.length > 120
                      ? '${diary.content.characters.take(120)}...'
                      : diary.content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: mutedColor,
                    height: 1.55,
                  ),
                ),
              ],
              // Photo / video preview — 朋友圈式，显示全部媒体
              if (mediaPaths.isNotEmpty) ...[
                const SizedBox(height: 10),
                _DiaryMediaGrid(paths: mediaPaths, onTap: onTap),
              ],
              // Tags
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: tags
                      .map(
                        (t) => Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Color(
                              t.color ?? 0xFF8B5E7A,
                            ).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            t.name,
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(t.color ?? 0xFF8B5E7A),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DiaryMediaGrid extends StatelessWidget {
  final List<String> paths;
  final VoidCallback onTap;

  const _DiaryMediaGrid({required this.paths, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final count = paths.length;
    if (count == 1) {
      final path = paths.first;
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: isVideoFile(path)
            ? VideoThumbnail(
                path: path,
                width: double.infinity,
                height: 200,
                onTap: onTap,
              )
            : AppImage(
                path: path,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
              ),
      );
    }

    final columns = count == 2 ? 2 : 3;
    const spacing = 6.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: paths.take(9).map((path) {
            return SizedBox(
              width: tileWidth,
              height: tileWidth,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: isVideoFile(path)
                    ? VideoThumbnail(
                        path: path,
                        width: tileWidth,
                        height: tileWidth,
                        onTap: onTap,
                      )
                    : AppImage(
                        path: path,
                        width: tileWidth,
                        height: tileWidth,
                        fit: BoxFit.cover,
                      ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
