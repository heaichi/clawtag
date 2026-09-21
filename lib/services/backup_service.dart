import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/database/app_database.dart';
import 'reminder_service.dart';

/// 备份包内的数据文件名（固定；导入时按名查找）。
const backupDataEntryName = 'data.json';

/// 备份包内媒体文件的归档名（纯函数，便于单测）。
///
/// 带序号是为了避免不同目录下的同名文件互相覆盖（相册里 `IMG_0001.jpg` 很常见）。
String backupMediaEntryName(int index, String sourcePath) {
  final base = p.basename(sourcePath);
  return 'media/${index}_${base.isEmpty ? 'file' : base}';
}

/// 是否 zip 备份（新格式，含媒体）；否则按旧版纯 JSON 备份处理。
bool isZipBackupPath(String path) => path.toLowerCase().endsWith('.zip');

/// 生成备份 zip：`data.json` + `media/` 下的照片与视频。
///
/// 写进**临时目录**而不是数据库目录（审计 P2-7：旧导出会在库目录里越堆越多）。
///
/// [tempDir] 仅供测试注入（生产走系统临时目录）。
Future<File> buildBackupZip({DateTime? now, Directory? tempDir}) async {
  final data = await AppDatabase.buildExportMap();
  final archive = Archive();

  // 注意：sqflite 查出来的行是**只读 map**，要改写路径必须先复制一份可变副本。
  final images = [
    for (final r in (data['diary_images'] as List?) ?? const [])
      Map<String, dynamic>.from(r as Map),
  ];
  final pets = [
    for (final r in (data['pets'] as List?) ?? const [])
      Map<String, dynamic>.from(r as Map),
  ];
  data['diary_images'] = images;
  data['pets'] = pets;

  final paths = <String>{
    for (final r in images) (r['local_path'] as String?)?.trim() ?? '',
    for (final r in pets) (r['avatar_path'] as String?)?.trim() ?? '',
  }..removeWhere((e) => e.isEmpty);

  final rewrite = <String, String>{};
  var index = 0;
  for (final path in paths) {
    try {
      final file = File(path);
      if (!await file.exists()) continue;
      final name = backupMediaEntryName(index++, path);
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
      rewrite[path] = name;
    } catch (e) {
      debugPrint('打包媒体失败（跳过）: $path → $e');
    }
  }

  for (final r in images) {
    final key = (r['local_path'] as String?)?.trim();
    if (key != null && rewrite.containsKey(key)) r['local_path'] = rewrite[key];
  }
  for (final r in pets) {
    final key = (r['avatar_path'] as String?)?.trim();
    if (key != null && rewrite.containsKey(key)) {
      r['avatar_path'] = rewrite[key];
    }
  }

  final jsonBytes = utf8.encode(
    const JsonEncoder.withIndent('  ').convert(data),
  );
  archive.addFile(
    ArchiveFile(backupDataEntryName, jsonBytes.length, jsonBytes),
  );

  final dir = tempDir ?? await getTemporaryDirectory();
  final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
  final out = File(p.join(dir.path, 'clawtag_backup_$stamp.zip'));
  await out.writeAsBytes(ZipEncoder().encode(archive), flush: true);
  return out;
}

/// 从备份文件导入。
///
/// 支持两种来源：
/// - `.zip` 新格式：`data.json` + `media/`，**照片视频一起恢复**；
/// - `.json` 旧格式（老版本导出的纯文字备份）：文字数据恢复，媒体缺失会如实计数。
///
/// [mediaDir] 仅供测试注入（生产走应用私有 documents/media）。
Future<ImportSummary> importBackupFile(
  String path, {
  Directory? mediaDir,
}) async {
  final file = File(path);
  if (!await file.exists()) throw Exception('文件不存在：$path');

  Map<String, dynamic> data;
  final mediaEntries = <String, ArchiveFile>{};
  if (isZipBackupPath(path)) {
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    ArchiveFile? dataFile;
    for (final f in archive.files) {
      if (!f.isFile) continue;
      // 有些压缩工具（Windows 的 Compress-Archive 等）用反斜杠写条目名，
      // 不归一化的话媒体会被全部当成「找不到文件」而跳过（真机上踩过）。
      final name = f.name.replaceAll('\\', '/');
      if (name == backupDataEntryName) {
        dataFile = f;
      } else if (name.startsWith('media/')) {
        mediaEntries[name] = f;
      }
    }
    if (dataFile == null) {
      throw Exception('这个备份包里没有 $backupDataEntryName，可能不是爪札的备份');
    }
    data =
        jsonDecode(utf8.decode(dataFile.content as List<int>))
            as Map<String, dynamic>;
  } else {
    data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  final targetMediaDir = mediaDir ?? await _mediaDir();
  var counter = 0;
  final summary = await AppDatabase.importExportMap(
    data,
    resolveMedia: (archivePath) async {
      final entry = mediaEntries[archivePath];
      if (entry == null) return null;
      final name =
          '${DateTime.now().millisecondsSinceEpoch}_${counter++}_${p.basename(archivePath)}';
      final target = File(p.join(targetMediaDir.path, name));
      await target.writeAsBytes(entry.content as List<int>, flush: true);
      return target.path;
    },
  );

  // 导入后重排通知：失败只记日志，不影响「数据已导入」这个事实。
  try {
    final reminders = await AppDatabase.getAllReminders();
    await rescheduleReminderNotifications(reminders);
    await rescheduleMedicationWindow();
  } catch (e) {
    debugPrint('导入后重排通知失败（数据已导入）: $e');
  }
  return summary;
}

Future<Directory> _mediaDir() async {
  final dir = await getApplicationDocumentsDirectory();
  final media = Directory(p.join(dir.path, 'media'));
  if (!await media.exists()) await media.create(recursive: true);
  return media;
}

/// 导入回执文案（纯函数，便于单测）：如实说明恢复了什么、跳过了什么。
String formatImportSummary(ImportSummary s) {
  if (s.isEmpty) return '这份备份里没有可导入的数据';
  final parts = <String>[
    if (s.pets > 0) '${s.pets} 只宠物',
    if (s.diaries > 0) '${s.diaries} 篇爪札',
    if (s.images > 0) '${s.images} 个媒体',
    if (s.tags > 0) '${s.tags} 个标签',
    if (s.reminders > 0) '${s.reminders} 条提醒',
    if (s.instances > 0) '${s.instances} 条提醒记录',
  ];
  final buf = StringBuffer('已恢复 ${parts.join('、')}');
  if (s.skippedMedia > 0) {
    buf.write('；跳过 ${s.skippedMedia} 个找不到文件的媒体');
  }
  return buf.toString();
}
