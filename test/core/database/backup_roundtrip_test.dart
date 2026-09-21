import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:clawtag/core/database/app_database.dart';
import 'package:clawtag/services/backup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 备份 / 恢复：导出 zip → 导入空库 → 断言数据与媒体都回来了。
///
/// 这是「换机迁移」的回归保护：ID 必须重新映射、外键必须有效、
/// 照片必须真的落到新目录、软删记录不参与导入。

DateTime _d(int y, int m, int day) => DateTime(y, m, day);

void main() {
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.debugDatabasePathOverride = inMemoryDatabasePath;
  });
  setUp(() async {
    await AppDatabase.debugResetForTest();
    tmp = Directory.systemTemp.createTempSync('clawtag_backup');
  });
  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  File _mediaFile(String name, String text) {
    final f = File(p.join(tmp.path, name));
    f.writeAsStringSync(text);
    return f;
  }

  Future<void> seed() async {
    final avatar = _mediaFile('avatar.jpg', 'avatar-bytes');
    final photo = _mediaFile('IMG_0001.jpg', 'photo-bytes');
    await AppDatabase.insertPet(
      Pet(
        id: 'p1',
        name: '团团',
        species: 'cat',
        avatarPath: avatar.path,
        meetDate: _d(2024, 1, 1),
        createdAt: _d(2024, 1, 1),
        updatedAt: _d(2024, 1, 1),
      ),
    );
    await AppDatabase.insertDiaryWithRelations(
      diary: Diary(
        id: 'd1',
        petId: 'p1',
        title: '第一次洗澡',
        content: '很乖',
        diaryDate: _d(2026, 9, 1),
        createdAt: _d(2026, 9, 1),
        updatedAt: _d(2026, 9, 1),
      ),
      imagePaths: [photo.path],
      tagIds: const [],
    );
    final tag = await AppDatabase.insertTag(
      Tag(id: 't1', name: '洗澡', createdAt: _d(2026, 9, 1)),
    );
    await AppDatabase.insertDiaryWithRelations(
      diary: Diary(
        id: 'd2',
        petId: 'p1',
        title: '打了疫苗',
        content: '有点蔫',
        diaryDate: _d(2026, 9, 10),
        createdAt: _d(2026, 9, 10),
        updatedAt: _d(2026, 9, 10),
      ),
      imagePaths: const [],
      tagIds: [tag],
    );
    await AppDatabase.insertReminder(
      Reminder(
        id: 'r1',
        petId: 'p1',
        title: '狂犬疫苗',
        type: 'vaccine',
        firstDueDate: _d(2026, 10, 1),
        createdAt: _d(2026, 9, 1),
        updatedAt: _d(2026, 9, 1),
      ),
    );
    await AppDatabase.insertReminderInstance(
      ReminderInstance(
        id: 'i1',
        reminderId: 'r1',
        dueDate: _d(2026, 10, 1),
        occurrenceNo: 1,
        createdAt: _d(2026, 9, 1),
      ),
    );
    // 软删的爪札不该被导入
    await AppDatabase.insertDiaryWithRelations(
      diary: Diary(
        id: 'd3',
        petId: 'p1',
        title: '删掉的',
        content: '-',
        diaryDate: _d(2026, 9, 2),
        createdAt: _d(2026, 9, 2),
        updatedAt: _d(2026, 9, 2),
      ),
      imagePaths: const [],
      tagIds: const [],
    );
    await AppDatabase.softDeleteDiary('d3');
  }

  test('导出地图只含业务表，且带格式版本', () async {
    await seed();
    final data = await AppDatabase.buildExportMap();
    expect(data['format_version'], AppDatabase.backupFormatVersion);
    for (final t in const [
      'pets',
      'diaries',
      'diary_images',
      'tags',
      'diary_tags',
      'reminders',
      'reminder_instances',
    ]) {
      expect(data.containsKey(t), isTrue, reason: '缺少业务表 $t');
    }
    for (final t in const [
      'virtual_pets',
      'game_currencies',
      'game_saves',
      'module_registry',
    ]) {
      expect(data.containsKey(t), isFalse, reason: '不该导出废弃表 $t');
    }
  });

  test('zip 往返：宠物/爪札/媒体/提醒都回来，软删记录不导入', () async {
    await seed();
    final zip = await buildBackupZip(tempDir: tmp);
    expect(zip.existsSync(), isTrue);

    final data =
        jsonDecode(
              utf8.decode(
                ZipDecoder()
                        .decodeBytes(zip.readAsBytesSync())
                        .files
                        .firstWhere((f) => f.name == backupDataEntryName)
                        .content
                    as List<int>,
              ),
            )
            as Map<String, dynamic>;
    expect(data['pets'], hasLength(1));
    expect(data['diaries'], hasLength(3), reason: '导出保留全部行（含软删）');

    // 换到一台「新设备」：清空数据库 + 新的媒体目录
    final newMedia = Directory(p.join(tmp.path, 'new_media'))..createSync();
    await AppDatabase.debugResetForTest();
    final summary = await importBackupFile(zip.path, mediaDir: newMedia);

    expect(summary.pets, 1);
    expect(summary.diaries, 2, reason: '软删的那篇不导入');
    expect(summary.images, 1);
    expect(summary.tags, 1);
    expect(summary.reminders, 1);
    expect(summary.instances, 1);
    expect(summary.skippedMedia, 0);

    final pets = await AppDatabase.getAllPets();
    expect(pets, hasLength(1));
    expect(pets.single.name, '团团');
    expect(pets.single.id, isNot('p1'), reason: 'id 必须重新生成，避免撞现有数据');
    expect(pets.single.avatarPath, isNotNull);
    expect(
      File(pets.single.avatarPath!).readAsStringSync(),
      'avatar-bytes',
      reason: '头像文件必须真的复制到新目录',
    );

    final diaries = await AppDatabase.getAllDiaries();
    expect(diaries.map((d) => d.title), containsAll(['第一次洗澡', '打了疫苗']));
    expect(
      diaries.every((d) => d.petId == pets.single.id),
      isTrue,
      reason: '外键必须指向新宠物',
    );

    final photos = await AppDatabase.getDiaryImages(
      diaries.firstWhere((d) => d.title == '第一次洗澡').id,
    );
    expect(photos, hasLength(1));
    expect(File(photos.single.localPath).readAsStringSync(), 'photo-bytes');

    expect(await AppDatabase.getAllReminders(), hasLength(1));
    expect(await AppDatabase.getPendingInstances(), hasLength(1));
  });

  test('重复导入不会重复建标签（按名称合并）', () async {
    await seed();
    final zip = await buildBackupZip(tempDir: tmp);
    final newMedia = Directory(p.join(tmp.path, 'm2'))..createSync();
    await AppDatabase.debugResetForTest();
    await importBackupFile(zip.path, mediaDir: newMedia);
    final firstTags = await AppDatabase.getAllTags();
    expect(firstTags, hasLength(1));

    final second = await importBackupFile(zip.path, mediaDir: newMedia);
    expect(second.pets, 1, reason: '宠物允许重名重导入（用户可能真的想再要一份）');
    expect(second.tags, 0, reason: '同名标签复用已有的，不再新建');
    expect(await AppDatabase.getAllTags(), hasLength(1));
  });

  test('旧版纯 JSON 备份：文字能恢复，媒体如实计入跳过', () async {
    await seed();
    final data = await AppDatabase.buildExportMap();
    final jsonFile = File(p.join(tmp.path, 'old_backup.json'))
      ..writeAsStringSync(jsonEncode(data));
    final newMedia = Directory(p.join(tmp.path, 'm3'))..createSync();
    await AppDatabase.debugResetForTest();

    final summary = await importBackupFile(jsonFile.path, mediaDir: newMedia);
    expect(summary.pets, 1);
    expect(summary.diaries, 2);
    expect(summary.images, 0, reason: '没有媒体文件，图片记录不保留');
    expect(summary.skippedMedia, greaterThan(0), reason: '要如实告诉用户跳过了几个');
    expect(
      (await AppDatabase.getAllPets()).single.avatarPath,
      isNull,
      reason: '文件不在，就不该留一个指向不存在文件的路径',
    );
  });

  test('纯函数：归档名 / 类型判断 / 回执文案', () {
    expect(
      backupMediaEntryName(0, r'C:\a\IMG_0001.jpg'),
      'media/0_IMG_0001.jpg',
    );
    expect(backupMediaEntryName(3, '/tmp/x/y.MP4'), 'media/3_y.MP4');
    expect(isZipBackupPath('a/b.zip'), isTrue);
    expect(isZipBackupPath('a/b.ZIP'), isTrue);
    expect(isZipBackupPath('a/b.json'), isFalse);
    expect(
      formatImportSummary(
        const ImportSummary(
          pets: 2,
          diaries: 4,
          images: 18,
          tags: 3,
          reminders: 6,
          instances: 9,
          skippedMedia: 1,
        ),
      ),
      '已恢复 2 只宠物、4 篇爪札、18 个媒体、3 个标签、6 条提醒、9 条提醒记录；跳过 1 个找不到文件的媒体',
    );
    expect(
      formatImportSummary(
        const ImportSummary(
          pets: 0,
          diaries: 0,
          images: 0,
          tags: 0,
          reminders: 0,
          instances: 0,
          skippedMedia: 0,
        ),
      ),
      '这份备份里没有可导入的数据',
    );
  });
}
