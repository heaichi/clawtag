import 'package:flutter_test/flutter_test.dart';
import 'package:pet_diary/core/database/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 批量查询的分片行为（docs/代码审计待办.md P2-6）。
///
/// 背景：getDiaryMediaBatch / getDiaryTagsBatch / getDiaryFirstImages 原先一次性
/// 把全部爪札 id 塞进 IN (...)；老设备 SQLite 绑定变量上限为 999，超过该数量时
/// 整页列表加载会失败。现在按 500 分片查询并合并。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AppDatabase.debugDatabasePathOverride = inMemoryDatabasePath;
  });
  setUp(() async => AppDatabase.debugResetForTest());

  test('超过分片阈值时结果仍正确合并（1200 个 id，含真实数据与不存在的 id）', () async {
    await AppDatabase.insertPet(
      Pet(
        id: 'p1',
        name: '咪咪',
        species: 'cat',
        meetDate: DateTime(2024, 1, 1),
        createdAt: DateTime(2024, 1, 1),
        updatedAt: DateTime(2024, 1, 1),
      ),
    );
    for (var i = 1; i <= 3; i++) {
      final n = i.toString();
      await AppDatabase.insertDiary(
        Diary(
          id: 'd$n',
          petId: 'p1',
          title: 't$n',
          content: 'c$n',
          diaryDate: DateTime(2026, 1, i),
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      );
      // 每条爪札两张图（sort_order 0/1），用于同时验证顺序
      await AppDatabase.insertDiaryImage(
        DiaryImage(
          id: 'img$n-a',
          diaryId: 'd$n',
          localPath: '/tmp/$n-a.jpg',
          sortOrder: 0,
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      await AppDatabase.insertDiaryImage(
        DiaryImage(
          id: 'img$n-b',
          diaryId: 'd$n',
          localPath: '/tmp/$n-b.jpg',
          sortOrder: 1,
          createdAt: DateTime(2026, 1, 1),
        ),
      );
    }
    await AppDatabase.insertTag(
      Tag(id: 'tag1', name: '疫苗', createdAt: DateTime(2026, 1, 1)),
    );
    await AppDatabase.setDiaryTags('d1', ['tag1']);

    // 让 id 总数远超 500（分片阈值）→ 必然走多分片
    final ids = <String>[
      'd1',
      'd2',
      'd3',
      ...List.generate(1197, (i) => 'missing-$i'),
    ];
    expect(ids.length, 1200);

    final media = await AppDatabase.getDiaryMediaBatch(ids);
    expect(media.keys.toSet(), {'d1', 'd2', 'd3'});
    expect(media['d1'], ['/tmp/1-a.jpg', '/tmp/1-b.jpg']);
    expect(media['d3'], ['/tmp/3-a.jpg', '/tmp/3-b.jpg']);

    final first = await AppDatabase.getDiaryFirstImages(ids);
    expect(first['d2'], '/tmp/2-a.jpg');
    expect(first.keys.toSet(), {'d1', 'd2', 'd3'});

    final tags = await AppDatabase.getDiaryTagsBatch(ids);
    expect(tags['d1']?.map((t) => t.name).toList(), ['疫苗']);
    expect(tags.containsKey('d2'), isFalse);
  });

  test('空列表直接返回空 Map（不查询）', () async {
    expect(await AppDatabase.getDiaryMediaBatch([]), isEmpty);
    expect(await AppDatabase.getDiaryTagsBatch([]), isEmpty);
    expect(await AppDatabase.getDiaryFirstImages([]), isEmpty);
  });
}
